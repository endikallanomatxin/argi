const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const integer = @import("../5_codegen/integer_arithmetic.zig");
const Storage = @import("storage.zig").Storage;
const WriteDestination = @import("storage.zig").WriteDestination;
const runtime_value = @import("../5_codegen/bytecode/value.zig");
const p = @import("../4_semantics/primitives/schema.zig");

pub const Limits = struct {
    instructions: usize = 1_000_000,
    call_depth: usize = 128,
    // Cumulative value cells, including frames and record snapshots. This bounds
    // the execution arena even when a loop repeatedly creates short-lived values.
    value_cells: usize = 1_000_000,
};

const Frame = struct {
    program: *const b.Program,
    function: *const b.Function,
    storage: runtime_value.FrameId,
    pc: usize = 0,
    return_slots: []const b.Slot,
    write_destinations: []?WriteDestination,
};

/// Execution identity and memory outlive individual verified programs. Session
/// owners can invoke several program versions against this context sequentially.
/// Cleanup remains checked language code; reset discards storage after cleanup
/// or a terminal trap and never attempts to synthesize an unwind.
pub const Context = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    storage: Storage = undefined,
    limit: usize,
    state: enum { fresh, ready, poisoned } = .fresh,
    running: bool = false,
    namespace: ?b.SessionNamespace = null,
    bindings: std.AutoHashMapUnmanaged(g.GlobalBindingId, runtime_value.FrameId) = .empty,
    literal_bytes: std.StringHashMapUnmanaged(runtime_value.Reference) = .empty,
    trace_locations: std.ArrayList(b.TraceLocation) = .empty,

    pub fn init(allocator: std.mem.Allocator, value_cells: usize) Context {
        return .{ .arena = .init(allocator), .allocator = allocator, .limit = value_cells };
    }
    fn ensureStorage(self: *Context) !void {
        if (self.state == .poisoned) return error.ExecutionContextPoisoned;
        if (self.state == .fresh) {
            self.storage = try Storage.init(self.arena.allocator(), self.limit);
            self.state = .ready;
        }
    }
    pub fn sessionSlots(self: *Context, count: usize, cleanup: []const b.Cleanup) !@import("storage.zig").Slots {
        if (self.running) return error.ExecutionContextBusy;
        if (self.state == .poisoned) return error.ExecutionContextPoisoned;
        errdefer self.state = .poisoned;
        try self.ensureStorage();
        return self.storage.enterSession(count, cleanup);
    }
    pub fn deinit(self: *Context) void {
        std.debug.assert(!self.running);
        self.arena.deinit();
        self.* = undefined;
    }
    pub fn reset(self: *Context) void {
        std.debug.assert(!self.running);
        self.arena.deinit();
        self.arena = .init(self.allocator);
        self.state = .fresh;
        self.namespace = null;
        self.bindings = .empty;
        self.literal_bytes = .empty;
        self.trace_locations = .empty;
    }

    fn checkNamespace(self: *const Context, session: ?b.Session) !void {
        if (session) |interface| if (self.namespace) |namespace| {
            if (namespace != interface.namespace) return error.ExecutionForeignSession;
        };
    }
    fn literalBytes(self: *Context, bytes: []const u8) !b.Value {
        if (self.literal_bytes.get(bytes)) |reference| return .{ .reference = reference };
        try self.storage.charge(1);
        const allocator = self.arena.allocator();
        try self.literal_bytes.ensureUnusedCapacity(allocator, 1);
        const reference = try self.storage.staticBytes(bytes);
        const key = try self.storage.literalBytes(reference);
        self.literal_bytes.putAssumeCapacity(key, reference);
        return .{ .reference = reference };
    }

    fn registerTraceLocation(self: *Context, location: b.TraceLocation) !b.Value {
        for (self.trace_locations.items, 0..) |existing, index| {
            if (existing.offset == location.offset and std.mem.eql(u8, existing.path, location.path) and
                existing.line == location.line and existing.column == location.column and std.mem.eql(u8, existing.source_line, location.source_line))
                return .{ .integer = @intCast(index) };
        }
        const id = std.math.cast(u32, self.trace_locations.items.len) orelse return error.ExecutionTraceLocationLimit;
        try self.storage.charge(1 + location.path.len + location.source_line.len);
        const a = self.arena.allocator();
        var retained = location;
        retained.path = try a.dupe(u8, location.path);
        retained.source_line = try a.dupe(u8, location.source_line);
        try self.trace_locations.append(a, retained);
        return .{ .integer = id };
    }

    fn resolveTraceLocation(self: *Context, id: i128) !b.Value {
        const index = std.math.cast(usize, id) orelse return error.ExecutionInvalidSourceLocation;
        if (index >= self.trace_locations.items.len) return error.ExecutionInvalidSourceLocation;
        const location = self.trace_locations.items[index];
        const fields = try self.storage.allocate(4);
        fields[0] = try self.literalBytes(location.path);
        fields[1] = try self.literalBytes(location.source_line);
        fields[2] = .{ .integer = location.line };
        fields[3] = .{ .integer = location.column };
        return .{ .record = fields };
    }

    fn initializeBinding(self: *Context, binding: b.SessionBinding, value: b.Value) !void {
        if (self.bindings.contains(binding.binding)) return error.ExecutionInitializedStorage;
        try self.storage.charge(1);
        try self.bindings.ensureUnusedCapacity(self.arena.allocator(), 1);
        const target = try self.storage.enterSession(binding.slots.len, binding.cleanup);
        try self.storage.initializeSession(target, 0, value);
        self.bindings.putAssumeCapacity(binding.binding, target.frame);
    }
    fn borrowBinding(self: *Context, binding: b.SessionBinding, permission: p.PointerMutability) !b.Value {
        const frame = self.bindings.get(binding.binding) orelse return error.ExecutionUninitializedStorage;
        return self.storage.borrow(.{ .context = self.storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write }, permission);
    }
};

pub const Vm = struct {
    allocator: std.mem.Allocator,
    program: b.Program,
    limits: Limits,
    steps: usize = 0,
    owned_context: Context,
    shared_context: ?*Context = null,
    source: p.SourceRef = .{ .file_index = 0, .offset = 0 },

    // Verify before executing anything, including before checking the entry.
    pub fn init(a: std.mem.Allocator, program: b.Program, limits: Limits) !Vm {
        try b.verify(a, program);
        return .{ .owned_context = Context.init(a, limits.value_cells), .allocator = a, .program = program, .limits = limits };
    }
    /// Borrow session-owned execution storage without transferring it. The
    /// memory quota belongs to that context; instruction/depth limits are local
    /// to each invocation. Fresh-run convenience APIs are unavailable here.
    pub fn initShared(a: std.mem.Allocator, program: b.Program, limits: Limits, shared: *Context) !Vm {
        if (limits.value_cells != shared.limit) return error.ExecutionContextLimitMismatch;
        try b.verify(a, program);
        return .{ .owned_context = undefined, .shared_context = shared, .allocator = a, .program = program, .limits = limits };
    }
    pub fn context(self: *Vm) *Context {
        return self.shared_context orelse &self.owned_context;
    }
    pub fn deinit(self: *Vm) void {
        if (self.shared_context == null) self.owned_context.deinit();
    }
    // Session owners must run checked exit cleanup before resetting a healthy
    // context. A trapped context has no resumable cleanup/unwind guarantee.
    pub fn reset(self: *Vm) void {
        self.context().reset();
        self.steps = 0;
    }

    pub fn run(self: *Vm, entry: g.GlobalFunctionId, args: []const b.Value) ![]const b.Value {
        return self.freshInvoke(entry, args);
    }
    pub fn runExpression(self: *Vm, args: []const b.Value) ![]const b.Value {
        return self.freshInvoke(null, args);
    }
    fn freshInvoke(self: *Vm, entry: ?g.GlobalFunctionId, args: []const b.Value) ![]const b.Value {
        if (self.shared_context != null) return error.SharedExecutionContext;
        // Preserve previous results until invoke has copied the supplied input.
        // This convenience API intentionally starts a fresh execution context.
        var previous = self.context().arena;
        self.context().arena = std.heap.ArenaAllocator.init(self.allocator);
        self.context().state = .fresh;
        self.context().namespace = null;
        self.context().bindings = .empty;
        defer previous.deinit();
        return if (entry) |id| self.invoke(id, args) else self.invokeExpression(args);
    }

    // Invoke within retained execution storage. Calls share the memory budget
    // and context identity; each invocation receives a fresh instruction budget.
    // Program validation and ordinary safety checking are not repeated here.
    pub fn invoke(self: *Vm, entry: g.GlobalFunctionId, args: []const b.Value) ![]const b.Value {
        if (self.context().state == .poisoned) return error.ExecutionContextPoisoned;
        const function = try self.entryFunction(entry, args);
        return self.invokeFunction(function, args);
    }
    pub fn invokeExpression(self: *Vm, args: []const b.Value) ![]const b.Value {
        if (self.context().state == .poisoned) return error.ExecutionContextPoisoned;
        const function = self.program.expression orelse return error.InvalidEntry;
        try self.validateArguments(function, args);
        return self.invokeFunction(function, args);
    }
    fn invokeFunction(self: *Vm, function: *const b.Function, args: []const b.Value) ![]const b.Value {
        if (self.context().running) return error.ExecutionContextBusy;
        try self.context().checkNamespace(self.program.session);
        self.context().running = true;
        defer self.context().running = false;
        try self.context().ensureStorage();
        if (self.program.session) |session| self.context().namespace = session.namespace;
        self.steps = 0;
        errdefer self.context().state = .poisoned;
        const inputs = try self.context().storage.cloneValues(args);
        return self.execute(&self.program, function, inputs);
    }
    fn chargeCleanup(self: *Vm, updated: usize) !void {
        if (updated > self.limits.instructions - self.steps) return error.ExecutionInstructionLimit;
        self.steps += updated;
    }
    fn allocate(self: *Vm, count: usize) ![]b.Value {
        return self.context().storage.allocate(count);
    }
    fn entryFunction(self: *Vm, id: g.GlobalFunctionId, args: []const b.Value) !*const b.Function {
        if (@intFromEnum(id) >= self.program.functions.len) return error.InvalidEntry;
        const function = if (self.program.functions[@intFromEnum(id)]) |*value| value else return error.InvalidEntry;
        try self.validateArguments(function, args);
        return function;
    }
    fn validateArguments(self: *Vm, function: *const b.Function, args: []const b.Value) !void {
        if (args.len != function.inputs.len) return error.InvalidArguments;
        // Check against the bounded supported type shape before cloning caller
        // values, so malformed input trees cannot drive unbounded recursion.
        for (args, function.inputs) |value, slot| if (!b.valueFits(self.program.graph, function.slots[slot], value)) return error.InvalidArguments;
    }
    fn frame(self: *Vm, program: *const b.Program, function: *const b.Function, args: []const b.Value, return_slots: []const b.Slot) !Frame {
        const id = try self.context().storage.enterCleanup(function.slots.len, function.cleanup);
        const slots = try self.context().storage.slots(id);
        for (args, function.inputs) |value, slot| try slots.put(slot, value);
        try self.context().storage.charge(function.write_destinations.len);
        const destinations = try self.context().arena.allocator().alloc(?WriteDestination, function.write_destinations.len);
        @memset(destinations, null);
        return .{ .program = program, .function = function, .storage = id, .return_slots = return_slots, .write_destinations = destinations };
    }
    fn resolvePlace(self: *Vm, program: *const b.Program, frame_id: runtime_value.FrameId, place: b.Place, path: *[64]runtime_value.Projection, comptime read_value: bool) !runtime_value.Reference {
        if (place.region == .session) {
            const binding = program.session.?.bindings[place.root].binding;
            const target = self.context().bindings.get(binding) orelse return error.ExecutionUninitializedStorage;
            return self.context().storage.resolveSession(frame_id, target, place, path, read_value);
        }
        return if (read_value) self.context().storage.resolve(frame_id, place, path) else self.context().storage.resolveCleanup(frame_id, place, path);
    }
    fn execute(self: *Vm, program: *const b.Program, function: *const b.Function, args: []const b.Value) ![]const b.Value {
        var frames: std.ArrayList(Frame) = .empty;
        defer frames.deinit(self.allocator);
        // Runtime failures end frame liveness without running user cleanup,
        // matching the current abort policy. Persistent sessions must not
        // treat this path as a recoverable cleanup/unwind protocol.
        defer for (frames.items) |active| self.context().storage.leave(active.storage);
        if (self.limits.call_depth == 0) return error.ExecutionCallDepthLimit;
        try frames.append(self.allocator, try self.frame(program, function, args, &.{}));
        while (true) {
            // Never retain this pointer across a push: the frame array may move.
            const current = &frames.items[frames.items.len - 1];
            const f = current.function;
            const unit = current.program;
            const slots = try self.context().storage.slots(current.storage);
            const inst = f.code[current.pc];
            self.source = inst.source;
            if (self.steps >= self.limits.instructions) return error.ExecutionInstructionLimit;
            self.steps += 1;
            current.pc += 1;
            switch (inst.op) {
                .constant => |x| try slots.put(x.dst, x.value),
                .resolve_location => |x| try slots.put(x.dst, try self.context().resolveTraceLocation((try slots.get(x.id)).integer)),
                .trace_location => |x| try slots.put(x.dst, try self.context().registerTraceLocation(x.location.*)),
                .static_bytes => |x| try slots.put(x.dst, try self.context().literalBytes(x.bytes)),
                .offset_reference => |x| try slots.put(x.dst, .{ .reference = try self.context().storage.offsetReference((try slots.get(x.src)).reference, (try slots.get(x.elements)).integer) }),
                .virtualize => |x| {
                    const receiver = try slots.get(x.receiver);
                    if (receiver != .reference) return error.ExecutionInvalidVirtual;
                    try slots.put(x.dst, try self.context().storage.virtualize(receiver.reference, unit, x.table));
                },
                .virtual_call => |x| {
                    if (frames.items.len >= self.limits.call_depth) return error.ExecutionCallDepthLimit;
                    const pointer = try slots.get(x.handle);
                    if (pointer != .reference) return error.ExecutionInvalidVirtual;
                    const erased = try self.context().storage.read(pointer.reference);
                    if (erased != .virtual_) return error.ExecutionInvalidVirtual;
                    const virtual = erased.virtual_;
                    _ = try self.context().storage.read(virtual.receiver);
                    if (unit.session) |namespace| {
                        const origin = virtual.program.session orelse return error.ExecutionForeignSession;
                        if (namespace.namespace != origin.namespace) return error.ExecutionForeignSession;
                    } else if (virtual.program.session != null or unit.graph != virtual.program.graph) return error.ExecutionForeignSession;
                    // Shared compilation namespaces preserve append-only type IDs.
                    // Either frame can be older; compare in the longer retained prefix.
                    const universe = if (unit.graph.types.items.len >= virtual.program.graph.types.items.len) unit.graph else virtual.program.graph;
                    const selected = virtual.table;
                    const signature = &x.signature;
                    const handle_type = unit.graph.semanticType(f.slots[x.handle]).pointer.child;
                    if (!types.equal(universe, handle_type, selected.virtual_type) or signature.method_count != selected.methods.len) return error.ExecutionInvalidVirtual;
                    const method = selected.methods[signature.method_index];
                    if (method.receiver_input_index != signature.receiver_input_index) return error.ExecutionInvalidVirtual;
                    const callee = &virtual.program.functions[@intFromEnum(method.function)].?;
                    if (callee.inputs.len != x.args.len or callee.outputs.len != x.outputs.len) return error.ExecutionInvalidVirtual;
                    const values = try self.allocate(x.args.len);
                    for (values, x.args, callee.inputs, 0..) |*value, slot, input, index| {
                        if (index == signature.receiver_input_index) {
                            var receiver = virtual.receiver;
                            const permission = virtual.program.graph.semanticType(callee.slots[input]).pointer.mutability;
                            if (permission == .read_write and (pointer.reference.mutability != .read_write or receiver.mutability != .read_write)) return error.ExecutionReadonlyReference;
                            receiver.mutability = permission;
                            value.* = .{ .reference = receiver };
                        } else {
                            if (!types.equal(universe, f.slots[slot], callee.slots[input])) return error.ExecutionInvalidVirtual;
                            value.* = try slots.get(slot);
                        }
                    }
                    for (x.outputs, callee.outputs) |slot, output| {
                        if (!types.equal(universe, f.slots[slot], callee.slots[output])) return error.ExecutionInvalidVirtual;
                    }
                    try frames.append(self.allocator, try self.frame(&virtual.program, callee, values, x.outputs));
                },
                .copy => |x| try slots.put(x.dst, try slots.get(x.src)),
                .session_initialize => |x| try self.context().initializeBinding(unit.session.?.bindings[x.binding], try slots.get(x.value)),
                .session_borrow => |x| try slots.put(x.dst, try self.context().borrowBinding(unit.session.?.bindings[x.binding], unit.graph.semanticType(f.slots[x.dst]).pointer.mutability)),
                .readonly => |x| {
                    var reference = (try slots.get(x.src)).reference;
                    reference.mutability = .read_only;
                    try slots.put(x.dst, .{ .reference = reference });
                },
                .record => |x| {
                    const fields = try self.allocate(x.fields.len);
                    for (fields, x.fields) |*value, slot| value.* = try slots.get(slot);
                    try slots.put(x.dst, .{ .record = fields });
                },
                .array => |x| {
                    const elements = try self.allocate(x.elements.len);
                    for (elements, x.elements) |*value, slot| value.* = try slots.get(slot);
                    try slots.put(x.dst, .{ .array = elements });
                },
                .index => |x| {
                    const elements = (try slots.get(x.base)).array;
                    const index = try Storage.elementIndex((try slots.get(x.index)).integer, elements.len);
                    try slots.put(x.dst, elements[index]);
                },
                .choice => |x| {
                    var payload: ?*const b.Value = null;
                    if (x.payload) |slot| {
                        const cell = try self.allocate(1);
                        cell[0] = try slots.get(slot);
                        payload = &cell[0];
                    }
                    try slots.put(x.dst, .{ .choice = .{ .variant = @intFromEnum(x.variant), .payload = payload } });
                },
                .payload => |x| {
                    const choice = (try slots.get(x.src)).choice;
                    if (choice.variant != @intFromEnum(x.variant) or choice.payload == null) return error.ExecutionInactiveVariant;
                    try slots.put(x.dst, choice.payload.?.*);
                },
                .is_variant => |x| try slots.put(x.dst, .{ .boolean = ((try slots.get(x.src)).choice.variant == @intFromEnum(x.variant)) != x.invert }),
                .branch_variant => |x| current.pc = if ((try slots.get(x.src)).choice.variant == @intFromEnum(x.variant)) x.yes else x.no,
                .borrow => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, true);
                    const permission = unit.graph.semanticType(f.slots[x.dst]).pointer.mutability;
                    try slots.put(x.dst, try self.context().storage.borrow(reference, permission));
                },
                .load => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, true);
                    var value = try self.context().storage.read(reference);
                    // Immutable byte backing is compact and untyped. A typed
                    // load interprets CChar signedness using the target width.
                    if (value == .integer and self.context().storage.frames.items[@intFromEnum(reference.frame)].duration == .static) {
                        if (b.integerBounds(unit.graph, f.slots[x.dst])) |bounds| {
                            if (bounds.maximum - bounds.minimum != 255) return error.ExecutionInvalidReference;
                            value.integer = try integer.evaluate(.addition, value.integer, 0, bounds);
                        }
                    }
                    try slots.put(x.dst, value);
                },
                .check_place => |place| {
                    var path: [64]runtime_value.Projection = undefined;
                    _ = try self.resolvePlace(unit, current.storage, place, &path, true);
                },
                .capture_write => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, true);
                    current.write_destinations[x.dst] = try self.context().storage.captureResolvedWrite(reference, x.activate_cleanup);
                },
                .check_write_cleanup => |id| {
                    const destination = current.write_destinations[id] orelse return error.UninitializedBytecodeDestination;
                    try self.chargeCleanup(try self.context().storage.checkWriteCleanup(destination));
                },
                .store => |x| {
                    const destination = current.write_destinations[x.destination] orelse return error.UninitializedBytecodeDestination;
                    try self.context().storage.write(destination, try slots.get(x.value));
                },
                .activate_write_cleanup => |id| {
                    const destination = current.write_destinations[id] orelse return error.UninitializedBytecodeDestination;
                    current.write_destinations[id] = null;
                    try self.chargeCleanup(try self.context().storage.activateWriteCleanup(destination));
                },
                .cleanup_test => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, false);
                    try slots.put(x.dst, .{ .boolean = try self.context().storage.cleanupTest(reference) });
                },
                .cleanup_set => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, false);
                    // A subtree update performs work without allocating value
                    // cells. Charge its flags too, so a large owner in a loop
                    // cannot turn one instruction into unbounded cleanup work.
                    const updated = try self.context().storage.cleanupSet(reference, x.enabled);
                    try self.chargeCleanup(updated);
                },
                .field => |x| try slots.put(x.dst, (try slots.get(x.base)).record[x.index]),
                .binary => |x| {
                    const left = (try slots.get(x.left)).integer;
                    const right = (try slots.get(x.right)).integer;
                    const range = b.integerBounds(unit.graph, f.slots[x.dst]).?;
                    const n = integer.evaluate(x.operator, left, right, range) catch return error.ExecutionDivisionByZero;
                    try slots.put(x.dst, .{ .integer = n });
                },
                .compare => |x| {
                    const left = try slots.get(x.left);
                    const right = try slots.get(x.right);
                    const yes = if (left == .choice) switch (x.operator) {
                        .equal => left.choice.variant == right.choice.variant,
                        .not_equal => left.choice.variant != right.choice.variant,
                        else => unreachable,
                    } else if (left == .boolean) switch (x.operator) {
                        .equal => left.boolean == right.boolean,
                        .not_equal => left.boolean != right.boolean,
                        else => unreachable,
                    } else switch (x.operator) {
                        .equal => left.integer == right.integer,
                        .not_equal => left.integer != right.integer,
                        .less_than => left.integer < right.integer,
                        .less_than_or_equal => left.integer <= right.integer,
                        .greater_than => left.integer > right.integer,
                        .greater_than_or_equal => left.integer >= right.integer,
                    };
                    try slots.put(x.dst, .{ .boolean = yes });
                },
                .call => |x| {
                    if (frames.items.len >= self.limits.call_depth) return error.ExecutionCallDepthLimit;
                    const values = try self.allocate(x.args.len);
                    for (values, x.args) |*value, slot| value.* = try slots.get(slot);
                    const callee = &unit.functions[@intFromEnum(x.function)].?;
                    try frames.append(self.allocator, try self.frame(unit, callee, values, x.outputs));
                },
                .branch => |x| current.pc = if ((try slots.get(x.condition)).boolean) x.yes else x.no,
                .jump => |target| current.pc = target,
                .ret => |outputs| {
                    const result = try self.allocate(outputs.len);
                    for (result, outputs) |*value, slot| value.* = try slots.get(slot);
                    const completed = frames.pop().?;
                    self.context().storage.leave(completed.storage);
                    try self.context().storage.validateLive(result);
                    if (frames.items.len == 0) return result;
                    const caller = try self.context().storage.slots(frames.items[frames.items.len - 1].storage);
                    for (completed.return_slots, result) |dst, value| try caller.put(dst, value);
                },
                .abort_ => return error.ExecutionAborted,
            }
        }
    }
};

test "source metadata resolution rejects invalid IDs and retains immutable text" {
    var context = Context.init(std.testing.allocator, 1024);
    defer context.deinit();
    _ = try context.sessionSlots(1, &.{});
    const id = try context.registerTraceLocation(.{ .path = "input.rg", .offset = 3, .line = 2, .column = 1, .source_line = "ñ" });
    const duplicate = try context.registerTraceLocation(.{ .path = "input.rg", .offset = 3, .line = 2, .column = 1, .source_line = "ñ" });
    try std.testing.expectEqual(id.integer, duplicate.integer);
    const resolved = try context.resolveTraceLocation(id.integer);
    try std.testing.expectEqual(@as(i128, 2), resolved.record[2].integer);
    try std.testing.expectEqual(@as(i128, 1), resolved.record[3].integer);
    const text = resolved.record[1].reference;
    try std.testing.expectEqual(@as(i128, 0xc3), (try context.storage.readOffset(text, 0)).integer);
    try std.testing.expectEqual(@as(i128, 0xb1), (try context.storage.readOffset(text, 1)).integer);
    try std.testing.expectEqual(@as(i128, 0), (try context.storage.readOffset(text, 2)).integer);
    try std.testing.expectError(error.ExecutionReadonlyReference, context.storage.borrow(text, .read_write));
    try std.testing.expectError(error.ExecutionInvalidSourceLocation, context.resolveTraceLocation(-1));
    try std.testing.expectError(error.ExecutionInvalidSourceLocation, context.resolveTraceLocation(1));
}

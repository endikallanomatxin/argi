const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const integer = @import("../5_codegen/integer_arithmetic.zig");
const Storage = @import("storage.zig").Storage;
const WriteDestination = @import("storage.zig").WriteDestination;
const runtime_value = @import("../5_codegen/bytecode/value.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const host = @import("host.zig");

/// Host-owned cooperative cancellation. Sharing this flag grants no permission
/// to share language values or mutate an executing context from another thread.
/// The token must outlive every invocation borrowing it; reset only while idle.
pub const Cancellation = struct {
    requested: std.atomic.Value(bool) = .init(false),

    pub fn cancel(self: *Cancellation) void {
        self.requested.store(true, .monotonic);
    }
    pub fn reset(self: *Cancellation) void {
        self.requested.store(false, .monotonic);
    }
    pub fn isCancelled(self: *const Cancellation) bool {
        return self.requested.load(.monotonic);
    }
};

pub const Limits = struct {
    instructions: usize = 1_000_000,
    call_depth: usize = 128,
    cancellation: ?*const Cancellation = null,
    // Cumulative value cells, including frames and record snapshots. This bounds
    // the execution arena even when a loop repeatedly creates short-lived values.
    value_cells: usize = 1_000_000,
};

const Frame = struct {
    program: *const b.Program,
    function: *const b.Function,
    host_bindings: []const host.Binding,
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
    const GlobalKey = struct { session: bool, owner: u64, binding: g.GlobalBindingId };
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    storage: Storage = undefined,
    limit: usize,
    host_bindings: []const host.Binding = &.{},
    state: enum { fresh, ready, poisoned } = .fresh,
    running: bool = false,
    namespace: ?b.SessionNamespace = null,
    bindings: std.AutoHashMapUnmanaged(g.GlobalBindingId, runtime_value.FrameId) = .empty,
    globals: std.AutoHashMapUnmanaged(GlobalKey, runtime_value.FrameId) = .empty,
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
    /// Host-side acquisition protocol only. These receipts cannot be supplied
    /// as language references or frozen into compile-time constants.
    pub fn acquireRegion(self: *Context, length: usize, alignment: usize) !@import("acquisitions.zig").Handle {
        if (self.running) return error.ExecutionContextBusy;
        try self.ensureStorage();
        return self.storage.acquisitions.acquire(&self.storage, length, alignment);
    }
    pub fn readRegion(self: *Context, handle: @import("acquisitions.zig").Handle, offset: usize, destination: []u8) !void {
        if (self.running) return error.ExecutionContextBusy;
        try self.ensureStorage();
        return self.storage.acquisitions.read(&self.storage, handle, offset, destination);
    }
    pub fn writeRegion(self: *Context, handle: @import("acquisitions.zig").Handle, offset: usize, source: []const u8) !void {
        if (self.running) return error.ExecutionContextBusy;
        try self.ensureStorage();
        return self.storage.acquisitions.write(&self.storage, handle, offset, source);
    }
    pub fn releaseRegion(self: *Context, handle: @import("acquisitions.zig").Handle) !void {
        if (self.running) return error.ExecutionContextBusy;
        try self.ensureStorage();
        return self.storage.acquisitions.release(&self.storage, handle);
    }
    pub fn deinit(self: *Context) void {
        std.debug.assert(!self.running);
        self.arena.deinit();
        self.* = undefined;
    }
    /// Detach all arena-backed indexes together. Fresh execution keeps the old
    /// arena alive while copying supplied arguments; reset releases it at once.
    fn detachStorage(self: *Context) std.heap.ArenaAllocator {
        std.debug.assert(!self.running);
        const previous = self.arena;
        self.arena = .init(self.allocator);
        self.state = .fresh;
        self.namespace = null;
        self.bindings = .empty;
        self.globals = .empty;
        self.literal_bytes = .empty;
        self.trace_locations = .empty;
        return previous;
    }

    pub fn reset(self: *Context) void {
        var previous = self.detachStorage();
        previous.deinit();
    }

    fn checkNamespace(self: *const Context, session: ?b.Session) !void {
        if (session) |interface| if (self.namespace) |namespace| {
            if (namespace != interface.namespace) return error.ExecutionForeignSession;
        };
    }
    fn globalKey(program: *const b.Program, binding: g.GlobalBindingId) GlobalKey {
        return .{ .session = program.session != null, .owner = if (program.session) |session| @intFromEnum(session.namespace) else @intFromPtr(program.graph), .binding = binding };
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

    fn declareBinding(self: *Context, binding: b.SessionBinding) !void {
        if (self.bindings.contains(binding.binding)) return error.ExecutionInitializedStorage;
        try self.storage.charge(1);
        try self.bindings.ensureUnusedCapacity(self.arena.allocator(), 1);
        const target = try self.storage.enterSession(1, binding.cleanup);
        self.bindings.putAssumeCapacity(binding.binding, target.frame);
    }
    fn initializeBinding(self: *Context, binding: b.SessionBinding, value: b.Value, reinitialize: bool) !void {
        if (!self.bindings.contains(binding.binding)) try self.declareBinding(binding);
        const target = try self.storage.slots(self.bindings.get(binding.binding).?);
        if (reinitialize) try self.storage.reinitializeSession(target, 0, value) else try self.storage.initializeSession(target, 0, value);
    }
};

pub const max_failure_frames = 64;
pub const FailureFrame = struct { graph: *const g.GlobalSemanticGraph, source: p.SourceRef };

pub const Vm = struct {
    allocator: std.mem.Allocator,
    program: b.Program,
    limits: Limits,
    steps: usize = 0,
    failure_trace: std.ArrayList(FailureFrame) = .empty,
    linked_hosts: host.LinkedPrograms = .{},
    input_layouts: @import("input_layout.zig").Inputs,
    owned_context: Context,
    shared_context: ?*Context = null,
    source: p.SourceRef = .{ .file_index = 0, .offset = 0 },

    // Verify before executing anything, including before checking the entry.
    pub fn init(a: std.mem.Allocator, program: b.Program, limits: Limits) !Vm {
        return initWithHost(a, program, limits, &.{});
    }
    pub fn initWithHost(a: std.mem.Allocator, program: b.Program, limits: Limits, bindings: []const host.Binding) !Vm {
        try b.verify(a, program);
        var linked: host.LinkedPrograms = .{};
        errdefer linked.deinit(a);
        _ = try linked.get(a, &program, bindings);
        var context_ = Context.init(a, limits.value_cells);
        context_.host_bindings = bindings;
        return .{ .input_layouts = try @import("input_layout.zig").Inputs.init(a, program), .linked_hosts = linked, .owned_context = context_, .allocator = a, .program = program, .limits = limits };
    }
    /// Borrow session-owned execution storage without transferring it. The
    /// memory quota belongs to that context; instruction/depth limits are local
    /// to each invocation. Fresh-run convenience APIs are unavailable here.
    pub fn initShared(a: std.mem.Allocator, program: b.Program, limits: Limits, shared: *Context) !Vm {
        if (limits.value_cells != shared.limit) return error.ExecutionContextLimitMismatch;
        try b.verify(a, program);
        var linked: host.LinkedPrograms = .{};
        errdefer linked.deinit(a);
        _ = try linked.get(a, &program, shared.host_bindings);
        return .{ .input_layouts = try @import("input_layout.zig").Inputs.init(a, program), .linked_hosts = linked, .owned_context = undefined, .shared_context = shared, .allocator = a, .program = program, .limits = limits };
    }
    pub fn context(self: *Vm) *Context {
        return self.shared_context orelse &self.owned_context;
    }
    pub fn deinit(self: *Vm) void {
        self.failure_trace.deinit(self.allocator);
        self.input_layouts.deinit();
        self.linked_hosts.deinit(self.allocator);
        if (self.shared_context == null) self.owned_context.deinit();
    }
    // Session owners must run checked exit cleanup before resetting a healthy
    // context. A trapped context has no resumable cleanup/unwind guarantee.
    pub fn reset(self: *Vm) void {
        self.context().reset();
        self.failure_trace.clearRetainingCapacity();
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
        var previous = self.context().detachStorage();
        defer previous.deinit();
        return if (entry) |id| self.invoke(id, args) else self.invokeExpression(args);
    }

    // Invoke within retained execution storage. Calls share the memory budget
    // and context identity; each invocation receives a fresh instruction budget.
    // Program validation and ordinary safety checking are not repeated here.
    pub fn invoke(self: *Vm, entry: g.GlobalFunctionId, args: []const b.Value) ![]const b.Value {
        self.failure_trace.clearRetainingCapacity();
        if (self.context().state == .poisoned) return error.ExecutionContextPoisoned;
        const function = try self.entryFunction(entry, args);
        return self.invokeFunction(function, args);
    }
    pub fn invokeExpression(self: *Vm, args: []const b.Value) ![]const b.Value {
        self.failure_trace.clearRetainingCapacity();
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
        for (self.program.globals) |global| {
            const key = Context.globalKey(&self.program, global.binding);
            if (self.context().globals.contains(key)) continue;
            const initialized = try self.execute(&self.program, &global.initializer, &.{});
            if (initialized.len != 1) return error.InvalidBytecode;
            const storage = try self.context().storage.enterSession(1, &.{});
            try self.context().storage.initializeSession(storage, 0, initialized[0]);
            try self.context().storage.charge(1);
            try self.context().globals.put(self.context().arena.allocator(), key, storage.frame);
        }
        return self.execute(&self.program, function, inputs);
    }
    fn chargeCleanup(self: *Vm, work: usize) !void {
        if (work > self.limits.instructions - self.steps) return error.ExecutionInstructionLimit;
        self.steps += work;
    }
    fn allocate(self: *Vm, count: usize) ![]b.Value {
        return self.context().storage.allocate(count);
    }
    fn entryFunction(self: *Vm, id: g.GlobalFunctionId, args: []const b.Value) !*const b.Function {
        if (@intFromEnum(id) >= self.program.functions.len) return error.InvalidEntry;
        const function = if (self.program.functions[@intFromEnum(id)]) |value| value else return error.InvalidEntry;
        try self.validateArguments(function, args);
        return function;
    }
    fn validateArguments(self: *Vm, function: *const b.Function, args: []const b.Value) !void {
        if (!self.input_layouts.accepts(function, args)) return error.InvalidArguments;
    }
    fn frame(self: *Vm, program: *const b.Program, function: *const b.Function, args: []const b.Value, return_slots: []const b.Slot) !Frame {
        const linked = try self.linked_hosts.get(self.allocator, program, self.context().host_bindings);
        const id = try self.context().storage.enterCleanup(function.slots.len, function.cleanup);
        const slots = try self.context().storage.slots(id);
        for (args, function.inputs) |value, slot| try slots.put(slot, value);
        try self.context().storage.charge(function.write_destinations.len);
        const destinations = try self.context().arena.allocator().alloc(?WriteDestination, function.write_destinations.len);
        @memset(destinations, null);
        return .{ .program = program, .function = function, .host_bindings = linked, .storage = id, .return_slots = return_slots, .write_destinations = destinations };
    }
    fn resolvePlace(self: *Vm, program: *const b.Program, frame_id: runtime_value.FrameId, place: b.Place, path: *[64]runtime_value.Projection, comptime read_value: bool) !runtime_value.Reference {
        if (place.region == .global) {
            const key = Context.globalKey(program, @enumFromInt(place.root));
            const target = self.context().globals.get(key) orelse return error.ExecutionUninitializedStorage;
            var persistent = place;
            persistent.root = 0;
            persistent.region = .session;
            return self.context().storage.resolveSession(frame_id, target, persistent, path, read_value);
        }
        if (place.region == .session) {
            const binding = program.session.?.bindings[place.root].binding;
            const target = self.context().bindings.get(binding) orelse return error.ExecutionUninitializedStorage;
            return self.context().storage.resolveSession(frame_id, target, place, path, read_value);
        }
        return if (read_value) self.context().storage.resolve(frame_id, place, path) else self.context().storage.resolveCleanup(frame_id, place, path);
    }
    fn captureFailure(self: *Vm, frames: []const Frame) void {
        // Diagnostics are best-effort under allocation failure. Retain only
        // borrowed code metadata, never language values or live frame storage.
        self.failure_trace.clearRetainingCapacity();
        var index = frames.len;
        while (index != 0 and self.failure_trace.items.len < max_failure_frames) {
            index -= 1;
            const active = frames[index];
            const source = if (index == frames.len - 1) self.source else blk: {
                if (active.pc == 0 or active.pc > active.function.code.len) break :blk self.source;
                break :blk active.function.code[active.pc - 1].source;
            };
            self.failure_trace.append(self.allocator, .{ .graph = active.program.graph, .source = source }) catch return;
        }
    }

    fn execute(self: *Vm, program: *const b.Program, function: *const b.Function, args: []const b.Value) ![]const b.Value {
        var frames: std.ArrayList(Frame) = .empty;
        defer frames.deinit(self.allocator);
        // Runtime failures end frame liveness without running user cleanup,
        // matching the current abort policy. Persistent sessions must not
        // treat this path as a recoverable cleanup/unwind protocol.
        defer for (frames.items) |active| self.context().storage.leave(active.storage);
        errdefer self.captureFailure(frames.items);
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
            // Stop only between verified instructions. Host adapters must
            // provide their own interruption for a blocking native operation.
            if (self.limits.cancellation) |token| if (token.isCancelled()) return error.ExecutionCancelled;
            if (self.steps >= self.limits.instructions) return error.ExecutionInstructionLimit;
            self.steps += 1;
            current.pc += 1;
            switch (inst.op) {
                .reserve_storage => |x| {
                    if (x.reset) {
                        try self.chargeCleanup(try self.context().storage.resetStorage(current.storage, x.dst, x.layout));
                    } else try self.context().storage.prepareStorage(current.storage, x.dst, x.layout);
                },
                .borrow_storage => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, false);
                    try slots.put(x.dst, try self.context().storage.address(reference, x.permission));
                },
                .constant => |x| try slots.put(x.dst, x.value),
                .resolve_location => |x| try slots.put(x.dst, try self.context().resolveTraceLocation((try slots.get(x.id)).integer)),
                .trace_location => |x| try slots.put(x.dst, try self.context().registerTraceLocation(x.location.*)),
                .static_bytes => |x| try slots.put(x.dst, try self.context().literalBytes(x.bytes)),
                .numeric_bytes => |x| {
                    var reference = try self.context().storage.numericBytes((try slots.get(x.src)).reference, x.layout, x.endian);
                    reference.mutability = x.permission;
                    try slots.put(x.dst, .{ .reference = reference });
                },
                // The verifier fixes this input to UIntNative: its bits already
                // express a nonnegative count, independent of target width.
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
                    if (!types.equal(universe, signature.virtual_type, selected.virtual_type) or signature.method_count != selected.methods.len) return error.ExecutionInvalidVirtual;
                    const method = selected.methods[signature.method_index];
                    if (method.receiver_input_index != signature.receiver_input_index) return error.ExecutionInvalidVirtual;
                    const callee = virtual.program.functions[@intFromEnum(method.function)].?;
                    if (callee.inputs.len != x.args.len or callee.outputs.len != x.outputs.len) return error.ExecutionInvalidVirtual;
                    const values = try self.allocate(x.args.len);
                    for (values, x.args, callee.inputs, 0..) |*value, slot, input, index| {
                        if (index == signature.receiver_input_index) {
                            var receiver = virtual.receiver;
                            const permission = method.receiver_permission;
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
                .acquired_reference => |x| {
                    const address = std.math.cast(usize, (try slots.get(x.address)).integer) orelse return error.ExecutionInvalidAcquisition;
                    const storage = &self.context().storage;
                    const range = try storage.acquisitions.resolveAddress(storage, address, x.layout.size, x.layout.alignment);
                    const logical_index: ?u64 = if (x.logical_index) |selection| blk: {
                        const value = (try slots.get(selection.value)).choice;
                        break :blk if (value.variant == selection.some_ordinal) value.payload.?.record[0].integer else null;
                    } else null;
                    const reference = try storage.acquiredReference(range.handle, range.offset, x.layout, x.endian, x.permission, logical_index);
                    try slots.put(x.dst, .{ .reference = reference });
                },
                .erase_reference => |x| {
                    const original = (try slots.get(x.src)).reference;
                    try slots.put(x.dst, try self.context().storage.address(original, .read_only));
                },
                .memory_call => |x| {
                    const storage = &self.context().storage;
                    switch (x.operation) {
                        .allocate => |signature| {
                            const size = std.math.cast(usize, (try slots.get(x.args[signature.size])).integer) orelse return error.ExecutionMemoryLimit;
                            const alignment = if (signature.alignment) |index| std.math.cast(usize, (try slots.get(x.args[index])).integer) orelse return error.ExecutionInvalidAlignment else @alignOf(u128);
                            const acquired = storage.acquisitions.acquire(storage, size, alignment) catch |err| switch (err) {
                                error.OutOfMemory => {
                                    try slots.put(x.outputs[0], .{ .integer = 0 });
                                    continue;
                                },
                                else => return err,
                            };
                            const address = try storage.acquisitions.address(storage, acquired, 0);
                            try slots.put(x.outputs[0], .{ .integer = address });
                        },
                        .release => {
                            const address = std.math.cast(usize, (try slots.get(x.args[0])).integer) orelse return error.ExecutionInvalidAcquisition;
                            if (address != 0) {
                                const acquired = try storage.acquisitions.resolveAddress(storage, address, 0, 1);
                                if (acquired.offset != 0) return error.ExecutionInvalidAcquisition;
                                try storage.acquisitions.release(storage, acquired.handle);
                            }
                        },
                    }
                },
                .host_call => |x| {
                    const binding = current.host_bindings[x.function];
                    var arguments: [host.max_values]i128 = undefined;
                    var results: [host.max_values]i128 = undefined;
                    for (binding.outputs, 0..) |range, index| results[index] = range.minimum - 1;
                    for (x.args[0 .. x.args.len - 1], binding.inputs, 0..) |slot, range, index| arguments[index] = integer.decode((try slots.get(slot)).integer, range);
                    // The logical ffi reference has already participated in
                    // checked argument evaluation. It never crosses this bridge.
                    _ = try slots.get(x.args[x.args.len - 1]);
                    try binding.call(binding.data, arguments[0..binding.inputs.len], results[0..binding.outputs.len]);
                    for (results[0..binding.outputs.len], binding.outputs) |value, range|
                        if (value < range.minimum or value > range.maximum) return error.ExecutionInvalidHostResult;
                    // Validate every output before changing any destination.
                    for (x.outputs, results[0..binding.outputs.len], binding.outputs) |slot, value, range| try slots.put(slot, .{ .integer = integer.encode(value, range) });
                },
                .copy => |x| try slots.put(x.dst, try slots.get(x.src)),
                .session_declare => |x| {
                    const binding = unit.session.?.bindings[x.binding];
                    try self.context().declareBinding(binding);
                    if (x.layout) |layout| try self.context().storage.prepareStorage(self.context().bindings.get(binding.binding).?, 0, layout);
                },
                .session_initialize => |x| try self.context().initializeBinding(unit.session.?.bindings[x.binding], try slots.get(x.value), x.reinitialize),
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
                    const index = try Storage.elementIndex(integer.decode((try slots.get(x.index)).integer, x.kind.bounds().?), elements.len);
                    try slots.put(x.dst, elements[index]);
                },
                .choice => |x| {
                    var payload: ?*const b.Value = null;
                    if (x.payload) |slot| {
                        const cell = try self.allocate(1);
                        cell[0] = try slots.get(slot);
                        payload = &cell[0];
                    }
                    try slots.put(x.dst, .{ .choice = .{ .variant = x.ordinal, .payload = payload } });
                },
                .payload => |x| {
                    const choice = (try slots.get(x.src)).choice;
                    if (choice.variant != x.ordinal or choice.payload == null) return error.ExecutionInactiveVariant;
                    try slots.put(x.dst, choice.payload.?.*);
                },
                .is_variant => |x| try slots.put(x.dst, .{ .boolean = ((try slots.get(x.src)).choice.variant == x.ordinal) != x.invert }),
                .branch_storage_variant => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, false);
                    current.pc = if (try self.context().storage.choiceTag(reference) == x.ordinal) x.yes else x.no;
                },
                .branch_variant => |x| current.pc = if ((try slots.get(x.src)).choice.variant == x.ordinal) x.yes else x.no,
                .borrow => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, true);
                    try slots.put(x.dst, try self.context().storage.borrow(reference, x.permission));
                },
                .load => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, true);
                    var value = try self.context().storage.read(reference);
                    // Reading an erased anchor checks its actual referent, but
                    // cannot expose that referent's concrete representation.
                    if (x.interpretation == .erased) value = .erased;
                    // Immutable byte backing is compact and untyped. A typed
                    // load interprets CChar signedness using the target width.
                    if (value == .integer and self.context().storage.frames.items[@intFromEnum(reference.frame)].duration == .static) {
                        const bounds = switch (x.interpretation) {
                            .signed_byte => b.ScalarKind.i8.bounds().?,
                            .unsigned_byte => b.ScalarKind.u8.bounds().?,
                            else => return error.ExecutionInvalidReference,
                        };
                        value.integer = try integer.evaluateBits(.addition, value.integer, 0, bounds);
                    }
                    try slots.put(x.dst, value);
                },
                .check_place => |place| {
                    var path: [64]runtime_value.Projection = undefined;
                    _ = try self.resolvePlace(unit, current.storage, place, &path, false);
                },
                .relocate => |x| {
                    const source = (try slots.get(x.source)).reference;
                    const destination = (try slots.get(x.destination)).reference;
                    try self.chargeCleanup(try self.context().storage.relocate(source, destination));
                },
                .capture_write => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, false);
                    const destination = try self.context().storage.captureWriteEvidence(reference, x.activate_cleanup, x.require_cleanup);
                    current.write_destinations[x.dst] = destination;
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
                .branch_cleanup => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.resolvePlace(unit, current.storage, x.place, &path, false);
                    current.pc = if (if (x.access == .present) try self.context().storage.cleanupPresent(reference) else try self.context().storage.cleanupTest(reference)) x.yes else x.no;
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
                    const left_value = try slots.get(x.left);
                    const right_value = try slots.get(x.right);
                    if (x.kind.floating()) {
                        const result = try floatValue(left_value).binary(x.operator, floatValue(right_value));
                        try slots.put(x.dst, fromFloatValue(result));
                        continue;
                    }
                    const left = (try slots.get(x.left)).integer;
                    const right = (try slots.get(x.right)).integer;
                    const range = x.kind.bounds().?;
                    const n = integer.evaluateBits(x.operator, left, right, range) catch return error.ExecutionDivisionByZero;
                    try slots.put(x.dst, .{ .integer = n });
                },
                .compare => |x| {
                    const left = try slots.get(x.left);
                    const right = try slots.get(x.right);
                    const yes = if (x.kind.floating())
                        try floatValue(left).compare(x.operator, floatValue(right))
                    else if (x.kind == .choice) switch (x.operator) {
                        .equal => left.choice.variant == right.choice.variant,
                        .not_equal => left.choice.variant != right.choice.variant,
                        else => unreachable,
                    } else if (x.kind == .boolean) switch (x.operator) {
                        .equal => left.boolean == right.boolean,
                        .not_equal => left.boolean != right.boolean,
                        else => unreachable,
                    } else integer.compareBits(x.operator, left.integer, right.integer, x.kind.bounds().?);
                    try slots.put(x.dst, .{ .boolean = yes });
                },
                .call => |x| {
                    if (frames.items.len >= self.limits.call_depth) return error.ExecutionCallDepthLimit;
                    const values = try self.allocate(x.args.len);
                    for (values, x.args) |*value, slot| value.* = try slots.get(slot);
                    const callee = unit.functions[@intFromEnum(x.function)].?;
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
                .trap => |reason| return switch (reason) {
                    .runtime_storage => error.RuntimeStorageInCompileTime,
                },
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

fn floatValue(value: b.Value) @import("../5_codegen/numeric_value.zig").Value {
    return switch (value) {
        inline .float16, .float32, .float64 => |number, kind| @unionInit(@import("../5_codegen/numeric_value.zig").Value, @tagName(kind), number),
        else => unreachable,
    };
}

fn fromFloatValue(value: @import("../5_codegen/numeric_value.zig").Value) b.Value {
    return switch (value) {
        inline .float16, .float32, .float64 => |number, kind| @unionInit(b.Value, @tagName(kind), number),
    };
}

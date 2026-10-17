const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const g = @import("../4_semantics/global/graph.zig");
const integer = @import("../5_codegen/integer_arithmetic.zig");
const Storage = @import("storage.zig").Storage;
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
    function: *const b.Function,
    storage: runtime_value.FrameId,
    pc: usize = 0,
    return_slots: []const b.Slot,
};

pub const Vm = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    program: b.Program,
    limits: Limits,
    steps: usize = 0,
    storage: Storage = undefined,
    source: p.SourceRef = .{ .file_index = 0, .offset = 0 },

    // Verify before executing anything, including before checking the entry.
    pub fn init(a: std.mem.Allocator, program: b.Program, limits: Limits) !Vm {
        try b.verify(a, program);
        return .{ .arena = std.heap.ArenaAllocator.init(a), .allocator = a, .program = program, .limits = limits };
    }
    pub fn deinit(self: *Vm) void {
        self.arena.deinit();
    }
    pub fn run(self: *Vm, entry: g.GlobalFunctionId, args: []const b.Value) ![]const b.Value {
        // Results belong to the execution arena until the next run or deinit.
        var previous = self.arena;
        self.arena = std.heap.ArenaAllocator.init(self.allocator);
        defer previous.deinit();
        self.steps = 0;
        self.storage = try Storage.init(self.arena.allocator(), self.limits.value_cells);
        const function = try self.entryFunction(entry, args);
        const inputs = try self.cloneValues(args);
        return self.execute(function, inputs);
    }
    fn cloneValues(self: *Vm, values: []const b.Value) anyerror![]const b.Value {
        const result = try self.allocate(values.len);
        for (result, values) |*out, value| out.* = switch (value) {
            .array => |elements| .{ .array = try self.cloneValues(elements) },
            .record => |fields| .{ .record = try self.cloneValues(fields) },
            .choice => |choice| .{ .choice = .{
                .variant = choice.variant,
                .payload = if (choice.payload) |payload| &(try self.cloneValues(payload[0..1]))[0] else null,
            } },
            else => value,
        };
        return result;
    }
    fn allocate(self: *Vm, count: usize) ![]b.Value {
        return self.storage.allocate(count);
    }
    fn entryFunction(self: *Vm, id: g.GlobalFunctionId, args: []const b.Value) !*const b.Function {
        if (@intFromEnum(id) >= self.program.functions.len) return error.InvalidEntry;
        const function = if (self.program.functions[@intFromEnum(id)]) |*value| value else return error.InvalidEntry;
        if (args.len != function.inputs.len) return error.InvalidArguments;
        // Check against the bounded supported type shape before cloning caller
        // values, so malformed input trees cannot drive unbounded recursion.
        for (args, function.inputs) |value, slot| if (!b.valueFits(self.program.graph, function.slots[slot], value)) return error.InvalidArguments;
        return function;
    }
    fn frame(self: *Vm, function: *const b.Function, args: []const b.Value, return_slots: []const b.Slot) !Frame {
        const id = try self.storage.enterCleanup(function.slots.len, function.cleanup);
        const slots = try self.storage.slots(id);
        for (args, function.inputs) |value, slot| try slots.put(slot, value);
        return .{ .function = function, .storage = id, .return_slots = return_slots };
    }
    fn execute(self: *Vm, function: *const b.Function, args: []const b.Value) ![]const b.Value {
        var frames: std.ArrayList(Frame) = .empty;
        defer frames.deinit(self.allocator);
        // Runtime failures end frame liveness without running user cleanup,
        // matching the current abort policy. Persistent sessions must not
        // treat this path as a recoverable cleanup/unwind protocol.
        defer for (frames.items) |active| self.storage.leave(active.storage);
        if (self.limits.call_depth == 0) return error.ExecutionCallDepthLimit;
        try frames.append(self.allocator, try self.frame(function, args, &.{}));
        while (true) {
            // Never retain this pointer across a push: the frame array may move.
            const current = &frames.items[frames.items.len - 1];
            const f = current.function;
            const slots = try self.storage.slots(current.storage);
            const inst = f.code[current.pc];
            self.source = inst.source;
            if (self.steps >= self.limits.instructions) return error.ExecutionInstructionLimit;
            self.steps += 1;
            current.pc += 1;
            switch (inst.op) {
                .constant => |x| try slots.put(x.dst, x.value),
                .copy => |x| try slots.put(x.dst, try slots.get(x.src)),
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
                    const reference = try self.storage.resolve(current.storage, x.place, &path);
                    const permission = self.program.graph.semanticType(f.slots[x.dst]).pointer.mutability;
                    try slots.put(x.dst, try self.storage.borrow(reference, permission));
                },
                .load => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    try slots.put(x.dst, try self.storage.read(try self.storage.resolve(current.storage, x.place, &path)));
                },
                .check_place => |place| {
                    var path: [64]runtime_value.Projection = undefined;
                    _ = try self.storage.resolve(current.storage, place, &path);
                },
                .store => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.storage.resolve(current.storage, x.place, &path);
                    try self.storage.store(reference, try slots.get(x.value));
                },
                .cleanup_test => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.storage.resolveCleanup(current.storage, x.place, &path);
                    try slots.put(x.dst, .{ .boolean = try self.storage.cleanupTest(reference) });
                },
                .cleanup_set => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.storage.resolveCleanup(current.storage, x.place, &path);
                    // A subtree update performs work without allocating value
                    // cells. Charge its flags too, so a large owner in a loop
                    // cannot turn one instruction into unbounded cleanup work.
                    const updated = try self.storage.cleanupSet(reference, x.enabled);
                    if (updated > self.limits.instructions - self.steps) return error.ExecutionInstructionLimit;
                    self.steps += updated;
                },
                .field => |x| try slots.put(x.dst, (try slots.get(x.base)).record[x.index]),
                .binary => |x| {
                    const left = (try slots.get(x.left)).integer;
                    const right = (try slots.get(x.right)).integer;
                    const range = b.integerBounds(self.program.graph, f.slots[x.dst]).?;
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
                    const callee = &self.program.functions[@intFromEnum(x.function)].?;
                    try frames.append(self.allocator, try self.frame(callee, values, x.outputs));
                },
                .branch => |x| current.pc = if ((try slots.get(x.condition)).boolean) x.yes else x.no,
                .jump => |target| current.pc = target,
                .ret => |outputs| {
                    const result = try self.allocate(outputs.len);
                    for (result, outputs) |*value, slot| value.* = try slots.get(slot);
                    const completed = frames.pop().?;
                    self.storage.leave(completed.storage);
                    try self.storage.validateLive(result);
                    if (frames.items.len == 0) return result;
                    const caller = try self.storage.slots(frames.items[frames.items.len - 1].storage);
                    for (completed.return_slots, result) |dst, value| try caller.put(dst, value);
                },
                .abort_ => return error.ExecutionAborted,
            }
        }
    }
};

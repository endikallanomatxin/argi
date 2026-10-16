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
        self.storage = .{ .allocator = self.arena.allocator(), .limit = self.limits.value_cells };
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
        const id = try self.storage.enter(function.slots.len);
        const slots = try self.storage.slots(id);
        for (args, function.inputs) |value, slot| slots[slot] = value;
        return .{ .function = function, .storage = id, .return_slots = return_slots };
    }
    fn execute(self: *Vm, function: *const b.Function, args: []const b.Value) ![]const b.Value {
        var frames: std.ArrayList(Frame) = .empty;
        defer frames.deinit(self.allocator);
        // Runtime failures unwind frame liveness as well. Resource cleanup is
        // still unsupported; no destructor can be skipped by this path.
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
                .constant => |x| slots[x.dst] = x.value,
                .copy => |x| slots[x.dst] = slots[x.src],
                .readonly => |x| {
                    var reference = slots[x.src].reference;
                    reference.mutability = .read_only;
                    slots[x.dst] = .{ .reference = reference };
                },
                .record => |x| {
                    const fields = try self.allocate(x.fields.len);
                    for (fields, x.fields) |*value, slot| value.* = slots[slot];
                    slots[x.dst] = .{ .record = fields };
                },
                .array => |x| {
                    const elements = try self.allocate(x.elements.len);
                    for (elements, x.elements) |*value, slot| value.* = slots[slot];
                    slots[x.dst] = .{ .array = elements };
                },
                .index => |x| {
                    const elements = slots[x.base].array;
                    const index = try Storage.elementIndex(slots[x.index].integer, elements.len);
                    slots[x.dst] = elements[index];
                },
                .choice => |x| {
                    var payload: ?*const b.Value = null;
                    if (x.payload) |slot| {
                        const cell = try self.allocate(1);
                        cell[0] = slots[slot];
                        payload = &cell[0];
                    }
                    slots[x.dst] = .{ .choice = .{ .variant = @intFromEnum(x.variant), .payload = payload } };
                },
                .payload => |x| {
                    const choice = slots[x.src].choice;
                    if (choice.variant != @intFromEnum(x.variant) or choice.payload == null) return error.ExecutionInactiveVariant;
                    slots[x.dst] = choice.payload.?.*;
                },
                .is_variant => |x| slots[x.dst] = .{ .boolean = (slots[x.src].choice.variant == @intFromEnum(x.variant)) != x.invert },
                .branch_variant => |x| current.pc = if (slots[x.src].choice.variant == @intFromEnum(x.variant)) x.yes else x.no,
                .borrow => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.storage.resolve(current.storage, x.place, &path);
                    const permission = self.program.graph.semanticType(f.slots[x.dst]).pointer.mutability;
                    slots[x.dst] = try self.storage.borrow(reference, permission);
                },
                .load => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    slots[x.dst] = try self.storage.read(try self.storage.resolve(current.storage, x.place, &path));
                },
                .check_place => |place| {
                    var path: [64]runtime_value.Projection = undefined;
                    _ = try self.storage.resolve(current.storage, place, &path);
                },
                .store => |x| {
                    var path: [64]runtime_value.Projection = undefined;
                    const reference = try self.storage.resolve(current.storage, x.place, &path);
                    try self.storage.store(reference, slots[x.value]);
                },
                .field => |x| slots[x.dst] = slots[x.base].record[x.index],
                .binary => |x| {
                    const left = slots[x.left].integer;
                    const right = slots[x.right].integer;
                    const range = b.integerBounds(self.program.graph, f.slots[x.dst]).?;
                    const n = integer.evaluate(x.operator, left, right, range) catch return error.ExecutionDivisionByZero;
                    slots[x.dst] = .{ .integer = n };
                },
                .compare => |x| {
                    const left = slots[x.left];
                    const right = slots[x.right];
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
                    slots[x.dst] = .{ .boolean = yes };
                },
                .call => |x| {
                    if (frames.items.len >= self.limits.call_depth) return error.ExecutionCallDepthLimit;
                    const values = try self.allocate(x.args.len);
                    for (values, x.args) |*value, slot| value.* = slots[slot];
                    const callee = &self.program.functions[@intFromEnum(x.function)].?;
                    try frames.append(self.allocator, try self.frame(callee, values, x.outputs));
                },
                .branch => |x| current.pc = if (slots[x.condition].boolean) x.yes else x.no,
                .jump => |target| current.pc = target,
                .ret => |outputs| {
                    const result = try self.allocate(outputs.len);
                    for (result, outputs) |*value, slot| value.* = slots[slot];
                    const completed = frames.pop().?;
                    self.storage.leave(completed.storage);
                    try self.storage.validateLive(result);
                    if (frames.items.len == 0) return result;
                    const caller = try self.storage.slots(frames.items[frames.items.len - 1].storage);
                    for (completed.return_slots, result) |dst, value| caller[dst] = value;
                },
                .abort_ => return error.ExecutionAborted,
            }
        }
    }
};

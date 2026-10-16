const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const g = @import("../4_semantics/global/graph.zig");
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
    slots: []b.Value,
    pc: usize = 0,
    return_slot: ?b.Slot,
};

pub const Vm = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    program: b.Program,
    limits: Limits,
    steps: usize = 0,
    cells: usize = 0,
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
        self.cells = 0;
        const function = try self.entryFunction(entry, args);
        const inputs = try self.cloneValues(args);
        return self.execute(function, inputs);
    }
    fn cloneValues(self: *Vm, values: []const b.Value) anyerror![]const b.Value {
        const result = try self.allocate(values.len);
        for (result, values) |*out, value| out.* = switch (value) {
            .array => |elements| .{ .array = try self.cloneValues(elements) },
            .record => |fields| .{ .record = try self.cloneValues(fields) },
            else => value,
        };
        return result;
    }
    fn allocate(self: *Vm, count: usize) ![]b.Value {
        if (count > self.limits.value_cells -| self.cells) return error.ExecutionMemoryLimit;
        self.cells += count;
        return self.arena.allocator().alloc(b.Value, count);
    }
    fn elementIndex(slots: []const b.Value, index_slot: b.Slot, length: usize) !usize {
        const index = slots[index_slot].integer;
        if (index < 0 or index >= length) return error.ExecutionIndexOutOfBounds;
        return @intCast(index);
    }
    fn readPlace(slots: []const b.Value, place: b.Place) !b.Value {
        var value = slots[place.root];
        for (place.path) |projection| value = switch (projection) {
            .field => |index| value.record[index],
            .element => |index| value.array[try elementIndex(slots, index, value.array.len)],
        };
        return value;
    }
    // Values are immutable snapshots. Rebuild only the path to the destination,
    // sharing every untouched subtree. The verifier bounds its depth and types;
    // all new aggregate cells count against the execution memory budget.
    fn update(self: *Vm, slots: []const b.Value, base: b.Value, path: []const b.Projection, value: b.Value) anyerror!b.Value {
        if (path.len == 0) return value;
        const elements, const index = switch (path[0]) {
            .field => |index| .{ base.record, @as(usize, index) },
            .element => |index| .{ base.array, try elementIndex(slots, index, base.array.len) },
        };
        const changed = try self.update(slots, elements[index], path[1..], value);
        const result = try self.allocate(elements.len);
        @memcpy(result, elements);
        result[index] = changed;
        return switch (path[0]) {
            .field => .{ .record = result },
            .element => .{ .array = result },
        };
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
    fn frame(self: *Vm, function: *const b.Function, args: []const b.Value, return_slot: ?b.Slot) !Frame {
        const slots = try self.allocate(function.slots.len);
        @memset(slots, .unit);
        for (args, function.inputs) |value, slot| slots[slot] = value;
        return .{ .function = function, .slots = slots, .return_slot = return_slot };
    }
    fn execute(self: *Vm, function: *const b.Function, args: []const b.Value) ![]const b.Value {
        var frames: std.ArrayList(Frame) = .empty;
        defer frames.deinit(self.allocator);
        if (self.limits.call_depth == 0) return error.ExecutionCallDepthLimit;
        try frames.append(self.allocator, try self.frame(function, args, null));
        while (true) {
            // Never retain this pointer across a push: the frame array may move.
            const current = &frames.items[frames.items.len - 1];
            const f = current.function;
            const slots = current.slots;
            const inst = f.code[current.pc];
            self.source = inst.source;
            if (self.steps >= self.limits.instructions) return error.ExecutionInstructionLimit;
            self.steps += 1;
            current.pc += 1;
            switch (inst.op) {
                .constant => |x| slots[x.dst] = x.value,
                .copy => |x| slots[x.dst] = slots[x.src],
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
                    const index = slots[x.index].integer;
                    if (index < 0 or index >= elements.len) return error.ExecutionIndexOutOfBounds;
                    slots[x.dst] = elements[@intCast(index)];
                },
                .check_place => |place| _ = try readPlace(slots, place),
                .store => |x| slots[x.place.root] = try self.update(slots, slots[x.place.root], x.place.path, slots[x.value]),
                .field => |x| slots[x.dst] = slots[x.base].record[x.index],
                .binary => |x| {
                    const left = slots[x.left].integer;
                    const right = slots[x.right].integer;
                    const n: i128 = switch (x.operator) {
                        .addition => blk: {
                            const v = @addWithOverflow(left, right);
                            if (v[1] != 0) return error.ExecutionIntegerOverflow;
                            break :blk v[0];
                        },
                        .subtraction => blk: {
                            const v = @subWithOverflow(left, right);
                            if (v[1] != 0) return error.ExecutionIntegerOverflow;
                            break :blk v[0];
                        },
                        .multiplication => blk: {
                            const v = @mulWithOverflow(left, right);
                            if (v[1] != 0) return error.ExecutionIntegerOverflow;
                            break :blk v[0];
                        },
                        .division => blk: {
                            if (right == 0) return error.ExecutionDivisionByZero;
                            break :blk @divTrunc(left, right);
                        },
                        .modulo => blk: {
                            if (right == 0) return error.ExecutionDivisionByZero;
                            break :blk @rem(left, right);
                        },
                    };
                    if (!b.valueFits(self.program.graph, f.slots[x.dst], .{ .integer = n })) return error.ExecutionIntegerOverflow;
                    slots[x.dst] = .{ .integer = n };
                },
                .compare => |x| {
                    const left = slots[x.left];
                    const right = slots[x.right];
                    const yes = if (left == .boolean) switch (x.operator) {
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
                    try frames.append(self.allocator, try self.frame(callee, values, x.dst));
                },
                .branch => |x| current.pc = if (slots[x.condition].boolean) x.yes else x.no,
                .jump => |target| current.pc = target,
                .ret => |outputs| {
                    const result = try self.allocate(outputs.len);
                    for (result, outputs) |*value, slot| value.* = slots[slot];
                    const completed = frames.pop().?;
                    if (frames.items.len == 0) return result;
                    if (completed.return_slot) |dst| frames.items[frames.items.len - 1].slots[dst] = result[0];
                },
                .abort_ => return error.ExecutionAborted,
            }
        }
    }
};

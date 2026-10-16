const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const p = @import("../4_semantics/primitives/schema.zig");

pub const Slot = u32;
pub const Type = g.GlobalTypeId;
pub const Value = union(enum) { integer: i128, boolean: bool, unit, record: []const Value };
pub const Instruction = struct {
    source: p.SourceRef,
    op: union(enum) {
        constant: struct { dst: Slot, value: Value },
        copy: struct { dst: Slot, src: Slot },
        binary: struct { dst: Slot, left: Slot, right: Slot, operator: p.BinaryOperator },
        compare: struct { dst: Slot, left: Slot, right: Slot, operator: p.ComparisonOperator },
        record: struct { dst: Slot, fields: []const Slot },
        field: struct { dst: Slot, base: Slot, index: u32 },
        call: struct { dst: ?Slot, function: g.GlobalFunctionId, args: []const Slot },
        branch: struct { condition: Slot, yes: u32, no: u32 },
        jump: u32,
        ret: []const Slot,
        abort_,
    },
};
pub const Function = struct {
    slots: []const Type,
    inputs: []const Slot,
    outputs: []const Slot,
    code: []const Instruction,
};

// Bytecode borrows the finalized graph's type and function identities. Its owner
// must retain that graph; execution never calls semantic resolution.
pub const Program = struct {
    graph: *const g.GlobalSemanticGraph,
    functions: []const ?Function,
};

pub fn integerBounds(graph: *const g.GlobalSemanticGraph, ty: Type) ?struct { min: i128, max: i128 } {
    const semantic = graph.semanticType(ty);
    if (semantic != .builtin) return null;
    const bits: u7, const signed = switch (semantic.builtin) {
        .Int8 => .{ 8, true },
        .Int16 => .{ 16, true },
        .Int32 => .{ 32, true },
        .Int64 => .{ 64, true },
        .UInt8 => .{ 8, false },
        .UInt16 => .{ 16, false },
        .UInt32 => .{ 32, false },
        .UInt64 => .{ 64, false },
        // A first host-only executor; cross-target execution is rejected by its caller.
        .UIntNative => .{ @bitSizeOf(usize), false },
        else => return null,
    };
    return if (signed) .{ .min = -(@as(i128, 1) << (bits - 1)), .max = (@as(i128, 1) << (bits - 1)) - 1 } else .{ .min = 0, .max = (@as(i128, 1) << bits) - 1 };
}

pub fn supportedType(graph: *const g.GlobalSemanticGraph, ty: Type, depth: usize) bool {
    if (depth > 64 or @intFromEnum(ty) >= graph.types.items.len) return false;
    if (integerBounds(graph, ty) != null) return true;
    const semantic = graph.semanticType(ty);
    if (semantic == .builtin) return semantic.builtin == .Bool or semantic.builtin == .Void;
    const fields = types.fields(graph, ty) orelse return false;
    for (graph.fields.items[fields.start..][0..fields.len]) |field| if (!supportedType(graph, field.ty, depth + 1)) return false;
    return true;
}

pub fn valueFits(graph: *const g.GlobalSemanticGraph, ty: Type, value: Value) bool {
    return switch (value) {
        .integer => |n| if (integerBounds(graph, ty)) |b| n >= b.min and n <= b.max else false,
        .boolean => graph.semanticType(ty) == .builtin and graph.semanticType(ty).builtin == .Bool,
        .unit => graph.semanticType(ty) == .builtin and graph.semanticType(ty).builtin == .Void,
        .record => |values| blk: {
            const fields = types.fields(graph, ty) orelse break :blk false;
            if (fields.len != values.len) break :blk false;
            for (graph.fields.items[fields.start..][0..fields.len], values) |field, v| if (!valueFits(graph, field.ty, v)) break :blk false;
            break :blk true;
        },
    };
}

// Structural validation precedes dataflow: even unreachable instructions may
// never address invalid slots, call signatures or branch targets.
pub fn verify(allocator: std.mem.Allocator, program: Program) !void {
    if (!program.graph.target.isNative()) return error.UnsupportedExecutionTarget;
    if (program.functions.len != program.graph.functions.items.len) return error.InvalidBytecode;
    for (program.functions, 0..) |maybe, fi| {
        const f = maybe orelse continue;
        if (f.code.len == 0) return error.InvalidBytecode;
        for (f.slots) |ty| if (!supportedType(program.graph, ty, 0)) return error.InvalidBytecode;
        const declaration = program.graph.function(@enumFromInt(fi));
        if (f.inputs.len != declaration.input.len or f.outputs.len != declaration.output.len) return error.InvalidBytecode;
        for (f.inputs, 0..) |slot, i| if (slot >= f.slots.len or !types.equal(program.graph, f.slots[slot], program.graph.fields.items[declaration.input.start + i].ty)) return error.InvalidBytecode;
        for (f.outputs, 0..) |slot, i| if (slot >= f.slots.len or !types.equal(program.graph, f.slots[slot], program.graph.fields.items[declaration.output.start + i].ty)) return error.InvalidBytecode;
        for (f.code) |inst| {
            var reads: std.ArrayList(Slot) = .empty;
            defer reads.deinit(allocator);
            const dst = destination(inst);
            if (dst) |d| if (d >= f.slots.len) return error.InvalidBytecode;
            try readSlots(allocator, inst, &reads);
            for (reads.items) |slot| if (slot >= f.slots.len) return error.InvalidBytecode;
            switch (inst.op) {
                .constant => |x| if (!valueFits(program.graph, f.slots[x.dst], x.value)) return error.InvalidBytecode,
                .copy => |x| if (!types.equal(program.graph, f.slots[x.dst], f.slots[x.src])) return error.InvalidBytecode,
                .binary => |x| if (integerBounds(program.graph, f.slots[x.dst]) == null or !types.equal(program.graph, f.slots[x.dst], f.slots[x.left]) or !types.equal(program.graph, f.slots[x.left], f.slots[x.right])) return error.InvalidBytecode,
                .compare => |x| {
                    if (!valueFits(program.graph, f.slots[x.dst], .{ .boolean = false }) or !types.equal(program.graph, f.slots[x.left], f.slots[x.right])) return error.InvalidBytecode;
                    if (integerBounds(program.graph, f.slots[x.left]) == null and !(valueFits(program.graph, f.slots[x.left], .{ .boolean = false }) and (x.operator == .equal or x.operator == .not_equal))) return error.InvalidBytecode;
                },
                .record => |x| {
                    const fields = types.fields(program.graph, f.slots[x.dst]) orelse return error.InvalidBytecode;
                    if (fields.len != x.fields.len) return error.InvalidBytecode;
                    for (x.fields, 0..) |slot, i| if (!types.equal(program.graph, f.slots[slot], program.graph.fields.items[fields.start + i].ty)) return error.InvalidBytecode;
                },
                .field => |x| {
                    const fields = types.fields(program.graph, f.slots[x.base]) orelse return error.InvalidBytecode;
                    if (x.index >= fields.len or !types.equal(program.graph, f.slots[x.dst], program.graph.fields.items[fields.start + x.index].ty)) return error.InvalidBytecode;
                },
                .branch => |x| if (x.yes >= f.code.len or x.no >= f.code.len or !valueFits(program.graph, f.slots[x.condition], .{ .boolean = false })) return error.InvalidBytecode,
                .jump => |target| if (target >= f.code.len) return error.InvalidBytecode,
                .ret => |slots| {
                    if (slots.len != f.outputs.len) return error.InvalidBytecode;
                    for (slots, f.outputs) |slot, output| if (!types.equal(program.graph, f.slots[slot], f.slots[output])) return error.InvalidBytecode;
                },
                .call => |x| {
                    if (@intFromEnum(x.function) >= program.functions.len) return error.InvalidBytecode;
                    const callee = program.functions[@intFromEnum(x.function)] orelse return error.InvalidBytecode;
                    if (x.args.len != callee.inputs.len or callee.outputs.len > 1 or ((x.dst != null) != (callee.outputs.len == 1))) return error.InvalidBytecode;
                    for (x.args, callee.inputs) |slot, input| if (!types.equal(program.graph, f.slots[slot], callee.slots[input])) return error.InvalidBytecode;
                    if (x.dst) |slot| if (!types.equal(program.graph, f.slots[slot], callee.slots[callee.outputs[0]])) return error.InvalidBytecode;
                },
                .abort_ => {},
            }
        }
        // Definite initialization is the intersection of every predecessor.
        const states = try allocator.alloc(?[]bool, f.code.len);
        defer {
            for (states) |s| if (s) |v| allocator.free(v);
            allocator.free(states);
        }
        @memset(states, null);
        states[0] = try allocator.alloc(bool, f.slots.len);
        @memset(states[0].?, false);
        for (f.inputs) |slot| states[0].?[slot] = true;
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(allocator);
        try pending.append(allocator, 0);
        while (pending.pop()) |pc| {
            const initialized = try allocator.dupe(bool, states[pc].?);
            defer allocator.free(initialized);
            var reads: std.ArrayList(Slot) = .empty;
            defer reads.deinit(allocator);
            const inst = f.code[pc];
            try readSlots(allocator, inst, &reads);
            for (reads.items) |slot| if (!initialized[slot]) return error.UninitializedBytecodeSlot;
            if (destination(inst)) |slot| initialized[slot] = true;
            var successors: [2]u32 = undefined;
            const count: usize = switch (inst.op) {
                .ret, .abort_ => 0,
                .jump => |target| blk: {
                    successors[0] = target;
                    break :blk 1;
                },
                .branch => |x| blk: {
                    successors = .{ x.yes, x.no };
                    break :blk 2;
                },
                else => blk: {
                    if (pc + 1 >= f.code.len) return error.InvalidBytecode;
                    successors[0] = pc + 1;
                    break :blk 1;
                },
            };
            for (successors[0..count]) |next| {
                var changed = false;
                if (states[next]) |old| {
                    for (old, initialized) |*was, now| if (was.* and !now) {
                        was.* = false;
                        changed = true;
                    };
                } else {
                    states[next] = try allocator.dupe(bool, initialized);
                    changed = true;
                }
                if (changed) try pending.append(allocator, next);
            }
        }
    }
}

pub fn destination(i: Instruction) ?Slot {
    return switch (i.op) {
        .constant => |x| x.dst,
        .copy => |x| x.dst,
        .binary => |x| x.dst,
        .compare => |x| x.dst,
        .record => |x| x.dst,
        .field => |x| x.dst,
        .call => |x| x.dst,
        else => null,
    };
}
fn readSlots(a: std.mem.Allocator, i: Instruction, out: *std.ArrayList(Slot)) !void {
    switch (i.op) {
        .copy => |x| try out.append(a, x.src),
        .binary => |x| try out.appendSlice(a, &.{ x.left, x.right }),
        .compare => |x| try out.appendSlice(a, &.{ x.left, x.right }),
        .record => |x| try out.appendSlice(a, x.fields),
        .field => |x| try out.append(a, x.base),
        .call => |x| try out.appendSlice(a, x.args),
        .branch => |x| try out.append(a, x.condition),
        .ret => |x| try out.appendSlice(a, x),
        else => {},
    }
}

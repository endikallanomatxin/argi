const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");
const p = @import("../../4_semantics/primitives/schema.zig");

pub const Slot = u32;
pub const Type = g.GlobalTypeId;
pub const Value = @import("value.zig").Value;
// A place starts in local storage and can follow checked safe references.
// Index operands are snapshots evaluated by lowering in source order.
pub const Projection = union(enum) { field: u32, element: Slot, variant: g.GlobalVariantId, dereference };
pub const Place = struct { root: Slot, path: []const Projection };

pub const Instruction = struct {
    source: p.SourceRef,
    op: union(enum) {
        constant: struct { dst: Slot, value: Value },
        copy: struct { dst: Slot, src: Slot },
        readonly: struct { dst: Slot, src: Slot },
        binary: struct { dst: Slot, left: Slot, right: Slot, operator: p.BinaryOperator },
        compare: struct { dst: Slot, left: Slot, right: Slot, operator: p.ComparisonOperator },
        record: struct { dst: Slot, fields: []const Slot },
        field: struct { dst: Slot, base: Slot, index: u32 },
        array: struct { dst: Slot, elements: []const Slot },
        index: struct { dst: Slot, base: Slot, index: Slot },
        choice: struct { dst: Slot, variant: g.GlobalVariantId, payload: ?Slot },
        payload: struct { dst: Slot, src: Slot, variant: g.GlobalVariantId },
        is_variant: struct { dst: Slot, src: Slot, variant: g.GlobalVariantId, invert: bool },
        branch_variant: struct { src: Slot, variant: g.GlobalVariantId, yes: u32, no: u32 },
        borrow: struct { dst: Slot, place: Place },
        load: struct { dst: Slot, place: Place },
        check_place: Place,
        store: struct { place: Place, value: Slot },
        call: struct { outputs: []const Slot, function: g.GlobalFunctionId, args: []const Slot },
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
    if (semantic == .pointer) return supportedType(graph, semantic.pointer.child, depth + 1);
    if (types.arrayElement(graph, ty)) |element| return supportedType(graph, element, depth + 1);
    if (types.variants(graph, ty)) |variants| {
        if (!regularChoice(graph, ty, depth)) return false;
        for (graph.variants.items[variants.start..][0..variants.len]) |variant| if (variant.payload_type) |payload| {
            if (!supportedType(graph, payload, depth + 1)) return false;
        };
        return true;
    }
    const fields = types.fields(graph, ty) orelse return false;
    for (graph.fields.items[fields.start..][0..fields.len]) |field| if (!supportedType(graph, field.ty, depth + 1)) return false;
    return true;
}

fn regularChoice(graph: *const g.GlobalSemanticGraph, ty: Type, depth: usize) bool {
    if (depth > 64) return false;
    return switch (graph.semanticType(ty)) {
        .structural_choice => |shape| shape.layout == .regular,
        .inferred_choice => true,
        .declared => |id| graph.declaration(id).choice_layout == .regular,
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .choice => |shape| shape.layout == .regular,
            .alias => |child| regularChoice(graph, child, depth + 1),
            else => false,
        } else false,
        else => false,
    };
}

pub fn valueFits(graph: *const g.GlobalSemanticGraph, ty: Type, value: Value) bool {
    return switch (value) {
        .integer => |n| if (integerBounds(graph, ty)) |b| n >= b.min and n <= b.max else false,
        .boolean => graph.semanticType(ty) == .builtin and graph.semanticType(ty).builtin == .Bool,
        .unit => graph.semanticType(ty) == .builtin and graph.semanticType(ty).builtin == .Void,
        .array => |values| blk: {
            const element = types.arrayElement(graph, ty) orelse break :blk false;
            if (types.arrayLength(graph, ty).? != values.len) break :blk false;
            for (values) |v| if (!valueFits(graph, element, v)) break :blk false;
            break :blk true;
        },
        // Reference values are created by borrow instructions, never constants
        // or external inputs. Their shape and access are checked separately.
        .reference => false,
        .choice => |choice| blk: {
            const variant = choiceVariant(graph, ty, @enumFromInt(choice.variant)) catch break :blk false;
            if (variant.payload_type) |payload_type| {
                const payload = choice.payload orelse break :blk false;
                break :blk valueFits(graph, payload_type, payload.*);
            }
            break :blk choice.payload == null;
        },
        .record => |values| blk: {
            const fields = types.fields(graph, ty) orelse break :blk false;
            if (fields.len != values.len) break :blk false;
            for (graph.fields.items[fields.start..][0..fields.len], values) |field, v| if (!valueFits(graph, field.ty, v)) break :blk false;
            break :blk true;
        },
    };
}

pub const verify = @import("verify.zig").verify;

pub fn choiceVariant(graph: *const g.GlobalSemanticGraph, ty: Type, id: g.GlobalVariantId) !g.ChoiceVariant {
    const range = types.variants(graph, ty) orelse return error.InvalidBytecode;
    const raw = @intFromEnum(id);
    if (raw < range.start or raw - range.start >= range.len) return error.InvalidBytecode;
    return graph.variants.items[raw];
}

const std = @import("std");
const graph_mod = @import("global_semantic_graph.zig");
const primitives = @import("semantic_primitives.zig");

pub const pointer_size_bytes: u64 = @sizeOf(*usize);
pub const pointer_alignment_bytes: u64 = pointer_size_bytes;

pub const FieldHit = struct {
    index: u32,
    id: graph_mod.GlobalFieldId,
    field: graph_mod.Field,
};

pub const VariantHit = struct {
    index: u32,
    id: graph_mod.GlobalVariantId,
    variant: graph_mod.ChoiceVariant,
};

pub const Layout = struct {
    size: u64,
    alignment: u64,
};

pub const LayoutError = error{
    UnmaterializedGlobalType,
    UnmaterializedGenericType,
    TypeHasNoRuntimeLayout,
};

pub fn fields(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.FieldRange {
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .structural => |shape| shape.fields,
        .declared => |decl| graph.declarations.items[@intFromEnum(decl)].struct_fields,
        .generic => genericFields(graph, ty),
        else => null,
    };
}

pub fn variants(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.VariantRange {
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .structural_choice => |shape| shape.variants,
        .inferred_choice => |shape| shape.variants,
        .declared => |decl| graph.declarations.items[@intFromEnum(decl)].choice_variants,
        .generic => genericVariants(graph, ty),
        else => null,
    };
}

pub fn arrayElement(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalTypeId {
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .array => |array| array.element,
        .generic => blk: {
            const instance = genericInstance(graph, ty) orelse break :blk null;
            break :blk switch (instance.shape) {
                .array => |shape| shape.element,
                .alias => |target| arrayElement(graph, target),
                else => null,
            };
        },
        else => null,
    };
}

pub fn arrayLength(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?u64 {
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .array => |array| array.length,
        .generic => blk: {
            const instance = genericInstance(graph, ty) orelse break :blk null;
            break :blk switch (instance.shape) {
                .array => |shape| shape.length,
                .alias => |target| arrayLength(graph, target),
                else => null,
            };
        },
        else => null,
    };
}

pub fn findField(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, name: []const u8) ?FieldHit {
    const range = fields(graph, ty) orelse return null;
    for (0..range.len) |index| {
        const raw = range.start + @as(u32, @intCast(index));
        const field = graph.fields.items[raw];
        if (!std.mem.eql(u8, graph.text(field.name), name)) continue;
        return .{
            .index = @intCast(index),
            .id = @enumFromInt(raw),
            .field = field,
        };
    }
    return null;
}

pub fn findVariant(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, name: []const u8) ?VariantHit {
    const range = variants(graph, ty) orelse return null;
    for (0..range.len) |index| {
        const raw = range.start + @as(u32, @intCast(index));
        const variant = graph.variants.items[raw];
        if (!std.mem.eql(u8, graph.text(variant.name), name)) continue;
        return .{
            .index = @intCast(index),
            .id = @enumFromInt(raw),
            .variant = variant,
        };
    }
    return null;
}

pub fn genericInstance(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GenericInstance {
    for (graph.generic_instances.items) |instance| if (instance.type_id == ty) return instance;
    return null;
}

pub fn typeForDeclaration(graph: *const graph_mod.GlobalSemanticGraph, decl: graph_mod.GlobalDeclId) ?graph_mod.GlobalTypeId {
    return graph.declarations.items[@intFromEnum(decl)].type_id;
}

pub fn effectiveFieldType(field: graph_mod.Field) graph_mod.GlobalTypeId {
    return field.storage_type orelse field.ty;
}

pub fn isBuiltin(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, builtin: primitives.BuiltinType) bool {
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .builtin => |value| value == builtin,
        else => false,
    };
}

pub fn equal(graph: *const graph_mod.GlobalSemanticGraph, a: graph_mod.GlobalTypeId, b: graph_mod.GlobalTypeId) bool {
    if (a == b) return true;
    const left = graph.types.items[@intFromEnum(a)];
    const right = graph.types.items[@intFromEnum(b)];
    return switch (left) {
        .builtin => |x| switch (right) { .builtin => |y| x == y, else => false },
        .declared => |x| switch (right) { .declared => |y| x == y, else => false },
        .pointer => |x| switch (right) {
            .pointer => |y| x.mutability == y.mutability and equal(graph, x.child, y.child),
            else => false,
        },
        .array => |x| switch (right) {
            .array => |y| x.length == y.length and equal(graph, x.element, y.element),
            else => false,
        },
        .nullable => |x| switch (right) { .nullable => |y| equal(graph, x, y), else => false },
        .inferred_errable => |x| switch (right) { .inferred_errable => |y| equal(graph, x, y), else => false },
        .generic => |x| switch (right) {
            .generic => |y| x.base == y.base and genericArgumentsEqual(graph, x.arguments, y.arguments),
            else => false,
        },
        .inferred_choice => |x| switch (right) { .inferred_choice => |y| x.identity == y.identity and x.kind == y.kind, else => false },
        .structural => |x| switch (right) { .structural => |y| fieldRangesEqual(graph, x.fields, y.fields), else => false },
        .structural_choice => |x| switch (right) { .structural_choice => |y| variantRangesEqual(graph, x.variants, y.variants), else => false },
    };
}

/// Runtime layout of a fully resolved GlobalTypeId. Compact ModuleSema sugar
/// (`nullable`/`inferred_errable`) is rejected because GlobalSema must
/// materialize it before Safety/Codegen.
pub fn layoutOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) LayoutError!Layout {
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .builtin => |builtin| builtinLayout(builtin),
        .pointer => .{ .size = pointer_size_bytes, .alignment = pointer_alignment_bytes },
        .array => |array| blk: {
            const element = try layoutOf(graph, array.element);
            const stride = alignForward(element.size, element.alignment);
            break :blk .{ .size = stride * array.length, .alignment = element.alignment };
        },
        .declared => |decl| declaredLayout(graph, decl),
        .structural => |shape| structLayout(graph, shape.fields, shape.layout),
        .structural_choice => |shape| choiceLayout(graph, shape.variants, shape.layout),
        .inferred_choice => |shape| choiceLayout(graph, shape.variants, .regular),
        .generic => genericLayout(graph, ty),
        .nullable, .inferred_errable => error.UnmaterializedGlobalType,
    };
}

pub fn sizeOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !u64 {
    return (try layoutOf(graph, ty)).size;
}

pub fn alignmentOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !u64 {
    return (try layoutOf(graph, ty)).alignment;
}

fn builtinLayout(builtin: primitives.BuiltinType) Layout {
    return switch (builtin) {
        .Void => .{ .size = 0, .alignment = 1 },
        .Int8, .UInt8, .Char, .Bool, .Any => .{ .size = 1, .alignment = 1 },
        .Int16, .UInt16, .Float16 => .{ .size = 2, .alignment = 2 },
        .Int32, .UInt32, .Float32 => .{ .size = 4, .alignment = 4 },
        .Int64, .UInt64, .Float64 => .{ .size = 8, .alignment = 8 },
        .UIntNative, .Type => .{ .size = pointer_size_bytes, .alignment = pointer_alignment_bytes },
    };
}

fn declaredLayout(graph: *const graph_mod.GlobalSemanticGraph, decl_id: graph_mod.GlobalDeclId) LayoutError!Layout {
    const decl = graph.declarations.items[@intFromEnum(decl_id)];
    if (decl.struct_fields) |range| return structLayout(graph, range, decl.struct_layout);
    if (decl.choice_variants) |range| return choiceLayout(graph, range, decl.choice_layout);
    return error.TypeHasNoRuntimeLayout;
}

fn genericLayout(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) LayoutError!Layout {
    const instance = genericInstance(graph, ty) orelse return error.UnmaterializedGenericType;
    return switch (instance.shape) {
        .structure => |shape| structLayout(graph, shape.fields, shape.layout),
        .choice => |shape| choiceLayout(graph, shape.variants, shape.layout),
        .array => |shape| blk: {
            const element = try layoutOf(graph, shape.element);
            const stride = alignForward(element.size, element.alignment);
            break :blk .{ .size = stride * shape.length, .alignment = element.alignment };
        },
        .alias => |target| layoutOf(graph, target),
    };
}

fn structLayout(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.FieldRange, kind: primitives.StructLayout) LayoutError!Layout {
    if (range.len == 0) return .{ .size = 0, .alignment = 1 };
    if (kind == .c_union) {
        var size: u64 = 0;
        var alignment: u64 = 1;
        for (graph.fields.items[range.start..][0..range.len]) |field| {
            const layout = try layoutOf(graph, effectiveFieldType(field));
            size = @max(size, layout.size);
            alignment = @max(alignment, layout.alignment);
        }
        return .{ .size = alignForward(size, alignment), .alignment = alignment };
    }

    var offset: u64 = 0;
    var alignment: u64 = 1;
    for (graph.fields.items[range.start..][0..range.len]) |field| {
        const layout = try layoutOf(graph, effectiveFieldType(field));
        offset = alignForward(offset, layout.alignment);
        offset += layout.size;
        alignment = @max(alignment, layout.alignment);
    }
    return .{ .size = alignForward(offset, alignment), .alignment = alignment };
}

fn choiceLayout(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.VariantRange, kind: primitives.ChoiceLayout) LayoutError!Layout {
    if (kind == .c_enum) return .{ .size = 4, .alignment = 4 };
    // Keep the current ABI exactly: regular choices are a tag followed by one
    // storage field per variant (rather than a payload union).
    var offset: u64 = 4;
    var alignment: u64 = 4;
    for (graph.variants.items[range.start..][0..range.len]) |variant| {
        const payload_ty = variant.payload_type orelse continue;
        const layout = try layoutOf(graph, payload_ty);
        offset = alignForward(offset, layout.alignment);
        offset += layout.size;
        alignment = @max(alignment, layout.alignment);
    }
    return .{ .size = alignForward(offset, alignment), .alignment = alignment };
}

fn alignForward(value: u64, alignment: u64) u64 {
    if (alignment <= 1) return value;
    const remainder = value % alignment;
    return if (remainder == 0) value else value + alignment - remainder;
}

fn genericFields(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.FieldRange {
    const instance = genericInstance(graph, ty) orelse return null;
    return switch (instance.shape) {
        .structure => |shape| shape.fields,
        .alias => |target| fields(graph, target),
        else => null,
    };
}

fn genericVariants(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.VariantRange {
    const instance = genericInstance(graph, ty) orelse return null;
    return switch (instance.shape) {
        .choice => |shape| shape.variants,
        .alias => |target| variants(graph, target),
        else => null,
    };
}

fn genericArgumentsEqual(graph: *const graph_mod.GlobalSemanticGraph, a: anytype, b: @TypeOf(a)) bool {
    if (a.len != b.len) return false;
    for (0..a.len) |index| {
        const left = graph.generic_arguments.items[a.start + @as(u32, @intCast(index))];
        const right = graph.generic_arguments.items[b.start + @as(u32, @intCast(index))];
        if (!std.mem.eql(u8, graph.text(left.name), graph.text(right.name))) return false;
        switch (left.value) {
            .type => |left_ty| switch (right.value) { .type => |right_ty| if (!equal(graph, left_ty, right_ty)) return false, else => return false },
            .comptime_int => |left_int| switch (right.value) { .comptime_int => |right_int| if (left_int != right_int) return false, else => return false },
        }
    }
    return true;
}

fn fieldRangesEqual(graph: *const graph_mod.GlobalSemanticGraph, a: graph_mod.FieldRange, b: graph_mod.FieldRange) bool {
    if (a.len != b.len) return false;
    for (0..a.len) |index| {
        const left = graph.fields.items[a.start + @as(u32, @intCast(index))];
        const right = graph.fields.items[b.start + @as(u32, @intCast(index))];
        if (!std.mem.eql(u8, graph.text(left.name), graph.text(right.name)) or !equal(graph, left.ty, right.ty)) return false;
    }
    return true;
}

fn variantRangesEqual(graph: *const graph_mod.GlobalSemanticGraph, a: graph_mod.VariantRange, b: graph_mod.VariantRange) bool {
    if (a.len != b.len) return false;
    for (0..a.len) |index| {
        const left = graph.variants.items[a.start + @as(u32, @intCast(index))];
        const right = graph.variants.items[b.start + @as(u32, @intCast(index))];
        if (!std.mem.eql(u8, graph.text(left.name), graph.text(right.name))) return false;
        if (left.payload_type == null and right.payload_type == null) continue;
        if (left.payload_type == null or right.payload_type == null) return false;
        if (!equal(graph, left.payload_type.?, right.payload_type.?)) return false;
    }
    return true;
}

test "global semantic types expose structural fields and variants" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const x = try graph.addString(allocator, "x");
    const some = try graph.addString(allocator, "some");
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.fields.append(allocator, .{ .name = x, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.variants.append(allocator, .{ .name = some, .payload_type = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 }, .value = 0 });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    try graph.types.append(allocator, .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 1 } } });
    try std.testing.expectEqual(@as(u32, 0), findField(&graph, @enumFromInt(1), "x").?.index);
    try std.testing.expectEqual(@as(u32, 0), findVariant(&graph, @enumFromInt(2), "some").?.index);
    try std.testing.expectEqual(@as(u64, 4), try sizeOf(&graph, @enumFromInt(1)));
    try std.testing.expect((try sizeOf(&graph, @enumFromInt(2))) >= 8);
}

const std = @import("std");
const graph_mod = @import("global_semantic_graph.zig");
const primitives = @import("semantic_primitives.zig");

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
}

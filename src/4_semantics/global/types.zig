const std = @import("std");
const graph_mod = @import("graph.zig");
const primitives = @import("../primitives/schema.zig");

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
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    return switch (semantic) {
        .structural => |shape| shape.fields,
        .declared => |decl| graph.declarations.items[@intFromEnum(decl)].struct_fields,
        .generic => genericFields(graph, ty),
        else => null,
    };
}

pub fn variants(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.VariantRange {
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    return switch (semantic) {
        .structural_choice => |shape| shape.variants,
        .inferred_choice => |shape| shape.variants,
        .declared => |decl| graph.declarations.items[@intFromEnum(decl)].choice_variants,
        .generic => genericVariants(graph, ty),
        else => null,
    };
}

pub fn arrayElement(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalTypeId {
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    return switch (semantic) {
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
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    return switch (semantic) {
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

/// Nullable is an inference-friendly wrapper until consumers need its concrete
/// choice layout. Parameterized bodies may create and consume the type within
/// one instantiation, before the outer semantizing fixed point can materialize
/// it, so layout materialization is shared by both paths.
pub fn materializeNullable(
    allocator: std.mem.Allocator,
    graph: *graph_mod.GlobalSemanticGraph,
    id: graph_mod.GlobalTypeId,
    child: graph_mod.GlobalTypeId,
    source: primitives.SourceRef,
) !void {
    if (graph.types.items[@intFromEnum(id)] != .nullable) return;
    const value_name = try graph.addString(allocator, "value");
    const none_name = try graph.addString(allocator, "none");
    const some_name = try graph.addString(allocator, "some");

    const field_start: u32 = @intCast(graph.fields.items.len);
    try graph.fields.append(allocator, .{ .name = value_name, .ty = child, .source = source });
    const payload_ty: graph_mod.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = field_start, .len = 1 } } });

    const variant_start: u32 = @intCast(graph.variants.items.len);
    try graph.variants.append(allocator, .{ .name = none_name, .source = source, .value = 0 });
    try graph.variants.append(allocator, .{ .name = some_name, .payload_type = payload_ty, .source = source, .value = 1 });
    try graph.resolveType(id, .{ .structural_choice = .{
        .variants = .{ .start = variant_start, .len = 2 },
    } });
}

/// Destructors receive an address of the owned value. A reference itself is
/// never the value whose lifetime that destructor closes.
pub fn deinitFunction(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalFunctionId {
    if (graph.semanticType(ty) == .pointer) return null;
    for (graph.functions.items, 0..) |function, raw| {
        if (!function.flags.is_deinit or function.input.len == 0) continue;
        const self_ty = graph.fields.items[function.input.start].ty;
        const child = switch (graph.semanticType(self_ty)) {
            .pointer => |pointer| pointer.child,
            else => self_ty,
        };
        if (equal(graph, child, ty)) return @enumFromInt(@as(u32, @intCast(raw)));
    }
    return null;
}

/// Opaque drops need the destructor for the concrete allocator supplied with
/// the slot. The value type alone can have several valid destructor instances.
pub fn deinitFunctionForInput(graph: *const graph_mod.GlobalSemanticGraph, value_type: graph_mod.GlobalTypeId, supplied: graph_mod.FieldRange) error{AmbiguousOpaqueDestructor}!?graph_mod.GlobalFunctionId {
    var found: ?graph_mod.GlobalFunctionId = null;
    for (graph.functions.items, 0..) |function, raw| {
        if (!function.flags.is_deinit) continue;
        var self_matches = false;
        var arguments_match = true;
        for (graph.fields.items[function.input.start..][0..function.input.len]) |expected| {
            const name = graph.text(expected.name);
            if (std.mem.eql(u8, name, "self")) {
                const child = switch (graph.semanticType(expected.ty)) {
                    .pointer => |pointer| pointer.child,
                    else => expected.ty,
                };
                self_matches = equal(graph, child, value_type);
                continue;
            }
            var provided = false;
            for (graph.fields.items[supplied.start..][0..supplied.len]) |actual| {
                if (!std.mem.eql(u8, name, graph.text(actual.name))) continue;
                provided = true;
                if (!equal(graph, expected.ty, actual.ty)) arguments_match = false;
                break;
            }
            if (!provided and expected.default_value == null) arguments_match = false;
            if (!arguments_match) break;
        }
        if (!self_matches or !arguments_match) continue;
        if (found != null) return error.AmbiguousOpaqueDestructor;
        found = @enumFromInt(@as(u32, @intCast(raw)));
    }
    return found;
}

pub fn genericInstance(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GenericInstance {
    if (graph.isTypeUnresolved(ty)) return null;
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
    const semantic = graph.resolvedSemanticType(ty) orelse return false;
    return switch (semantic) {
        .builtin => |value| value == builtin,
        else => false,
    };
}

pub fn identityEqual(graph: *const graph_mod.GlobalSemanticGraph, a: graph_mod.GlobalTypeId, b: graph_mod.GlobalTypeId) bool {
    return a == b or equal(graph, a, b);
}

pub fn equal(graph: *const graph_mod.GlobalSemanticGraph, a: graph_mod.GlobalTypeId, b: graph_mod.GlobalTypeId) bool {
    if (graph.isTypeUnresolved(a) or graph.isTypeUnresolved(b)) return false;
    if (a == b) return true;
    const left = graph.types.items[@intFromEnum(a)];
    const right = graph.types.items[@intFromEnum(b)];
    return switch (left) {
        .builtin => |x| switch (right) {
            .builtin => |y| x == y,
            else => false,
        },
        .declared => |x| switch (right) {
            .declared => |y| x == y,
            else => false,
        },
        .pointer => |x| switch (right) {
            .pointer => |y| x.mutability == y.mutability and equal(graph, x.child, y.child),
            else => false,
        },
        .array => |x| switch (right) {
            .array => |y| x.length == y.length and equal(graph, x.element, y.element),
            else => false,
        },
        .nullable => |x| switch (right) {
            .nullable => |y| equal(graph, x, y),
            else => false,
        },
        .inferred_errable => |x| switch (right) {
            .inferred_errable => |y| equal(graph, x, y),
            else => false,
        },
        .generic => |x| switch (right) {
            .generic => |y| x.base == y.base and genericArgumentsEqual(graph, x.arguments, y.arguments),
            else => false,
        },
        .virtual => |x| switch (right) {
            .virtual => |y| equal(graph, x, y),
            else => false,
        },
        .inferred_choice => |x| switch (right) {
            .inferred_choice => |y| x.identity == y.identity and x.kind == y.kind,
            else => false,
        },
        .structural => |x| switch (right) {
            .structural => |y| fieldRangesEqual(graph, x.fields, y.fields),
            else => false,
        },
        .structural_choice => |x| switch (right) {
            .structural_choice => |y| variantRangesEqual(graph, x.variants, y.variants),
            else => false,
        },
    };
}

/// Runtime layout of a fully resolved GlobalTypeId. Compact ModuleSema sugar
/// (`nullable`/`inferred_errable`) and construction-time holes are rejected
/// because GlobalSema must materialize them before Safety/Codegen.
pub fn layoutOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) LayoutError!Layout {
    const semantic = graph.resolvedSemanticType(ty) orelse return error.UnmaterializedGlobalType;
    return switch (semantic) {
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
        .virtual => .{ .size = pointer_size_bytes * 2, .alignment = pointer_alignment_bytes },
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
    const raw: usize = @intFromEnum(decl_id);
    if (raw >= graph.declarations.items.len) return error.UnmaterializedGlobalType;
    const decl = graph.declarations.items[raw];
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

pub fn genericArgumentsEqual(graph: *const graph_mod.GlobalSemanticGraph, a: anytype, b: @TypeOf(a)) bool {
    if (a.len != b.len) return false;
    for (0..a.len) |index| {
        const left = graph.generic_arguments.items[a.start + @as(u32, @intCast(index))];
        const right = graph.generic_arguments.items[b.start + @as(u32, @intCast(index))];
        if (!std.mem.eql(u8, graph.text(left.name), graph.text(right.name))) return false;
        switch (left.value) {
            .type => |left_ty| switch (right.value) {
                .type => |right_ty| if (!identityEqual(graph, left_ty, right_ty)) return false,
                else => return false,
            },
            .comptime_int => |left_int| switch (right.value) {
                .comptime_int => |right_int| if (left_int != right_int) return false,
                else => return false,
            },
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

test "generic argument identity uses semantic type equality" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    // Globalization can leave distinct IDs for the same semantic type. Generic
    // identity must not depend on those construction-time IDs.
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const name = try graph.addString(allocator, "t");
    try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(0) } });
    try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(1) } });

    const first: primitives.Range(graph_mod.GlobalGenericArgId) = .{ .start = 0, .len = 1 };
    const second: primitives.Range(graph_mod.GlobalGenericArgId) = .{ .start = 1, .len = 1 };
    try std.testing.expect(genericArgumentsEqual(&graph, first, second));
}

test "opaque destructor selection uses the supplied allocator type" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const slot_name = try graph.addString(allocator, "slot");
    const self_name = try graph.addString(allocator, "self");
    const allocator_name = try graph.addString(allocator, "allocator");
    const deinit_name = try graph.addString(allocator, "deinit");
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },
        .{ .builtin = .Int64 },
        .{ .builtin = .UInt8 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } },
        .{ .pointer = .{ .child = @enumFromInt(2), .mutability = .read_write } },
    });
    try graph.fields.appendSlice(allocator, &.{
        .{ .name = slot_name, .ty = @enumFromInt(3), .source = source },
        .{ .name = allocator_name, .ty = @enumFromInt(4), .source = source },
        .{ .name = allocator_name, .ty = @enumFromInt(5), .source = source },
        .{ .name = self_name, .ty = @enumFromInt(3), .source = source },
        .{ .name = allocator_name, .ty = @enumFromInt(5), .source = source },
        .{ .name = allocator_name, .ty = @enumFromInt(4), .source = source },
        .{ .name = self_name, .ty = @enumFromInt(3), .source = source },
    });
    try graph.declarations.append(allocator, .{ .kind = .function, .name = deinit_name, .source = source });
    try graph.functions.appendSlice(allocator, &.{
        .{ .declaration = @enumFromInt(0), .input = .{ .start = 3, .len = 2 }, .output = .{ .start = 0, .len = 0 }, .flags = .{ .is_deinit = true } },
        .{ .declaration = @enumFromInt(0), .input = .{ .start = 5, .len = 2 }, .output = .{ .start = 0, .len = 0 }, .flags = .{ .is_deinit = true } },
    });

    try std.testing.expectEqual(@as(graph_mod.GlobalFunctionId, @enumFromInt(1)), (try deinitFunctionForInput(&graph, @enumFromInt(0), .{ .start = 0, .len = 2 })).?);
    try std.testing.expectEqual(@as(graph_mod.GlobalFunctionId, @enumFromInt(0)), (try deinitFunctionForInput(&graph, @enumFromInt(0), .{ .start = 2, .len = 1 })).?);
    try graph.functions.append(allocator, .{ .declaration = @enumFromInt(0), .input = .{ .start = 5, .len = 2 }, .output = .{ .start = 0, .len = 0 }, .flags = .{ .is_deinit = true } });
    try std.testing.expectError(error.AmbiguousOpaqueDestructor, deinitFunctionForInput(&graph, @enumFromInt(0), .{ .start = 0, .len = 2 }));
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

test "type helpers reject construction-time unresolved slots" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Any });
    try graph.markTypeUnresolved(allocator, @enumFromInt(0));

    try std.testing.expect(!isBuiltin(&graph, @enumFromInt(0), .Any));
    try std.testing.expect(!equal(&graph, @enumFromInt(0), @enumFromInt(0)));
    try std.testing.expectError(error.UnmaterializedGlobalType, layoutOf(&graph, @enumFromInt(0)));
}

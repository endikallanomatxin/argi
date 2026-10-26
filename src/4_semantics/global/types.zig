const contract_evidence = @import("contract_evidence.zig");
const std = @import("std");
const standard_contracts = @import("standard_contracts.zig");
const graph_mod = @import("graph.zig");
const primitives = @import("../primitives/schema.zig");

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

/// Follow storage links without changing nominal equality or contract lookup.
/// The bounded walk safely probes unresolved or cyclic definitions while the
/// semantic fixed point is still materializing types.
pub fn representationType(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalTypeId {
    var current = ty;
    for (0..graph.types.items.len + 1) |_| {
        const semantic = graph.resolvedSemanticType(current) orelse return null;
        const next: ?graph_mod.GlobalTypeId = switch (semantic) {
            .generic => if (genericInstance(graph, current)) |instance| switch (instance.shape) {
                .alias => |target| target,
                else => null,
            } else null,
            else => null,
        };
        current = next orelse return current;
    }
    return null;
}

pub fn representation(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalType {
    return graph.resolvedSemanticType(representationType(graph, ty) orelse return null);
}

/// Init and Convert return their target directly or in one Errable success payload.
pub fn resultMatchesTarget(graph: *const graph_mod.GlobalSemanticGraph, result: graph_mod.GlobalTypeId, target: graph_mod.GlobalTypeId) bool {
    if (equal(graph, result, target)) return true;
    if (!isErrable(graph, result)) return false;
    const ok = findVariant(graph, result, "ok") orelse return false;
    return equal(graph, ok.variant.payload_type orelse return false, target);
}

/// Local handling accepts the bundled Errable family and the identity-bearing
/// inferred form used by fallible output shorthand, never arbitrary choices
/// that merely happen to spell their alternatives `ok` and `error`.
pub fn isErrable(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    const semantic = graph.resolvedSemanticType(ty) orelse return false;
    return switch (semantic) {
        .inferred_choice => |choice| choice.kind == .errable,
        .generic => |generic| blk: {
            const owner = graph.moduleForFamilyDefinition(generic.base) orelse break :blk false;
            break :blk graph.modules.items[@intFromEnum(owner)].is_bundled_core and
                std.mem.eql(u8, graph.familyDefinitionName(generic.base), "Errable");
        },
        else => false,
    };
}

pub fn isCUnion(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return switch (graph.semanticType(ty)) {
        .nominal => |decl| graph.typeDefinition(decl).struct_layout == .c_union,
        .structural => |shape| shape.layout == .c_union,
        .generic => if (genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .structure => |shape| shape.layout == .c_union,
            else => false,
        } else false,
        else => false,
    };
}

pub fn fields(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.FieldRange {
    const semantic = representation(graph, ty) orelse return null;
    return switch (semantic) {
        .structural => |shape| shape.fields,
        .nominal => |decl| graph.typeDefinition(decl).struct_fields,
        .generic => genericFields(graph, ty),
        else => null,
    };
}

pub fn variants(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.VariantRange {
    const semantic = representation(graph, ty) orelse return null;
    return switch (semantic) {
        .structural_choice => |shape| shape.variants,
        .inferred_choice => |shape| shape.variants,
        .nominal => |decl| graph.typeDefinition(decl).choice_variants,
        .generic => genericVariants(graph, ty),
        else => null,
    };
}

pub fn arrayElement(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalTypeId {
    const semantic = representation(graph, ty) orelse return null;
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
    const semantic = representation(graph, ty) orelse return null;
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

pub fn variantTag(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, hit: VariantHit) i32 {
    const layout: primitives.ChoiceLayout = switch (graph.semanticType(ty)) {
        .nominal => |id| graph.typeDefinition(id).choice_layout,
        .structural_choice => |shape| shape.layout,
        .generic => if (genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .choice => |shape| shape.layout,
            .alias => |child| return variantTag(graph, child, hit),
            else => .regular,
        } else .regular,
        else => .regular,
    };
    // Regular choices use the position within their family. C enums preserve
    // the explicit C value, independently of where their variants are stored.
    return if (layout == .c_enum) hit.variant.value else @intCast(hit.index);
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
    try graph.resolveType(allocator, id, .{ .structural_choice = .{
        .variants = .{ .start = variant_start, .len = 2 },
    } });
}

/// Recover nullable's element before or after choice materialization. The
/// sugar has structural identity, including its variant and payload names.
pub fn nullableChild(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalTypeId {
    if (graph.types.items[@intFromEnum(ty)] == .nullable) return graph.types.items[@intFromEnum(ty)].nullable;
    const choices = variants(graph, ty) orelse return null;
    if (choices.len != 2) return null;
    const none = findVariant(graph, ty, "none") orelse return null;
    if (none.variant.payload_type != null) return null;
    const some = findVariant(graph, ty, "some") orelse return null;
    const payload = some.variant.payload_type orelse return null;
    const members = fields(graph, payload) orelse return null;
    if (members.len != 1) return null;
    const field = graph.fields.items[members.start];
    if (!std.mem.eql(u8, graph.text(field.name), "value")) return null;
    return field.ty;
}

/// Destructors receive an address of the owned value. A reference itself is
/// never the value whose lifetime that destructor closes.
pub fn deinitFunction(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalFunctionId {
    if (graph.semanticType(ty) == .pointer) return null;
    const contract = standard_contracts.standardDefinition(graph, "Deinit") orelse return null;
    var operations = contract_evidence.materializedOperations(graph, contract);
    var found: ?graph_mod.GlobalFunctionId = null;
    while (operations.next()) |selected| {
        const id = selected.materializedFunction() orelse continue;
        const function = graph.function(id);
        if (!function.flags.is_deinit or function.input.len == 0) continue;
        const participant = selected.participant(graph, 0) orelse continue;
        if (!equal(graph, participant, ty)) continue;
        // Preserve declaration-order selection when the same evidence is reached
        // through several caller contexts.
        if (found == null or @intFromEnum(id) < @intFromEnum(found.?)) found = id;
    }
    return found;
}

/// A cleanup obligation comes from selected Deinit evidence, independently
/// of storage acquisition.
pub fn hasDestructor(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return deinitFunction(graph, ty) != null;
}

pub fn genericInstance(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GenericInstance {
    if (graph.isTypeUnresolved(ty)) return null;
    for (graph.generic_instances.items) |instance| if (instance.type_id == ty) return instance;
    return null;
}

pub fn typeForDeclaration(graph: *const graph_mod.GlobalSemanticGraph, decl: graph_mod.GlobalDeclId) ?graph_mod.GlobalTypeId {
    return graph.declarations.items[@intFromEnum(decl)].type_id;
}

pub fn isBuiltin(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, builtin: primitives.BuiltinType) bool {
    const semantic = graph.resolvedSemanticType(ty) orelse return false;
    return switch (semantic) {
        .builtin => |value| value == builtin,
        else => false,
    };
}

pub fn identityEqual(graph: *const graph_mod.GlobalSemanticGraph, a: graph_mod.GlobalTypeId, b: graph_mod.GlobalTypeId) bool {
    if (a == b) return true;
    if (!equal(graph, a, b)) return false;
    const left = graph.types.items[@intFromEnum(a)];
    const right = graph.types.items[@intFromEnum(b)];
    // Structural assignability ignores defaults, but specialization must retain
    // them: a generic body can construct a value using the supplied type.
    return switch (left) {
        .pointer => |value| identityEqual(graph, value.child, right.pointer.child),
        .array => |value| identityEqual(graph, value.element, right.array.element),
        .nullable => |value| identityEqual(graph, value, right.nullable),
        .virtual => |value| identityEqual(graph, value, right.virtual),
        .structural => |value| result: {
            if (value.layout != right.structural.layout) break :result false;
            for (graph.fields.items[value.fields.start..][0..value.fields.len], graph.fields.items[right.structural.fields.start..][0..right.structural.fields.len]) |first, second| {
                if (first.default_value != second.default_value or !identityEqual(graph, first.ty, second.ty)) break :result false;
            }
            break :result true;
        },
        .structural_choice => |value| result: {
            if (value.layout != right.structural_choice.layout) break :result false;
            for (graph.variants.items[value.variants.start..][0..value.variants.len], graph.variants.items[right.structural_choice.variants.start..][0..right.structural_choice.variants.len]) |first, second| {
                if (first.payload_type) |payload| if (!identityEqual(graph, payload, second.payload_type.?)) break :result false;
            }
            break :result true;
        },
        else => true,
    };
}

/// Operation compatibility compares the callable fields, not the nominal
/// identity of their enclosing records. Field types retain ordinary equality.
/// Extra implementation inputs must be optional so requirement-only callers
/// can still invoke the implementation.
pub fn operationInputsCompatible(graph: *const graph_mod.GlobalSemanticGraph, required: graph_mod.FieldRange, implementation: graph_mod.FieldRange) bool {
    if (implementation.len < required.len) return false;
    if (!operationFieldsEqual(graph, required, .{ .start = implementation.start, .len = required.len })) return false;
    for (graph.fields.items[implementation.start + required.len ..][0 .. implementation.len - required.len]) |field|
        if (field.default_value == null) return false;
    return true;
}

pub fn operationFieldsEqual(graph: *const graph_mod.GlobalSemanticGraph, required: graph_mod.FieldRange, implementation: graph_mod.FieldRange) bool {
    if (required.len != implementation.len) return false;
    for (graph.fields.items[required.start..][0..required.len], graph.fields.items[implementation.start..][0..implementation.len]) |expected, actual| {
        if (!std.mem.eql(u8, graph.text(expected.name), graph.text(actual.name)) or !equal(graph, expected.ty, actual.ty)) return false;
    }
    return true;
}

pub fn hasNominalIdentity(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return switch (graph.resolvedSemanticType(ty) orelse return false) {
        .nominal, .generic => true,
        else => false,
    };
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
        .definition => |x| right == .definition and x == right.definition,
        .nominal => |x| switch (right) {
            .nominal => |y| x == y,
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
    const semantic = representation(graph, ty) orelse return error.UnmaterializedGlobalType;
    return switch (semantic) {
        .builtin => |builtin| builtinLayout(graph, builtin),
        .pointer => .{ .size = graph.target.pointerBytes(), .alignment = graph.target.pointerBytes() },
        .array => |array| blk: {
            const element = try layoutOf(graph, array.element);
            const stride = alignForward(element.size, element.alignment);
            break :blk .{ .size = stride * array.length, .alignment = element.alignment };
        },
        .nominal => |decl| nominalLayout(graph, decl),
        .structural => |shape| structLayout(graph, shape.fields, shape.layout),
        .structural_choice => |shape| choiceLayout(graph, shape.variants, shape.layout),
        .inferred_choice => |shape| choiceLayout(graph, shape.variants, .regular),
        .generic => genericLayout(graph, ty),
        .virtual => .{ .size = graph.target.pointerBytes() * 2, .alignment = graph.target.pointerBytes() },
        .definition => error.TypeHasNoRuntimeLayout,
        .nullable, .inferred_errable => error.UnmaterializedGlobalType,
    };
}

pub fn sizeOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !u64 {
    return (try layoutOf(graph, ty)).size;
}

pub fn alignmentOf(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !u64 {
    return (try layoutOf(graph, ty)).alignment;
}

fn builtinLayout(graph: *const graph_mod.GlobalSemanticGraph, builtin: primitives.BuiltinType) Layout {
    return switch (builtin) {
        .Void => .{ .size = 0, .alignment = 1 },
        .Int8, .UInt8, .Bool, .Any => .{ .size = 1, .alignment = 1 },
        .Int16, .UInt16, .Float16 => .{ .size = 2, .alignment = 2 },
        .Int32, .UInt32, .Float32 => .{ .size = 4, .alignment = 4 },
        .Int64, .UInt64, .Float64 => .{ .size = 8, .alignment = 8 },
        .UIntNative, .Type => .{ .size = graph.target.pointerBytes(), .alignment = graph.target.pointerBytes() },
    };
}

fn nominalLayout(graph: *const graph_mod.GlobalSemanticGraph, decl_id: graph_mod.GlobalTypeDefinitionId) LayoutError!Layout {
    const raw: usize = @intFromEnum(decl_id);
    if (raw >= graph.type_definitions.items.len) return error.UnmaterializedGlobalType;
    const decl = graph.type_definitions.items[raw];
    if (decl.struct_layout == .c_function_pointer) return .{ .size = graph.target.pointerBytes(), .alignment = graph.target.pointerBytes() };
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
            const layout = try layoutOf(graph, field.ty);
            size = @max(size, layout.size);
            alignment = @max(alignment, layout.alignment);
        }
        return .{ .size = alignForward(size, alignment), .alignment = alignment };
    }

    var offset: u64 = 0;
    var alignment: u64 = 1;
    for (graph.fields.items[range.start..][0..range.len]) |field| {
        const layout = try layoutOf(graph, field.ty);
        offset = alignForward(offset, layout.alignment);
        offset += layout.size;
        alignment = @max(alignment, layout.alignment);
    }
    return .{ .size = alignForward(offset, alignment), .alignment = alignment };
}

/// Regular-choice ABI shared with execution descriptors: an i32 tag followed
/// by one physical field per alternative. Payloadless fields occupy one byte.
pub const ChoiceStorage = struct {
    offset: u64 = 4,
    alignment: u64 = 4,

    pub fn append(self: *ChoiceStorage, payload: ?Layout) u64 {
        const field = payload orelse Layout{ .size = 1, .alignment = 1 };
        self.offset = alignForward(self.offset, field.alignment);
        const offset = self.offset;
        self.offset += field.size;
        self.alignment = @max(self.alignment, field.alignment);
        return offset;
    }

    pub fn finish(self: ChoiceStorage) Layout {
        return .{ .size = alignForward(self.offset, self.alignment), .alignment = self.alignment };
    }
};

fn choiceLayout(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.VariantRange, kind: primitives.ChoiceLayout) LayoutError!Layout {
    if (kind == .c_enum) return .{ .size = 4, .alignment = 4 };
    var storage: ChoiceStorage = .{};
    for (graph.variants.items[range.start..][0..range.len]) |variant|
        _ = storage.append(if (variant.payload_type) |payload| try layoutOf(graph, payload) else null);
    return storage.finish();
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
        // Positional arguments and their named spelling identify the same
        // specialization when their declaration-order values agree.
        if (left.name.len != 0 and right.name.len != 0 and !std.mem.eql(u8, graph.text(left.name), graph.text(right.name))) return false;
        switch (left.value) {
            .definition => |left_definition| {
                if (right.value != .definition or left_definition.origin != right.value.definition.origin or
                    !genericArgumentsEqual(graph, left_definition.captures, right.value.definition.captures)) return false;
            },
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

test "cleanup queries require selected Deinit evidence" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const name = try graph.addString(allocator, "Deinit");
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.modules.append(allocator, .{
        .dir = name,
        .is_bundled_core = true,
        .files = .{ .start = 0, .len = 0 },
        .declarations = .{ .start = 0, .len = 2 },
    });
    try graph.family_definitions.append(allocator, .{ .source = source, .declaration = @enumFromInt(0), .kind = .contract, .parameter_count = 1 });
    try graph.declarations.appendSlice(allocator, &.{
        .{ .kind = .contract_type, .name = name, .source = source, .family_definition = @enumFromInt(0) },
        .{ .kind = .function, .name = name, .source = source },
    });
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
    });
    try graph.fields.append(allocator, .{ .name = name, .ty = @enumFromInt(1), .source = source });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(1),
        .input = .{ .start = 0, .len = 1 },
        .output = .{ .start = 0, .len = 0 },
        .flags = .{ .is_deinit = true },
    });
    try std.testing.expect(!hasDestructor(&graph, @enumFromInt(0)));

    try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(0) } });
    try graph.contract_operation_bindings.append(allocator, .{
        .contract_definition = @enumFromInt(0),
        .requirement_index = 0,
        .requirement_source = source,
        .implementation_source = source,
        .name = name,
        .declaration = @enumFromInt(1),
        .materialized_function = @enumFromInt(0),
    });
    try graph.contract_conformances.append(allocator, .{
        .declaration = @enumFromInt(0),
        .participants = .{ .start = 0, .len = 1 },
        .associated_arguments = .{ .start = 1, .len = 0 },
        .operation_bindings = .{ .start = 0, .len = 1 },
        .source = source,
    });
    try std.testing.expect(hasDestructor(&graph, @enumFromInt(0)));
    try std.testing.expect(!hasDestructor(&graph, @enumFromInt(1)));
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

/// An incomplete C declaration has a nominal identity but no value layout.
/// RawPointer does not query the representation of its pointee.
pub fn incompleteDeclaration(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalDeclId {
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    return switch (semantic) {
        .nominal => |id| if (graph.typeDefinition(id).struct_layout == .c_incomplete) graph.typeDefinition(id).declaration else null,
        .generic => if (genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .alias => |target| incompleteDeclaration(graph, target),
            else => null,
        } else null,
        else => null,
    };
}

/// Lifecycle lookup can consult the module defining a nominal destination
/// while retaining the caller's lexical context for reached arguments.
pub fn nominalTypeOwner(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalModuleId {
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    if (semantic == .generic) return graph.moduleForFamilyDefinition(semantic.generic.base);
    if (semantic != .nominal) return null;
    return graph.moduleForTypeDefinition(semantic.nominal);
}

/// References retain the extension owner of their nominal referent. Structural
/// containers do not grant ownership through nested fields or type arguments.
pub fn conformanceParticipantOwner(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalModuleId {
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    if (semantic == .pointer) return conformanceParticipantOwner(graph, semantic.pointer.child);
    return nominalTypeOwner(graph, ty);
}

/// Runtime layout of the language's validated borrowed string literals.
/// Shared by executor presentation and both literal lowerers.
pub fn isStringView(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    const range = fields(graph, ty) orelse return false;
    if (range.len != 2) return false;
    const data = graph.fields.items[range.start];
    const length = graph.fields.items[range.start + 1];
    if (!std.mem.eql(u8, graph.text(data.name), "_data") or !std.mem.eql(u8, graph.text(length.name), "_length")) return false;
    const pointer = graph.semanticType(data.ty);
    return pointer == .pointer and pointer.pointer.mutability == .read_only and
        isBuiltin(graph, pointer.pointer.child, .UInt8) and isBuiltin(graph, length.ty, .UIntNative);
}

/// Compiler-owned entity values have no runtime storage. Following a binding
/// preserves the value, including its precise classification and identity.
pub const EntityValue = union(enum) {
    type: graph_mod.GlobalTypeId,
    definition: graph_mod.DefinitionValue,
};

pub fn entityValue(graph: *const graph_mod.GlobalSemanticGraph, initial: graph_mod.GlobalNodeId) ?EntityValue {
    var node = initial;
    for (0..graph.nodes.items.len + 1) |_| {
        switch (graph.node(node).content) {
            .type_literal => |ty| return .{ .type = ty },
            .definition_literal => |definition| return .{ .definition = definition },
            .binding_use => |id| {
                const binding = graph.binding(id);
                if (binding.mutability != .constant or binding.deferred_initialization) return null;
                node = binding.initialization orelse return null;
            },
            else => return null,
        }
    }
    return null;
}

pub fn typeValue(graph: *const graph_mod.GlobalSemanticGraph, initial: graph_mod.GlobalNodeId) ?graph_mod.GlobalTypeId {
    const value = entityValue(graph, initial) orelse return null;
    return if (value == .type) value.type else null;
}

pub fn definitionClass(allocator: std.mem.Allocator, graph: *graph_mod.GlobalSemanticGraph, definition: graph_mod.GlobalFamilyDefinitionId) !graph_mod.GlobalTypeId {
    for (graph.types.items, 0..) |ty, raw| {
        if (ty == .definition and ty.definition == definition) return @enumFromInt(@as(u32, @intCast(raw)));
    }
    const id: graph_mod.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .definition = definition });
    return id;
}

/// Definition values are distinct from concrete types. Aliases preserve the
/// producer identity and never allocate another template or specialization.
pub fn definitionValue(graph: *const graph_mod.GlobalSemanticGraph, initial: graph_mod.GlobalNodeId) ?graph_mod.DefinitionValue {
    const value = entityValue(graph, initial) orelse return null;
    return if (value == .definition) value.definition else null;
}

pub fn staticDefinitionBinding(graph: *const graph_mod.GlobalSemanticGraph, id: graph_mod.GlobalBindingId) ?graph_mod.DefinitionValue {
    const binding = graph.binding(id);
    if (binding.mutability != .constant or binding.deferred_initialization) return null;
    const semantic = graph.resolvedSemanticType(binding.ty) orelse return null;
    if (semantic != .definition) return null;
    return definitionValue(graph, binding.initialization orelse return null);
}

pub fn isStaticBinding(graph: *const graph_mod.GlobalSemanticGraph, id: graph_mod.GlobalBindingId) bool {
    return staticTypeBinding(graph, id) != null or staticDefinitionBinding(graph, id) != null;
}

pub fn staticTypeBinding(graph: *const graph_mod.GlobalSemanticGraph, id: graph_mod.GlobalBindingId) ?graph_mod.GlobalTypeId {
    const binding = graph.binding(id);
    if (binding.mutability != .constant or binding.deferred_initialization or !isBuiltin(graph, binding.ty, .Type)) return null;
    return typeValue(graph, binding.initialization orelse return null);
}

test "structural compatibility keeps defaults separate from specialization identity" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    const name = try graph.addString(a, "value");
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    for (0..2) |index| {
        try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = @intCast(41 + index) } });
        try graph.fields.append(a, .{ .name = name, .source = source, .ty = @enumFromInt(0), .default_value = @enumFromInt(index) });
        try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = @intCast(index), .len = 1 } } });
    }
    try std.testing.expect(equal(&graph, @enumFromInt(1), @enumFromInt(2)));
    try std.testing.expect(!identityEqual(&graph, @enumFromInt(1), @enumFromInt(2)));
    for ([_]u32{ 1, 2 }) |child|
        try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(child), .mutability = .read_only } });
    try std.testing.expect(equal(&graph, @enumFromInt(3), @enumFromInt(4)));
    try std.testing.expect(!identityEqual(&graph, @enumFromInt(3), @enumFromInt(4)));
}

test "nominal definitions retain identity without declarations and share only representation" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .UInt8 },
        .{ .nominal = @enumFromInt(0) },
        .{ .nominal = @enumFromInt(1) },
    });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "value"), .source = source, .ty = @enumFromInt(0) });
    for (0..2) |index| try graph.type_definitions.append(allocator, .{
        .source = .{ .file_index = 0, .offset = @intCast(index) },
        .struct_fields = .{ .start = 0, .len = 1 },
    });
    try std.testing.expect(!equal(&graph, @enumFromInt(0), @enumFromInt(1)));
    try std.testing.expect(!equal(&graph, @enumFromInt(1), @enumFromInt(2)));
    try std.testing.expectEqual(Layout{ .size = 1, .alignment = 1 }, try layoutOf(&graph, @enumFromInt(1)));
    try std.testing.expectEqual(Layout{ .size = 1, .alignment = 1 }, try layoutOf(&graph, @enumFromInt(2)));
}

test "static type values preserve long alias chains and reject cycles or mutable bindings" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Type } });
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(1), .content = .{ .type_literal = @enumFromInt(0) } });
    const name = try graph.addString(a, "alias");
    for (0..128) |raw| {
        try graph.bindings.append(a, .{ .source = source, .name = name, .ty = @enumFromInt(1), .initialization = @enumFromInt(@as(u32, @intCast(raw))), .mutability = .constant });
        try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(1), .content = .{ .binding_use = @enumFromInt(@as(u32, @intCast(raw))) } });
    }
    try std.testing.expectEqual(@as(?graph_mod.GlobalTypeId, @enumFromInt(0)), staticTypeBinding(&graph, @enumFromInt(127)));
    graph.bindings.items[0].mutability = .variable;
    try std.testing.expectEqual(@as(?graph_mod.GlobalTypeId, null), staticTypeBinding(&graph, @enumFromInt(127)));
    graph.bindings.items[0].mutability = .constant;
    graph.bindings.items[0].initialization = @enumFromInt(128);
    try std.testing.expectEqual(@as(?graph_mod.GlobalTypeId, null), staticTypeBinding(&graph, @enumFromInt(127)));
}

test "definition values preserve classification and aliases without runtime layout" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    const declaration: graph_mod.GlobalFamilyDefinitionId = @enumFromInt(0);
    const name = try graph.addString(a, "family");
    try graph.family_definitions.append(a, .{ .source = source, .kind = .type, .parameter_count = 1 });
    const classification = try definitionClass(a, &graph, declaration);
    try std.testing.expectEqual(classification, try definitionClass(a, &graph, declaration));
    try graph.nodes.append(a, .{ .source = source, .ty = classification, .content = .{ .definition_literal = .{ .origin = declaration } } });
    for (0..128) |raw| {
        try graph.bindings.append(a, .{ .source = source, .name = name, .ty = classification, .initialization = @enumFromInt(@as(u32, @intCast(raw))), .mutability = .constant });
        try graph.nodes.append(a, .{ .source = source, .ty = classification, .content = .{ .binding_use = @enumFromInt(@as(u32, @intCast(raw))) } });
    }
    const last: graph_mod.GlobalBindingId = @enumFromInt(127);
    try std.testing.expectEqual(declaration, staticDefinitionBinding(&graph, last).?.origin);
    try std.testing.expectEqual(null, staticTypeBinding(&graph, last));
    try std.testing.expect(isStaticBinding(&graph, last));
    try std.testing.expectError(error.TypeHasNoRuntimeLayout, layoutOf(&graph, classification));
    graph.bindings.items[0].mutability = .variable;
    try std.testing.expectEqual(null, staticDefinitionBinding(&graph, last));
    graph.bindings.items[0].mutability = .constant;
    graph.bindings.items[0].initialization = @enumFromInt(128);
    try std.testing.expectEqual(null, staticDefinitionBinding(&graph, last));
}

test "nominal identity survives binding aliases pool growth and rejected definitions" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.fields.append(a, .{ .source = source, .name = try graph.addString(a, "value"), .ty = @enumFromInt(0) });
    try graph.type_definitions.append(a, .{ .source = source, .struct_fields = .{ .start = 0, .len = 1 } });
    try graph.types.append(a, .{ .nominal = @enumFromInt(0) });
    const retained = graph.checkpoint();
    const name = try graph.addString(a, "Alias");
    for (0..128) |_| {
        try graph.declarations.append(a, .{ .kind = .type, .name = name, .source = source, .type_id = @enumFromInt(1) });
        try graph.type_definitions.append(a, .{ .source = source, .struct_fields = .{ .start = 0, .len = 1 } });
    }
    try graph.types.append(a, .{ .nominal = @enumFromInt(128) });
    try std.testing.expect(!equal(&graph, @enumFromInt(1), @enumFromInt(2)));
    graph.rollback(a, retained);
    try std.testing.expectEqual(@as(usize, 1), graph.type_definitions.items.len);
    try std.testing.expectEqual(@as(usize, 0), graph.declarations.items.len);
    try graph.types.append(a, .{ .nominal = @enumFromInt(0) });
    try std.testing.expect(equal(&graph, @enumFromInt(1), @enumFromInt(2)));
    try std.testing.expectEqual(Layout{ .size = 4, .alignment = 4 }, try layoutOf(&graph, @enumFromInt(2)));
}

test "family identity survives aliases pool growth and rejected definitions" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    const family: graph_mod.GlobalFamilyDefinitionId = @enumFromInt(0);
    try graph.family_definitions.append(a, .{ .source = source, .kind = .type, .parameter_count = 1 });
    const classification = try definitionClass(a, &graph, family);
    const retained = graph.checkpoint();
    const name = try graph.addString(a, "Alias");
    for (0..128) |_| {
        try graph.declarations.append(a, .{ .kind = .binding, .name = name, .source = source });
        try graph.family_definitions.append(a, .{ .source = source, .kind = .type, .parameter_count = 1 });
    }
    const other = try definitionClass(a, &graph, @enumFromInt(128));
    try std.testing.expect(!equal(&graph, classification, other));
    try std.testing.expectEqual(classification, try definitionClass(a, &graph, family));
    graph.rollback(a, retained);
    try std.testing.expectEqual(@as(usize, 1), graph.family_definitions.items.len);
    try std.testing.expectEqual(@as(usize, 0), graph.declarations.items.len);
    try std.testing.expectEqual(classification, try definitionClass(a, &graph, family));
}

test "operation compatibility retains nominal field identity and allows only optional extra inputs" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    const item = try graph.addString(a, "item");
    const fallback = try graph.addString(a, "fallback");
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Bool }, .{ .nominal = @enumFromInt(0) }, .{ .nominal = @enumFromInt(1) } });
    for (0..2) |_| try graph.type_definitions.append(a, .{ .source = source, .struct_fields = .{ .start = 0, .len = 1 } });
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .bool_literal = false } });
    try graph.fields.appendSlice(a, &.{
        .{ .source = source, .name = item, .ty = @enumFromInt(0) },
        .{ .source = source, .name = item, .ty = @enumFromInt(1) },
        .{ .source = source, .name = item, .ty = @enumFromInt(1) },
        .{ .source = source, .name = fallback, .ty = @enumFromInt(0), .default_value = @enumFromInt(0) },
        .{ .source = source, .name = item, .ty = @enumFromInt(2) },
        .{ .source = source, .name = fallback, .ty = @enumFromInt(0) },
    });
    const required: graph_mod.FieldRange = .{ .start = 1, .len = 1 };
    try std.testing.expect(operationInputsCompatible(&graph, required, .{ .start = 2, .len = 2 }));
    try std.testing.expect(!operationFieldsEqual(&graph, required, .{ .start = 2, .len = 2 }));
    try std.testing.expect(!operationInputsCompatible(&graph, required, .{ .start = 4, .len = 1 }));
    try std.testing.expect(!operationInputsCompatible(&graph, .{ .start = 4, .len = 1 }, .{ .start = 4, .len = 2 }));
    try std.testing.expect(!equal(&graph, @enumFromInt(1), @enumFromInt(2)));
}

test "definition values preserve captured environments through binding aliases" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.family_definitions.append(a, .{ .source = source, .kind = .type, .parameter_count = 2 });
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Bool }, .{ .builtin = .Int32 } });
    const classification = try definitionClass(a, &graph, @enumFromInt(0));
    for (0..2) |raw| {
        try graph.generic_arguments.append(a, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = @enumFromInt(raw) } });
        try graph.nodes.append(a, .{ .source = source, .ty = classification, .content = .{ .definition_literal = .{ .origin = @enumFromInt(0), .captures = .{ .start = @intCast(raw), .len = 1 } } } });
        try graph.bindings.append(a, .{ .source = source, .name = try graph.addString(a, "alias"), .ty = classification, .initialization = @enumFromInt(raw), .mutability = .constant });
    }
    const first = staticDefinitionBinding(&graph, @enumFromInt(0)).?;
    const second = staticDefinitionBinding(&graph, @enumFromInt(1)).?;
    try std.testing.expectEqual(first.origin, second.origin);
    try std.testing.expect(!genericArgumentsEqual(&graph, first.captures, second.captures));
    for (0..128) |_| try graph.generic_arguments.append(a, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .comptime_int = 7 } });
    try std.testing.expectEqualDeep(first, staticDefinitionBinding(&graph, @enumFromInt(0)).?);
    try std.testing.expectEqualDeep(second, staticDefinitionBinding(&graph, @enumFromInt(1)).?);
}

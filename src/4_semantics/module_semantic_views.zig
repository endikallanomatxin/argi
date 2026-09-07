const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");
const entities = @import("module_semantic_entities.zig");

pub fn typeView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleTypeId) !entities.ModuleType {
    if (@intFromEnum(id) >= graph.types.items.len) return error.InvalidModuleTypeId;
    return switch (graph.types.items[@intFromEnum(id)]) {
        .builtin => |value| .{ .builtin = value },
        .declared => |value| .{ .declared = value },
        .pointer => |value| .{ .pointer = .{ .child = value.child, .mutability = value.mutability } },
        .array => |value| .{ .array = .{ .length = value.length, .element = value.element } },
        .nullable => |value| .{ .nullable = value },
        .inferred_errable => |value| .{ .inferred_errable = value },
        .structural => |range| .{ .structural = .{
            .fields = .{ .start = @as(u32, @intCast(graph.fields.items.len)) + range.start, .len = range.len },
            .layout = .regular,
        } },
        .structural_choice => |range| .{ .structural_choice = .{
            .variants = .{ .start = @as(u32, @intCast(graph.choice_variant_entries.items.len)) + range.start, .len = range.len },
            .layout = .regular,
        } },
        .generic => |value| .{ .generic = .{
            .base = value.base,
            .arguments = .{ .start = value.arguments.start, .len = value.arguments.len },
        } },
    };
}

pub fn fieldView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFieldId) !entities.Field {
    const raw = @intFromEnum(id);
    const regular_count: u32 = @intCast(graph.fields.items.len);
    const field = if (raw < regular_count)
        graph.fields.items[raw]
    else blk: {
        const structural = raw - regular_count;
        if (structural >= graph.structural_fields.items.len) return error.InvalidModuleFieldId;
        break :blk graph.structural_fields.items[structural];
    };
    if (field.module_file_index >= graph.file_offsets.items.len) return error.InvalidModuleFileIndex;

    const semantic = findFieldSemantic(graph, id);
    if (field.default_value != null and (semantic == null or semantic.?.default_value == null))
        return error.ModuleFieldDefaultNotLowered;

    return .{
        .name = field.name,
        .ty = field.ty,
        .storage_type = if (semantic) |value| value.storage_type else null,
        .source = .{ .file_index = field.module_file_index, .offset = field.source_offset },
        .default_value = if (semantic) |value| value.default_value else null,
    };
}

pub fn variantView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleVariantId) !entities.ChoiceVariant {
    const raw = @intFromEnum(id);
    const regular_count: u32 = @intCast(graph.choice_variant_entries.items.len);
    const variant = if (raw < regular_count)
        graph.choice_variant_entries.items[raw]
    else blk: {
        const structural = raw - regular_count;
        if (structural >= graph.structural_choice_variants.items.len) return error.InvalidModuleVariantId;
        break :blk graph.structural_choice_variants.items[structural];
    };
    if (variant.qualifier != null) return error.UnresolvedChoiceQualifier;
    if (variant.module_file_index >= graph.file_offsets.items.len) return error.InvalidModuleFileIndex;

    const semantic = findVariantSemantic(graph, id);
    return .{
        .name = variant.name,
        .payload_type = variant.payload_type,
        .option_decl = if (semantic) |value| value.option_decl else null,
        .source = .{ .file_index = variant.module_file_index, .offset = variant.source_offset },
        .value = if (semantic) |value| value.value else @intCast(raw),
    };
}

pub fn genericArgumentView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleGenericArgId) !entities.GenericArgument {
    const raw = @intFromEnum(id);
    if (raw >= graph.generic_type_arguments.items.len) return error.InvalidModuleGenericArgumentId;
    const value = graph.generic_type_arguments.items[raw];
    return .{ .name = value.name, .value = .{ .type = value.ty } };
}

pub fn functionView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) !entities.Function {
    const raw = @intFromEnum(id);
    if (raw >= graph.functions.items.len) return error.InvalidModuleFunctionId;
    const function = graph.functions.items[raw];
    const semantic = findFunctionSemantic(graph, id);
    return .{
        .declaration = function.declaration,
        .input = .{ .start = function.input.start, .len = function.input.len },
        .output = .{ .start = function.output.start, .len = function.output.len },
        .body = if (semantic) |value| value.body else null,
        .input_bindings = if (semantic) |value| value.input_bindings else .{ .start = 0, .len = 0 },
        .output_bindings = if (semantic) |value| value.output_bindings else .{ .start = 0, .len = 0 },
        .inferred_error_reasons = if (semantic) |value| value.inferred_error_reasons else null,
        .safety_primitive = if (semantic) |value| value.safety_primitive else .none,
        .flags = if (semantic) |value| value.flags else .{},
    };
}

fn findFunctionSemantic(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) ?entities.FunctionSemantic {
    for (graph.semantic.function_semantics.items) |value| if (value.function == id) return value;
    return null;
}

fn findFieldSemantic(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFieldId) ?entities.FieldSemantic {
    for (graph.semantic.field_semantics.items) |value| if (value.field == id) return value;
    return null;
}

fn findVariantSemantic(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleVariantId) ?entities.VariantSemantic {
    for (graph.semantic.variant_semantics.items) |value| if (value.variant == id) return value;
    return null;
}

test "module views expose compatibility types through shared primitives" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const view = try typeView(&graph, @enumFromInt(0));
    try std.testing.expectEqual(@import("semantic_primitives.zig").BuiltinType.Int32, view.builtin);
}

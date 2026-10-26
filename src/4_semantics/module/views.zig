const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");

pub fn typeCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.types.items.len;
}

pub fn fieldCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.fields.items.len;
}

pub fn variantCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.variants.items.len;
}

pub fn genericArgumentCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.generic_arguments.items.len;
}

pub fn bindingTypeUnresolved(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleBindingId) bool {
    for (graph.semantic.unresolved_binding_types.items) |candidate|
        if (candidate == id) return true;
    return false;
}

pub fn declarationView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleDeclId) !entities.Declaration {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.declarations.items.len) return error.InvalidModuleDeclarationId;
    const declaration = graph.declarations.items[raw];
    if (declaration.module_file_index >= graph.file_offsets.items.len) return error.InvalidModuleFileIndex;
    const domain_count: u32 = if (declaration.kind == .contract_type) count: {
        for (graph.semantic.parameterized_storage.contract_definitions.items) |definition|
            if (definition.declaration == id) break :count @intCast(definition.domains.len);
        break :count 0;
    } else 0;

    return .{
        .kind = declaration.kind,
        .name = declaration.name,
        .source = .{ .file_index = declaration.module_file_index, .offset = declaration.source_offset },
        .type_id = declaration.type_id,
        .function_id = declaration.function_id,
        .generic_parameter_count = declaration.generic_parameter_count,
        .contract_domain_count = domain_count,
    };
}

pub fn typeView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleTypeId) !entities.ModuleType {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.semantic.types.items.len) return error.InvalidModuleTypeId;
    return graph.semantic.types.items[raw];
}

pub fn fieldView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFieldId) !entities.Field {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.semantic.fields.items.len) return error.InvalidModuleFieldId;
    return graph.semantic.fields.items[raw];
}

pub fn variantView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleVariantId) !entities.ChoiceVariant {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.semantic.variants.items.len) return error.InvalidModuleVariantId;
    return graph.semantic.variants.items[raw];
}

pub fn genericArgumentView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleGenericArgId) !entities.GenericArgument {
    const raw: usize = @intFromEnum(id);
    if (raw < graph.semantic.generic_arguments.items.len) return graph.semantic.generic_arguments.items[raw];
    return error.InvalidModuleGenericArgumentId;
}

pub fn functionView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) !entities.Function {
    const raw: usize = @intFromEnum(id);
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
        .foreign_symbol = if (semantic) |value| value.foreign_symbol else null,
        .safety_primitive = if (semantic) |value| value.safety_primitive else .none,
        .flags = if (semantic) |value| value.flags else .{},
    };
}

fn findFunctionSemantic(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) ?entities.FunctionSemantic {
    for (graph.semantic.function_semantics.items) |value| if (value.function == id) return value;
    return null;
}
test "module views expose one canonical type pool" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.semantic.types.append(allocator, .{ .resolved = .{ .builtin = .Int32 } });
    try graph.semantic.external_refs.append(allocator, .{
        .kind = .type,
        .module_path = null,
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try graph.semantic.types.append(allocator, .{ .resolved = .{ .inferred_choice = .{
        .identity = 4,
        .kind = .reasons,
        .variants = .{ .start = 0, .len = 0 },
    } } });
    try graph.semantic.types.append(allocator, .{ .external = @enumFromInt(0) });
    try graph.semantic.types.append(allocator, .{ .resolved = .{ .pointer = .{
        .child = @enumFromInt(2),
        .mutability = .read_only,
    } } });

    try std.testing.expectEqual(@import("../primitives/schema.zig").BuiltinType.Int32, (try typeView(&graph, @enumFromInt(0))).resolved.builtin);
    try std.testing.expectEqual(@import("../primitives/schema.zig").InferredChoiceKind.reasons, (try typeView(&graph, @enumFromInt(1))).resolved.inferred_choice.kind);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum((try typeView(&graph, @enumFromInt(2))).external));
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum((try typeView(&graph, @enumFromInt(3))).resolved.pointer.child));
    try std.testing.expectEqual(@as(usize, 4), typeCount(&graph));
}

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
    return .{
        .kind = declaration.kind,
        .name = declaration.name,
        .source = .{ .file_index = declaration.module_file_index, .offset = declaration.source_offset },
        .type_id = declaration.type_id,
        .function_id = declaration.function_id,
        .family_definition = declaration.family_definition,
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

pub fn recordFields(graph: *const graph_mod.ModuleSemanticGraph, ty: entities.ModuleTypeId) ?entities.FieldRange {
    const value = typeView(graph, ty) catch return null;
    if (value != .resolved) return null;
    return switch (value.resolved) {
        .structural => |shape| shape.fields,
        .nominal => |id| graph.semantic.type_definitions.items[@intFromEnum(id)].struct_fields,
        else => null,
    };
}

pub fn functionSignatureDeferred(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) bool {
    const function = graph.functions.items[@intFromEnum(id)];
    if (function.input_type) |ty| if (recordFields(graph, ty) == null) return true;
    if (function.output_type) |ty| if (recordFields(graph, ty) == null) return true;
    return false;
}

pub fn functionView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) !entities.Function {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.functions.items.len) return error.InvalidModuleFunctionId;
    return graph.functions.items[raw];
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

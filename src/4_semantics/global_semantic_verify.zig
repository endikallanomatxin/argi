const std = @import("std");
const graph_mod = @import("global_semantic_graph.zig");
const payload = @import("semantic_payload_verify.zig");
const verify = @import("semantic_verify.zig");

pub fn verifyGlobal(graph: *const graph_mod.GlobalSemanticGraph) !void {
    const bounds = makeBounds(graph);
    try verifyModulePartitions(graph);

    for (graph.declarations.items) |declaration| try payload.declaration(graph_mod.Ids, declaration, bounds);
    for (graph.symbols.items) |symbol| {
        try require(verify.stringFits(symbol.name, graph.strings.items));
        try require(verify.rangeFits(symbol.declarations, graph.symbol_declarations.items.len));
    }
    for (graph.symbol_declarations.items) |id| try require(verify.idFits(id, graph.declarations.items.len));

    for (graph.types.items) |value| try payload.semanticType(graph_mod.Ids, value, bounds);
    try verifyGenericInstances(graph);
    for (graph.fields.items) |value| try payload.field(graph_mod.Ids, value, bounds);
    for (graph.variants.items) |value| try payload.variant(graph_mod.Ids, value, bounds);
    for (graph.generic_arguments.items) |value| try payload.genericArgument(graph_mod.Ids, value, bounds);
    for (graph.functions.items) |value| try payload.function(graph_mod.Ids, value, bounds);
    for (graph.bindings.items) |value| try payload.binding(graph_mod.Ids, value, bounds);
    for (graph.blocks.items) |value| try payload.block(graph_mod.Ids, value, bounds);
    for (graph.value_fields.items) |value| try payload.valueField(graph_mod.Ids, value, bounds);
    for (graph.switch_cases.items) |value| try payload.switchCase(graph_mod.Ids, value, bounds);
    for (graph.switches.items) |value| try payload.switchPayload(graph_mod.Ids, value, bounds);
    for (graph.auto_deinit_fields.items) |value| try payload.autoDeinitField(graph_mod.Ids, value, bounds);
    for (graph.auto_deinits.items) |value| try payload.autoDeinit(graph_mod.Ids, value, bounds);
    for (graph.virtual_registries.items) |value| try payload.virtualRegistry(graph_mod.Ids, value, bounds);
    for (graph.virtualizes.items) |value| try payload.virtualize(graph_mod.Ids, value, bounds);
    for (graph.virtual_calls.items) |value| try payload.virtualCall(graph_mod.Ids, value, bounds);
    for (graph.reach_segments.items) |range| try require(verify.stringFits(range, graph.strings.items));
    for (graph.reach_alternatives.items) |value| try payload.reachAlternative(graph_mod.Ids, value, bounds);
    for (graph.reaches.items) |value| try payload.reach(graph_mod.Ids, value, bounds);
    for (graph.nullable_unwraps.items) |value| try payload.nullableUnwrap(graph_mod.Ids, value, bounds);
    for (graph.testing_expect_errors.items) |value| try payload.testingExpectError(graph_mod.Ids, value, bounds);
    for (graph.error_propagations.items) |value| try payload.errorPropagation(graph_mod.Ids, value, bounds);
    for (graph.error_contexts.items) |value| try payload.errorContext(graph_mod.Ids, value, bounds);
    for (graph.nodes.items) |value| try payload.node(graph_mod.Ids, value, bounds);

    for (graph.node_refs.items) |id| try require(verify.idFits(id, graph.nodes.items.len));
    for (graph.type_refs.items) |id| try require(verify.idFits(id, graph.types.items.len));
    for (graph.binding_refs.items) |id| try require(verify.idFits(id, graph.bindings.items.len));
    for (graph.function_refs.items) |id| try require(verify.idFits(id, graph.functions.items.len));
    for (graph.virtual_registry_refs.items) |id| try require(verify.idFits(id, graph.virtual_registries.items.len));
    for (graph.roots.items) |id| try require(verify.idFits(id, graph.nodes.items.len));
}

fn verifyGenericInstances(graph: *const graph_mod.GlobalSemanticGraph) !void {
    var generic_count: usize = 0;
    for (graph.types.items) |ty| switch (ty) {
        .generic => generic_count += 1,
        else => {},
    };
    try require(generic_count == graph.generic_instances.items.len);

    for (graph.generic_instances.items, 0..) |instance, index| {
        try require(verify.idFits(instance.type_id, graph.types.items.len));
        try require(graph.types.items[@intFromEnum(instance.type_id)] == .generic);
        for (graph.generic_instances.items[0..index]) |previous|
            try require(previous.type_id != instance.type_id);
        switch (instance.shape) {
            .structure => |shape| try require(verify.rangeFits(shape.fields, graph.fields.items.len)),
            .choice => |shape| try require(verify.rangeFits(shape.variants, graph.variants.items.len)),
            .array => |shape| try require(verify.idFits(shape.element, graph.types.items.len)),
            .alias => |target| try require(verify.idFits(target, graph.types.items.len)),
        }
    }
}

fn verifyModulePartitions(graph: *const graph_mod.GlobalSemanticGraph) !void {
    var file_cursor: usize = 0;
    var declaration_cursor: usize = 0;

    for (graph.modules.items, 0..) |module, module_index| {
        try require(verify.stringFits(module.dir, graph.strings.items));
        try require(module.files.start == file_cursor);
        try require(module.declarations.start == declaration_cursor);
        try require(verify.rangeFits(module.files, graph.files.items.len));
        try require(verify.rangeFits(module.declarations, graph.declarations.items.len));

        for (graph.files.items[module.files.start..][0..module.files.len]) |file| {
            try require(@intFromEnum(file.module) == module_index);
            try require(verify.stringFits(file.path, graph.strings.items));
        }

        file_cursor += module.files.len;
        declaration_cursor += module.declarations.len;
    }

    try require(file_cursor == graph.files.items.len);
    try require(declaration_cursor == graph.declarations.items.len);
}

fn makeBounds(graph: *const graph_mod.GlobalSemanticGraph) payload.Bounds {
    return .{
        .files = graph.files.items.len,
        .declarations = graph.declarations.items.len,
        .types = graph.types.items.len,
        .functions = graph.functions.items.len,
        .bindings = graph.bindings.items.len,
        .nodes = graph.nodes.items.len,
        .blocks = graph.blocks.items.len,
        .fields = graph.fields.items.len,
        .variants = graph.variants.items.len,
        .generic_arguments = graph.generic_arguments.items.len,
        .value_fields = graph.value_fields.items.len,
        .switch_cases = graph.switch_cases.items.len,
        .switches = graph.switches.items.len,
        .auto_deinit_fields = graph.auto_deinit_fields.items.len,
        .auto_deinits = graph.auto_deinits.items.len,
        .virtual_registries = graph.virtual_registries.items.len,
        .virtualizes = graph.virtualizes.items.len,
        .virtual_calls = graph.virtual_calls.items.len,
        .reach_segments = graph.reach_segments.items.len,
        .reach_alternatives = graph.reach_alternatives.items.len,
        .reaches = graph.reaches.items.len,
        .nullable_unwraps = graph.nullable_unwraps.items.len,
        .testing_expect_errors = graph.testing_expect_errors.items.len,
        .error_propagations = graph.error_propagations.items.len,
        .error_contexts = graph.error_contexts.items.len,
        .node_refs = graph.node_refs.items.len,
        .type_refs = graph.type_refs.items.len,
        .binding_refs = graph.binding_refs.items.len,
        .function_refs = graph.function_refs.items.len,
        .virtual_registry_refs = graph.virtual_registry_refs.items.len,
        .strings = graph.strings.items,
    };
}

fn require(ok: bool) !void {
    if (!ok) return error.InvalidGlobalSemanticGraph;
}

test "global verifier accepts an empty linked graph" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try verifyGlobal(&graph);
}

test "global verifier rejects dangling root ids" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.roots.append(allocator, @enumFromInt(0));
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyGlobal(&graph));
}
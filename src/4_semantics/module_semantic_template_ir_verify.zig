const graph_mod = @import("module_semantic_graph.zig");
const ir = @import("module_semantic_template_ir.zig");
const payload = @import("semantic_payload_verify.zig");
const verify = @import("semantic_verify.zig");
const views = @import("module_semantic_views.zig");

pub fn verifyIR(graph: *const graph_mod.ModuleSemanticGraph) !void {
    const storage = &graph.semantic.templates.ir;
    const bounds = makeBounds(graph);

    for (storage.int_expressions.items) |expression| switch (expression) {
        .literal => {},
        .parameter => |id| try require(verify.idFits(id, graph.semantic.templates.generic_parameters.items.len)),
        .binary => |value| {
            try require(verify.idFits(value.left, storage.int_expressions.items.len));
            try require(verify.idFits(value.right, storage.int_expressions.items.len));
        },
    };

    for (storage.types.items) |ty| switch (ty) {
        .concrete => |id| try require(verify.idFits(id, views.typeCount(graph))),
        .parameter => |id| try require(verify.idFits(id, graph.semantic.templates.generic_parameters.items.len)),
        .abstract_self => {},
        .external => |id| try require(verify.idFits(id, graph.semantic.external_refs.items.len)),
        .array => |value| {
            try require(verify.idFits(value.length, storage.int_expressions.items.len));
            try require(verify.idFits(value.element, storage.types.items.len));
        },
        .resolved => |resolved| try payload.semanticType(ir.Ids, resolved, bounds),
    };

    for (storage.declarations.items) |decl| try declarationRef(graph, decl.target);
    for (storage.functions.items) |function| switch (function.target) {
        .module => |id| try require(verify.idFits(id, graph.functions.items.len)),
        .external => |id| try require(verify.idFits(id, graph.semantic.external_refs.items.len)),
    };
    for (storage.variants.items) |variant| switch (variant) {
        .reference => |reference| switch (reference) {
            .module => |id| try require(verify.idFits(id, views.variantCount(graph))),
            .external => |id| try require(verify.idFits(id, graph.semantic.external_refs.items.len)),
        },
        .semantic => |value| try payload.variant(ir.Ids, value, bounds),
    };

    for (storage.fields.items) |value| try payload.field(ir.Ids, value, bounds);
    for (storage.generic_arguments.items) |value| {
        try require(verify.stringFits(value.name, graph.strings.items));
        switch (value.value) {
            .type => |id| try require(verify.idFits(id, storage.types.items.len)),
            .comptime_int => |id| try require(verify.idFits(id, storage.int_expressions.items.len)),
        }
    }
    for (storage.bindings.items) |value| try payload.binding(ir.Ids, value, bounds);
    for (storage.blocks.items) |value| try payload.block(ir.Ids, value, bounds);
    for (storage.value_fields.items) |value| try payload.valueField(ir.Ids, value, bounds);
    for (storage.switch_cases.items) |value| try payload.switchCase(ir.Ids, value, bounds);
    for (storage.switches.items) |value| try payload.switchPayload(ir.Ids, value, bounds);
    for (storage.auto_deinit_fields.items) |value| try payload.autoDeinitField(ir.Ids, value, bounds);
    for (storage.auto_deinits.items) |value| try payload.autoDeinit(ir.Ids, value, bounds);
    for (storage.virtual_registries.items) |value| try payload.virtualRegistry(ir.Ids, value, bounds);
    for (storage.virtualizes.items) |value| try payload.virtualize(ir.Ids, value, bounds);
    for (storage.virtual_calls.items) |value| try payload.virtualCall(ir.Ids, value, bounds);
    for (storage.reach_segments.items) |range| try require(verify.stringFits(range, graph.strings.items));
    for (storage.reach_alternatives.items) |value| try payload.reachAlternative(ir.Ids, value, bounds);
    for (storage.reaches.items) |value| try payload.reach(ir.Ids, value, bounds);
    for (storage.nullable_unwraps.items) |value| try payload.nullableUnwrap(ir.Ids, value, bounds);
    for (storage.testing_expect_errors.items) |value| try payload.testingExpectError(ir.Ids, value, bounds);
    for (storage.error_propagations.items) |value| try payload.errorPropagation(ir.Ids, value, bounds);
    for (storage.error_contexts.items) |value| try payload.errorContext(ir.Ids, value, bounds);

    for (storage.pending.items) |pending| try verifyPending(graph, pending);
    for (storage.match_cases.items) |case| {
        try require(verify.stringFits(case.name, graph.strings.items));
        try require(verify.optionalIdFits(case.payload_binding, storage.bindings.items.len));
        try require(verify.idFits(case.body, storage.blocks.items.len));
        try require(verify.sourceFits(case.source, graph.file_offsets.items.len));
    }
    for (storage.nodes.items) |node| switch (node) {
        .resolved => |resolved| try payload.node(ir.Ids, resolved, bounds),
        .pending => |id| try require(verify.idFits(id, storage.pending.items.len)),
    };

    for (storage.node_refs.items) |id| try require(verify.idFits(id, storage.nodes.items.len));
    for (storage.type_refs.items) |id| try require(verify.idFits(id, storage.types.items.len));
    for (storage.binding_refs.items) |id| try require(verify.idFits(id, storage.bindings.items.len));
    for (storage.function_refs.items) |id| try require(verify.idFits(id, storage.functions.items.len));
    for (storage.virtual_registry_refs.items) |id| try require(verify.idFits(id, storage.virtual_registries.items.len));
}

fn verifyPending(graph: *const graph_mod.ModuleSemanticGraph, pending: ir.Pending) !void {
    const storage = &graph.semantic.templates.ir;
    switch (pending) {
        .resolve_name => |value| {
            try require(verify.stringFits(value.name, graph.strings.items));
            try require(verify.sourceFits(value.source, graph.file_offsets.items.len));
        },
        .resolve_call => |value| {
            try require(verify.stringFits(value.name, graph.strings.items));
            try require(verify.idFits(value.input, storage.nodes.items.len));
            try require(verify.sourceFits(value.source, graph.file_offsets.items.len));
        },
        .resolve_field => |value| {
            try require(verify.idFits(value.value, storage.nodes.items.len));
            try require(verify.stringFits(value.field_name, graph.strings.items));
            try require(verify.sourceFits(value.source, graph.file_offsets.items.len));
        },
        .resolve_expression => |value| {
            try require(verify.rangeFits(value.operands, storage.node_refs.items.len));
            if (value.name) |name| try require(verify.stringFits(name, graph.strings.items));
            if (value.module_path) |path| try require(verify.stringFits(path, graph.strings.items));
            try require(verify.rangeFits(value.generic_arguments, storage.generic_arguments.items.len));
            try require(verify.rangeFits(value.match_cases, storage.match_cases.items.len));
            try require(verify.optionalIdFits(value.expected_type, storage.types.items.len));
            try require(verify.sourceFits(value.source, graph.file_offsets.items.len));
        },
        .resolve_copy => |value| try require(verify.idFits(value.value, storage.nodes.items.len)),
        .resolve_deinit => |value| try require(verify.idFits(value.binding, storage.bindings.items.len)),
    }
}

fn declarationRef(graph: *const graph_mod.ModuleSemanticGraph, ref: ir.DeclarationRef) !void {
    switch (ref) {
        .module => |id| try require(verify.idFits(id, graph.declarations.items.len)),
        .external => |id| try require(verify.idFits(id, graph.semantic.external_refs.items.len)),
    }
}

fn makeBounds(graph: *const graph_mod.ModuleSemanticGraph) payload.Bounds {
    const storage = &graph.semantic.templates.ir;
    return .{
        .files = graph.file_offsets.items.len,
        .declarations = storage.declarations.items.len,
        .types = storage.types.items.len,
        .functions = storage.functions.items.len,
        .bindings = storage.bindings.items.len,
        .nodes = storage.nodes.items.len,
        .blocks = storage.blocks.items.len,
        .fields = storage.fields.items.len,
        .variants = storage.variants.items.len,
        .generic_arguments = storage.generic_arguments.items.len,
        .value_fields = storage.value_fields.items.len,
        .switch_cases = storage.switch_cases.items.len,
        .switches = storage.switches.items.len,
        .auto_deinit_fields = storage.auto_deinit_fields.items.len,
        .auto_deinits = storage.auto_deinits.items.len,
        .virtual_registries = storage.virtual_registries.items.len,
        .virtualizes = storage.virtualizes.items.len,
        .virtual_calls = storage.virtual_calls.items.len,
        .reach_segments = storage.reach_segments.items.len,
        .reach_alternatives = storage.reach_alternatives.items.len,
        .reaches = storage.reaches.items.len,
        .nullable_unwraps = storage.nullable_unwraps.items.len,
        .testing_expect_errors = storage.testing_expect_errors.items.len,
        .error_propagations = storage.error_propagations.items.len,
        .error_contexts = storage.error_contexts.items.len,
        .node_refs = storage.node_refs.items.len,
        .type_refs = storage.type_refs.items.len,
        .binding_refs = storage.binding_refs.items.len,
        .function_refs = storage.function_refs.items.len,
        .virtual_registry_refs = storage.virtual_registry_refs.items.len,
        .strings = graph.strings.items,
    };
}

fn require(ok: bool) !void {
    if (!ok) return error.InvalidModuleTemplateIR;
}

test "template IR verifier accepts semantic variants and qualified generic calls" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.file_offsets.append(allocator, .{
        .path = .{ .start = 0, .len = 0 },
        .declaration_base = 0,
        .declaration_count = 0,
        .type_reference_base = 0,
        .type_reference_count = 0,
        .import_reference_base = 0,
        .import_reference_count = 0,
    });
    try graph.semantic.templates.generic_parameters.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .kind = .comptime_int });
    try graph.semantic.templates.ir.int_expressions.append(allocator, .{ .parameter = @enumFromInt(0) });
    try graph.semantic.templates.ir.types.append(allocator, .abstract_self);
    try graph.semantic.templates.ir.variants.append(allocator, .{ .semantic = .{
        .name = .{ .start = 0, .len = 0 },
        .payload_type = @enumFromInt(0),
        .source = .{ .file_index = 0, .offset = 0 },
        .value = 0,
    } });
    try graph.semantic.templates.ir.pending.append(allocator, .{ .resolve_expression = .{
        .kind = .generic_call,
        .module_path = .{ .start = 0, .len = 0 },
        .generic_arguments = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
    } });
    try graph.semantic.templates.ir.nodes.append(allocator, .{ .pending = @enumFromInt(0) });
    try verifyIR(&graph);
}

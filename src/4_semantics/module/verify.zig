const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const views = @import("views.zig");
const payload = @import("../semantic_payload_verify.zig");
const verify = @import("../semantic_verify.zig");

pub fn verifyModule(graph: *const graph_mod.ModuleSemanticGraph) !void {
    try requireLogicalDomainsFit(graph);
    const bounds = makeBounds(graph);
    try verifyFilePartitions(graph);

    for (graph.declarations.items, 0..) |_, index| {
        const declaration = try views.declarationView(graph, @enumFromInt(@as(u32, @intCast(index))));
        try payload.declaration(entities.Ids, declaration, bounds);
    }

    for (graph.symbols.items) |symbol| {
        try require(verify.stringFits(symbol.name, graph.strings.items));
        try require(verify.rangeFits(symbol.declarations, graph.symbol_declarations.items.len));
    }
    for (graph.symbol_declarations.items) |id| try require(verify.idFits(id, graph.declarations.items.len));

    for (graph.type_references.items) |reference| {
        try require(verify.stringFits(reference.name, graph.strings.items));
        if (reference.qualifier) |name| try require(verify.stringFits(name, graph.strings.items));
        try require(verify.optionalIdFits(reference.resolved_type, views.typeCount(graph)));
        switch (reference.resolution) {
            .builtin, .external => {},
            .module => |id| try require(verify.idFits(id, graph.declarations.items.len)),
        }
    }
    for (0..views.typeCount(graph)) |index| {
        const ty = try views.typeView(graph, @enumFromInt(@as(u32, @intCast(index))));
        switch (ty) {
            .resolved => |resolved| try payload.semanticType(entities.Ids, resolved, bounds),
            .external => |external| {
                try require(verify.idFits(external, graph.semantic.external_refs.items.len));
                try require(graph.semantic.external_refs.items[@intFromEnum(external)].kind == .type);
            },
        }
    }
    for (0..views.fieldCount(graph)) |index|
        try payload.field(entities.Ids, try views.fieldView(graph, @enumFromInt(@as(u32, @intCast(index)))), bounds);
    for (0..views.variantCount(graph)) |index|
        try payload.variant(entities.Ids, try views.variantView(graph, @enumFromInt(@as(u32, @intCast(index)))), bounds);
    for (0..views.genericArgumentCount(graph)) |index|
        try payload.genericArgument(entities.Ids, try views.genericArgumentView(graph, @enumFromInt(@as(u32, @intCast(index)))), bounds);
    for (graph.functions.items, 0..) |_, index|
        try payload.function(entities.Ids, try views.functionView(graph, @enumFromInt(@as(u32, @intCast(index)))), bounds);

    const semantic = &graph.semantic;
    try verifyOverlays(graph);

    for (semantic.bindings.items) |value| try payload.binding(entities.Ids, value, bounds);
    for (semantic.blocks.items) |value| try payload.block(entities.Ids, value, bounds);
    for (semantic.value_fields.items) |value| try payload.valueField(entities.Ids, value, bounds);
    for (semantic.switch_cases.items) |value| try payload.switchCase(entities.Ids, value, bounds);
    for (semantic.switches.items) |value| try payload.switchPayload(entities.Ids, value, bounds);
    for (semantic.auto_deinit_fields.items) |value| try payload.autoDeinitField(entities.Ids, value, bounds);
    for (semantic.auto_deinits.items) |value| try payload.autoDeinit(entities.Ids, value, bounds);
    for (semantic.virtual_registries.items) |value| try payload.virtualRegistry(entities.Ids, value, bounds);
    for (semantic.virtualizes.items) |value| try payload.virtualize(entities.Ids, value, bounds);
    for (semantic.virtual_calls.items) |value| try payload.virtualCall(entities.Ids, value, bounds);
    for (semantic.reach_segments.items) |range| try require(verify.stringFits(range, graph.strings.items));
    for (semantic.reach_alternatives.items) |value| try payload.reachAlternative(entities.Ids, value, bounds);
    for (semantic.reaches.items) |value| try payload.reach(entities.Ids, value, bounds);
    for (semantic.nullable_unwraps.items) |value| try payload.nullableUnwrap(entities.Ids, value, bounds);
    for (semantic.testing_expect_errors.items) |value| try payload.testingExpectError(entities.Ids, value, bounds);
    for (semantic.error_propagations.items) |value| try payload.errorPropagation(entities.Ids, value, bounds);
    for (semantic.error_contexts.items) |value| try payload.errorContext(entities.Ids, value, bounds);

    for (semantic.scopes.items) |scope| {
        if (scope.parent != .none) try require(verify.idFits(scope.parent, semantic.scopes.items.len));
        try require(verify.rangeFits(scope.bindings, semantic.binding_refs.items.len));
    }
    for (semantic.external_refs.items) |reference| {
        try require(verify.stringFits(reference.name, graph.strings.items));
        if (reference.module_path) |path| try require(verify.stringFits(path, graph.strings.items));
        if (reference.generic_arguments) |arguments|
            try require(verify.rangeFits(arguments, views.genericArgumentCount(graph)));
        try require(verify.sourceFits(reference.source, graph.file_offsets.items.len));
    }
    for (semantic.pending_operations.items) |operation| try verifyPending(graph, operation);

    for (semantic.nodes.items) |node| switch (node) {
        .resolved => |value| try payload.node(entities.Ids, value, bounds),
        .pending => |id| try require(verify.idFits(id, semantic.pending_operations.items.len)),
    };

    for (semantic.node_refs.items) |id| try require(verify.idFits(id, semantic.nodes.items.len));
    for (semantic.type_refs.items) |id| try require(verify.idFits(id, views.typeCount(graph)));
    for (semantic.binding_refs.items) |id| try require(verify.idFits(id, semantic.bindings.items.len));
    for (semantic.function_refs.items) |id| try require(verify.idFits(id, graph.functions.items.len));
    for (semantic.virtual_registry_refs.items) |id| try require(verify.idFits(id, semantic.virtual_registries.items.len));
    for (semantic.roots.items) |id| try require(verify.idFits(id, semantic.nodes.items.len));
}

fn requireLogicalDomainsFit(graph: *const graph_mod.ModuleSemanticGraph) !void {
    const max = std.math.maxInt(u32);
    try require(graph.declarations.items.len <= max);
    try require(graph.functions.items.len <= max);
    try require(graph.file_offsets.items.len <= max);
    try require(views.typeCount(graph) <= max);
    try require(views.fieldCount(graph) <= max);
    try require(views.variantCount(graph) <= max);
    try require(views.genericArgumentCount(graph) <= max);
    try require(graph.semantic.nodes.items.len <= max);
    try require(graph.semantic.bindings.items.len <= max);
    try require(graph.semantic.blocks.items.len <= max);
}

fn verifyFilePartitions(graph: *const graph_mod.ModuleSemanticGraph) !void {
    var declaration_cursor: usize = 0;
    var type_reference_cursor: usize = 0;

    for (graph.file_offsets.items) |file| {
        try require(verify.stringFits(file.path, graph.strings.items));
        try require(file.declaration_base == declaration_cursor);
        try require(file.type_reference_base == type_reference_cursor);
        try require(rangeFitsRaw(file.declaration_base, file.declaration_count, graph.declarations.items.len));
        try require(rangeFitsRaw(file.type_reference_base, file.type_reference_count, graph.type_references.items.len));
        declaration_cursor += file.declaration_count;
        type_reference_cursor += file.type_reference_count;
    }

    try require(declaration_cursor == graph.declarations.items.len);
    try require(type_reference_cursor == graph.type_references.items.len);
}

fn verifyOverlays(graph: *const graph_mod.ModuleSemanticGraph) !void {
    for (graph.semantic.declaration_semantics.items, 0..) |value, index| {
        try require(verify.idFits(value.declaration, graph.declarations.items.len));
        try require(!hasDeclarationOverlayBefore(graph, index, value.declaration));
    }
    for (graph.semantic.function_semantics.items, 0..) |value, index| {
        try require(verify.idFits(value.function, graph.functions.items.len));
        try require(!hasFunctionOverlayBefore(graph, index, value.function));
        try require(verify.optionalIdFits(value.body, graph.semantic.blocks.items.len));
        try require(verify.rangeFits(value.input_bindings, graph.semantic.binding_refs.items.len));
        try require(verify.rangeFits(value.output_bindings, graph.semantic.binding_refs.items.len));
        try require(verify.optionalIdFits(value.inferred_error_reasons, views.typeCount(graph)));
    }
    for (graph.semantic.field_semantics.items, 0..) |value, index| {
        try require(verify.idFits(value.field, views.fieldCount(graph)));
        try require(!hasFieldOverlayBefore(graph, index, value.field));
        try require(verify.optionalIdFits(value.storage_type, views.typeCount(graph)));
        try require(verify.optionalIdFits(value.default_value, graph.semantic.nodes.items.len));
    }
    for (graph.semantic.variant_semantics.items, 0..) |value, index| {
        try require(verify.idFits(value.variant, views.variantCount(graph)));
        try require(!hasVariantOverlayBefore(graph, index, value.variant));
        try require(verify.optionalIdFits(value.option_decl, graph.declarations.items.len));
    }
}

fn verifyPending(graph: *const graph_mod.ModuleSemanticGraph, operation: entities.PendingOperation) !void {
    const semantic = &graph.semantic;
    switch (operation) {
        .resolve_type => |value| {
            try require(verify.idFits(value.external, semantic.external_refs.items.len));
            try require(semantic.external_refs.items[@intFromEnum(value.external)].kind == .type);
            try require(verify.idFits(value.destination, views.typeCount(graph)));
        },
        .resolve_call => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.callee, semantic.external_refs.items.len));
            try require(semantic.external_refs.items[@intFromEnum(value.callee)].kind == .function);
            try require(verify.idFits(value.input, semantic.nodes.items.len));
            try require(verify.optionalIdFits(value.expected_type, views.typeCount(graph)));
        },
        .resolve_field => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
            try require(verify.stringFits(value.field_name, graph.strings.items));
        },
        .resolve_binary => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.left, semantic.nodes.items.len));
            try require(verify.idFits(value.right, semantic.nodes.items.len));
        },
        .resolve_comparison => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.left, semantic.nodes.items.len));
            try require(verify.idFits(value.right, semantic.nodes.items.len));
        },
        .resolve_index => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
            try require(verify.idFits(value.index, semantic.nodes.items.len));
            try require(verify.optionalIdFits(value.store_value, semantic.nodes.items.len));
        },
        .resolve_choice_literal => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.option, semantic.external_refs.items.len));
            try require(semantic.external_refs.items[@intFromEnum(value.option)].kind == .choice_option);
            try require(verify.optionalIdFits(value.payload, semantic.nodes.items.len));
            try require(verify.optionalIdFits(value.expected_type, views.typeCount(graph)));
        },
        .resolve_choice_payload => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
            try require(verify.stringFits(value.option_name, graph.strings.items));
        },
        .resolve_nullable_unwrap => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.nullable_value, semantic.nodes.items.len));
            try require(verify.idFits(value.fallback_value, semantic.nodes.items.len));
        },
        .resolve_error_propagation => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.errable_value, semantic.nodes.items.len));
            try require(verify.optionalIdFits(value.context, semantic.nodes.items.len));
        },
        .resolve_nullable_test => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
        },
        .resolve_for_each => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.binding, semantic.bindings.items.len));
            try require(verify.idFits(value.iterable, semantic.nodes.items.len));
            try require(verify.idFits(value.body, semantic.blocks.items.len));
        },
        .resolve_match => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
            try require(verify.rangeFits(value.cases, semantic.node_refs.items.len));
        },
        .resolve_match_case => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.option, semantic.external_refs.items.len));
            try require(semantic.external_refs.items[@intFromEnum(value.option)].kind == .choice_option);
            try require(verify.optionalIdFits(value.payload_binding, semantic.bindings.items.len));
            try require(verify.idFits(value.body, semantic.blocks.items.len));
        },
        .resolve_defer => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
        },
        .resolve_keep => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.binding, semantic.bindings.items.len));
        },
        .resolve_name_use => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.stringFits(value.name, graph.strings.items));
        },
        .resolve_name_assignment => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.stringFits(value.name, graph.strings.items));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
        },
        .resolve_import => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.stringFits(value.path, graph.strings.items));
        },
        .resolve_keep_name => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.stringFits(value.name, graph.strings.items));
        },
        .resolve_abstract => |value| {
            try require(verify.idFits(value.declaration, graph.declarations.items.len));
            try require(verify.idFits(value.abstract_ref, semantic.external_refs.items.len));
            try require(semantic.external_refs.items[@intFromEnum(value.abstract_ref)].kind == .abstract);
        },
        .resolve_copy => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
        },
        .resolve_deinit => |value| try require(verify.idFits(value.binding, semantic.bindings.items.len)),
    }
}

fn makeBounds(graph: *const graph_mod.ModuleSemanticGraph) payload.Bounds {
    const semantic = &graph.semantic;
    return .{
        .files = graph.file_offsets.items.len,
        .declarations = graph.declarations.items.len,
        .types = views.typeCount(graph),
        .functions = graph.functions.items.len,
        .bindings = semantic.bindings.items.len,
        .nodes = semantic.nodes.items.len,
        .blocks = semantic.blocks.items.len,
        .fields = views.fieldCount(graph),
        .variants = views.variantCount(graph),
        .generic_arguments = views.genericArgumentCount(graph),
        .value_fields = semantic.value_fields.items.len,
        .switch_cases = semantic.switch_cases.items.len,
        .switches = semantic.switches.items.len,
        .auto_deinit_fields = semantic.auto_deinit_fields.items.len,
        .auto_deinits = semantic.auto_deinits.items.len,
        .virtual_registries = semantic.virtual_registries.items.len,
        .virtualizes = semantic.virtualizes.items.len,
        .virtual_calls = semantic.virtual_calls.items.len,
        .reach_segments = semantic.reach_segments.items.len,
        .reach_alternatives = semantic.reach_alternatives.items.len,
        .reaches = semantic.reaches.items.len,
        .nullable_unwraps = semantic.nullable_unwraps.items.len,
        .testing_expect_errors = semantic.testing_expect_errors.items.len,
        .error_propagations = semantic.error_propagations.items.len,
        .error_contexts = semantic.error_contexts.items.len,
        .node_refs = semantic.node_refs.items.len,
        .type_refs = semantic.type_refs.items.len,
        .binding_refs = semantic.binding_refs.items.len,
        .function_refs = semantic.function_refs.items.len,
        .virtual_registry_refs = semantic.virtual_registry_refs.items.len,
        .strings = graph.strings.items,
    };
}

fn hasDeclarationOverlayBefore(graph: *const graph_mod.ModuleSemanticGraph, end: usize, id: entities.ModuleDeclId) bool {
    for (graph.semantic.declaration_semantics.items[0..end]) |value| if (value.declaration == id) return true;
    return false;
}
fn hasFunctionOverlayBefore(graph: *const graph_mod.ModuleSemanticGraph, end: usize, id: entities.ModuleFunctionId) bool {
    for (graph.semantic.function_semantics.items[0..end]) |value| if (value.function == id) return true;
    return false;
}
fn hasFieldOverlayBefore(graph: *const graph_mod.ModuleSemanticGraph, end: usize, id: entities.ModuleFieldId) bool {
    for (graph.semantic.field_semantics.items[0..end]) |value| if (value.field == id) return true;
    return false;
}
fn hasVariantOverlayBefore(graph: *const graph_mod.ModuleSemanticGraph, end: usize, id: entities.ModuleVariantId) bool {
    for (graph.semantic.variant_semantics.items[0..end]) |value| if (value.variant == id) return true;
    return false;
}

fn rangeFitsRaw(start: u32, len: u32, total: usize) bool {
    const start_index: usize = start;
    const count: usize = len;
    return start_index <= total and count <= total - start_index;
}

fn require(ok: bool) !void {
    if (!ok) return error.InvalidModuleSemanticGraph;
}

test "module verifier accepts an empty semantic module" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "empty") };
    defer graph.deinit(allocator);
    try verifyModule(&graph);
}

test "module verifier accepts a well formed external type hole" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    const path = try @import("../primitives/strings.zig").append(&graph.strings, allocator, "main.rg");
    const name = try @import("../primitives/strings.zig").append(&graph.strings, allocator, "Other");
    try graph.file_offsets.append(allocator, .{
        .path = path,
        .declaration_base = 0,
        .declaration_count = 0,
        .type_reference_base = 0,
        .type_reference_count = 0,
    });
    try graph.semantic.external_refs.append(allocator, .{
        .kind = .type,
        .module_path = null,
        .name = name,
        .source = .{ .file_index = 0, .offset = 1 },
    });
    try graph.semantic.types.append(allocator, .{ .external = @enumFromInt(0) });
    try verifyModule(&graph);
}

test "module verifier accepts canonical generic argument tails" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);
    const name = try @import("../primitives/strings.zig").append(&graph.strings, allocator, "n");
    try graph.semantic.generic_arguments.append(allocator, .{ .name = name, .value = .{ .comptime_int = 4 } });
    try verifyModule(&graph);
}

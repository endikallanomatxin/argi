const std = @import("std");
const graph_mod = @import("../graph.zig");
const parameterized_storage = @import("storage.zig");
const ir = @import("ir.zig");
const ir_verify = @import("ir_verify.zig");
const views = @import("../views.zig");
const verify = @import("../../semantic_verify.zig");

pub fn verifyParameterizedForms(graph: *const graph_mod.ModuleSemanticGraph) !void {
    const storage = &graph.semantic.parameterized_storage;
    try ir_verify.verifyIR(graph);

    for (storage.comptime_parameters.items) |parameter| {
        try require(verify.stringFits(parameter.name, graph.strings.items));
        try require(verify.optionalIdFits(parameter.value_type, storage.ir.types.items.len));
        try require(verify.optionalIdFits(parameter.constraint, storage.abstract_constraints.items.len));
    }

    for (storage.abstract_constraints.items) |constraint| {
        try declarationRef(graph, constraint.abstract_ref);
        try require(verify.rangeFits(constraint.arguments, storage.ir.generic_arguments.items.len));
        try require(verify.sourceFits(constraint.source, graph.file_offsets.items.len));
    }

    for (storage.parameterized_functions.items) |parameterized| {
        try require(verify.idFits(parameterized.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(parameterized.parameters, storage.comptime_parameters.items.len));
        try require(verify.idFits(parameterized.input, storage.ir.types.items.len));
        try require(verify.idFits(parameterized.output, storage.ir.types.items.len));
        try require(verify.optionalIdFits(parameterized.body, storage.ir.blocks.items.len));
    }

    for (storage.parameterized_types.items) |parameterized| {
        try require(verify.idFits(parameterized.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(parameterized.parameters, storage.comptime_parameters.items.len));
        try require(verify.idFits(parameterized.body, storage.ir.types.items.len));
    }

    for (storage.abstract_requirements.items) |requirement| {
        try require(verify.stringFits(requirement.name, graph.strings.items));
        try require(verify.idFits(requirement.input, storage.ir.types.items.len));
        try require(verify.idFits(requirement.output, storage.ir.types.items.len));
        try require(verify.rangeFits(requirement.parameters, storage.comptime_parameters.items.len));
    }

    for (storage.abstract_definitions.items) |definition| {
        try require(verify.idFits(definition.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(definition.parameters, storage.comptime_parameters.items.len));
        try require(verify.rangeFits(definition.requirements, storage.abstract_requirements.items.len));
    }

    for (storage.abstract_arguments.items) |argument| switch (argument) {
        .none, .comptime_int => {},
        .type => |ty| try require(verify.idFits(ty, views.typeCount(graph))),
    };

    for (storage.abstract_implementations.items) |implementation| {
        try declarationRef(graph, implementation.abstract_ref);
        try require(verify.idFits(implementation.ty, views.typeCount(graph)));
        try require(verify.rangeFits(implementation.arguments, storage.abstract_arguments.items.len));
        try require(verify.sourceFits(implementation.source, graph.file_offsets.items.len));
    }

    for (storage.parameterized_abstract_implementations.items) |parameterized| {
        try declarationRef(graph, parameterized.abstract_ref);
        try require(verify.rangeFits(parameterized.parameters, storage.comptime_parameters.items.len));
        try require(verify.optionalIdFits(parameterized.concrete_type_pattern, storage.ir.types.items.len));
        if (parameterized.concrete_name) |name| try require(verify.stringFits(name, graph.strings.items));
        try require(verify.rangeFits(parameterized.arguments, storage.ir.generic_arguments.items.len));
        try require(verify.sourceFits(parameterized.source, graph.file_offsets.items.len));
    }

    for (storage.abstract_defaults.items) |default| {
        try declarationRef(graph, default.abstract_ref);
        try require(verify.idFits(default.ty, views.typeCount(graph)));
        try require(verify.sourceFits(default.source, graph.file_offsets.items.len));
    }

    for (storage.parameterized_abstract_defaults.items) |default| {
        try declarationRef(graph, default.abstract_ref);
        try require(verify.rangeFits(default.parameters, storage.comptime_parameters.items.len));
        try require(verify.idFits(default.ty, storage.ir.types.items.len));
        try require(verify.sourceFits(default.source, graph.file_offsets.items.len));
    }
}

fn declarationRef(graph: *const graph_mod.ModuleSemanticGraph, ref: parameterized_storage.DeclarationRef) !void {
    switch (ref) {
        .module => |id| try require(verify.idFits(id, graph.declarations.items.len)),
        .external => |id| try require(verify.idFits(id, graph.semantic.external_refs.items.len)),
    }
}

fn require(ok: bool) !void {
    if (!ok) return error.InvalidModuleSemanticParameterizedState;
}

test "parameterized verifier accepts self contained semantic IR" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    const path = try @import("../../primitives/strings.zig").append(&graph.strings, allocator, "main.rg");
    const name = try @import("../../primitives/strings.zig").append(&graph.strings, allocator, "T");
    try graph.file_offsets.append(allocator, .{
        .path = path,
        .declaration_base = 0,
        .declaration_count = 1,
        .type_reference_base = 0,
        .type_reference_count = 0,
    });
    try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = name,
        .source_offset = 0,
        .module_file_index = 0,
        .syntax_node = @enumFromInt(1),
    });
    try graph.semantic.parameterized_storage.comptime_parameters.append(allocator, .{
        .name = name,
        .kind = .type,
    });
    try graph.semantic.parameterized_storage.ir.types.append(allocator, .{ .parameter = @enumFromInt(0) });
    try graph.semantic.parameterized_storage.parameterized_functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .parameters = .{ .start = 0, .len = 1 },
        .input = @enumFromInt(0),
        .output = @enumFromInt(0),
        .body = null,
    });
    try graph.semantic.parameterized_storage.parameterized_abstract_defaults.append(allocator, .{
        .abstract_ref = .{ .module = @enumFromInt(0) },
        .parameters = .{ .start = 0, .len = 1 },
        .ty = @enumFromInt(0),
        .source = .{ .file_index = 0, .offset = 0 },
    });

    try verifyParameterizedForms(&graph);
}

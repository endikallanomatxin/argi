const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");
const templates = @import("module_semantic_templates.zig");
const views = @import("module_semantic_views.zig");
const verify = @import("semantic_verify.zig");

pub fn verifyTemplates(graph: *const graph_mod.ModuleSemanticGraph) !void {
    const storage = &graph.semantic.templates;

    for (storage.generic_parameters.items) |parameter| {
        try require(verify.stringFits(parameter.name, graph.strings.items));
        try require(verify.optionalIdFits(parameter.value_type, views.typeCount(graph)));
        try require(verify.optionalIdFits(parameter.constraint, storage.abstract_constraints.items.len));
    }

    for (storage.abstract_constraints.items) |constraint| {
        try declarationRef(graph, constraint.abstract_ref);
        if (constraint.arguments) |syntax| try syntaxRef(graph, syntax);
        try require(verify.sourceFits(constraint.source, graph.file_offsets.items.len));
    }

    for (storage.generic_function_templates.items) |template| {
        try require(verify.idFits(template.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(template.parameters, storage.generic_parameters.items.len));
        try syntaxRef(graph, template.input);
        try syntaxRef(graph, template.output);
        if (template.body) |body| try syntaxRef(graph, body);
    }

    for (storage.generic_type_templates.items) |template| {
        try require(verify.idFits(template.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(template.parameters, storage.generic_parameters.items.len));
        try syntaxRef(graph, template.body);
    }

    for (storage.abstract_requirements.items) |requirement| {
        try require(verify.stringFits(requirement.name, graph.strings.items));
        try syntaxRef(graph, requirement.input);
        try syntaxRef(graph, requirement.output);
        try require(verify.rangeFits(requirement.parameters, storage.generic_parameters.items.len));
    }

    for (storage.abstract_definitions.items) |definition| {
        try require(verify.idFits(definition.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(definition.parameters, storage.generic_parameters.items.len));
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

    for (storage.abstract_implementation_templates.items) |template| {
        try declarationRef(graph, template.abstract_ref);
        try require(verify.rangeFits(template.parameters, storage.generic_parameters.items.len));
        if (template.concrete_type_pattern) |syntax| try syntaxRef(graph, syntax);
        if (template.concrete_name) |name| try require(verify.stringFits(name, graph.strings.items));
        if (template.arguments) |syntax| try syntaxRef(graph, syntax);
        try require(verify.sourceFits(template.source, graph.file_offsets.items.len));
    }

    for (storage.abstract_defaults.items) |default| {
        try declarationRef(graph, default.abstract_ref);
        try require(verify.idFits(default.ty, views.typeCount(graph)));
        try require(verify.sourceFits(default.source, graph.file_offsets.items.len));
    }
}

fn syntaxRef(graph: *const graph_mod.ModuleSemanticGraph, ref: templates.ModuleSyntaxRef) !void {
    try require(verify.idFits(ref.file, graph.file_offsets.items.len));
}

fn declarationRef(graph: *const graph_mod.ModuleSemanticGraph, ref: templates.DeclarationRef) !void {
    switch (ref) {
        .local => |id| try require(verify.idFits(id, graph.declarations.items.len)),
        .external => |id| try require(verify.idFits(id, graph.semantic.external_refs.items.len)),
    }
}

fn require(ok: bool) !void {
    if (!ok) return error.InvalidModuleSemanticTemplateState;
}

test "template verifier accepts durable syntax references" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    const path = try @import("semantic_strings.zig").append(&graph.strings, allocator, "main.rg");
    const name = try @import("semantic_strings.zig").append(&graph.strings, allocator, "T");
    try graph.file_offsets.append(allocator, .{
        .path = path,
        .declaration_base = 0,
        .declaration_count = 1,
        .type_reference_base = 0,
        .type_reference_count = 0,
        .import_reference_base = 0,
        .import_reference_count = 0,
    });
    try graph.declarations.append(allocator, .{
        .kind = .function,
        .name = name,
        .source_offset = 0,
        .module_file_index = 0,
        .syntax_node = @enumFromInt(1),
    });
    try graph.semantic.templates.generic_parameters.append(allocator, .{
        .name = name,
        .kind = .type,
    });
    try graph.semantic.templates.generic_function_templates.append(allocator, .{
        .declaration = @enumFromInt(0),
        .parameters = .{ .start = 0, .len = 1 },
        .input = .{ .file = @enumFromInt(0), .node = @enumFromInt(2) },
        .output = .{ .file = @enumFromInt(0), .node = @enumFromInt(3) },
        .body = .{ .file = @enumFromInt(0), .node = @enumFromInt(4) },
    });

    try verifyTemplates(&graph);
}
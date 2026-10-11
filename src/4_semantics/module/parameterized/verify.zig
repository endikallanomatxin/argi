const std = @import("std");
const graph_mod = @import("../graph.zig");
const parameterized_storage = @import("storage.zig");
const ir = @import("ir.zig");
const ir_verify = @import("ir_verify.zig");
const views = @import("../views.zig");
const verify = @import("../../semantic_verify.zig");

fn verifyDomainMappings(graph: *const graph_mod.ModuleSemanticGraph, mappings: []const parameterized_storage.DomainMapping) !void {
    for (mappings) |mapping| {
        try require(verify.stringFits(mapping.name, graph.strings.items));
        try require(mapping.paths.len != 0);
        for (mapping.paths) |path| {
            try require(path.fields.len != 0);
            for (path.fields) |field| try require(verify.stringFits(field, graph.strings.items));
        }
    }
}

fn verifyOutcome(graph: *const graph_mod.ModuleSemanticGraph, outcome: @import("../../primitives/schema.zig").MethodSafetyContract.Outcome, output_count: usize, input_count: usize) anyerror!void {
    try require(outcome.output_index < output_count);
    try require(verify.stringFits(outcome.variant, graph.strings.items));
    try require(verify.sourceFits(outcome.source, graph.file_offsets.items.len));
    for (outcome.dependencies) |dependency| {
        try require(dependency.output_index == outcome.output_index);
        try require(dependency.input_index <= input_count);
    }
    for (outcome.domain_dependencies) |dependency| {
        try require(dependency.output_index == outcome.output_index);
        try require(dependency.input.input_index < input_count);
    }
    for (outcome.owned_outputs) |index| try require(index == outcome.output_index);
    for (outcome.consumed_inputs) |index| try require(index < input_count);
    for (outcome.relocations) |relocation| try require(relocation.destination < input_count and relocation.source < input_count);
    for (outcome.invalidates) |index| try require(index < input_count);
    for (outcome.invalidated_domains) |domain| try require(domain.input_index < input_count);
    for (outcome.outcomes) |child| {
        try require(child.output_index == outcome.output_index);
        try verifyOutcome(graph, child, output_count, input_count);
    }
}

fn verifyOutcomeDomains(outcome: @import("../../primitives/schema.zig").MethodSafetyContract.Outcome, domain_count: usize) anyerror!void {
    for (outcome.domain_dependencies) |dependency| try require(dependency.input.domain_index < domain_count);
    for (outcome.invalidated_domains) |domain| try require(domain.domain_index < domain_count);
    for (outcome.outcomes) |child| try verifyOutcomeDomains(child, domain_count);
}

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
        if (requirement.safety_contract) |contract| {
            try require(verify.sourceFits(contract.source, graph.file_offsets.items.len));
            const input = storage.ir.types.items[@intFromEnum(requirement.input)];
            const output = storage.ir.types.items[@intFromEnum(requirement.output)];
            try require(input == .resolved and input.resolved == .structural);
            try require(output == .resolved and output.resolved == .structural);
            try require(contract.output_count == output.resolved.structural.fields.len);
            for (contract.owned_outputs) |index| try require(index < contract.output_count);
            for (contract.outcomes) |outcome| try verifyOutcome(graph, outcome, contract.output_count, input.resolved.structural.fields.len);
            for (contract.transfers) |transfer| {
                try require(transfer.output_index < contract.output_count);
                try require(transfer.input_index < input.resolved.structural.fields.len);
            }
            for (contract.invalidates) |index| try require(index < input.resolved.structural.fields.len);
            for (contract.retained_inputs) |retained| try require(retained.storage < input.resolved.structural.fields.len and retained.input < input.resolved.structural.fields.len);
            for (contract.emptied_inputs) |index| try require(index < input.resolved.structural.fields.len);
            for (contract.storage_sources) |source| try require(source.output_index < contract.output_count and source.input_index < input.resolved.structural.fields.len);
            for (contract.relocations) |relocation| try require(relocation.destination < input.resolved.structural.fields.len and relocation.source < input.resolved.structural.fields.len);
            for (contract.consumed_inputs) |index| try require(index < input.resolved.structural.fields.len);
            for (contract.domain_dependencies) |dependency| {
                try require(dependency.output_index < contract.output_count);
                try require(dependency.input.input_index < input.resolved.structural.fields.len);
            }
            for (contract.invalidated_domains) |domain| try require(domain.input_index < input.resolved.structural.fields.len);
            for (contract.dependencies) |dependency| {
                try require(dependency.output_index < contract.output_count);
                try require(dependency.input_index <= input.resolved.structural.fields.len);
            }
            for (contract.referents, 0..) |referent, index| {
                try require(referent.output_index < contract.output_count);
                try require(referent.input_index < input.resolved.structural.fields.len);
                for (contract.referents[0..index]) |previous| try require(previous.output_index != referent.output_index);
                var permitted = false;
                for (contract.dependencies) |dependency| if (dependency.output_index == referent.output_index and dependency.input_index == referent.input_index) {
                    permitted = true;
                    break;
                };
                try require(permitted);
            }
        }
    }

    for (storage.abstract_definitions.items) |definition| {
        try require(verify.idFits(definition.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(definition.parameters, storage.comptime_parameters.items.len));
        try require(verify.rangeFits(definition.requirements, storage.abstract_requirements.items.len));
        for (definition.domains) |domain| try require(verify.stringFits(domain, graph.strings.items));
        for (storage.abstract_requirements.items[definition.requirements.start..][0..definition.requirements.len]) |requirement| if (requirement.safety_contract) |contract| {
            for (contract.domain_dependencies) |dependency| try require(dependency.input.domain_index < definition.domains.len);
            for (contract.invalidated_domains) |domain| try require(domain.domain_index < definition.domains.len);
            for (contract.outcomes) |outcome| try verifyOutcomeDomains(outcome, definition.domains.len);
        };
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
        try verifyDomainMappings(graph, implementation.domains);
    }

    for (storage.parameterized_abstract_implementations.items) |parameterized| {
        try declarationRef(graph, parameterized.abstract_ref);
        try require(verify.rangeFits(parameterized.parameters, storage.comptime_parameters.items.len));
        try require(verify.optionalIdFits(parameterized.concrete_type_pattern, storage.ir.types.items.len));
        if (parameterized.concrete_name) |name| try require(verify.stringFits(name, graph.strings.items));
        try require(verify.rangeFits(parameterized.arguments, storage.ir.generic_arguments.items.len));
        try require(verify.sourceFits(parameterized.source, graph.file_offsets.items.len));
        try verifyDomainMappings(graph, parameterized.domains);
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

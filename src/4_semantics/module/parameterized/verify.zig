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
    if (outcome.input_index) |input| try require(input < input_count) else try require(outcome.output_index < output_count);
    try require(verify.stringFits(outcome.variant, graph.strings.items));
    try require(verify.sourceFits(outcome.source, graph.file_offsets.items.len));
    for (outcome.dependencies) |dependency| {
        try require(dependency.output_index < output_count);
        try require(dependency.input_index <= input_count);
    }
    for (outcome.domain_dependencies) |dependency| {
        try require(dependency.output_index < output_count);
        try require(dependency.input.input_index < input_count);
    }
    for (outcome.storage_sources) |source| try require(source.output_index < output_count and source.storage.input_index < input_count);
    for (outcome.emptied_inputs) |storage| try require(storage.input_index < input_count);
    for (outcome.owned_outputs) |index| try require(index < output_count);
    for (outcome.consumed_inputs) |index| try require(index < input_count);
    for (outcome.relocations) |relocation| try require(relocation.destination < input_count and relocation.source < input_count);
    for (outcome.invalidates) |index| try require(index < input_count);
    for (outcome.invalidated_domains) |domain| try require(domain.input_index < input_count);
    for (outcome.outcomes) |child| {
        try verifyOutcome(graph, child, output_count, input_count);
    }
}

fn verifyOutcomeDomains(outcome: @import("../../primitives/schema.zig").MethodSafetyContract.Outcome, domain_count: usize) anyerror!void {
    for (outcome.emptied_inputs) |storage| if (storage.domain_index) |domain| try require(domain < domain_count);
    for (outcome.storage_sources) |source| if (source.storage.domain_index) |domain| try require(domain < domain_count);
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
        try require(verify.optionalIdFits(parameter.default_type, storage.ir.types.items.len));
        try require(verify.optionalIdFits(parameter.default_integer, storage.ir.int_expressions.items.len));
        try require(parameter.default_type == null or parameter.kind == .type);
        try require(parameter.default_integer == null or parameter.kind == .comptime_int);
        try require(verify.optionalIdFits(parameter.constraint, storage.contract_constraints.items.len));
    }

    for (storage.contract_constraints.items) |constraint| {
        try declarationRef(graph, constraint.contract_ref);
        try require(verify.rangeFits(constraint.arguments, storage.ir.generic_arguments.items.len));
        try require(verify.sourceFits(constraint.source, graph.file_offsets.items.len));
    }

    for (storage.parameterized_functions.items) |parameterized| {
        try require(verify.idFits(parameterized.declaration, graph.declarations.items.len));
        if (parameterized.concrete_function) |function| {
            try require(verify.idFits(function, graph.functions.items.len));
            try require(graph.functions.items[@intFromEnum(function)].declaration == parameterized.declaration);
            try require(parameterized.parameters.len == 0 and parameterized.body != null);
        }
        try require(verify.rangeFits(parameterized.parameters, storage.comptime_parameters.items.len));
        try require(verify.idFits(parameterized.input, storage.ir.types.items.len));
        try require(verify.idFits(parameterized.output, storage.ir.types.items.len));
        try require(verify.optionalIdFits(parameterized.body, storage.ir.blocks.items.len));
        try require(verify.rangeFits(parameterized.input_bindings, storage.ir.bindings.items.len));
        try require(verify.rangeFits(parameterized.output_bindings, storage.ir.bindings.items.len));
    }

    for (storage.parameterized_types.items) |parameterized| {
        try require(verify.idFits(parameterized.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(parameterized.parameters, storage.comptime_parameters.items.len));
        try require(verify.idFits(parameterized.body, storage.ir.types.items.len));
    }

    for (storage.contract_requirements.items) |requirement| {
        try require(verify.stringFits(requirement.name, graph.strings.items));
        try require(verify.idFits(requirement.input, storage.ir.types.items.len));
        try require(verify.idFits(requirement.output, storage.ir.types.items.len));
        try require(verify.sourceFits(requirement.source, graph.file_offsets.items.len));
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
            for (contract.retained_inputs) |retained| try require(retained.storage.input_index < input.resolved.structural.fields.len and retained.input < input.resolved.structural.fields.len);
            for (contract.emptied_inputs) |empty| try require(empty.input_index < input.resolved.structural.fields.len);
            for (contract.storage_sources) |source| try require(source.output_index < contract.output_count and source.storage.input_index < input.resolved.structural.fields.len);
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

    for (storage.contract_definitions.items) |definition| {
        try require(verify.idFits(definition.declaration, graph.declarations.items.len));
        try require(verify.rangeFits(definition.parameters, storage.comptime_parameters.items.len));
        try require(verify.rangeFits(definition.participants, storage.comptime_parameters.items.len));
        try require(verify.rangeFits(definition.composition, storage.contract_constraints.items.len));
        for (storage.comptime_parameters.items[definition.participants.start..][0..definition.participants.len]) |parameter| try require(parameter.kind == .type);
        if (definition.participants.len != 0 and definition.parameters.len != 0) {
            try require(definition.parameters.start + definition.parameters.len <= definition.participants.start or
                definition.participants.start + definition.participants.len <= definition.parameters.start);
        }
        try require(verify.rangeFits(definition.requirements, storage.contract_requirements.items.len));
        for (definition.domains) |domain| try require(verify.stringFits(domain, graph.strings.items));
        for (storage.contract_requirements.items[definition.requirements.start..][0..definition.requirements.len]) |requirement| if (requirement.safety_contract) |contract| {
            for (contract.domain_dependencies) |dependency| try require(dependency.input.domain_index < definition.domains.len);
            for (contract.invalidated_domains) |domain| try require(domain.domain_index < definition.domains.len);
            for (contract.outcomes) |outcome| try verifyOutcomeDomains(outcome, definition.domains.len);
        };
    }

    for (storage.contract_conformances.items) |conformance| {
        try verifyDomainMappings(graph, conformance.domains);
        try require(verify.rangeFits(conformance.parameters, storage.comptime_parameters.items.len));
        try declarationRef(graph, conformance.contract_ref);
        try require(verify.rangeFits(conformance.participants, storage.ir.generic_arguments.items.len));
        try require(verify.rangeFits(conformance.associated_arguments, storage.ir.generic_arguments.items.len));
        try require(verify.rangeFits(conformance.operations, storage.contract_operations.items.len));
        try require(verify.sourceFits(conformance.source, graph.file_offsets.items.len));
    }

    for (storage.contract_operations.items) |operation| {
        try require(verify.stringFits(operation.name, graph.strings.items));
        try declarationRef(graph, operation.function);
        try require(verify.sourceFits(operation.source, graph.file_offsets.items.len));
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
    try graph.semantic.parameterized_storage.contract_conformances.append(allocator, .{
        .contract_ref = .{ .module = @enumFromInt(0) },
        .participants = .{ .start = 0, .len = 0 },
        .associated_arguments = .{ .start = 0, .len = 0 },
        .parameters = .{ .start = 0, .len = 1 },
        .source = .{ .file_index = 0, .offset = 0 },
    });

    try verifyParameterizedForms(&graph);
    graph.semantic.parameterized_storage.parameterized_functions.items[0].input_bindings = .{ .start = 0, .len = 1 };
    try std.testing.expectError(error.InvalidModuleSemanticParameterizedState, verifyParameterizedForms(&graph));
    graph.semantic.parameterized_storage.parameterized_functions.items[0].input_bindings = .{ .start = 0, .len = 0 };
    graph.semantic.parameterized_storage.parameterized_functions.items[0].output_bindings = .{ .start = 0, .len = 1 };
    try std.testing.expectError(error.InvalidModuleSemanticParameterizedState, verifyParameterizedForms(&graph));
}

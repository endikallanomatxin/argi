const std = @import("std");
const graph_mod = @import("graph.zig");
const payload = @import("../semantic_payload_verify.zig");
const verify = @import("../semantic_verify.zig");
const lexical_storage = @import("lexical_storage.zig");
const types = @import("types.zig");

pub fn verifyGlobal(graph: *const graph_mod.GlobalSemanticGraph) !void {
    return verifyUnit(graph, null);
}

pub fn verifyUnit(graph: *const graph_mod.GlobalSemanticGraph, unit: ?*const @import("reachability.zig").FunctionSet) !void {
    // Readiness is a property of the selected semantic data, not of whether
    // an incremental owner has released its resolution bookkeeping.
    try require(!graph.hasUnresolvedTypes());
    const bounds = makeBounds(graph);
    for (graph.comptime_requests.items) |id| try require(verify.idFits(id, graph.nodes.items.len));
    try verifyModulePartitions(graph);
    for (graph.argument_defaults.items) |recipe| {
        try require(recipe.module_index < graph.modules.items.len);
        try require(verify.rangeFits(recipe.bindings, graph.argument_default_bindings.items.len));
    }
    for (graph.argument_default_bindings.items) |binding|
        try require(verify.optionalIdFits(binding.ty, graph.types.items.len));
    for (graph.argument_default_temporaries.items) |temporary| {
        try require(verify.idFits(temporary.expression, graph.nodes.items.len));
        try require(verify.idFits(temporary.declaration, graph.nodes.items.len));
        try require(graph.node(temporary.declaration).content == .binding_declaration);
    }
    for (graph.module_aliases.items) |alias| {
        try require(verify.idFits(alias.owner, graph.modules.items.len));
        try require(verify.idFits(alias.target, graph.modules.items.len));
        try require(graph.modules.items[@intFromEnum(alias.target)].namespace == null);
        try require(verify.idFits(alias.declaration, graph.declarations.items.len));
        try require(graph.moduleForDeclaration(alias.declaration) == alias.owner);
        try require(alias.source.file_index < graph.files.items.len);
        try require(graph.declarations.items[@intFromEnum(alias.declaration)].kind == .import_alias);
    }

    for (graph.family_definitions.items) |definition| try payload.familyDefinition(graph_mod.Ids, definition, bounds);
    for (graph.type_definitions.items) |definition| try payload.typeDefinition(graph_mod.Ids, definition, bounds);
    for (graph.declarations.items) |declaration| try payload.declaration(graph_mod.Ids, declaration, bounds);
    try verifySymbols(graph);

    for (graph.types.items) |value| {
        try payload.semanticType(graph_mod.Ids, value, bounds);
        switch (value) {
            .nullable, .inferred_errable => return error.InvalidGlobalSemanticGraph,
            else => {},
        }
    }
    try verifyGenericInstances(graph);
    for (graph.fields.items) |value| try payload.field(graph_mod.Ids, value, bounds);
    for (graph.variants.items) |value| try payload.variant(graph_mod.Ids, value, bounds);
    for (graph.generic_arguments.items) |value| try payload.genericArgument(graph_mod.Ids, value, bounds);
    for (graph.functions.items, 0..) |value, raw| {
        try payload.function(graph_mod.Ids, value, bounds);
        if (value.body != null and (unit == null or unit.?.contains(@enumFromInt(raw)))) for (graph.binding_refs.items[value.output_bindings.start..][0..value.output_bindings.len]) |binding|
            try require(graph.binding(binding).initialization == null);
    }
    try verifyGenericFunctionInstances(graph);
    for (graph.bindings.items, 0..) |value, raw| {
        const id: graph_mod.GlobalBindingId = @enumFromInt(raw);
        if (graph.isBindingTypeUnresolved(id)) {
            try require(unit != null and !unit.?.containsBinding(id));
            try payload.bindingMetadata(graph_mod.Ids, value, bounds);
        } else try payload.binding(graph_mod.Ids, value, bounds);
    }
    for (graph.block_assumptions.items) |value| {
        try require(verify.idFits(value.block, graph.blocks.items.len));
        try require(verify.rangeFits(value.bindings, graph.binding_refs.items.len));
    }
    for (graph.blocks.items) |value| try payload.block(graph_mod.Ids, value, bounds);
    for (graph.value_fields.items) |value| try payload.valueField(graph_mod.Ids, value, bounds);
    for (graph.switch_cases.items) |value| try payload.switchCase(graph_mod.Ids, value, bounds);
    for (graph.switches.items) |value| try payload.switchPayload(graph_mod.Ids, value, bounds);
    for (graph.auto_deinit_fields.items) |value| try payload.autoDeinitField(graph_mod.Ids, value, bounds);
    for (graph.auto_deinits.items) |value| try payload.autoDeinit(graph_mod.Ids, value, bounds);
    for (graph.virtual_registries.items) |value| {
        try payload.virtualRegistry(graph_mod.Ids, value, bounds);
        if (value.safety_contract) |contract| {
            try require(verify.sourceFits(contract.source, graph.files.items.len));
            for (contract.dependencies) |dependency| try require(dependency.output_index < contract.output_count);
            for (contract.referents) |referent| try require(referent.output_index < contract.output_count);
            for (contract.domain_dependencies) |dependency| try require(dependency.output_index < contract.output_count);
        }
    }
    for (graph.contract_conformances.items) |value| {
        try require(verify.idFits(value.context, graph.modules.items.len));
        try require(verify.idFits(value.declaration, graph.family_definitions.items.len));
        try require(graph.familyDefinition(value.declaration).kind == .contract);
        try require(verify.rangeFits(value.participants, graph.generic_arguments.items.len));
        try require(value.participants.len != 0);
        try require(verify.rangeFits(value.operation_bindings, graph.contract_operation_bindings.items.len));
        try require(verify.rangeFits(value.implementation_arguments, graph.generic_arguments.items.len));
        for (graph.generic_arguments.items[value.participants.start..][0..value.participants.len]) |argument| try require(argument.value == .type);
        try require(verify.rangeFits(value.associated_arguments, graph.generic_arguments.items.len));
        try require(verify.sourceFits(value.source, graph.files.items.len));
    }
    for (graph.nodes.items) |node| {
        if (node.content != .function_call) continue;
        const call = node.content.function_call;
        if (graph.callOperation(call)) |identity| {
            try require(identity.conformance < graph.contract_conformances.items.len);
            const conformance = graph.contract_conformances.items[identity.conformance];
            try require(identity.index < conformance.operation_bindings.len);
            try require((@import("contract_evidence.zig").operationInConformance(graph, conformance, identity.index) orelse return error.InvalidGlobalSemanticGraph).acceptsFunction(graph, call.callee));
        }
    }
    for (graph.contract_operation_bindings.items) |binding| {
        try require(verify.optionalIdFits(binding.materialized_function, graph.functions.items.len));
        try require(verify.stringFits(binding.name, graph.strings.items));
        try require(verify.idFits(binding.definition, graph.nodes.items.len));
        if (@import("types.zig").definitionValue(graph, binding.definition)) |definition|
            try require(graph.familyDefinition(definition.origin).kind == .function);
    }
    for (graph.contract_safety_conformances.items) |value| {
        try require(value.selection.conformance < graph.contract_conformances.items.len);
        const selected = graph.contract_conformances.items[value.selection.conformance];
        try require(value.selection.index < selected.operation_bindings.len);
        try require((@import("contract_evidence.zig").operationInConformance(graph, selected, value.selection.index) orelse return error.InvalidGlobalSemanticGraph).acceptsFunction(graph, value.method));
        try require(verify.idFits(value.method, graph.functions.items.len));
        try require(verify.sourceFits(value.source, graph.files.items.len));
        try require(verify.sourceFits(value.contract.source, graph.files.items.len));
        const method = graph.function(value.method);
        if (value.receiver_input_index) |index| try require(index < method.input.len);
        try require(value.contract.output_count == method.output.len);
        for (value.contract.dependencies) |dependency| {
            try require(dependency.output_index < method.output.len);
            try require(dependency.input_index < method.input.len);
        }
        for (value.contract.referents) |dependency| {
            try require(dependency.output_index < method.output.len);
            try require(dependency.input_index < method.input.len);
        }
        for (value.contract.transfers) |transfer| {
            try require(transfer.output_index < method.output.len);
            try require(transfer.input_index < method.input.len);
        }
    }
    for (graph.virtualizes.items) |value| {
        try payload.virtualize(graph_mod.Ids, value, bounds);
        try require(value.methods.len == value.safety_methods.len);
        for (graph.function_refs.items[value.methods.start..][0..value.methods.len], graph.virtual_registry_refs.items[value.safety_methods.start..][0..value.safety_methods.len]) |method, registry| {
            try require(verify.idFits(registry, graph.virtual_registries.items.len));
            try verifyVirtualImplementation(graph, graph.virtual_registries.items[@intFromEnum(registry)], method);
        }
    }
    for (graph.virtual_calls.items) |value| {
        try payload.virtualCall(graph_mod.Ids, value, bounds);
        try require(graph.virtual_registries.items[@intFromEnum(value.safety_methods)].receiver_input_index == value.self_input_index);
    }
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

    try verifyWriteCleanupTargets(graph);
    for (graph.nodes.items, 0..) |node, index| {
        const replacement = @import("replacement.zig");
        const id: graph_mod.GlobalNodeId = @enumFromInt(index);
        if (node.content == .replacement) _ = try replacement.plan(graph, id);
    }
}

fn verifyVirtualImplementation(graph: *const graph_mod.GlobalSemanticGraph, descriptor: graph_mod.VirtualMethodRegistry, method: graph_mod.GlobalFunctionId) !void {
    try require(verify.idFits(method, graph.functions.items.len));
    const function = graph.function(method);
    try require(descriptor.receiver_input_index < function.input.len);
    if (descriptor.safety_contract) |contract| {
        try require(contract.output_count == function.output.len);
        for (contract.invalidates) |index| try require(index < function.input.len);
        for (contract.dependencies) |dependency| try require(dependency.input_index < function.input.len);
        for (contract.referents) |referent| try require(referent.input_index < function.input.len);
        for (contract.domain_dependencies) |dependency| try require(dependency.input.input_index < function.input.len);
        for (contract.invalidated_domains) |domain| try require(domain.input_index < function.input.len);
    }
}

fn verifyWriteCleanupTargets(graph: *const graph_mod.GlobalSemanticGraph) !void {
    // Cleanup metadata must prove the actual destination without evaluating a
    // second address expression or following a retargetable reference slot.
    for (graph.nodes.items) |node| switch (node.content) {
        .pointer_assignment => |write| if (write.cleanup_target) |target| {
            const destination = graph.node(target).content;
            if (destination == .dereference and destination.dereference.pointer == write.pointer) {
                // Exact operand identity describes an evaluated destination;
                // owning transitions additionally require a replacement plan.
            } else {
                const actual = lexical_storage.addressedTarget(graph, write.pointer) orelse return error.InvalidGlobalSemanticGraph;
                try require(lexical_storage.root(graph, target) != null);
                try require(lexical_storage.equal(graph, actual, target));
            }
            const pointer_type = graph.semanticType(graph.node(write.pointer).ty orelse return error.InvalidGlobalSemanticGraph);
            try require(pointer_type == .pointer);
            try require(types.equal(graph, pointer_type.pointer.child, graph.node(target).ty orelse return error.InvalidGlobalSemanticGraph));
        },
        .struct_field_store => |write| if (write.cleanup_target) |target| {
            const field = graph.node(target).content;
            try require(field == .struct_field_access);
            try require(field.struct_field_access.field_index == write.field_index);
            const base = graph.node(field.struct_field_access.value).content;
            if (base != .dereference or base.dereference.pointer != write.struct_ptr) {
                const actual = lexical_storage.addressedTarget(graph, write.struct_ptr) orelse return error.InvalidGlobalSemanticGraph;
                try require(lexical_storage.root(graph, target) != null);
                try require(lexical_storage.equal(graph, actual, field.struct_field_access.value));
            }
            try require(types.equal(graph, write.field_type, graph.node(target).ty orelse return error.InvalidGlobalSemanticGraph));
        },
        else => {},
    };
}

fn verifySymbols(graph: *const graph_mod.GlobalSemanticGraph) !void {
    for (graph.symbols.items) |symbol| {
        try require(verify.stringFits(symbol.name, graph.strings.items));
        try require(symbol.declarations.len != 0);
        try require(verify.rangeFits(symbol.declarations, graph.symbol_declarations.items.len));
        const declarations = graph.symbol_declarations.items[symbol.declarations.start..][0..symbol.declarations.len];
        const owner = graph.moduleForDeclaration(declarations[0]) orelse return error.InvalidGlobalSemanticGraph;
        for (declarations) |id| {
            try require(verify.idFits(id, graph.declarations.items.len));
            try require(graph.moduleForDeclaration(id) == owner);
            try require(std.mem.eql(u8, graph.text(symbol.name), graph.text(graph.declaration(id).name)));
        }
    }
    for (graph.symbol_declarations.items) |id| try require(verify.idFits(id, graph.declarations.items.len));
}

fn verifyGenericInstances(graph: *const graph_mod.GlobalSemanticGraph) !void {
    var materialized_generic_count: usize = 0;
    for (graph.types.items) |ty| switch (ty) {
        .generic => |generic| {
            try require(verify.idFits(generic.base, graph.family_definitions.items.len));
            switch (graph.familyDefinition(generic.base).kind) {
                .type => materialized_generic_count += 1,
                // Parameterized contract identities are semantic contracts, not
                // runtime layouts. They intentionally have no GenericInstance.
                .contract => {},
                else => return error.InvalidGlobalSemanticGraph,
            }
        },
        else => {},
    };
    try require(materialized_generic_count == graph.generic_instances.items.len);

    for (graph.generic_instances.items, 0..) |instance, index| {
        try require(verify.idFits(instance.type_id, graph.types.items.len));
        const generic = switch (graph.types.items[@intFromEnum(instance.type_id)]) {
            .generic => |value| value,
            else => return error.InvalidGlobalSemanticGraph,
        };
        try require(graph.familyDefinition(generic.base).kind == .type);
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

test "parameterized contract identities do not require runtime generic instances" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const name = try graph.addString(allocator, "Iterable");
    try graph.declarations.append(allocator, .{
        .kind = .contract_type,
        .name = name,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try graph.family_definitions.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .kind = .contract, .parameter_count = 1 });
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const arg_name = try graph.addString(allocator, "t");
    try graph.generic_arguments.append(allocator, .{
        .name = arg_name,
        .value = .{ .type = @enumFromInt(0) },
    });
    try graph.types.append(allocator, .{ .generic = .{
        .base = @enumFromInt(0),
        .arguments = .{ .start = 0, .len = 1 },
    } });

    try verifyGenericInstances(&graph);
}

fn verifyGenericFunctionInstances(graph: *const graph_mod.GlobalSemanticGraph) !void {
    for (graph.generic_function_instances.items, 0..) |instance, index| {
        try require(verify.idFits(instance.function, graph.functions.items.len));
        try require(verify.idFits(instance.parameterized_definition, graph.family_definitions.items.len));
        try require(verify.rangeFits(instance.arguments, graph.generic_arguments.items.len));
        const function = graph.functions.items[@intFromEnum(instance.function)];
        try require(function.flags.is_generic_instantiation);
        try require(function.declaration == graph.familyDefinition(instance.parameterized_definition).declaration);
        for (graph.generic_function_instances.items[0..index]) |previous| {
            if (previous.parameterized_definition != instance.parameterized_definition) continue;
            try require(!genericArgumentRangesEqual(graph, previous.arguments, instance.arguments));
        }
    }
}

fn genericArgumentRangesEqual(
    graph: *const graph_mod.GlobalSemanticGraph,
    a: @TypeOf(graph.generic_function_instances.items[0].arguments),
    b: @TypeOf(graph.generic_function_instances.items[0].arguments),
) bool {
    if (a.len != b.len) return false;
    for (0..a.len) |offset| {
        const left = graph.generic_arguments.items[a.start + @as(u32, @intCast(offset))];
        const right = graph.generic_arguments.items[b.start + @as(u32, @intCast(offset))];
        if (!std.mem.eql(u8, graph.text(left.name), graph.text(right.name))) return false;
        switch (left.value) {
            .definition => |left_definition| {
                if (right.value != .definition or left_definition.origin != right.value.definition.origin or
                    !genericArgumentRangesEqual(graph, left_definition.captures, right.value.definition.captures)) return false;
            },
            .type => |left_ty| switch (right.value) {
                .type => |right_ty| if (left_ty != right_ty) return false,
                else => return false,
            },
            .comptime_int => |left_int| switch (right.value) {
                .comptime_int => |right_int| if (left_int != right_int) return false,
                else => return false,
            },
        }
    }
    return true;
}

fn verifyModulePartitions(graph: *const graph_mod.GlobalSemanticGraph) !void {
    var file_cursor: usize = 0;
    var declaration_cursor: usize = 0;
    for (graph.modules.items, 0..) |module, module_index| {
        try require(verify.stringFits(module.dir, graph.strings.items));
        if (module.namespace) |namespace| {
            try require(@intFromEnum(namespace) < module_index);
            const owner = graph.modules.items[@intFromEnum(namespace)];
            try require(owner.namespace == null);
            try require(owner.is_bundled_core == module.is_bundled_core);
            try require(std.mem.eql(u8, graph.text(owner.dir), graph.text(module.dir)));
        }
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
        .argument_defaults = graph.argument_defaults.items.len,
        .files = graph.files.items.len,
        .declarations = graph.declarations.items.len,
        .type_definitions = graph.type_definitions.items.len,
        .family_definitions = graph.family_definitions.items.len,
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

test "global verifier rejects unmaterialized compact sugar types" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .inferred_errable = @enumFromInt(0) });
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyGlobal(&graph));
}

test "global verifier requires cleanup targets to prove the written storage" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const value_type: graph_mod.GlobalTypeId = @enumFromInt(0);
    const pointer_type: graph_mod.GlobalTypeId = @enumFromInt(1);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = value_type, .mutability = .read_write } },
        .{ .builtin = .Bool },
    });
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.bindings.appendSlice(allocator, &.{
        .{ .name = .{ .start = 0, .len = 0 }, .source = source, .ty = value_type, .mutability = .variable },
        .{ .name = .{ .start = 0, .len = 0 }, .source = source, .ty = value_type, .mutability = .variable },
        .{ .name = .{ .start = 0, .len = 0 }, .source = source, .ty = pointer_type, .mutability = .constant, .initialization = @enumFromInt(1) },
    });
    try graph.nodes.appendSlice(allocator, &.{
        .{ .source = source, .ty = value_type, .content = .{ .binding_use = @enumFromInt(0) } },
        .{ .source = source, .ty = pointer_type, .content = .{ .address_of = @enumFromInt(0) } },
        .{ .source = source, .ty = pointer_type, .content = .{ .binding_use = @enumFromInt(2) } },
        .{ .source = source, .ty = value_type, .content = .{ .binding_use = @enumFromInt(1) } },
        .{ .source = source, .ty = value_type, .content = .{ .int_literal = 42 } },
        .{ .source = source, .ty = null, .content = .{ .pointer_assignment = .{ .pointer = @enumFromInt(2), .value = @enumFromInt(4), .cleanup_target = @enumFromInt(0) } } },
    });
    try verifyWriteCleanupTargets(&graph);
    graph.nodes.items[5].content.pointer_assignment.cleanup_target = @enumFromInt(3);
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyWriteCleanupTargets(&graph));
    graph.nodes.items[5].content.pointer_assignment.cleanup_target = @enumFromInt(0);
    graph.bindings.items[2].mutability = .variable;
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyWriteCleanupTargets(&graph));
    graph.bindings.items[2].mutability = .constant;
    graph.bindings.items[2].initialization = @enumFromInt(2);
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyWriteCleanupTargets(&graph));
    graph.bindings.items[2].initialization = @enumFromInt(1);
    graph.nodes.items[0].ty = @enumFromInt(2);
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyWriteCleanupTargets(&graph));
    graph.nodes.items[0].ty = value_type;
    const evaluated: graph_mod.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(allocator, .{ .source = source, .ty = value_type, .content = .{ .dereference = .{ .pointer = @enumFromInt(2), .pointer_type = pointer_type, .ty = value_type } } });
    graph.nodes.items[5].content.pointer_assignment.cleanup_target = evaluated;
    try verifyWriteCleanupTargets(&graph);
    graph.nodes.items[@intFromEnum(evaluated)].content.dereference.pointer = @enumFromInt(1);
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyWriteCleanupTargets(&graph));
    graph.nodes.items[5].content.pointer_assignment.cleanup_target = @enumFromInt(0);
    try graph.binding_refs.append(allocator, @enumFromInt(2));
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .input_bindings = .{ .start = 0, .len = 1 },
    });
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verifyWriteCleanupTargets(&graph));
}

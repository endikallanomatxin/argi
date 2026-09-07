const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const global_sg = @import("global_semantic_graph.zig");
const primitives = @import("semantic_primitives.zig");

const Offsets = struct {
    file_base: u32,
    declaration_base: u32,
    type_base: u32,
    function_base: u32,
    field_base: u32,
    variant_base: u32,
    generic_argument_base: u32,
    binding_base: u32,
    node_base: u32,
    block_base: u32,
    value_field_base: u32,
    switch_case_base: u32,
    switch_base: u32,
    auto_deinit_field_base: u32,
    auto_deinit_base: u32,
    virtual_registry_base: u32,
    virtualize_base: u32,
    virtual_call_base: u32,
    reach_segment_base: u32,
    reach_alternative_base: u32,
    reach_base: u32,
    nullable_unwrap_base: u32,
    testing_expect_error_base: u32,
    error_propagation_base: u32,
    error_context_base: u32,
    node_ref_base: u32,
    type_ref_base: u32,
    binding_ref_base: u32,
    function_ref_base: u32,
    virtual_registry_ref_base: u32,
    string_base: u32,
    regular_field_count: u32,
    regular_variant_count: u32,
};

pub fn globalize(allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph) !global_sg.GlobalSemanticGraph {
    var result: global_sg.GlobalSemanticGraph = .{};
    errdefer result.deinit(allocator);

    for (modules) |*module| try appendModule(allocator, &result, module);
    return result;
}

fn appendModule(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph) !void {
    if (module.semantic.pending_operations.items.len != 0 or module.semantic.external_refs.items.len != 0)
        return error.UnresolvedModuleSemantics;
    for (module.semantic.nodes.items) |node| if (node == .pending) return error.UnresolvedModuleSemantics;

    const module_id: global_sg.GlobalModuleId = @enumFromInt(try index32(result.modules.items.len));
    const module_dir = try result.addString(allocator, module.module_dir);
    const string_base = try index32(result.strings.items.len);
    try result.strings.appendSlice(allocator, module.strings.items);

    const offsets = Offsets{
        .file_base = try index32(result.files.items.len),
        .declaration_base = try index32(result.declarations.items.len),
        .type_base = try index32(result.types.items.len),
        .function_base = try index32(result.functions.items.len),
        .field_base = try index32(result.fields.items.len),
        .variant_base = try index32(result.variants.items.len),
        .generic_argument_base = try index32(result.generic_arguments.items.len),
        .binding_base = try index32(result.bindings.items.len),
        .node_base = try index32(result.nodes.items.len),
        .block_base = try index32(result.blocks.items.len),
        .value_field_base = try index32(result.value_fields.items.len),
        .switch_case_base = try index32(result.switch_cases.items.len),
        .switch_base = try index32(result.switches.items.len),
        .auto_deinit_field_base = try index32(result.auto_deinit_fields.items.len),
        .auto_deinit_base = try index32(result.auto_deinits.items.len),
        .virtual_registry_base = try index32(result.virtual_registries.items.len),
        .virtualize_base = try index32(result.virtualizes.items.len),
        .virtual_call_base = try index32(result.virtual_calls.items.len),
        .reach_segment_base = try index32(result.reach_segments.items.len),
        .reach_alternative_base = try index32(result.reach_alternatives.items.len),
        .reach_base = try index32(result.reaches.items.len),
        .nullable_unwrap_base = try index32(result.nullable_unwraps.items.len),
        .testing_expect_error_base = try index32(result.testing_expect_errors.items.len),
        .error_propagation_base = try index32(result.error_propagations.items.len),
        .error_context_base = try index32(result.error_contexts.items.len),
        .node_ref_base = try index32(result.node_refs.items.len),
        .type_ref_base = try index32(result.type_refs.items.len),
        .binding_ref_base = try index32(result.binding_refs.items.len),
        .function_ref_base = try index32(result.function_refs.items.len),
        .virtual_registry_ref_base = try index32(result.virtual_registry_refs.items.len),
        .string_base = string_base,
        .regular_field_count = try index32(module.fields.items.len),
        .regular_variant_count = try index32(module.choice_variant_entries.items.len),
    };

    const file_start = offsets.file_base;
    for (module.file_offsets.items) |file| try result.files.append(allocator, .{
        .module = module_id,
        .path = try relocateString(module, file.path, string_base),
    });

    try appendDeclarations(allocator, result, module, offsets);
    try appendFields(allocator, result, module, offsets);
    try appendVariants(allocator, result, module, offsets);
    try appendGenericArguments(allocator, result, module, offsets);
    try appendTypes(allocator, result, module, offsets);
    try appendFunctions(allocator, result, module, offsets);
    try appendReferencePools(allocator, result, module, offsets);
    try appendBodyTables(allocator, result, module, offsets);

    try result.modules.append(allocator, .{
        .dir = module_dir,
        .files = .{ .start = file_start, .len = try index32(module.file_offsets.items.len) },
        .declarations = .{ .start = offsets.declaration_base, .len = try index32(module.declarations.items.len) },
    });
}

fn appendDeclarations(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.declarations.items) |decl| {
        try checkFile(module, decl.module_file_index);
        try result.declarations.append(allocator, .{
            .kind = decl.kind,
            .name = try relocateString(module, decl.name, o.string_base),
            .source = .{ .file_index = o.file_base + decl.module_file_index, .offset = decl.source_offset },
            .type_id = if (decl.type_id) |id| globalType(o, id) else null,
            .function_id = if (decl.function_id) |id| globalFunction(o, id) else null,
            .struct_fields = if (decl.struct_fields) |range| .{ .start = o.field_base + range.start, .len = range.len } else null,
            .choice_variants = if (decl.choice_variants) |range| .{ .start = o.variant_base + range.start, .len = range.len } else null,
            .generic_parameter_count = decl.generic_parameter_count,
        });
    }
}

fn appendFields(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.fields.items, 0..) |field, index| try appendField(allocator, result, module, o, field, @intCast(index));
    for (module.structural_fields.items, 0..) |field, index| try appendField(allocator, result, module, o, field, o.regular_field_count + @as(u32, @intCast(index)));
}

fn appendField(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets, field: module_sg.Field, logical_index: u32) !void {
    try checkFile(module, field.module_file_index);
    const overlay = findFieldSemantic(module, @enumFromInt(logical_index));
    if (field.default_value != null and (overlay == null or overlay.?.default_value == null))
        return error.ModuleFieldDefaultNotLowered;
    try result.fields.append(allocator, .{
        .name = try relocateString(module, field.name, o.string_base),
        .ty = globalType(o, field.ty),
        .storage_type = if (overlay) |value| if (value.storage_type) |ty| globalType(o, ty) else null else null,
        .source = .{ .file_index = o.file_base + field.module_file_index, .offset = field.source_offset },
        .default_value = if (overlay) |value| if (value.default_value) |node| globalNode(o, node) else null else null,
    });
}

fn appendVariants(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.choice_variant_entries.items, 0..) |variant, index| try appendVariant(allocator, result, module, o, variant, @intCast(index));
    for (module.structural_choice_variants.items, 0..) |variant, index| try appendVariant(allocator, result, module, o, variant, o.regular_variant_count + @as(u32, @intCast(index)));
}

fn appendVariant(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets, variant: module_sg.ChoiceVariant, logical_index: u32) !void {
    if (variant.qualifier != null) return error.UnresolvedChoiceQualifier;
    try checkFile(module, variant.module_file_index);
    const overlay = findVariantSemantic(module, @enumFromInt(logical_index));
    try result.variants.append(allocator, .{
        .name = try relocateString(module, variant.name, o.string_base),
        .payload_type = if (variant.payload_type) |ty| globalType(o, ty) else null,
        .option_decl = if (overlay) |value| if (value.option_decl) |decl| globalDecl(o, decl) else null else null,
        .source = .{ .file_index = o.file_base + variant.module_file_index, .offset = variant.source_offset },
        .value = if (overlay) |value| value.value else @intCast(logical_index),
    });
}

fn appendGenericArguments(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.generic_type_arguments.items) |argument| try result.generic_arguments.append(allocator, .{
        .name = try relocateString(module, argument.name, o.string_base),
        .value = .{ .type = globalType(o, argument.ty) },
    });
}

fn appendTypes(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.types.items) |ty| try result.types.append(allocator, switch (ty) {
        .builtin => |builtin| .{ .builtin = builtin },
        .declared => |decl| .{ .declared = globalDecl(o, decl) },
        .pointer => |pointer| .{ .pointer = .{ .child = globalType(o, pointer.child), .mutability = pointer.mutability } },
        .array => |array| .{ .array = .{ .length = array.length, .element = globalType(o, array.element) } },
        .nullable => |child| .{ .nullable = globalType(o, child) },
        .inferred_errable => |child| .{ .inferred_errable = globalType(o, child) },
        .structural => |range| .{ .structural = .{
            .fields = .{ .start = o.field_base + o.regular_field_count + range.start, .len = range.len },
            .layout = .regular,
        } },
        .structural_choice => |range| .{ .structural_choice = .{
            .variants = .{ .start = o.variant_base + o.regular_variant_count + range.start, .len = range.len },
            .layout = .regular,
        } },
        .generic => |generic| .{ .generic = .{
            .base = globalDecl(o, generic.base),
            .arguments = .{ .start = o.generic_argument_base + generic.arguments.start, .len = generic.arguments.len },
        } },
    });
}

fn appendFunctions(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.functions.items, 0..) |function, index| {
        const local_id: module_entities.ModuleFunctionId = @enumFromInt(@as(u32, @intCast(index)));
        const semantic = findFunctionSemantic(module, local_id);
        try result.functions.append(allocator, .{
            .declaration = globalDecl(o, function.declaration),
            .input = .{ .start = o.field_base + function.input.start, .len = function.input.len },
            .output = .{ .start = o.field_base + function.output.start, .len = function.output.len },
            .body = if (semantic) |value| if (value.body) |body| globalBlock(o, body) else null else null,
            .input_bindings = if (semantic) |value| relocateBindingRefRange(o, value.input_bindings) else .{ .start = 0, .len = 0 },
            .output_bindings = if (semantic) |value| relocateBindingRefRange(o, value.output_bindings) else .{ .start = 0, .len = 0 },
            .inferred_error_reasons = if (semantic) |value| if (value.inferred_error_reasons) |ty| globalType(o, ty) else null else null,
            .safety_primitive = if (semantic) |value| value.safety_primitive else .none,
            .flags = if (semantic) |value| value.flags else .{},
        });
    }
}

fn appendReferencePools(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.semantic.node_refs.items) |id| try result.node_refs.append(allocator, globalNode(o, id));
    for (module.semantic.type_refs.items) |id| try result.type_refs.append(allocator, globalType(o, id));
    for (module.semantic.binding_refs.items) |id| try result.binding_refs.append(allocator, globalBinding(o, id));
    for (module.semantic.function_refs.items) |id| try result.function_refs.append(allocator, globalFunction(o, id));
    for (module.semantic.virtual_registry_refs.items) |id| try result.virtual_registry_refs.append(allocator, globalVirtualRegistry(o, id));
}

fn appendBodyTables(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    const storage = &module.semantic;

    for (storage.bindings.items) |binding| {
        try checkSource(module, binding.source);
        try result.bindings.append(allocator, .{
            .name = try relocateString(module, binding.name, o.string_base),
            .source = globalSource(o, binding.source),
            .ty = globalType(o, binding.ty),
            .initialization = if (binding.initialization) |node| globalNode(o, node) else null,
            .mutability = binding.mutability,
        });
    }
    for (storage.blocks.items) |block| try result.blocks.append(allocator, .{
        .nodes = relocateNodeRefRange(o, block.nodes),
        .ret_val = if (block.ret_val) |node| globalNode(o, node) else null,
    });
    for (storage.value_fields.items) |field| try result.value_fields.append(allocator, .{
        .name = try relocateString(module, field.name, o.string_base),
        .value = globalNode(o, field.value),
    });
    for (storage.switch_cases.items) |case| try result.switch_cases.append(allocator, .{
        .value = globalNode(o, case.value),
        .variant = globalVariant(o, case.variant),
        .body = globalBlock(o, case.body),
    });
    for (storage.switches.items) |item| try result.switches.append(allocator, .{
        .expression = globalNode(o, item.expression),
        .cases = .{ .start = o.switch_case_base + item.cases.start, .len = item.cases.len },
        .default_block = if (item.default_block) |block| globalBlock(o, block) else null,
        .exhaustive = item.exhaustive,
    });
    for (storage.auto_deinit_fields.items) |field| try result.auto_deinit_fields.append(allocator, .{
        .field_index = field.field_index,
        .deinit_fn = if (field.deinit_fn) |function| globalFunction(o, function) else null,
        .input = if (field.input) |node| globalNode(o, node) else null,
        .self_field_index = field.self_field_index,
        .fields = .{ .start = o.auto_deinit_field_base + field.fields.start, .len = field.fields.len },
    });
    for (storage.auto_deinits.items) |item| try result.auto_deinits.append(allocator, .{
        .binding = globalBinding(o, item.binding),
        .deinit_fn = if (item.deinit_fn) |function| globalFunction(o, function) else null,
        .input = if (item.input) |node| globalNode(o, node) else null,
        .self_field_index = item.self_field_index,
        .fields = .{ .start = o.auto_deinit_field_base + item.fields.start, .len = item.fields.len },
    });
    for (storage.virtual_registries.items) |registry| try result.virtual_registries.append(allocator, .{
        .implementations = relocateFunctionRefRange(o, registry.implementations),
    });
    for (storage.virtualizes.items) |item| {
        try checkSource(module, item.source);
        try result.virtualizes.append(allocator, .{
            .value = globalNode(o, item.value),
            .concrete_type = globalType(o, item.concrete_type),
            .abstract_decl = globalDecl(o, item.abstract_decl),
            .virtual_type = globalType(o, item.virtual_type),
            .methods = relocateFunctionRefRange(o, item.methods),
            .safety_methods = relocateVirtualRegistryRefRange(o, item.safety_methods),
            .source = globalSource(o, item.source),
        });
    }
    for (storage.virtual_calls.items) |item| try result.virtual_calls.append(allocator, .{
        .handle = globalNode(o, item.handle),
        .input = globalNode(o, item.input),
        .self_input_index = item.self_input_index,
        .method_index = item.method_index,
        .method_count = item.method_count,
        .method_name = try relocateString(module, item.method_name, o.string_base),
        .input_type = globalType(o, item.input_type),
        .output_type = globalType(o, item.output_type),
        .self_permission = item.self_permission,
        .safety_methods = globalVirtualRegistry(o, item.safety_methods),
        .consumes_auto_deinit = if (item.consumes_auto_deinit) |node| globalNode(o, node) else null,
    });
    for (storage.reach_segments.items) |segment| try result.reach_segments.append(allocator, try relocateString(module, segment, o.string_base));
    for (storage.reach_alternatives.items) |alternative| try result.reach_alternatives.append(allocator, .{
        .segments = .{ .start = o.reach_segment_base + alternative.segments.start, .len = alternative.segments.len },
    });
    for (storage.reaches.items) |reach| try result.reaches.append(allocator, .{
        .alternatives = .{ .start = o.reach_alternative_base + reach.alternatives.start, .len = reach.alternatives.len },
    });
    for (storage.nullable_unwraps.items) |item| try result.nullable_unwraps.append(allocator, .{
        .nullable_value = globalNode(o, item.nullable_value),
        .fallback_value = globalNode(o, item.fallback_value),
        .some_variant = globalVariant(o, item.some_variant),
        .some_value_field_index = item.some_value_field_index,
        .result_type = globalType(o, item.result_type),
    });
    for (storage.testing_expect_errors.items) |item| try result.testing_expect_errors.append(allocator, .{
        .expected_reason = globalNode(o, item.expected_reason),
        .actual_result = globalNode(o, item.actual_result),
        .actual_error_variant = globalVariant(o, item.actual_error_variant),
        .actual_error_payload_type = globalType(o, item.actual_error_payload_type),
        .actual_reason_field_index = item.actual_reason_field_index,
        .result_type = globalType(o, item.result_type),
        .result_ok_variant = globalVariant(o, item.result_ok_variant),
        .test_fail_function = globalFunction(o, item.test_fail_function),
        .expected_reason_name = if (item.expected_reason_name) |name| try relocateString(module, name, o.string_base) else null,
        .diagnostic_line = item.diagnostic_line,
        .diagnostic_column = item.diagnostic_column,
        .diagnostic_source_line = try relocateString(module, item.diagnostic_source_line, o.string_base),
    });
    for (storage.error_propagations.items) |item| try result.error_propagations.append(allocator, .{
        .errable_value = globalNode(o, item.errable_value),
        .cleanup_nodes = relocateNodeRefRange(o, item.cleanup_nodes),
        .ok_variant = globalVariant(o, item.ok_variant),
        .ok_value_field_index = item.ok_value_field_index,
        .error_variant = globalVariant(o, item.error_variant),
        .propagated_errable_type = globalType(o, item.propagated_errable_type),
        .propagated_error_variant = globalVariant(o, item.propagated_error_variant),
        .ok_payload_type = globalType(o, item.ok_payload_type),
        .error_payload_type = globalType(o, item.error_payload_type),
        .propagated_error_payload_type = globalType(o, item.propagated_error_payload_type),
        .diagnostic_line = item.diagnostic_line,
        .diagnostic_column = item.diagnostic_column,
        .diagnostic_source_line = try relocateString(module, item.diagnostic_source_line, o.string_base),
    });
    for (storage.error_contexts.items) |item| try result.error_contexts.append(allocator, .{
        .errable_value = globalNode(o, item.errable_value),
        .context = globalNode(o, item.context),
        .cleanup_nodes = relocateNodeRefRange(o, item.cleanup_nodes),
        .ok_variant = globalVariant(o, item.ok_variant),
        .ok_value_field_index = item.ok_value_field_index,
        .error_variant = globalVariant(o, item.error_variant),
        .propagated_errable_type = globalType(o, item.propagated_errable_type),
        .propagated_error_variant = globalVariant(o, item.propagated_error_variant),
        .ok_payload_type = globalType(o, item.ok_payload_type),
        .error_payload_type = globalType(o, item.error_payload_type),
        .propagated_error_payload_type = globalType(o, item.propagated_error_payload_type),
        .diagnostic_line = item.diagnostic_line,
        .diagnostic_column = item.diagnostic_column,
        .diagnostic_source_line = try relocateString(module, item.diagnostic_source_line, o.string_base),
    });

    for (storage.nodes.items) |node| switch (node) {
        .pending => return error.UnresolvedModuleSemantics,
        .resolved => |resolved| try result.nodes.append(allocator, try relocateNode(module, o, resolved)),
    };
    for (storage.roots.items) |node| try result.roots.append(allocator, globalNode(o, node));
}

fn relocateNode(module: *const module_sg.ModuleSemanticGraph, o: Offsets, node: module_entities.ResolvedNode) !global_sg.Node {
    try checkSource(module, node.source);
    return .{
        .source = globalSource(o, node.source),
        .ty = if (node.ty) |ty| globalType(o, ty) else null,
        .content = switch (node.content) {
            .declaration => |id| .{ .declaration = globalDecl(o, id) },
            .binding_declaration => |id| .{ .binding_declaration = globalBinding(o, id) },
            .binding_use => |id| .{ .binding_use = globalBinding(o, id) },
            .reach_directive => |id| .{ .reach_directive = @enumFromInt(o.reach_base + @intFromEnum(id)) },
            .move_value => |id| .{ .move_value = globalNode(o, id) },
            .assignment => |value| .{ .assignment = .{ .binding = globalBinding(o, value.binding), .value = globalNode(o, value.value) } },
            .auto_deinit_binding => |id| .{ .auto_deinit_binding = @enumFromInt(o.auto_deinit_base + @intFromEnum(id)) },
            .function_call => |value| .{ .function_call = .{
                .callee = globalFunction(o, value.callee),
                .input = globalNode(o, value.input),
                .consumes_auto_deinit = if (value.consumes_auto_deinit) |id| globalNode(o, id) else null,
                .initializes_auto_deinit = if (value.initializes_auto_deinit) |id| globalNode(o, id) else null,
            } },
            .virtualize => |id| .{ .virtualize = @enumFromInt(o.virtualize_base + @intFromEnum(id)) },
            .virtual_call => |id| .{ .virtual_call = @enumFromInt(o.virtual_call_base + @intFromEnum(id)) },
            .code_block => |id| .{ .code_block = globalBlock(o, id) },
            .int_literal => |value| .{ .int_literal = value },
            .float_literal => |value| .{ .float_literal = value },
            .char_literal => |value| .{ .char_literal = value },
            .string_literal => |value| .{ .string_literal = try relocateString(module, value, o.string_base) },
            .bool_literal => |value| .{ .bool_literal = value },
            .list_literal => |value| .{ .list_literal = .{
                .elements = relocateNodeRefRange(o, value.elements),
                .element_types = relocateTypeRefRange(o, value.element_types),
            } },
            .struct_value_literal => |value| .{ .struct_value_literal = .{
                .fields = .{ .start = o.value_field_base + value.fields.start, .len = value.fields.len },
                .ty = globalType(o, value.ty),
                .dispatch_prefix_positional_count = value.dispatch_prefix_positional_count,
            } },
            .struct_field_access => |value| .{ .struct_field_access = .{
                .value = globalNode(o, value.value),
                .field_name = try relocateString(module, value.field_name, o.string_base),
                .field_index = value.field_index,
            } },
            .choice_literal => |value| .{ .choice_literal = .{
                .choice_type = globalType(o, value.choice_type),
                .variant = globalVariant(o, value.variant),
                .payload = if (value.payload) |id| globalNode(o, id) else null,
            } },
            .choice_payload_access => |value| .{ .choice_payload_access = .{
                .value = globalNode(o, value.value),
                .variant = globalVariant(o, value.variant),
                .payload_type = globalType(o, value.payload_type),
            } },
            .nullable_unwrap_or => |id| .{ .nullable_unwrap_or = @enumFromInt(o.nullable_unwrap_base + @intFromEnum(id)) },
            .testing_expect_error => |id| .{ .testing_expect_error = @enumFromInt(o.testing_expect_error_base + @intFromEnum(id)) },
            .error_propagation => |id| .{ .error_propagation = @enumFromInt(o.error_propagation_base + @intFromEnum(id)) },
            .error_context => |id| .{ .error_context = @enumFromInt(o.error_context_base + @intFromEnum(id)) },
            .array_literal => |value| .{ .array_literal = .{
                .elements = relocateNodeRefRange(o, value.elements),
                .element_type = globalType(o, value.element_type),
                .length = value.length,
            } },
            .array_index => |value| .{ .array_index = .{
                .array_ptr = globalNode(o, value.array_ptr),
                .index = globalNode(o, value.index),
                .element_type = globalType(o, value.element_type),
                .array_type = globalType(o, value.array_type),
            } },
            .array_store => |value| .{ .array_store = .{
                .array_ptr = globalNode(o, value.array_ptr),
                .index = globalNode(o, value.index),
                .value = globalNode(o, value.value),
                .element_type = globalType(o, value.element_type),
                .array_type = globalType(o, value.array_type),
            } },
            .struct_field_store => |value| .{ .struct_field_store = .{
                .struct_ptr = globalNode(o, value.struct_ptr),
                .struct_type = globalType(o, value.struct_type),
                .field_index = value.field_index,
                .field_type = globalType(o, value.field_type),
                .value = globalNode(o, value.value),
            } },
            .binary_operation => |value| .{ .binary_operation = .{ .operator = value.operator, .left = globalNode(o, value.left), .right = globalNode(o, value.right) } },
            .comparison => |value| .{ .comparison = .{ .operator = value.operator, .left = globalNode(o, value.left), .right = globalNode(o, value.right) } },
            .logical_operation => |value| .{ .logical_operation = .{ .operator = value.operator, .left = globalNode(o, value.left), .right = globalNode(o, value.right) } },
            .return_statement => |value| .{ .return_statement = .{
                .expression = if (value.expression) |id| globalNode(o, id) else null,
                .cleanup = relocateNodeRefRange(o, value.cleanup),
            } },
            .if_statement => |value| .{ .if_statement = .{
                .condition = globalNode(o, value.condition),
                .choice_test = if (value.choice_test) |test_value| .{
                    .choice_value = globalNode(o, test_value.choice_value),
                    .choice_type = globalType(o, test_value.choice_type),
                    .variant = globalVariant(o, test_value.variant),
                    .then_has_variant = test_value.then_has_variant,
                } else null,
                .then_block = globalBlock(o, value.then_block),
                .else_block = if (value.else_block) |id| globalBlock(o, id) else null,
            } },
            .while_statement => |value| .{ .while_statement = .{ .condition = globalNode(o, value.condition), .body = globalBlock(o, value.body) } },
            .for_statement => |value| .{ .for_statement = .{
                .init = if (value.init) |id| globalNode(o, id) else null,
                .condition = globalNode(o, value.condition),
                .increment = if (value.increment) |id| globalNode(o, id) else null,
                .body = globalBlock(o, value.body),
            } },
            .switch_statement => |id| .{ .switch_statement = @enumFromInt(o.switch_base + @intFromEnum(id)) },
            .break_statement => .break_statement,
            .continue_statement => .continue_statement,
            .address_of => |id| .{ .address_of = globalNode(o, id) },
            .dereference => |value| .{ .dereference = .{
                .pointer = globalNode(o, value.pointer),
                .ty = globalType(o, value.ty),
                .pointer_type = globalType(o, value.pointer_type),
            } },
            .pointer_assignment => |value| .{ .pointer_assignment = .{ .pointer = globalNode(o, value.pointer), .value = globalNode(o, value.value) } },
            .type_initializer => |value| .{ .type_initializer = .{
                .type_decl = globalDecl(o, value.type_decl),
                .init_fn = globalFunction(o, value.init_fn),
                .args = globalNode(o, value.args),
            } },
            .type_literal => |id| .{ .type_literal = globalType(o, id) },
            .explicit_cast => |value| .{ .explicit_cast = .{ .value = globalNode(o, value.value), .target_type = globalType(o, value.target_type) } },
        },
    };
}

fn findFunctionSemantic(module: *const module_sg.ModuleSemanticGraph, id: module_entities.ModuleFunctionId) ?module_entities.FunctionSemantic {
    for (module.semantic.function_semantics.items) |value| if (value.function == id) return value;
    return null;
}

fn findFieldSemantic(module: *const module_sg.ModuleSemanticGraph, id: module_entities.ModuleFieldId) ?module_entities.FieldSemantic {
    for (module.semantic.field_semantics.items) |value| if (value.field == id) return value;
    return null;
}

fn findVariantSemantic(module: *const module_sg.ModuleSemanticGraph, id: module_entities.ModuleVariantId) ?module_entities.VariantSemantic {
    for (module.semantic.variant_semantics.items) |value| if (value.variant == id) return value;
    return null;
}

fn relocateString(module: *const module_sg.ModuleSemanticGraph, value: module_sg.StringRange, base: u32) !global_sg.StringRange {
    if (value.start > module.strings.items.len or value.len > module.strings.items.len - value.start) return error.InvalidModuleStringRange;
    if (base > std.math.maxInt(u32) - value.start) return error.GlobalSemanticGraphTooLarge;
    return .{ .start = base + value.start, .len = value.len };
}

fn globalSource(o: Offsets, source: primitives.SourceRef) primitives.SourceRef {
    return .{ .file_index = o.file_base + source.file_index, .offset = source.offset };
}

fn checkFile(module: *const module_sg.ModuleSemanticGraph, file_index: u32) !void {
    if (file_index >= module.file_offsets.items.len) return error.InvalidModuleFileIndex;
}

fn checkSource(module: *const module_sg.ModuleSemanticGraph, source: primitives.SourceRef) !void {
    try checkFile(module, source.file_index);
}

fn globalDecl(o: Offsets, id: module_entities.ModuleDeclId) global_sg.GlobalDeclId {
    return @enumFromInt(o.declaration_base + @intFromEnum(id));
}
fn globalType(o: Offsets, id: module_entities.ModuleTypeId) global_sg.GlobalTypeId {
    return @enumFromInt(o.type_base + @intFromEnum(id));
}
fn globalFunction(o: Offsets, id: module_entities.ModuleFunctionId) global_sg.GlobalFunctionId {
    return @enumFromInt(o.function_base + @intFromEnum(id));
}
fn globalBinding(o: Offsets, id: module_entities.ModuleBindingId) global_sg.GlobalBindingId {
    return @enumFromInt(o.binding_base + @intFromEnum(id));
}
fn globalNode(o: Offsets, id: module_entities.ModuleNodeId) global_sg.GlobalNodeId {
    return @enumFromInt(o.node_base + @intFromEnum(id));
}
fn globalBlock(o: Offsets, id: module_entities.ModuleBlockId) global_sg.GlobalBlockId {
    return @enumFromInt(o.block_base + @intFromEnum(id));
}
fn globalVariant(o: Offsets, id: module_entities.ModuleVariantId) global_sg.GlobalVariantId {
    return @enumFromInt(o.variant_base + @intFromEnum(id));
}
fn globalVirtualRegistry(o: Offsets, id: module_entities.ModuleVirtualRegistryId) global_sg.GlobalVirtualRegistryId {
    return @enumFromInt(o.virtual_registry_base + @intFromEnum(id));
}

fn relocateNodeRefRange(o: Offsets, range: primitives.Range(module_entities.ModuleNodeId)) primitives.Range(global_sg.GlobalNodeId) {
    return .{ .start = o.node_ref_base + range.start, .len = range.len };
}
fn relocateTypeRefRange(o: Offsets, range: primitives.Range(module_entities.ModuleTypeId)) primitives.Range(global_sg.GlobalTypeId) {
    return .{ .start = o.type_ref_base + range.start, .len = range.len };
}
fn relocateBindingRefRange(o: Offsets, range: primitives.Range(module_entities.ModuleBindingId)) primitives.Range(global_sg.GlobalBindingId) {
    return .{ .start = o.binding_ref_base + range.start, .len = range.len };
}
fn relocateFunctionRefRange(o: Offsets, range: primitives.Range(module_entities.ModuleFunctionId)) primitives.Range(global_sg.GlobalFunctionId) {
    return .{ .start = o.function_ref_base + range.start, .len = range.len };
}
fn relocateVirtualRegistryRefRange(o: Offsets, range: primitives.Range(module_entities.ModuleVirtualRegistryId)) primitives.Range(global_sg.GlobalVirtualRegistryId) {
    return .{ .start = o.virtual_registry_ref_base + range.start, .len = range.len };
}

fn index32(value: usize) !u32 {
    if (value > std.math.maxInt(u32)) return error.GlobalSemanticGraphTooLarge;
    return @intCast(value);
}

test "globalize module semantic declarations and types" {
    const allocator = std.testing.allocator;
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer module.deinit(allocator);

    const path = try @import("semantic_strings.zig").append(&module.strings, allocator, "main.rg");
    const name = try @import("semantic_strings.zig").append(&module.strings, allocator, "Thing");
    try module.file_offsets.append(allocator, .{
        .path = path,
        .declaration_base = 0,
        .declaration_count = 1,
        .type_reference_base = 0,
        .type_reference_count = 0,
        .import_reference_base = 0,
        .import_reference_count = 0,
    });
    try module.declarations.append(allocator, .{
        .kind = .type,
        .name = name,
        .source_offset = 4,
        .module_file_index = 0,
        .syntax_node = @enumFromInt(0),
        .type_id = @enumFromInt(0),
    });
    try module.types.append(allocator, .{ .declared = @enumFromInt(0) });

    var global = try globalize(allocator, &.{module});
    defer global.deinit(allocator);
    // Ownership moved nowhere: globalize copies and module remains valid too.
    try std.testing.expectEqual(@as(usize, 1), global.modules.items.len);
    try std.testing.expectEqual(@as(usize, 1), global.declarations.items.len);
    try std.testing.expectEqualStrings("Thing", global.text(global.declarations.items[0].name));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(global.types.items[0].declared));
}

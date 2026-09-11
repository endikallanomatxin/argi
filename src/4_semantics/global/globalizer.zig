const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const module_views = @import("../module/views.zig");
const module_verify = @import("../module/complete_verify.zig");
const global_sg = @import("graph.zig");
const global_verify = @import("verify.zig");
const primitives = @import("../primitives/schema.zig");

pub const Mode = enum { strict, allow_holes };

pub const Offsets = struct {
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
    symbol_declaration_base: u32,
    string_base: u32,
};

pub const Relocation = struct {
    graph: global_sg.GlobalSemanticGraph,
    offsets: std.ArrayList(Offsets) = .empty,

    pub fn deinit(self: *Relocation, allocator: std.mem.Allocator) void {
        self.graph.deinit(allocator);
        self.offsets.deinit(allocator);
        self.* = undefined;
    }

    pub fn takeGraph(self: *Relocation, allocator: std.mem.Allocator) global_sg.GlobalSemanticGraph {
        const graph = self.graph;
        self.graph = .{};
        self.offsets.deinit(allocator);
        self.offsets = .empty;
        return graph;
    }
};

/// Relocate every module-owned identity into the final Global* spaces. In
/// `allow_holes` mode unresolved types/nodes occupy placeholders at their final
/// IDs; GlobalSema patches those exact slots without rebuilding ranges.
pub fn relocate(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
    mode: Mode,
) !Relocation {
    var result: Relocation = .{ .graph = .{} };
    errdefer result.deinit(allocator);
    try result.offsets.ensureTotalCapacity(allocator, modules.len);

    for (modules) |*module| {
        try module_verify.verifyModule(module);
        if (mode == .strict) try requireFinalizable(module);
        const offsets = try appendModule(allocator, &result.graph, module, mode);
        result.offsets.appendAssumeCapacity(offsets);
    }

    if (mode == .strict) try global_verify.verifyGlobal(&result.graph);
    return result;
}

pub fn globalize(allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph) !global_sg.GlobalSemanticGraph {
    var relocated = try relocate(allocator, modules, .strict);
    return relocated.takeGraph(allocator);
}

pub const finalizeResolvedModules = globalize;

fn requireFinalizable(module: *const module_sg.ModuleSemanticGraph) !void {
    const semantic = &module.semantic;
    if (!semantic.local_semantics_complete) return error.ModuleLocalSemanticsIncomplete;
    if (semantic.external_refs.items.len != 0 or semantic.pending_operations.items.len != 0)
        return error.UnresolvedModuleSemantics;
    if (semantic.parameterized_storage.storageBytes() != 0) return error.ModuleParameterizedSemanticsNotConsumed;
    for (semantic.types.items) |ty| switch (ty) {
        .resolved => {},
        .external => return error.UnresolvedModuleSemantics,
    };
    for (semantic.nodes.items) |node| switch (node) {
        .resolved => {},
        .pending => return error.UnresolvedModuleSemantics,
    };
    for (module.type_references.items) |reference| switch (reference.resolution) {
        .external => return error.UnresolvedModuleSemantics,
        else => {},
    };
}

fn appendModule(
    allocator: std.mem.Allocator,
    result: *global_sg.GlobalSemanticGraph,
    module: *const module_sg.ModuleSemanticGraph,
    mode: Mode,
) !Offsets {
    const module_id: global_sg.GlobalModuleId = @enumFromInt(try index32(result.modules.items.len));
    const module_dir = try result.addString(allocator, module.module_dir);
    const string_base = try index32(result.strings.items.len);
    if (module.strings.items.len > std.math.maxInt(u32) - string_base) return error.GlobalSemanticGraphTooLarge;
    try result.strings.appendSlice(allocator, module.strings.items);

    const o = Offsets{
        .file_base = try baseFor(result.files.items.len, module.file_offsets.items.len),
        .declaration_base = try baseFor(result.declarations.items.len, module.declarations.items.len),
        .type_base = try baseFor(result.types.items.len, module_views.typeCount(module)),
        .function_base = try baseFor(result.functions.items.len, module.functions.items.len),
        .field_base = try baseFor(result.fields.items.len, module_views.fieldCount(module)),
        .variant_base = try baseFor(result.variants.items.len, module_views.variantCount(module)),
        .generic_argument_base = try baseFor(result.generic_arguments.items.len, module_views.genericArgumentCount(module)),
        .binding_base = try baseFor(result.bindings.items.len, module.semantic.bindings.items.len),
        .node_base = try baseFor(result.nodes.items.len, module.semantic.nodes.items.len),
        .block_base = try baseFor(result.blocks.items.len, module.semantic.blocks.items.len),
        .value_field_base = try baseFor(result.value_fields.items.len, module.semantic.value_fields.items.len),
        .switch_case_base = try baseFor(result.switch_cases.items.len, module.semantic.switch_cases.items.len),
        .switch_base = try baseFor(result.switches.items.len, module.semantic.switches.items.len),
        .auto_deinit_field_base = try baseFor(result.auto_deinit_fields.items.len, module.semantic.auto_deinit_fields.items.len),
        .auto_deinit_base = try baseFor(result.auto_deinits.items.len, module.semantic.auto_deinits.items.len),
        .virtual_registry_base = try baseFor(result.virtual_registries.items.len, module.semantic.virtual_registries.items.len),
        .virtualize_base = try baseFor(result.virtualizes.items.len, module.semantic.virtualizes.items.len),
        .virtual_call_base = try baseFor(result.virtual_calls.items.len, module.semantic.virtual_calls.items.len),
        .reach_segment_base = try baseFor(result.reach_segments.items.len, module.semantic.reach_segments.items.len),
        .reach_alternative_base = try baseFor(result.reach_alternatives.items.len, module.semantic.reach_alternatives.items.len),
        .reach_base = try baseFor(result.reaches.items.len, module.semantic.reaches.items.len),
        .nullable_unwrap_base = try baseFor(result.nullable_unwraps.items.len, module.semantic.nullable_unwraps.items.len),
        .testing_expect_error_base = try baseFor(result.testing_expect_errors.items.len, module.semantic.testing_expect_errors.items.len),
        .error_propagation_base = try baseFor(result.error_propagations.items.len, module.semantic.error_propagations.items.len),
        .error_context_base = try baseFor(result.error_contexts.items.len, module.semantic.error_contexts.items.len),
        .node_ref_base = try baseFor(result.node_refs.items.len, module.semantic.node_refs.items.len),
        .type_ref_base = try baseFor(result.type_refs.items.len, module.semantic.type_refs.items.len),
        .binding_ref_base = try baseFor(result.binding_refs.items.len, module.semantic.binding_refs.items.len),
        .function_ref_base = try baseFor(result.function_refs.items.len, module.semantic.function_refs.items.len),
        .virtual_registry_ref_base = try baseFor(result.virtual_registry_refs.items.len, module.semantic.virtual_registry_refs.items.len),
        .symbol_declaration_base = try baseFor(result.symbol_declarations.items.len, module.symbol_declarations.items.len),
        .string_base = string_base,
    };

    for (module.file_offsets.items) |file| try result.files.append(allocator, .{
        .module = module_id,
        .path = try relocateString(module, file.path, o.string_base),
    });

    try appendDeclarations(allocator, result, module, o);
    try appendFields(allocator, result, module, o);
    try appendVariants(allocator, result, module, o);
    try appendGenericArguments(allocator, result, module, o);
    try appendTypes(allocator, result, module, o, mode);
    try appendGenericInstances(allocator, result, module, o);
    try appendFunctions(allocator, result, module, o);
    try appendSymbols(allocator, result, module, o);
    try appendReferencePools(allocator, result, module, o);
    try appendBodyTables(allocator, result, module, o, mode);

    try result.modules.append(allocator, .{
        .dir = module_dir,
        .is_bundled_core = module.is_bundled_core,
        .files = .{ .start = o.file_base, .len = try index32(module.file_offsets.items.len) },
        .declarations = .{ .start = o.declaration_base, .len = try index32(module.declarations.items.len) },
    });
    return o;
}

fn appendDeclarations(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.declarations.items, 0..) |_, index| {
        const value = try module_views.declarationView(module, @enumFromInt(@as(u32, @intCast(index))));
        try result.declarations.append(allocator, .{
            .kind = value.kind,
            .name = try relocateString(module, value.name, o.string_base),
            .source = globalSource(o, value.source),
            .type_id = if (value.type_id) |id| globalType(o, id) else null,
            .function_id = if (value.function_id) |id| globalFunction(o, id) else null,
            .struct_fields = if (value.struct_fields) |range| relocateEntityRange(global_sg.GlobalFieldId, o.field_base, range) else null,
            .choice_variants = if (value.choice_variants) |range| relocateEntityRange(global_sg.GlobalVariantId, o.variant_base, range) else null,
            .generic_parameter_count = value.generic_parameter_count,
            .struct_layout = value.struct_layout,
            .choice_layout = value.choice_layout,
        });
    }
}

fn appendFields(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (0..module_views.fieldCount(module)) |index| {
        const value = try module_views.fieldView(module, @enumFromInt(@as(u32, @intCast(index))));
        try result.fields.append(allocator, .{
            .name = try relocateString(module, value.name, o.string_base),
            .ty = globalType(o, value.ty),
            .storage_type = if (value.storage_type) |id| globalType(o, id) else null,
            .source = globalSource(o, value.source),
            .default_value = if (value.default_value) |id| globalNode(o, id) else null,
        });
    }
}

fn appendVariants(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (0..module_views.variantCount(module)) |index| {
        const value = try module_views.variantView(module, @enumFromInt(@as(u32, @intCast(index))));
        try result.variants.append(allocator, .{
            .name = try relocateString(module, value.name, o.string_base),
            .payload_type = if (value.payload_type) |id| globalType(o, id) else null,
            .option_decl = if (value.option_decl) |id| globalDecl(o, id) else null,
            .source = globalSource(o, value.source),
            .value = value.value,
        });
    }
}

fn appendGenericArguments(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (0..module_views.genericArgumentCount(module)) |index| {
        const value = try module_views.genericArgumentView(module, @enumFromInt(@as(u32, @intCast(index))));
        try result.generic_arguments.append(allocator, .{
            .name = try relocateString(module, value.name, o.string_base),
            .value = switch (value.value) {
                .type => |id| .{ .type = globalType(o, id) },
                .comptime_int => |number| .{ .comptime_int = number },
            },
        });
    }
}

fn appendTypes(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets, mode: Mode) !void {
    for (0..module_views.typeCount(module)) |index| {
        const value = try module_views.typeView(module, @enumFromInt(@as(u32, @intCast(index))));
        const global: global_sg.GlobalType = switch (value) {
            .resolved => |item| relocateType(o, item),
            .external => if (mode == .allow_holes) .{ .builtin = .Any } else return error.UnresolvedModuleSemantics,
        };
        try result.types.append(allocator, global);
    }
}

fn appendGenericInstances(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.semantic.generic_instances.items) |instance| try result.generic_instances.append(allocator, .{
        .type_id = globalType(o, instance.type_id),
        .shape = switch (instance.shape) {
            .structure => |shape| .{ .structure = .{
                .fields = relocateEntityRange(global_sg.GlobalFieldId, o.field_base, shape.fields),
                .layout = shape.layout,
            } },
            .choice => |shape| .{ .choice = .{
                .variants = relocateEntityRange(global_sg.GlobalVariantId, o.variant_base, shape.variants),
                .layout = shape.layout,
            } },
            .array => |shape| .{ .array = .{ .length = shape.length, .element = globalType(o, shape.element) } },
            .alias => |target| .{ .alias = globalType(o, target) },
        },
    });
}

fn relocateType(o: Offsets, value: module_entities.ResolvedType) global_sg.GlobalType {
    return switch (value) {
        .builtin => |item| .{ .builtin = item },
        .declared => |id| .{ .declared = globalDecl(o, id) },
        .pointer => |item| .{ .pointer = .{ .child = globalType(o, item.child), .mutability = item.mutability } },
        .array => |item| .{ .array = .{ .length = item.length, .element = globalType(o, item.element) } },
        .nullable => |id| .{ .nullable = globalType(o, id) },
        .inferred_errable => |id| .{ .inferred_errable = globalType(o, id) },
        .inferred_choice => |item| .{ .inferred_choice = .{
            .identity = item.identity,
            .kind = item.kind,
            .variants = relocateEntityRange(global_sg.GlobalVariantId, o.variant_base, item.variants),
        } },
        .structural => |item| .{ .structural = .{
            .fields = relocateEntityRange(global_sg.GlobalFieldId, o.field_base, item.fields),
            .layout = item.layout,
        } },
        .structural_choice => |item| .{ .structural_choice = .{
            .variants = relocateEntityRange(global_sg.GlobalVariantId, o.variant_base, item.variants),
            .layout = item.layout,
        } },
        .generic => |item| .{ .generic = .{
            .base = globalDecl(o, item.base),
            .arguments = relocateEntityRange(global_sg.GlobalGenericArgId, o.generic_argument_base, item.arguments),
        } },
        .virtual => |abstract_type| .{ .virtual = globalType(o, abstract_type) },
    };
}

fn appendFunctions(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.functions.items, 0..) |_, index| {
        const value = try module_views.functionView(module, @enumFromInt(@as(u32, @intCast(index))));
        try result.functions.append(allocator, .{
            .declaration = globalDecl(o, value.declaration),
            .input = relocateEntityRange(global_sg.GlobalFieldId, o.field_base, value.input),
            .output = relocateEntityRange(global_sg.GlobalFieldId, o.field_base, value.output),
            .body = if (value.body) |id| globalBlock(o, id) else null,
            .input_bindings = relocatePoolRange(global_sg.GlobalBindingId, o.binding_ref_base, value.input_bindings),
            .output_bindings = relocatePoolRange(global_sg.GlobalBindingId, o.binding_ref_base, value.output_bindings),
            .inferred_error_reasons = if (value.inferred_error_reasons) |id| globalType(o, id) else null,
            .safety_primitive = value.safety_primitive,
            .flags = value.flags,
        });
        const operator = if (index < module.semantic.function_operators.items.len) module.semantic.function_operators.items[index] else null;
        try result.function_operators.append(allocator, operator);
    }
}

fn appendSymbols(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.symbol_declarations.items) |id| try result.symbol_declarations.append(allocator, globalDecl(o, id));
    for (module.symbols.items) |symbol| try result.symbols.append(allocator, .{
        .name = try relocateString(module, symbol.name, o.string_base),
        .declarations = .{ .start = o.symbol_declaration_base + symbol.declarations.start, .len = symbol.declarations.len },
    });
}

fn appendReferencePools(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets) !void {
    for (module.semantic.node_refs.items) |id| try result.node_refs.append(allocator, globalNode(o, id));
    for (module.semantic.type_refs.items) |id| try result.type_refs.append(allocator, globalType(o, id));
    for (module.semantic.binding_refs.items) |id| try result.binding_refs.append(allocator, globalBinding(o, id));
    for (module.semantic.function_refs.items) |id| try result.function_refs.append(allocator, globalFunction(o, id));
    for (module.semantic.virtual_registry_refs.items) |id| try result.virtual_registry_refs.append(allocator, globalVirtualRegistry(o, id));
}

fn appendBodyTables(allocator: std.mem.Allocator, result: *global_sg.GlobalSemanticGraph, module: *const module_sg.ModuleSemanticGraph, o: Offsets, mode: Mode) !void {
    const storage = &module.semantic;
    for (storage.bindings.items) |value| try result.bindings.append(allocator, .{
        .name = try relocateString(module, value.name, o.string_base),
        .source = globalSource(o, value.source),
        .ty = globalType(o, value.ty),
        .initialization = if (value.initialization) |id| globalNode(o, id) else null,
        .mutability = value.mutability,
    });
    for (storage.blocks.items) |value| try result.blocks.append(allocator, .{
        .nodes = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.nodes),
        .ret_val = if (value.ret_val) |id| globalNode(o, id) else null,
    });
    for (storage.value_fields.items) |value| try result.value_fields.append(allocator, .{
        .name = try relocateString(module, value.name, o.string_base),
        .value = globalNode(o, value.value),
    });
    for (storage.switch_cases.items) |value| try result.switch_cases.append(allocator, .{
        .value = globalNode(o, value.value),
        .variant = globalVariant(o, value.variant),
        .body = globalBlock(o, value.body),
    });
    for (storage.switches.items) |value| try result.switches.append(allocator, .{
        .expression = globalNode(o, value.expression),
        .cases = relocateEntityRange(global_sg.GlobalSwitchCaseId, o.switch_case_base, value.cases),
        .default_block = if (value.default_block) |id| globalBlock(o, id) else null,
        .exhaustive = value.exhaustive,
    });
    for (storage.auto_deinit_fields.items) |value| try result.auto_deinit_fields.append(allocator, .{
        .field_index = value.field_index,
        .deinit_fn = if (value.deinit_fn) |id| globalFunction(o, id) else null,
        .input = if (value.input) |id| globalNode(o, id) else null,
        .self_field_index = value.self_field_index,
        .fields = relocateEntityRange(global_sg.GlobalAutoDeinitFieldId, o.auto_deinit_field_base, value.fields),
    });
    for (storage.auto_deinits.items) |value| try result.auto_deinits.append(allocator, .{
        .binding = globalBinding(o, value.binding),
        .deinit_fn = if (value.deinit_fn) |id| globalFunction(o, id) else null,
        .input = if (value.input) |id| globalNode(o, id) else null,
        .self_field_index = value.self_field_index,
        .fields = relocateEntityRange(global_sg.GlobalAutoDeinitFieldId, o.auto_deinit_field_base, value.fields),
    });
    for (storage.virtual_registries.items) |value| try result.virtual_registries.append(allocator, .{
        .implementations = relocatePoolRange(global_sg.GlobalFunctionId, o.function_ref_base, value.implementations),
    });
    for (storage.virtualizes.items) |value| try result.virtualizes.append(allocator, .{
        .value = globalNode(o, value.value),
        .concrete_type = globalType(o, value.concrete_type),
        .abstract_decl = globalDecl(o, value.abstract_decl),
        .virtual_type = globalType(o, value.virtual_type),
        .methods = relocatePoolRange(global_sg.GlobalFunctionId, o.function_ref_base, value.methods),
        .safety_methods = relocatePoolRange(global_sg.GlobalVirtualRegistryId, o.virtual_registry_ref_base, value.safety_methods),
        .source = globalSource(o, value.source),
    });
    for (storage.virtual_calls.items) |value| try result.virtual_calls.append(allocator, .{
        .handle = globalNode(o, value.handle),
        .input = globalNode(o, value.input),
        .self_input_index = value.self_input_index,
        .method_index = value.method_index,
        .method_count = value.method_count,
        .method_name = try relocateString(module, value.method_name, o.string_base),
        .input_type = globalType(o, value.input_type),
        .output_type = globalType(o, value.output_type),
        .self_permission = value.self_permission,
        .safety_methods = globalVirtualRegistry(o, value.safety_methods),
        .consumes_auto_deinit = if (value.consumes_auto_deinit) |id| globalNode(o, id) else null,
    });
    for (storage.reach_segments.items) |value| try result.reach_segments.append(allocator, try relocateString(module, value, o.string_base));
    for (storage.reach_alternatives.items) |value| try result.reach_alternatives.append(allocator, .{
        .segments = relocateEntityRange(global_sg.GlobalReachSegmentId, o.reach_segment_base, value.segments),
    });
    for (storage.reaches.items) |value| try result.reaches.append(allocator, .{
        .alternatives = relocateEntityRange(global_sg.GlobalReachAlternativeId, o.reach_alternative_base, value.alternatives),
    });
    for (storage.nullable_unwraps.items) |value| try result.nullable_unwraps.append(allocator, .{
        .nullable_value = globalNode(o, value.nullable_value),
        .fallback_value = globalNode(o, value.fallback_value),
        .some_variant = globalVariant(o, value.some_variant),
        .some_value_field_index = value.some_value_field_index,
        .result_type = globalType(o, value.result_type),
    });
    for (storage.testing_expect_errors.items) |value| try result.testing_expect_errors.append(allocator, .{
        .expected_reason = globalNode(o, value.expected_reason),
        .actual_result = globalNode(o, value.actual_result),
        .actual_error_variant = globalVariant(o, value.actual_error_variant),
        .actual_error_payload_type = globalType(o, value.actual_error_payload_type),
        .actual_reason_field_index = value.actual_reason_field_index,
        .result_type = globalType(o, value.result_type),
        .result_ok_variant = globalVariant(o, value.result_ok_variant),
        .test_fail_function = globalFunction(o, value.test_fail_function),
        .expected_reason_name = if (value.expected_reason_name) |name| try relocateString(module, name, o.string_base) else null,
        .diagnostic_line = value.diagnostic_line,
        .diagnostic_column = value.diagnostic_column,
        .diagnostic_source_line = try relocateString(module, value.diagnostic_source_line, o.string_base),
    });
    for (storage.error_propagations.items) |value| try result.error_propagations.append(allocator, .{
        .errable_value = globalNode(o, value.errable_value),
        .cleanup_nodes = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.cleanup_nodes),
        .ok_variant = globalVariant(o, value.ok_variant),
        .ok_value_field_index = value.ok_value_field_index,
        .error_variant = globalVariant(o, value.error_variant),
        .propagated_errable_type = globalType(o, value.propagated_errable_type),
        .propagated_error_variant = globalVariant(o, value.propagated_error_variant),
        .ok_payload_type = globalType(o, value.ok_payload_type),
        .error_payload_type = globalType(o, value.error_payload_type),
        .propagated_error_payload_type = globalType(o, value.propagated_error_payload_type),
        .diagnostic_line = value.diagnostic_line,
        .diagnostic_column = value.diagnostic_column,
        .diagnostic_source_line = try relocateString(module, value.diagnostic_source_line, o.string_base),
    });
    for (storage.error_contexts.items) |value| try result.error_contexts.append(allocator, .{
        .errable_value = globalNode(o, value.errable_value),
        .context = globalNode(o, value.context),
        .cleanup_nodes = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.cleanup_nodes),
        .ok_variant = globalVariant(o, value.ok_variant),
        .ok_value_field_index = value.ok_value_field_index,
        .error_variant = globalVariant(o, value.error_variant),
        .propagated_errable_type = globalType(o, value.propagated_errable_type),
        .propagated_error_variant = globalVariant(o, value.propagated_error_variant),
        .ok_payload_type = globalType(o, value.ok_payload_type),
        .error_payload_type = globalType(o, value.error_payload_type),
        .propagated_error_payload_type = globalType(o, value.propagated_error_payload_type),
        .diagnostic_line = value.diagnostic_line,
        .diagnostic_column = value.diagnostic_column,
        .diagnostic_source_line = try relocateString(module, value.diagnostic_source_line, o.string_base),
    });

    for (storage.nodes.items) |node| switch (node) {
        .resolved => |value| try result.nodes.append(allocator, try relocateNode(module, o, value)),
        .pending => if (mode == .allow_holes) try result.nodes.append(allocator, .{
            .source = .{ .file_index = o.file_base, .offset = 0 },
            .ty = null,
            .content = .{ .bool_literal = false },
        }) else return error.UnresolvedModuleSemantics,
    };
    for (storage.roots.items) |id| try result.roots.append(allocator, globalNode(o, id));
}

fn relocateNode(module: *const module_sg.ModuleSemanticGraph, o: Offsets, node: module_entities.ResolvedNode) !global_sg.Node {
    return .{
        .source = globalSource(o, node.source),
        .ty = if (node.ty) |id| globalType(o, id) else null,
        .content = switch (node.content) {
            .declaration => |id| .{ .declaration = globalDecl(o, id) },
            .binding_declaration => |id| .{ .binding_declaration = globalBinding(o, id) },
            .binding_use => |id| .{ .binding_use = globalBinding(o, id) },
            .reach_directive => |id| .{ .reach_directive = globalReach(o, id) },
            .move_value => |id| .{ .move_value = globalNode(o, id) },
            .assignment => |value| .{ .assignment = .{ .binding = globalBinding(o, value.binding), .value = globalNode(o, value.value) } },
            .auto_deinit_binding => |id| .{ .auto_deinit_binding = globalAutoDeinit(o, id) },
            .function_call => |value| .{ .function_call = .{
                .callee = globalFunction(o, value.callee),
                .input = globalNode(o, value.input),
                .consumes_auto_deinit = if (value.consumes_auto_deinit) |id| globalNode(o, id) else null,
                .initializes_auto_deinit = if (value.initializes_auto_deinit) |id| globalNode(o, id) else null,
            } },
            .virtualize => |id| .{ .virtualize = globalVirtualize(o, id) },
            .virtual_call => |id| .{ .virtual_call = globalVirtualCall(o, id) },
            .code_block => |id| .{ .code_block = globalBlock(o, id) },
            .int_literal => |value| .{ .int_literal = value },
            .float_literal => |value| .{ .float_literal = value },
            .char_literal => |value| .{ .char_literal = value },
            .string_literal => |value| .{ .string_literal = try relocateString(module, value, o.string_base) },
            .bool_literal => |value| .{ .bool_literal = value },
            .list_literal => |value| .{ .list_literal = .{
                .elements = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.elements),
                .element_types = relocatePoolRange(global_sg.GlobalTypeId, o.type_ref_base, value.element_types),
            } },
            .struct_value_literal => |value| .{ .struct_value_literal = .{
                .fields = relocateEntityRange(global_sg.GlobalValueFieldId, o.value_field_base, value.fields),
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
            .nullable_unwrap_or => |id| .{ .nullable_unwrap_or = globalNullableUnwrap(o, id) },
            .testing_expect_error => |id| .{ .testing_expect_error = globalTestingExpectError(o, id) },
            .error_propagation => |id| .{ .error_propagation = globalErrorPropagation(o, id) },
            .error_context => |id| .{ .error_context = globalErrorContext(o, id) },
            .array_literal => |value| .{ .array_literal = .{
                .elements = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.elements),
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
                .cleanup = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.cleanup),
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
            .switch_statement => |id| .{ .switch_statement = globalSwitch(o, id) },
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

fn relocateString(module: *const module_sg.ModuleSemanticGraph, value: module_sg.StringRange, base: u32) !global_sg.StringRange {
    if (value.start > module.strings.items.len or value.len > module.strings.items.len - value.start) return error.InvalidModuleStringRange;
    if (value.start > std.math.maxInt(u32) - base) return error.GlobalSemanticGraphTooLarge;
    return .{ .start = base + value.start, .len = value.len };
}

fn globalSource(o: Offsets, value: primitives.SourceRef) primitives.SourceRef {
    return .{ .file_index = o.file_base + value.file_index, .offset = value.offset };
}
fn relocateEntityRange(comptime GlobalId: type, base: u32, range: anytype) primitives.Range(GlobalId) {
    return .{ .start = base + range.start, .len = range.len };
}
fn relocatePoolRange(comptime GlobalId: type, pool_base: u32, range: anytype) primitives.Range(GlobalId) {
    return .{ .start = pool_base + range.start, .len = range.len };
}

pub fn globalDecl(o: Offsets, id: module_entities.ModuleDeclId) global_sg.GlobalDeclId {
    return @enumFromInt(o.declaration_base + @intFromEnum(id));
}
pub fn globalType(o: Offsets, id: module_entities.ModuleTypeId) global_sg.GlobalTypeId {
    return @enumFromInt(o.type_base + @intFromEnum(id));
}
pub fn globalFunction(o: Offsets, id: module_entities.ModuleFunctionId) global_sg.GlobalFunctionId {
    return @enumFromInt(o.function_base + @intFromEnum(id));
}
pub fn globalBinding(o: Offsets, id: module_entities.ModuleBindingId) global_sg.GlobalBindingId {
    return @enumFromInt(o.binding_base + @intFromEnum(id));
}
pub fn globalNode(o: Offsets, id: module_entities.ModuleNodeId) global_sg.GlobalNodeId {
    return @enumFromInt(o.node_base + @intFromEnum(id));
}
pub fn globalBlock(o: Offsets, id: module_entities.ModuleBlockId) global_sg.GlobalBlockId {
    return @enumFromInt(o.block_base + @intFromEnum(id));
}
pub fn globalVariant(o: Offsets, id: module_entities.ModuleVariantId) global_sg.GlobalVariantId {
    return @enumFromInt(o.variant_base + @intFromEnum(id));
}
fn globalSwitch(o: Offsets, id: module_entities.ModuleSwitchId) global_sg.GlobalSwitchId {
    return @enumFromInt(o.switch_base + @intFromEnum(id));
}
fn globalAutoDeinit(o: Offsets, id: module_entities.ModuleAutoDeinitId) global_sg.GlobalAutoDeinitId {
    return @enumFromInt(o.auto_deinit_base + @intFromEnum(id));
}
fn globalVirtualRegistry(o: Offsets, id: module_entities.ModuleVirtualRegistryId) global_sg.GlobalVirtualRegistryId {
    return @enumFromInt(o.virtual_registry_base + @intFromEnum(id));
}
fn globalVirtualize(o: Offsets, id: module_entities.ModuleVirtualizeId) global_sg.GlobalVirtualizeId {
    return @enumFromInt(o.virtualize_base + @intFromEnum(id));
}
fn globalVirtualCall(o: Offsets, id: module_entities.ModuleVirtualCallId) global_sg.GlobalVirtualCallId {
    return @enumFromInt(o.virtual_call_base + @intFromEnum(id));
}
fn globalReach(o: Offsets, id: module_entities.ModuleReachId) global_sg.GlobalReachId {
    return @enumFromInt(o.reach_base + @intFromEnum(id));
}
fn globalNullableUnwrap(o: Offsets, id: module_entities.ModuleNullableUnwrapId) global_sg.GlobalNullableUnwrapId {
    return @enumFromInt(o.nullable_unwrap_base + @intFromEnum(id));
}
fn globalTestingExpectError(o: Offsets, id: module_entities.ModuleTestingExpectErrorId) global_sg.GlobalTestingExpectErrorId {
    return @enumFromInt(o.testing_expect_error_base + @intFromEnum(id));
}
fn globalErrorPropagation(o: Offsets, id: module_entities.ModuleErrorPropagationId) global_sg.GlobalErrorPropagationId {
    return @enumFromInt(o.error_propagation_base + @intFromEnum(id));
}
fn globalErrorContext(o: Offsets, id: module_entities.ModuleErrorContextId) global_sg.GlobalErrorContextId {
    return @enumFromInt(o.error_context_base + @intFromEnum(id));
}

fn baseFor(existing: usize, additional: usize) !u32 {
    if (existing > std.math.maxInt(u32) or additional > std.math.maxInt(u32) - existing) return error.GlobalSemanticGraphTooLarge;
    return @intCast(existing);
}
fn index32(value: usize) !u32 {
    if (value > std.math.maxInt(u32)) return error.GlobalSemanticGraphTooLarge;
    return @intCast(value);
}

test "globalizer preserves hole identity for GlobalSema" {
    const allocator = std.testing.allocator;
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer module.deinit(allocator);
    try module.file_offsets.append(allocator, .{
        .path = .{ .start = 0, .len = 0 },
        .declaration_base = 0,
        .declaration_count = 0,
        .type_reference_base = 0,
        .type_reference_count = 0,
    });
    try module.semantic.external_refs.append(allocator, .{
        .kind = .type,
        .module_path = null,
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try module.semantic.types.append(allocator, .{ .external = @enumFromInt(0) });
    try module.semantic.nodes.append(allocator, .{ .pending = @enumFromInt(0) });
    try module.semantic.pending_operations.append(allocator, .{ .resolve_name_use = .{
        .node = @enumFromInt(0),
        .name = .{ .start = 0, .len = 0 },
    } });
    var result = try relocate(allocator, &.{module}, .allow_holes);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.graph.types.items.len);
    try std.testing.expectEqual(@as(usize, 1), result.graph.nodes.items.len);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(globalType(result.offsets.items[0], @enumFromInt(0))));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(globalNode(result.offsets.items[0], @enumFromInt(0))));
}

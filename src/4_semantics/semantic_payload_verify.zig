const std = @import("std");
const primitives = @import("semantic_primitives.zig");
const verify = @import("semantic_verify.zig");

pub const Bounds = struct {
    files: usize = 0,
    declarations: usize = 0,
    types: usize = 0,
    functions: usize = 0,
    bindings: usize = 0,
    nodes: usize = 0,
    blocks: usize = 0,
    fields: usize = 0,
    variants: usize = 0,
    generic_arguments: usize = 0,
    value_fields: usize = 0,
    switch_cases: usize = 0,
    switches: usize = 0,
    auto_deinit_fields: usize = 0,
    auto_deinits: usize = 0,
    virtual_registries: usize = 0,
    virtualizes: usize = 0,
    virtual_calls: usize = 0,
    reach_segments: usize = 0,
    reach_alternatives: usize = 0,
    reaches: usize = 0,
    nullable_unwraps: usize = 0,
    testing_expect_errors: usize = 0,
    error_propagations: usize = 0,
    error_contexts: usize = 0,
    node_refs: usize = 0,
    type_refs: usize = 0,
    binding_refs: usize = 0,
    function_refs: usize = 0,
    virtual_registry_refs: usize = 0,
    strings: []const u8 = &.{},
};

fn require(ok: bool) !void {
    if (!ok) return error.InvalidSemanticGraphReference;
}

pub fn declaration(comptime Ids: type, value: primitives.Declaration(Ids), bounds: Bounds) !void {
    try require(verify.stringFits(value.name, bounds.strings));
    try require(verify.sourceFits(value.source, bounds.files));
    try require(verify.optionalIdFits(value.type_id, bounds.types));
    try require(verify.optionalIdFits(value.function_id, bounds.functions));
    if (value.struct_fields) |range| try require(verify.rangeFits(range, bounds.fields));
    if (value.choice_variants) |range| try require(verify.rangeFits(range, bounds.variants));
}

pub fn semanticType(comptime Ids: type, value: primitives.SemanticType(Ids), bounds: Bounds) !void {
    switch (value) {
        .builtin => {},
        .declared => |id| try require(verify.idFits(id, bounds.declarations)),
        .pointer => |item| try require(verify.idFits(item.child, bounds.types)),
        .array => |item| try require(verify.idFits(item.element, bounds.types)),
        .nullable, .inferred_errable => |id| try require(verify.idFits(id, bounds.types)),
        .inferred_choice => |item| try require(verify.rangeFits(item.variants, bounds.variants)),
        .structural => |item| try require(verify.rangeFits(item.fields, bounds.fields)),
        .structural_choice => |item| try require(verify.rangeFits(item.variants, bounds.variants)),
        .generic => |item| {
            try require(verify.idFits(item.base, bounds.declarations));
            try require(verify.rangeFits(item.arguments, bounds.generic_arguments));
        },
    }
}

pub fn field(comptime Ids: type, value: primitives.Field(Ids), bounds: Bounds) !void {
    try require(verify.stringFits(value.name, bounds.strings));
    try require(verify.idFits(value.ty, bounds.types));
    try require(verify.optionalIdFits(value.storage_type, bounds.types));
    try require(verify.sourceFits(value.source, bounds.files));
    try require(verify.optionalIdFits(value.default_value, bounds.nodes));
}

pub fn variant(comptime Ids: type, value: primitives.ChoiceVariant(Ids), bounds: Bounds) !void {
    try require(verify.stringFits(value.name, bounds.strings));
    try require(verify.optionalIdFits(value.payload_type, bounds.types));
    try require(verify.optionalIdFits(value.option_decl, bounds.declarations));
    try require(verify.sourceFits(value.source, bounds.files));
}

pub fn genericArgument(comptime Ids: type, value: primitives.GenericArgument(Ids), bounds: Bounds) !void {
    try require(verify.stringFits(value.name, bounds.strings));
    switch (value.value) {
        .type => |id| try require(verify.idFits(id, bounds.types)),
        .comptime_int => {},
    }
}

pub fn function(comptime Ids: type, value: primitives.Function(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.declaration, bounds.declarations));
    try require(verify.rangeFits(value.input, bounds.fields));
    try require(verify.rangeFits(value.output, bounds.fields));
    try require(verify.optionalIdFits(value.body, bounds.blocks));
    try require(verify.rangeFits(value.input_bindings, bounds.binding_refs));
    try require(verify.rangeFits(value.output_bindings, bounds.binding_refs));
    try require(verify.optionalIdFits(value.inferred_error_reasons, bounds.types));
}

pub fn binding(comptime Ids: type, value: primitives.Binding(Ids), bounds: Bounds) !void {
    try require(verify.stringFits(value.name, bounds.strings));
    try require(verify.sourceFits(value.source, bounds.files));
    try require(verify.idFits(value.ty, bounds.types));
    try require(verify.optionalIdFits(value.initialization, bounds.nodes));
}

pub fn block(comptime Ids: type, value: primitives.Block(Ids), bounds: Bounds) !void {
    try require(verify.rangeFits(value.nodes, bounds.node_refs));
    try require(verify.optionalIdFits(value.ret_val, bounds.nodes));
}

pub fn valueField(comptime Ids: type, value: primitives.ValueField(Ids), bounds: Bounds) !void {
    try require(verify.stringFits(value.name, bounds.strings));
    try require(verify.idFits(value.value, bounds.nodes));
}

pub fn switchCase(comptime Ids: type, value: primitives.SwitchCase(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.value, bounds.nodes));
    try require(verify.idFits(value.variant, bounds.variants));
    try require(verify.idFits(value.body, bounds.blocks));
}

pub fn switchPayload(comptime Ids: type, value: primitives.Switch(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.expression, bounds.nodes));
    try require(verify.rangeFits(value.cases, bounds.switch_cases));
    try require(verify.optionalIdFits(value.default_block, bounds.blocks));
}

pub fn autoDeinitField(comptime Ids: type, value: primitives.AutoDeinitField(Ids), bounds: Bounds) !void {
    try require(verify.optionalIdFits(value.deinit_fn, bounds.functions));
    try require(verify.optionalIdFits(value.input, bounds.nodes));
    try require(verify.rangeFits(value.fields, bounds.auto_deinit_fields));
}

pub fn autoDeinit(comptime Ids: type, value: primitives.AutoDeinit(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.binding, bounds.bindings));
    try require(verify.optionalIdFits(value.deinit_fn, bounds.functions));
    try require(verify.optionalIdFits(value.input, bounds.nodes));
    try require(verify.rangeFits(value.fields, bounds.auto_deinit_fields));
}

pub fn virtualRegistry(comptime Ids: type, value: primitives.VirtualMethodRegistry(Ids), bounds: Bounds) !void {
    try require(verify.rangeFits(value.implementations, bounds.function_refs));
}

pub fn virtualize(comptime Ids: type, value: primitives.Virtualize(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.value, bounds.nodes));
    try require(verify.idFits(value.concrete_type, bounds.types));
    try require(verify.idFits(value.abstract_decl, bounds.declarations));
    try require(verify.idFits(value.virtual_type, bounds.types));
    try require(verify.rangeFits(value.methods, bounds.function_refs));
    try require(verify.rangeFits(value.safety_methods, bounds.virtual_registry_refs));
    try require(verify.sourceFits(value.source, bounds.files));
}

pub fn virtualCall(comptime Ids: type, value: primitives.VirtualCall(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.handle, bounds.nodes));
    try require(verify.idFits(value.input, bounds.nodes));
    try require(verify.stringFits(value.method_name, bounds.strings));
    try require(verify.idFits(value.input_type, bounds.types));
    try require(verify.idFits(value.output_type, bounds.types));
    try require(verify.idFits(value.safety_methods, bounds.virtual_registries));
    try require(verify.optionalIdFits(value.consumes_auto_deinit, bounds.nodes));
}

pub fn reachAlternative(comptime Ids: type, value: primitives.ReachAlternative(Ids), bounds: Bounds) !void {
    try require(verify.rangeFits(value.segments, bounds.reach_segments));
}

pub fn reach(comptime Ids: type, value: primitives.Reach(Ids), bounds: Bounds) !void {
    try require(verify.rangeFits(value.alternatives, bounds.reach_alternatives));
}

pub fn nullableUnwrap(comptime Ids: type, value: primitives.NullableUnwrap(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.nullable_value, bounds.nodes));
    try require(verify.idFits(value.fallback_value, bounds.nodes));
    try require(verify.idFits(value.some_variant, bounds.variants));
    try require(verify.idFits(value.result_type, bounds.types));
}

pub fn testingExpectError(comptime Ids: type, value: primitives.TestingExpectError(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.expected_reason, bounds.nodes));
    try require(verify.idFits(value.actual_result, bounds.nodes));
    try require(verify.idFits(value.actual_error_variant, bounds.variants));
    try require(verify.idFits(value.actual_error_payload_type, bounds.types));
    try require(verify.idFits(value.result_type, bounds.types));
    try require(verify.idFits(value.result_ok_variant, bounds.variants));
    try require(verify.idFits(value.test_fail_function, bounds.functions));
    if (value.expected_reason_name) |name| try require(verify.stringFits(name, bounds.strings));
    try require(verify.stringFits(value.diagnostic_source_line, bounds.strings));
}

pub fn errorPropagation(comptime Ids: type, value: primitives.ErrorPropagation(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.errable_value, bounds.nodes));
    try require(verify.rangeFits(value.cleanup_nodes, bounds.node_refs));
    try require(verify.idFits(value.ok_variant, bounds.variants));
    try require(verify.idFits(value.error_variant, bounds.variants));
    try require(verify.idFits(value.propagated_errable_type, bounds.types));
    try require(verify.idFits(value.propagated_error_variant, bounds.variants));
    try require(verify.idFits(value.ok_payload_type, bounds.types));
    try require(verify.idFits(value.error_payload_type, bounds.types));
    try require(verify.idFits(value.propagated_error_payload_type, bounds.types));
    try require(verify.stringFits(value.diagnostic_source_line, bounds.strings));
}

pub fn errorContext(comptime Ids: type, value: primitives.ErrorContext(Ids), bounds: Bounds) !void {
    try require(verify.idFits(value.errable_value, bounds.nodes));
    try require(verify.idFits(value.context, bounds.nodes));
    try require(verify.rangeFits(value.cleanup_nodes, bounds.node_refs));
    try require(verify.idFits(value.ok_variant, bounds.variants));
    try require(verify.idFits(value.error_variant, bounds.variants));
    try require(verify.idFits(value.propagated_errable_type, bounds.types));
    try require(verify.idFits(value.propagated_error_variant, bounds.variants));
    try require(verify.idFits(value.ok_payload_type, bounds.types));
    try require(verify.idFits(value.error_payload_type, bounds.types));
    try require(verify.idFits(value.propagated_error_payload_type, bounds.types));
    try require(verify.stringFits(value.diagnostic_source_line, bounds.strings));
}

pub fn node(comptime Ids: type, value: primitives.Node(Ids), bounds: Bounds) !void {
    try require(verify.sourceFits(value.source, bounds.files));
    try require(verify.optionalIdFits(value.ty, bounds.types));
    switch (value.content) {
        .declaration => |id| try require(verify.idFits(id, bounds.declarations)),
        .binding_declaration, .binding_use => |id| try require(verify.idFits(id, bounds.bindings)),
        .reach_directive => |id| try require(verify.idFits(id, bounds.reaches)),
        .move_value, .address_of => |id| try require(verify.idFits(id, bounds.nodes)),
        .assignment => |item| {
            try require(verify.idFits(item.binding, bounds.bindings));
            try require(verify.idFits(item.value, bounds.nodes));
        },
        .auto_deinit_binding => |id| try require(verify.idFits(id, bounds.auto_deinits)),
        .function_call => |item| {
            try require(verify.idFits(item.callee, bounds.functions));
            try require(verify.idFits(item.input, bounds.nodes));
            try require(verify.optionalIdFits(item.consumes_auto_deinit, bounds.nodes));
            try require(verify.optionalIdFits(item.initializes_auto_deinit, bounds.nodes));
        },
        .virtualize => |id| try require(verify.idFits(id, bounds.virtualizes)),
        .virtual_call => |id| try require(verify.idFits(id, bounds.virtual_calls)),
        .code_block => |id| try require(verify.idFits(id, bounds.blocks)),
        .int_literal, .float_literal, .char_literal, .bool_literal, .break_statement, .continue_statement => {},
        .string_literal => |text| try require(verify.stringFits(text, bounds.strings)),
        .list_literal => |item| {
            try require(verify.rangeFits(item.elements, bounds.node_refs));
            try require(verify.rangeFits(item.element_types, bounds.type_refs));
        },
        .struct_value_literal => |item| {
            try require(verify.rangeFits(item.fields, bounds.value_fields));
            try require(verify.idFits(item.ty, bounds.types));
        },
        .struct_field_access => |item| {
            try require(verify.idFits(item.value, bounds.nodes));
            try require(verify.stringFits(item.field_name, bounds.strings));
        },
        .choice_literal => |item| {
            try require(verify.idFits(item.choice_type, bounds.types));
            try require(verify.idFits(item.variant, bounds.variants));
            try require(verify.optionalIdFits(item.payload, bounds.nodes));
        },
        .choice_payload_access => |item| {
            try require(verify.idFits(item.value, bounds.nodes));
            try require(verify.idFits(item.variant, bounds.variants));
            try require(verify.idFits(item.payload_type, bounds.types));
        },
        .nullable_unwrap_or => |id| try require(verify.idFits(id, bounds.nullable_unwraps)),
        .testing_expect_error => |id| try require(verify.idFits(id, bounds.testing_expect_errors)),
        .error_propagation => |id| try require(verify.idFits(id, bounds.error_propagations)),
        .error_context => |id| try require(verify.idFits(id, bounds.error_contexts)),
        .array_literal => |item| {
            try require(verify.rangeFits(item.elements, bounds.node_refs));
            try require(verify.idFits(item.element_type, bounds.types));
        },
        .array_index => |item| {
            try require(verify.idFits(item.array_ptr, bounds.nodes));
            try require(verify.idFits(item.index, bounds.nodes));
            try require(verify.idFits(item.element_type, bounds.types));
            try require(verify.idFits(item.array_type, bounds.types));
        },
        .array_store => |item| {
            try require(verify.idFits(item.array_ptr, bounds.nodes));
            try require(verify.idFits(item.index, bounds.nodes));
            try require(verify.idFits(item.value, bounds.nodes));
            try require(verify.idFits(item.element_type, bounds.types));
            try require(verify.idFits(item.array_type, bounds.types));
        },
        .struct_field_store => |item| {
            try require(verify.idFits(item.struct_ptr, bounds.nodes));
            try require(verify.idFits(item.struct_type, bounds.types));
            try require(verify.idFits(item.field_type, bounds.types));
            try require(verify.idFits(item.value, bounds.nodes));
        },
        .binary_operation, .comparison, .logical_operation => |item| {
            try require(verify.idFits(item.left, bounds.nodes));
            try require(verify.idFits(item.right, bounds.nodes));
        },
        .return_statement => |item| {
            try require(verify.optionalIdFits(item.expression, bounds.nodes));
            try require(verify.rangeFits(item.cleanup, bounds.node_refs));
        },
        .if_statement => |item| {
            try require(verify.idFits(item.condition, bounds.nodes));
            try require(verify.idFits(item.then_block, bounds.blocks));
            try require(verify.optionalIdFits(item.else_block, bounds.blocks));
            if (item.choice_test) |test_value| {
                try require(verify.idFits(test_value.choice_value, bounds.nodes));
                try require(verify.idFits(test_value.choice_type, bounds.types));
                try require(verify.idFits(test_value.variant, bounds.variants));
            }
        },
        .while_statement => |item| {
            try require(verify.idFits(item.condition, bounds.nodes));
            try require(verify.idFits(item.body, bounds.blocks));
        },
        .for_statement => |item| {
            try require(verify.optionalIdFits(item.init, bounds.nodes));
            try require(verify.idFits(item.condition, bounds.nodes));
            try require(verify.optionalIdFits(item.increment, bounds.nodes));
            try require(verify.idFits(item.body, bounds.blocks));
        },
        .switch_statement => |id| try require(verify.idFits(id, bounds.switches)),
        .dereference => |item| {
            try require(verify.idFits(item.pointer, bounds.nodes));
            try require(verify.idFits(item.ty, bounds.types));
            try require(verify.idFits(item.pointer_type, bounds.types));
        },
        .pointer_assignment => |item| {
            try require(verify.idFits(item.pointer, bounds.nodes));
            try require(verify.idFits(item.value, bounds.nodes));
        },
        .type_initializer => |item| {
            try require(verify.idFits(item.type_decl, bounds.declarations));
            try require(verify.idFits(item.init_fn, bounds.functions));
            try require(verify.idFits(item.args, bounds.nodes));
        },
        .type_literal => |id| try require(verify.idFits(id, bounds.types)),
        .explicit_cast => |item| {
            try require(verify.idFits(item.value, bounds.nodes));
            try require(verify.idFits(item.target_type, bounds.types));
        },
    }
}

test "shared payload verifier covers declarations and inferred choices" {
    const Ids = struct {
        pub const DeclId = enum(u32) { _ };
        pub const TypeId = enum(u32) { _ };
        pub const FunctionId = enum(u32) { _ };
        pub const BindingId = enum(u32) { _ };
        pub const NodeId = enum(u32) { _ };
        pub const BlockId = enum(u32) { _ };
        pub const FieldId = enum(u32) { _ };
        pub const VariantId = enum(u32) { _ };
        pub const GenericArgId = enum(u32) { _ };
        pub const ValueFieldId = enum(u32) { _ };
        pub const SwitchCaseId = enum(u32) { _ };
        pub const SwitchId = enum(u32) { _ };
        pub const AutoDeinitFieldId = enum(u32) { _ };
        pub const AutoDeinitId = enum(u32) { _ };
        pub const VirtualRegistryId = enum(u32) { _ };
        pub const VirtualizeId = enum(u32) { _ };
        pub const VirtualCallId = enum(u32) { _ };
        pub const ReachSegmentId = enum(u32) { _ };
        pub const ReachAlternativeId = enum(u32) { _ };
        pub const ReachId = enum(u32) { _ };
        pub const NullableUnwrapId = enum(u32) { _ };
        pub const TestingExpectErrorId = enum(u32) { _ };
        pub const ErrorPropagationId = enum(u32) { _ };
        pub const ErrorContextId = enum(u32) { _ };
    };

    try declaration(Ids, .{
        .kind = .type,
        .name = .{ .start = 0, .len = 1 },
        .source = .{ .file_index = 0, .offset = 0 },
    }, .{ .files = 1, .strings = "T" });

    try semanticType(Ids, .{ .inferred_choice = .{
        .identity = 3,
        .kind = .reasons,
        .variants = .{ .start = 0, .len = 0 },
    } }, .{});

    const Node = primitives.Node(Ids);
    try node(Ids, Node{
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = null,
        .content = .{ .int_literal = 3 },
    }, .{ .files = 1 });
}
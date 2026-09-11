const std = @import("std");
const semantic_strings = @import("strings.zig");

pub const StringRange = semantic_strings.StringRange;

/// A range of values of `T` stored in the table implied by its use site.
/// `start` is a table offset, not a semantic identity itself.
pub fn Range(comptime T: type) type {
    _ = T;
    return struct { start: u32, len: u32 };
}

pub const BuiltinType = enum {
    Int8,
    Int16,
    Int32,
    Int64,
    UIntNative,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Float16,
    Float32,
    Float64,
    Char,
    Bool,
    Void,
    Type,
    Any,
};

pub const PointerMutability = enum(u8) { read_only, read_write };
pub const Mutability = enum(u8) { constant, variable };
pub const ForMode = enum(u8) { value, borrow, mut_borrow };
pub const MatchCaseMode = enum(u8) { value, borrow, mut_borrow, move };
pub const BinaryOperator = enum(u8) { addition, subtraction, multiplication, division, modulo };
pub const ComparisonOperator = enum(u8) { equal, not_equal, less_than, greater_than, less_than_or_equal, greater_than_or_equal };

pub const DeclarationKind = enum {
    binding,
    import_alias,
    abstract_type,
    type,
    choice_option,
    function,
    test_function,
};

pub const SafetyPrimitive = enum {
    none,
    establish_fresh_reference,
    establish_inherited_reference,
    establish_inherited_storage,
    establish_allocation,
    raw_allocated_storage,
    reference_offset,
    mutable_reference_offset,
    reinterpret_reference,
    mutable_reinterpret_reference,
    read_reference,
    restrict_reference,
    trusted_opaque_move,
    trusted_opaque_move_in,
    trusted_opaque_move_out,
    trusted_opaque_relocate,
    trusted_opaque_drop,
    trusted_opaque_mark_empty,
    relocate,
};

pub const FunctionFlags = packed struct(u16) {
    is_once: bool = false,
    is_test: bool = false,
    has_declared_body: bool = false,
    uses_inferred_error_reasons: bool = false,
    is_deinit: bool = false,
    is_generic_instantiation: bool = false,
    is_abstract_dispatch: bool = false,
    _padding: u9 = 0,
};

pub const StructLayout = enum(u8) { regular, c_union };
pub const ChoiceLayout = enum(u8) { regular, c_enum };
pub const InferredChoiceKind = enum(u8) { errable, reasons };
pub const LogicalOperator = enum(u8) { and_, or_ };

pub const SourceRef = struct {
    file_index: u32,
    offset: u32,
};

/// Canonical declaration payload shared by ModuleSG and GlobalSG. Source
/// provenance is graph-local; semantic references use the corresponding Ids
/// namespace. Layout lives here for nominal types because `.declared` type IDs
/// intentionally carry only nominal identity.
pub fn Declaration(comptime Ids: type) type {
    return struct {
        kind: DeclarationKind,
        name: StringRange,
        source: SourceRef,
        type_id: ?Ids.TypeId = null,
        function_id: ?Ids.FunctionId = null,
        struct_fields: ?Range(Ids.FieldId) = null,
        choice_variants: ?Range(Ids.VariantId) = null,
        generic_parameter_count: ?u32 = null,
        struct_layout: StructLayout = .regular,
        choice_layout: ChoiceLayout = .regular,
    };
}

/// `Ids` is a namespace containing the graph-specific identity types. ModuleSG
/// and GlobalSG instantiate the same resolved semantic shapes with different
/// enum IDs.
pub fn SemanticType(comptime Ids: type) type {
    return union(enum) {
        builtin: BuiltinType,
        declared: Ids.DeclId,
        pointer: struct { child: Ids.TypeId, mutability: PointerMutability },
        array: struct { length: u64, element: Ids.TypeId },
        nullable: Ids.TypeId,
        inferred_errable: Ids.TypeId,
        /// Identity-bearing inferred choices are distinct from ordinary
        /// structural choices even when their current variant sets match.
        inferred_choice: struct {
            identity: u32,
            kind: InferredChoiceKind,
            variants: Range(Ids.VariantId),
        },
        structural: struct {
            fields: Range(Ids.FieldId),
            layout: StructLayout = .regular,
        },
        structural_choice: struct {
            variants: Range(Ids.VariantId),
            layout: ChoiceLayout = .regular,
        },
        generic: struct {
            base: Ids.DeclId,
            arguments: Range(Ids.GenericArgId),
        },
        /// Runtime pair (data pointer, vtable pointer) carrying an Abstract.
        /// The abstract type identity is explicit because `Virtual` is an
        /// intrinsic type constructor, not a source declaration.
        virtual: Ids.TypeId,
    };
}

pub fn Field(comptime Ids: type) type {
    return struct {
        name: StringRange,
        ty: Ids.TypeId,
        storage_type: ?Ids.TypeId = null,
        source: SourceRef,
        default_value: ?Ids.NodeId = null,
    };
}

pub fn ChoiceVariant(comptime Ids: type) type {
    return struct {
        name: StringRange,
        payload_type: ?Ids.TypeId = null,
        option_decl: ?Ids.DeclId = null,
        source: SourceRef,
        value: i32,
    };
}

pub fn GenericArgument(comptime Ids: type) type {
    return struct {
        name: StringRange,
        value: Value,

        pub const Value = union(enum) {
            type: Ids.TypeId,
            comptime_int: i64,
        };
    };
}

pub fn Function(comptime Ids: type) type {
    return struct {
        declaration: Ids.DeclId,
        input: Range(Ids.FieldId),
        output: Range(Ids.FieldId),
        body: ?Ids.BlockId = null,
        input_bindings: Range(Ids.BindingId) = .{ .start = 0, .len = 0 },
        output_bindings: Range(Ids.BindingId) = .{ .start = 0, .len = 0 },
        inferred_error_reasons: ?Ids.TypeId = null,
        safety_primitive: SafetyPrimitive = .none,
        flags: FunctionFlags = .{},
    };
}

pub fn Binding(comptime Ids: type) type {
    return struct {
        name: StringRange,
        source: SourceRef,
        ty: Ids.TypeId,
        initialization: ?Ids.NodeId = null,
        mutability: Mutability,
    };
}

pub fn Block(comptime Ids: type) type {
    return struct {
        nodes: Range(Ids.NodeId),
        ret_val: ?Ids.NodeId = null,
    };
}

pub fn ValueField(comptime Ids: type) type {
    return struct {
        name: StringRange,
        value: Ids.NodeId,
    };
}

pub fn ChoiceTagTest(comptime Ids: type) type {
    return struct {
        choice_value: Ids.NodeId,
        choice_type: Ids.TypeId,
        variant: Ids.VariantId,
        then_has_variant: bool,
    };
}

pub fn SwitchCase(comptime Ids: type) type {
    return struct {
        value: Ids.NodeId,
        variant: Ids.VariantId,
        body: Ids.BlockId,
    };
}

pub fn Switch(comptime Ids: type) type {
    return struct {
        expression: Ids.NodeId,
        cases: Range(Ids.SwitchCaseId),
        default_block: ?Ids.BlockId,
        exhaustive: bool = false,
    };
}

pub fn AutoDeinitField(comptime Ids: type) type {
    return struct {
        field_index: u32,
        deinit_fn: ?Ids.FunctionId,
        input: ?Ids.NodeId = null,
        self_field_index: u32 = 0,
        fields: Range(Ids.AutoDeinitFieldId) = .{ .start = 0, .len = 0 },
    };
}

pub fn AutoDeinit(comptime Ids: type) type {
    return struct {
        binding: Ids.BindingId,
        deinit_fn: ?Ids.FunctionId,
        input: ?Ids.NodeId = null,
        self_field_index: u32 = 0,
        fields: Range(Ids.AutoDeinitFieldId) = .{ .start = 0, .len = 0 },
    };
}

pub fn VirtualMethodRegistry(comptime Ids: type) type {
    return struct {
        implementations: Range(Ids.FunctionId),
    };
}

pub fn Virtualize(comptime Ids: type) type {
    return struct {
        value: Ids.NodeId,
        concrete_type: Ids.TypeId,
        abstract_decl: Ids.DeclId,
        virtual_type: Ids.TypeId,
        methods: Range(Ids.FunctionId),
        safety_methods: Range(Ids.VirtualRegistryId),
        source: SourceRef,
    };
}

pub fn VirtualCall(comptime Ids: type) type {
    return struct {
        handle: Ids.NodeId,
        input: Ids.NodeId,
        self_input_index: u32,
        method_index: u32,
        method_count: u32,
        method_name: StringRange,
        input_type: Ids.TypeId,
        output_type: Ids.TypeId,
        self_permission: PointerMutability,
        safety_methods: Ids.VirtualRegistryId,
        consumes_auto_deinit: ?Ids.NodeId = null,
    };
}

pub fn ReachAlternative(comptime Ids: type) type {
    return struct {
        segments: Range(Ids.ReachSegmentId),
    };
}

pub fn Reach(comptime Ids: type) type {
    return struct {
        alternatives: Range(Ids.ReachAlternativeId),
    };
}

pub fn NullableUnwrap(comptime Ids: type) type {
    return struct {
        nullable_value: Ids.NodeId,
        fallback_value: Ids.NodeId,
        some_variant: Ids.VariantId,
        some_value_field_index: u32,
        result_type: Ids.TypeId,
    };
}

pub fn TestingExpectError(comptime Ids: type) type {
    return struct {
        expected_reason: Ids.NodeId,
        actual_result: Ids.NodeId,
        actual_error_variant: Ids.VariantId,
        actual_error_payload_type: Ids.TypeId,
        actual_reason_field_index: u32,
        result_type: Ids.TypeId,
        result_ok_variant: Ids.VariantId,
        test_fail_function: Ids.FunctionId,
        expected_reason_name: ?StringRange,
        diagnostic_line: u32,
        diagnostic_column: u32,
        diagnostic_source_line: StringRange,
    };
}

pub fn ErrorPropagation(comptime Ids: type) type {
    return struct {
        errable_value: Ids.NodeId,
        cleanup_nodes: Range(Ids.NodeId),
        ok_variant: Ids.VariantId,
        ok_value_field_index: ?u32,
        error_variant: Ids.VariantId,
        propagated_errable_type: Ids.TypeId,
        propagated_error_variant: Ids.VariantId,
        ok_payload_type: Ids.TypeId,
        error_payload_type: Ids.TypeId,
        propagated_error_payload_type: Ids.TypeId,
        diagnostic_line: u32,
        diagnostic_column: u32,
        diagnostic_source_line: StringRange,
    };
}

pub fn ErrorContext(comptime Ids: type) type {
    return struct {
        errable_value: Ids.NodeId,
        context: Ids.NodeId,
        cleanup_nodes: Range(Ids.NodeId),
        ok_variant: Ids.VariantId,
        ok_value_field_index: ?u32,
        error_variant: Ids.VariantId,
        propagated_errable_type: Ids.TypeId,
        propagated_error_variant: Ids.VariantId,
        ok_payload_type: Ids.TypeId,
        error_payload_type: Ids.TypeId,
        propagated_error_payload_type: Ids.TypeId,
        diagnostic_line: u32,
        diagnostic_column: u32,
        diagnostic_source_line: StringRange,
    };
}

pub fn Node(comptime Ids: type) type {
    return struct {
        source: SourceRef,
        ty: ?Ids.TypeId,
        content: Content,

        pub const Content = union(enum) {
            declaration: Ids.DeclId,
            binding_declaration: Ids.BindingId,
            binding_use: Ids.BindingId,
            reach_directive: Ids.ReachId,
            move_value: Ids.NodeId,
            assignment: struct { binding: Ids.BindingId, value: Ids.NodeId },
            auto_deinit_binding: Ids.AutoDeinitId,
            function_call: struct {
                callee: Ids.FunctionId,
                input: Ids.NodeId,
                consumes_auto_deinit: ?Ids.NodeId = null,
                initializes_auto_deinit: ?Ids.NodeId = null,
            },
            virtualize: Ids.VirtualizeId,
            virtual_call: Ids.VirtualCallId,
            code_block: Ids.BlockId,
            int_literal: i64,
            float_literal: f64,
            char_literal: u8,
            string_literal: StringRange,
            bool_literal: bool,
            list_literal: struct {
                elements: Range(Ids.NodeId),
                element_types: Range(Ids.TypeId),
            },
            struct_value_literal: struct {
                fields: Range(Ids.ValueFieldId),
                ty: Ids.TypeId,
                dispatch_prefix_positional_count: u32 = 0,
            },
            struct_field_access: struct {
                value: Ids.NodeId,
                field_name: StringRange,
                field_index: u32,
            },
            choice_literal: struct {
                choice_type: Ids.TypeId,
                variant: Ids.VariantId,
                payload: ?Ids.NodeId,
            },
            choice_payload_access: struct {
                value: Ids.NodeId,
                variant: Ids.VariantId,
                payload_type: Ids.TypeId,
            },
            nullable_unwrap_or: Ids.NullableUnwrapId,
            testing_expect_error: Ids.TestingExpectErrorId,
            error_propagation: Ids.ErrorPropagationId,
            error_context: Ids.ErrorContextId,
            array_literal: struct {
                elements: Range(Ids.NodeId),
                element_type: Ids.TypeId,
                length: u32,
            },
            array_index: struct {
                array_ptr: Ids.NodeId,
                index: Ids.NodeId,
                element_type: Ids.TypeId,
                array_type: Ids.TypeId,
            },
            array_store: struct {
                array_ptr: Ids.NodeId,
                index: Ids.NodeId,
                value: Ids.NodeId,
                element_type: Ids.TypeId,
                array_type: Ids.TypeId,
            },
            struct_field_store: struct {
                struct_ptr: Ids.NodeId,
                struct_type: Ids.TypeId,
                field_index: u32,
                field_type: Ids.TypeId,
                value: Ids.NodeId,
            },
            binary_operation: struct { operator: BinaryOperator, left: Ids.NodeId, right: Ids.NodeId },
            comparison: struct { operator: ComparisonOperator, left: Ids.NodeId, right: Ids.NodeId },
            logical_operation: struct { operator: LogicalOperator, left: Ids.NodeId, right: Ids.NodeId },
            return_statement: struct { expression: ?Ids.NodeId, cleanup: Range(Ids.NodeId) },
            if_statement: struct {
                condition: Ids.NodeId,
                choice_test: ?ChoiceTagTest(Ids) = null,
                then_block: Ids.BlockId,
                else_block: ?Ids.BlockId,
            },
            while_statement: struct { condition: Ids.NodeId, body: Ids.BlockId },
            for_statement: struct { init: ?Ids.NodeId, condition: Ids.NodeId, increment: ?Ids.NodeId, body: Ids.BlockId },
            switch_statement: Ids.SwitchId,
            break_statement,
            continue_statement,
            address_of: Ids.NodeId,
            dereference: struct {
                pointer: Ids.NodeId,
                ty: Ids.TypeId,
                pointer_type: Ids.TypeId,
            },
            pointer_assignment: struct { pointer: Ids.NodeId, value: Ids.NodeId },
            type_initializer: struct {
                type_decl: Ids.DeclId,
                init_fn: Ids.FunctionId,
                args: Ids.NodeId,
            },
            type_literal: Ids.TypeId,
            explicit_cast: struct { value: Ids.NodeId, target_type: Ids.TypeId },
        };
    };
}

test "semantic primitives instantiate with isolated id namespaces" {
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

    const Ty = SemanticType(Ids);
    const pointer = Ty{ .pointer = .{ .child = @enumFromInt(3), .mutability = .read_only } };
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(pointer.pointer.child));

    const Decl = Declaration(Ids);
    const decl = Decl{
        .kind = .type,
        .name = .{ .start = 0, .len = 1 },
        .source = .{ .file_index = 0, .offset = 0 },
        .struct_layout = .c_union,
    };
    try std.testing.expectEqual(StructLayout.c_union, decl.struct_layout);

    const SemanticNode = Node(Ids);
    const node = SemanticNode{
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = null,
        .content = .{ .int_literal = 42 },
    };
    try std.testing.expectEqual(@as(i64, 42), node.content.int_literal);
}

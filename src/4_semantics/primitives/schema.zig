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
    Bool,
    Void,
    Type,
    Any,
};

pub const IntegerRange = struct { minimum: i128, maximum: i128 };

/// Conversion contracts depend on the compilation target, including native
/// integers and C aliases already resolved to their underlying builtin.
pub fn integerRange(kind: BuiltinType, target: std.Target) ?IntegerRange {
    const bits: u7 = switch (kind) {
        .Int8, .UInt8 => 8,
        .Int16, .UInt16 => 16,
        .Int32, .UInt32 => 32,
        .Int64, .UInt64 => 64,
        .UIntNative => @intCast(target.ptrBitWidth()),
        else => return null,
    };
    const signed = switch (kind) {
        .Int8, .Int16, .Int32, .Int64 => true,
        else => false,
    };
    return integerRangeForWidth(bits, signed);
}

pub fn integerRangeForWidth(bits: u7, signed: bool) IntegerRange {
    const bound = @as(i128, 1) << (if (signed) bits - 1 else bits);
    return .{ .minimum = if (signed) -bound else 0, .maximum = bound - 1 };
}

test "integer conversion ranges follow signedness and target pointer width" {
    var target = @import("builtin").target;
    target.cpu.arch = .x86_64;
    try std.testing.expectEqualDeep(IntegerRange{ .minimum = -128, .maximum = 127 }, integerRange(.Int8, target).?);
    try std.testing.expectEqualDeep(IntegerRange{ .minimum = 0, .maximum = 255 }, integerRange(.UInt8, target).?);
    try std.testing.expectEqualDeep(IntegerRange{ .minimum = -9223372036854775808, .maximum = 9223372036854775807 }, integerRange(.Int64, target).?);
    try std.testing.expectEqualDeep(IntegerRange{ .minimum = 0, .maximum = 18446744073709551615 }, integerRange(.UIntNative, target).?);
    target.cpu.arch = .x86;
    try std.testing.expectEqualDeep(IntegerRange{ .minimum = 0, .maximum = 4294967295 }, integerRange(.UIntNative, target).?);
    try std.testing.expect(integerRange(.Float32, target) == null);
}

/// Builtin spellings and C aliases share one lookup across module and global
/// semantizing. The explicit target keeps ABI width decisions out of callers.
pub fn builtinTypeNamedForTarget(name: []const u8, target: std.Target) ?BuiltinType {
    inline for (@typeInfo(BuiltinType).@"enum".fields) |field| {
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    }
    const aliases = .{
        .{ "CShort", std.Target.CType.short, true },
        .{ "CUShort", std.Target.CType.ushort, false },
        .{ "CInt", std.Target.CType.int, true },
        .{ "CUInt", std.Target.CType.uint, false },
        .{ "CLong", std.Target.CType.long, true },
        .{ "CULong", std.Target.CType.ulong, false },
        .{ "CLongLong", std.Target.CType.longlong, true },
        .{ "CULongLong", std.Target.CType.ulonglong, false },
    };
    inline for (aliases) |alias| {
        if (std.mem.eql(u8, name, alias[0])) return cIntegerType(target.cTypeBitSize(alias[1]), alias[2]);
    }
    if (std.mem.eql(u8, name, "CChar")) return cIntegerType(8, target.cCharSignedness() == .signed);
    if (std.mem.eql(u8, name, "CSignedChar")) return .Int8;
    if (std.mem.eql(u8, name, "CUnsignedChar")) return .UInt8;
    if (std.mem.eql(u8, name, "CSize")) return .UIntNative;
    if (std.mem.eql(u8, name, "CPtrDiff")) return cIntegerType(target.ptrBitWidth(), true);
    if (std.mem.eql(u8, name, "CFloat")) return if (target.cTypeBitSize(.float) == 32) .Float32 else null;
    if (std.mem.eql(u8, name, "CDouble")) return if (target.cTypeBitSize(.double) == 64) .Float64 else null;
    if (std.mem.eql(u8, name, "CBool")) return .Bool;
    return null;
}

fn cIntegerType(bits: u16, signed: bool) ?BuiltinType {
    return switch (bits) {
        8 => if (signed) .Int8 else .UInt8,
        16 => if (signed) .Int16 else .UInt16,
        32 => if (signed) .Int32 else .UInt32,
        64 => if (signed) .Int64 else .UInt64,
        else => null,
    };
}

test "C scalar aliases follow the target data model" {
    var target = @import("builtin").target;
    target.cpu.arch = .x86_64;
    target.os.tag = .linux;
    target.abi = .gnu;
    try std.testing.expectEqual(BuiltinType.Int64, builtinTypeNamedForTarget("CLong", target).?);
    target.os.tag = .windows;
    target.abi = .msvc;
    try std.testing.expectEqual(BuiltinType.Int32, builtinTypeNamedForTarget("CLong", target).?);
    try std.testing.expectEqual(BuiltinType.Int64, builtinTypeNamedForTarget("CPtrDiff", target).?);
    target.cpu.arch = .aarch64;
    target.os.tag = .linux;
    target.abi = .gnu;
    try std.testing.expectEqual(BuiltinType.UInt8, builtinTypeNamedForTarget("CChar", target).?);
    target.os.tag = .macos;
    try std.testing.expectEqual(BuiltinType.Int8, builtinTypeNamedForTarget("CChar", target).?);
    try std.testing.expect(builtinTypeNamedForTarget("CLongDouble", target) == null);
}

pub const PointerMutability = enum(u8) { read_only, read_write };
pub const Mutability = enum(u8) { constant, variable };
pub const ForMode = enum(u8) { value, borrow, mut_borrow, move };
pub const MatchCaseMode = enum(u8) { value, borrow, mut_borrow, move };
pub const BinaryOperator = enum(u8) { addition, subtraction, multiplication, division, modulo };
pub const ComparisonOperator = enum(u8) { equal, not_equal, less_than, greater_than, less_than_or_equal, greater_than_or_equal };

pub const DeclarationKind = enum {
    binding,
    import_alias,
    contract_type,
    type,
    choice_option,
    function,
    test_function,
};

pub const SafetyPrimitive = enum {
    none,
    establish_inherited_reference,
    establish_inherited_storage,
    establish_allocation,
    native_allocated_storage,
    acquisition_subaddress,
    establish_allocation_slot,
    raw_allocated_storage,
    reference_offset,
    mutable_reference_offset,
    reinterpret_reference,
    mutable_reinterpret_reference,
    read_reference,
    restrict_reference,
    depend_on,
    trusted_opaque_move,
    trusted_opaque_move_in,
    trusted_opaque_move_out,
    trusted_opaque_relocate,
    trusted_opaque_drop,
    trusted_opaque_mark_empty,
    relocate,
    float_math,
};

pub const FunctionFlags = packed struct(u16) {
    is_once: bool = false,
    is_test: bool = false,
    has_declared_body: bool = false,
    uses_inferred_error_reasons: bool = false,
    is_deinit: bool = false,
    is_generic_instantiation: bool = false,
    is_entry: bool = false,
    is_c_abi: bool = false,
    is_c_export: bool = false,
    has_foreign_capability: bool = false,
    is_c_function_pointer: bool = false,
    _padding: u5 = 0,
};

pub const StructLayout = enum(u8) { regular, c_union, c_struct, c_incomplete, c_function_pointer };
pub const ChoiceLayout = enum(u8) { regular, c_enum };
pub const InferredChoiceKind = enum(u8) { errable, reasons };
pub const LogicalOperator = enum(u8) { and_, or_ };

pub const SourceRef = struct {
    file_index: u32,
    offset: u32,
};

/// Syntax-free method contract coordinates survive associated specialization.
/// Source provenance is relocated together with the defining module.
pub const MethodSafetyContract = struct {
    /// General selectors may combine entry inputs and distinct returned values.
    general_conditions: bool = false,
    output_count: u32,
    dependencies: []const Dependency = &.{},
    referents: []const Dependency = &.{},
    consumed_inputs: []const u32 = &.{},
    relocations: []const Relocation = &.{},
    invalidates: []const u32 = &.{},
    domain_dependencies: []const DomainDependency = &.{},
    invalidated_domains: []const DomainInput = &.{},
    owned_outputs: []const u32 = &.{},
    transfers: []const Dependency = &.{},
    retained_inputs: []const Retention = &.{},
    emptied_inputs: []const StorageInput = &.{},
    storage_sources: []const StorageDependency = &.{},
    outcomes: []const Outcome = &.{},
    source: SourceRef,

    pub const Relocation = struct { destination: u32, source: u32 };
    pub const StorageInput = struct { input_index: u32, domain_index: ?u32 = null };
    pub const Retention = struct { storage: StorageInput, input: u32 };
    pub const StorageDependency = struct { output_index: u32, storage: StorageInput };
    pub const Dependency = struct { output_index: u32, input_index: u32 };
    pub const DomainInput = struct { input_index: u32, domain_index: u32 };
    pub const DomainDependency = struct { output_index: u32, input: DomainInput };
    pub const Outcome = struct {
        input_index: ?u32 = null,
        input_dereference: bool = false,
        output_index: u32 = 0,
        /// Resolved ancestor tags for this selector, independent of other terms.
        parent_variants: []const u32 = &.{},
        variant: StringRange,
        variant_index: ?u32 = null,
        dependencies: []const Dependency = &.{},
        domain_dependencies: []const DomainDependency = &.{},
        owned_outputs: []const u32 = &.{},
        storage_sources: []const StorageDependency = &.{},
        emptied_inputs: []const StorageInput = &.{},
        consumed_inputs: []const u32 = &.{},
        relocations: []const Relocation = &.{},
        invalidates: []const u32 = &.{},
        invalidated_domains: []const DomainInput = &.{},
        /// Repeated selectors follow their payload; other selectors conjoin.
        outcomes: []const Outcome = &.{},
        source: SourceRef,
    };
};

pub const StorageDomainMapping = struct {
    domain_index: u32,
    paths: []const Path,
    pub const Path = struct { fields: []const u32 };
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
        /// Runtime pair (data pointer, vtable pointer) carrying contract evidence.
        /// The contract type identity is explicit because `Virtual` is an
        /// intrinsic type constructor, not a source declaration.
        virtual: Ids.TypeId,
    };
}

pub fn Field(comptime Ids: type) type {
    return struct {
        name: StringRange,
        ty: Ids.TypeId,
        source: SourceRef,
        default_value: ?Ids.NodeId = null,
    };
}

pub fn ChoiceVariant(comptime Ids: type) type {
    return struct {
        name: StringRange,
        qualifier: ?StringRange = null,
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
        foreign_symbol: ?StringRange = null,
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
        /// The initializer supplies the inferred type; evaluation happens at
        /// ordered expression effects that initialize this temporary.
        deferred_initialization: bool = false,
        reinitialize_cleanup: ?Ids.NodeId = null,
        /// Lexical argument candidates captured where this local is declared,
        /// for resolving the same dependencies in its implicit destructor.
        cleanup_arguments: ?Ids.NodeId = null,
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
        // Pattern bindings retain their transfer mode after match lowering so
        // safety inference can follow ownership into the selected payload.
        payload_binding: ?Ids.BindingId = null,
        payload_mode: MatchCaseMode = .value,
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
        /// A choice payload uses a variant index and requires its active tag.
        is_variant: bool = false,
        deinit_fn: ?Ids.FunctionId,
        input: ?Ids.NodeId = null,
        self_field_index: u32 = 0,
        fields: Range(Ids.AutoDeinitFieldId) = .{ .start = 0, .len = 0 },
    };
}

pub fn AutoDeinit(comptime Ids: type) type {
    return struct {
        binding: Ids.BindingId,
        /// Optional subplace of the owning binding, evaluated without reading it.
        target: ?Ids.NodeId = null,
        deinit_fn: ?Ids.FunctionId,
        input: ?Ids.NodeId = null,
        self_field_index: u32 = 0,
        fields: Range(Ids.AutoDeinitFieldId) = .{ .start = 0, .len = 0 },
    };
}

pub fn VirtualMethodRegistry(comptime Ids: type) type {
    return struct {
        implementations: Range(Ids.FunctionId),
        /// Receiver position comes from the erased contract. A known
        /// argument may have the same concrete type as the participant after substitution.
        receiver_input_index: u32,
        safety_contract: ?MethodSafetyContract = null,
        /// Scalar outputs and declared input referents need no concrete receiver
        /// layout. Their call summaries are generated without concrete bodies.
        contract_input_count: ?u32 = null,
        contract_output_type: ?Ids.TypeId = null,
    };
}

pub fn Virtualize(comptime Ids: type) type {
    return struct {
        value: Ids.NodeId,
        concrete_type: Ids.TypeId,
        // Unreached construction in executable mode retains no proof obligation.
        safety_required: bool = true,
        contract_decl: Ids.DeclId,
        virtual_type: Ids.TypeId,
        methods: Range(Ids.FunctionId),
        safety_methods: Range(Ids.VirtualRegistryId),
        source: SourceRef,
        domains: []const StorageDomainMapping = &.{},
    };
}

/// A returned choice selects whether the caller still owns cleanup of a place.
/// Parent variants guard nested payload tags before their values are inspected.
pub fn OutcomeCleanup(comptime Ids: type) type {
    return struct {
        place: Ids.NodeId,
        output_index: u32,
        parent_variants: []const u32 = &.{},
        variant_index: u32,
        enabled: bool = false,
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
        /// Safety records every consumed caller place, including aliases and
        /// multiple resource inputs. These nodes identify cleanup flags only.
        consumed_auto_deinits: []const Ids.NodeId = &.{},
        /// Returning calls enable these destination cleanup flags.
        initialized_auto_deinits: []const Ids.NodeId = &.{},
        outcome_cleanups: []const OutcomeCleanup(Ids) = &.{},
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
        test_fail_input: ?Ids.NodeId = null,
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

pub const ContractOperationIdentity = struct {
    conformance: u32 = std.math.maxInt(u32),
    index: u32 = 0,
};

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
            denied_implicit_copy: Ids.NodeId,
            assignment: struct { binding: Ids.BindingId, value: Ids.NodeId },
            auto_deinit_binding: Ids.AutoDeinitId,
            function_address: Ids.FunctionId,
            function_call: struct {
                // A sentinel conformance denotes an ordinary call. Avoid an
                // optional tag: its padding enlarges every semantic node.
                // Frontend calls retain symbolic evidence in pending IR.
                contract_operation: ContractOperationIdentity = .{},
                callee: Ids.FunctionId,
                // For indirect C calls, callee identifies signature metadata;
                // the runtime address is evaluated separately from arguments.
                callee_value: ?Ids.NodeId = null,
                input: Ids.NodeId,
                consumes_auto_deinit: ?Ids.NodeId = null,
                /// Safety records every consumed caller place, including aliases and
                /// multiple resource inputs. These nodes identify cleanup flags only.
                consumed_auto_deinits: []const Ids.NodeId = &.{},
                /// Returning calls enable these destination cleanup flags.
                initialized_auto_deinits: []const Ids.NodeId = &.{},
                outcome_cleanups: []const OutcomeCleanup(Ids) = &.{},
                initializes_auto_deinit: ?Ids.NodeId = null,
            },
            virtualize: Ids.VirtualizeId,
            virtual_call: Ids.VirtualCallId,
            code_block: Ids.BlockId,
            // Compiler-generated ordered expressions have an explicit result,
            // unlike source blocks. Their storage belongs to the outer scope.
            value_sequence: Ids.BlockId,
            int_literal: i128,
            float_literal: f64,
            char_literal: u32,
            // Global-only recipe, expanded independently for each omitted input.
            argument_default: u32,
            string_literal: StringRange,
            bool_literal: bool,
            list_literal: struct {
                elements: Range(Ids.NodeId),
            },
            struct_value_literal: struct {
                fields: Range(Ids.ValueFieldId),
                dispatch_prefix_positional_count: u32 = 0,
                // Lexical candidates for omitted call arguments. Resolution
                // selects only names present in the callee's input and erases
                // this pool before safety and codegen see the call.
                assumed_fields: Range(Ids.ValueFieldId) = .{ .start = 0, .len = 0 },
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
                // Proven lexical destination; metadata, never evaluated.
                cleanup_target: ?Ids.NodeId = null,
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
            abort_statement,
            address_of: Ids.NodeId,
            dereference: struct {
                pointer: Ids.NodeId,
                ty: Ids.TypeId,
                pointer_type: Ids.TypeId,
            },
            pointer_assignment: struct { pointer: Ids.NodeId, value: Ids.NodeId, cleanup_target: ?Ids.NodeId = null },
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
    try std.testing.expectEqual(@as(i128, 42), node.content.int_literal);
}

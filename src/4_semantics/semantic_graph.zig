const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");

pub const SemanticGraph = struct {
    allocator: *const std.mem.Allocator,
    main_scope: *const Scope,
};

pub const Scope = struct {
    parent: ?*Scope,
    nodes: []const *SGNode,
    type_declarations: []const *TypeDeclaration,
    function_declarations: []const *FunctionDeclaration,
    binding_declarations: []const *BindingDeclaration,
};

pub const SGNode = struct {
    location: tok.Location,
    sem_type: ?Type = null,
    content: Content,
};

pub inline fn makeSGNode(content: Content, location: tok.Location, allocator: *const std.mem.Allocator) !*SGNode {
    const node = try allocator.create(SGNode);
    node.* = SGNode{
        .location = location,
        .sem_type = null,
        .content = content,
    };
    return node;
}

pub const Content = union(enum) {
    choice_option_declaration: *ChoiceOptionDeclaration,
    type_declaration: *TypeDeclaration,
    function_declaration: *FunctionDeclaration,
    test_declaration: *TestDeclaration,

    binding_declaration: *BindingDeclaration,
    binding_use: *BindingDeclaration,
    reach_directive: *const ReachDirective,
    move_value: *const SGNode,
    binding_assignment: *Assignment,
    auto_deinit_binding: *AutoDeinitBinding,

    function_call: *FunctionCall,
    virtualize: *const Virtualize,
    virtual_call: *const VirtualCall,
    code_block: *CodeBlock,
    value_literal: ValueLiteral,
    choice_literal: *const ChoiceLiteral,
    list_literal: *const ListLiteral,
    struct_value_literal: *const StructValueLiteral,
    struct_field_access: *const StructFieldAccess,
    choice_payload_access: *const ChoicePayloadAccess,
    nullable_unwrap_or: *const NullableUnwrapOr,
    testing_expect_error: *const TestingExpectError,
    error_propagation: *const ErrorPropagation,
    error_context: *const ErrorContext,
    array_literal: *const ArrayLiteral,
    array_index: ArrayIndex,
    array_store: ArrayStore,
    struct_field_store: StructFieldStore,
    binary_operation: BinaryOperation,
    comparison: Comparison,
    logical_operation: LogicalOperation,
    return_statement: *ReturnStatement,
    if_statement: *IfStatement,

    while_statement: *WhileStatement,
    for_statement: *ForStatement,
    switch_statement: *SwitchStatement,
    break_statement: struct {},
    continue_statement: struct {},

    address_of: *const SGNode,
    dereference: Dereference,
    pointer_assignment: PointerAssignment,
    type_initializer: TypeInitializer,
    type_literal: *const TypeLiteral,
    explicit_cast: ExplicitCast,
};

//
// Types

pub const Type = union(enum) {
    builtin: BuiltinType,
    abstract_type: *const AbstractType,
    choice_type: *const ChoiceType,
    struct_type: *const StructType,
    pointer_type: *const PointerType,
    array_type: *const ArrayType,
};

pub const AbstractType = struct {
    name: []const u8,
};

pub const ChoiceType = struct {
    variants: []const ChoiceVariant,
    identity: ?TypeIdentity = null,
    layout: Layout = .regular,

    pub const Layout = enum {
        regular,
        c_enum,
    };
};

pub const InferredChoiceKind = enum {
    errable,
    reasons,
};

pub const InferredChoiceIdentity = struct {
    id: u32,
    kind: InferredChoiceKind,
};

pub const ChoiceOptionDeclaration = struct {
    name: []const u8,
    origin_file: []const u8,
    id: u32,
};

pub const ChoiceVariant = struct {
    name: []const u8,
    value: i32,
    payload_type: ?Type = null,
    option_decl: ?*const ChoiceOptionDeclaration = null,
};

pub const ChoiceLiteral = struct {
    variant_name: []const u8,
    module_qualifier: ?[]const u8 = null,
    choice_type: *const ChoiceType,
    variant_index: u32,
    payload: ?*const SGNode,
};

pub const ChoicePayloadAccess = struct {
    choice_value: *const SGNode,
    variant_index: u32,
    payload_type: Type,
};

pub const NullableUnwrapOr = struct {
    nullable_value: *const SGNode,
    fallback_value: *const SGNode,
    some_variant_index: u32,
    some_value_field_index: u32,
    result_type: Type,
};

pub const TestingExpectError = struct {
    expected_reason: *const SGNode,
    actual_result: *const SGNode,
    actual_error_variant_index: u32,
    actual_error_payload_type: Type,
    actual_reason_field_index: u32,
    result_type: Type,
    result_ok_variant_index: u32,
    test_fail_function: *const FunctionDeclaration,
    expected_reason_name: ?[]const u8,
    line: u32,
    column: u32,
    source_file: []const u8,
    source_line: []const u8,
};

pub const PointerType = struct {
    mutability: syn.PointerMutability,
    child: *const Type,
};

pub const ArrayType = struct {
    length: usize,
    element_type: *const Type,
    identity: ?TypeIdentity = null,
};

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

pub const StructType = struct {
    fields: []const StructTypeField,
    identity: ?TypeIdentity = null,
    layout: Layout = .regular,

    pub const Layout = enum {
        regular,
        c_union,
    };
};

pub const TypeIdentity = union(enum) {
    generic: *const GenericTypeIdentity,
    inferred_choice: *const InferredChoiceIdentity,
};

pub const GenericTypeIdentity = struct {
    base_name: []const u8,
    arg_names: []const []const u8,
    arg_values: []const GenericIdentityArg,
};

pub const GenericIdentityArg = union(enum) {
    type: Type,
    comptime_int: i64,
};

pub const StructTypeField = struct {
    name: []const u8,
    ty: Type,
    // When an abstract-typed field always stores the same concrete implementer,
    // semantizing records that backing type here so field access and codegen can
    // stay fully static.
    storage_type: ?Type = null,
    default_value: ?*SGNode = null,
};

//
// Value Literals

pub const ValueLiteral = union(enum) {
    int_literal: i64,
    float_literal: f64,
    char_literal: u8,
    string_literal: []const u8,
    bool_literal: bool,
};

pub const ListLiteral = struct {
    elements: []const *const SGNode,
    element_types: []const Type,
};

pub const ArrayLiteral = struct {
    elements: []const *const SGNode,
    element_type: Type,
    length: usize,
};

pub const ArrayIndex = struct {
    array_ptr: *const SGNode,
    index: *const SGNode,
    element_type: Type,
    array_type: *const ArrayType,
};

pub const ArrayStore = struct {
    array_ptr: *const SGNode,
    index: *const SGNode,
    value: *const SGNode,
    element_type: Type,
    array_type: *const ArrayType,
};

pub const TypeLiteral = struct {
    ty: Type,
};

pub const ExplicitCast = struct {
    value: *const SGNode,
    target_type: Type,
};

pub const StructValueLiteral = struct {
    fields: []const StructValueLiteralField,
    ty: Type,
    dispatch_prefix_positional_count: u32 = 0,
};

pub const StructValueLiteralField = struct {
    name: []const u8,
    value: *const SGNode,
};

pub const StructFieldAccess = struct {
    struct_value: *const SGNode,
    field_name: []const u8,
    field_index: u32,
};

pub const StructFieldStore = struct {
    struct_ptr: *const SGNode,
    struct_type: *const StructType,
    field_index: u32,
    field_type: Type,
    value: *const SGNode,
};

pub const ErrorPropagation = struct {
    errable_value: *const SGNode,
    cleanup_nodes: []const *SGNode,
    ok_variant_index: u32,
    ok_value_field_index: ?u32,
    error_variant_index: u32,
    propagated_errable_type: Type,
    propagated_error_variant_index: u32,
    ok_payload_type: Type,
    error_payload_type: Type,
    propagated_error_payload_type: Type,
    line: u32,
    column: u32,
    source_file: []const u8,
    source_line: []const u8,
};

pub const ErrorContext = struct {
    errable_value: *const SGNode,
    context: *const SGNode,
    cleanup_nodes: []const *SGNode,
    ok_variant_index: u32,
    ok_value_field_index: ?u32,
    error_variant_index: u32,
    propagated_errable_type: Type,
    propagated_error_variant_index: u32,
    ok_payload_type: Type,
    error_payload_type: Type,
    propagated_error_payload_type: Type,
    line: u32,
    column: u32,
    source_file: []const u8,
    source_line: []const u8,
};

//
// Declarations

pub const TypeDeclaration = struct {
    name: []const u8,
    origin_file: []const u8,
    ty: Type,
};

pub const FunctionDeclaration = struct {
    // Stable semantic identity for this concrete declaration.
    //
    // Generic instantiations can erase key information from their callable
    // input/output shape (for example DynamicArray helpers whose `self` layout
    // is the same across element types). Codegen therefore cannot rely on the
    // structural signature alone to produce unique internal symbols.
    id: u32,
    name: []const u8,
    location: tok.Location,
    origin_kind: OriginKind = .declared,
    // Generic instantiations from abstract-contract templates must stay
    // distinct from regular generic instantiations even when they collapse to
    // the same concrete callable shape. Call resolution and reuse of existing
    // monomorphizations need that distinction to rank abstract-driven dispatch
    // correctly against broader regular generics.
    generic_dispatch_kind: ?GenericDispatchKind = null,
    is_once: bool,
    is_test: bool = false,
    input: StructType, // Arguments
    output: StructType, // Named return params
    body: ?*const CodeBlock,
    uses_inferred_error_reasons: bool = false,
    input_bindings: []const *const BindingDeclaration = &.{},
    output_bindings: []const *const BindingDeclaration = &.{},
    temporal_contract: TemporalContract = .{},
    temporal_summary: ?*const TemporalSummary = null,
    inferred_error_reasons: ?*const ChoiceType = null,

    pub fn isExtern(self: *const FunctionDeclaration) bool {
        return self.body == null;
    }

    pub const OriginKind = enum {
        declared,
        generic_instantiation,
    };

    pub const GenericDispatchKind = enum {
        regular,
        abstract_contract,
    };
};

pub const TemporalContract = struct {
    invalidates_inputs: []const u32 = &.{},
    invalidates_dependencies: []const InvalidationFootprint = &.{},
    return_dependencies: []const ReturnDependency = &.{},
    dependency_transitions: []const DependencyTransition = &.{},
    return_root: ?ReturnRoot = null,
    trusted_transitions: bool = false,
    raw_boundary: bool = false,

    pub const ReturnRoot = struct {
        output_index: u32,
        source: Source,

        pub const Source = union(enum) {
            fresh,
            follows_input: u32,
        };
    };
};

/// Compiler-internal temporal contract inferred from a concrete function body.
/// Paths use semantic field/index projections and deliberately do not appear in
/// source-level function types.
pub const TemporalSummary = struct {
    is_widened: bool = false,
    return_dependencies: []const ReturnDependency = &.{},
    dependency_transitions: []const DependencyTransition = &.{},
    invalidations: []const InvalidationFootprint = &.{},
    return_roots: []const ReturnStorageRoot = &.{},
    address_dependent_outputs: []const AddressDependentOutput = &.{},
};

pub const AddressDependentOutput = struct {
    output_index: u32,
    value_path: []const TemporalProjection,
    target_path: []const TemporalProjection,
};

pub const DependencyTransition = struct {
    target_input_index: u32,
    target_path: []const TemporalProjection,
    source: Source,

    pub const Source = union(enum) {
        fresh,
        input: struct {
            index: u32,
            value_path: []const TemporalProjection = &.{},
            path: []const TemporalProjection,
        },
    };
};

pub const TemporalProjection = union(enum) {
    field: u32,
    choice_payload: u32,
    array_index: ?i64,
    dereference,
};

pub const ReturnDependency = struct {
    output_path: []const TemporalProjection,
    input_index: u32,
    input_value_path: []const TemporalProjection = &.{},
    input_path: []const TemporalProjection,
};

pub const InvalidationFootprint = struct {
    input_index: u32,
    input_value_path: []const TemporalProjection = &.{},
    input_path: []const TemporalProjection,
};

pub const ReturnStorageRoot = struct {
    output_path: []const TemporalProjection,
    source: Source,

    pub const Source = union(enum) {
        fresh,
        input: struct {
            index: u32,
            path: []const TemporalProjection,
        },
    };
};

pub const TestDeclaration = struct {
    name: []const u8,
    location: tok.Location,
    function: *const FunctionDeclaration,
};

pub const BindingDeclaration = struct {
    name: []const u8,
    location: tok.Location,
    origin_file: []const u8,
    mutability: syn.Mutability,
    ty: Type,
    initialization: ?*const SGNode,
};

pub const CodeBlock = struct {
    nodes: []const *SGNode,
    ret_val: ?*SGNode,
};

//
// Asigments

pub const Assignment = struct {
    sym_id: *const BindingDeclaration,
    value: *const SGNode,
};

pub const AutoDeinitBinding = struct {
    binding: *const BindingDeclaration,
    deinit_fn: ?*const FunctionDeclaration,
    input: ?*const SGNode = null,
    fields: []const AutoDeinitField = &.{},
};

pub const AutoDeinitField = struct {
    field_index: u32,
    deinit_fn: ?*const FunctionDeclaration,
    input: ?*const SGNode = null,
    self_field_index: u32 = 0,
    fields: []const AutoDeinitField = &.{},
};

//
// Function Calls

pub const FunctionCall = struct {
    callee: *const FunctionDeclaration,
    input: *const SGNode, // Arguments
};

pub const Virtualize = struct {
    value: *const SGNode,
    concrete_type: Type,
    abstract_type: *const AbstractType,
    virtual_type: *const StructType,
    methods: []const *const FunctionDeclaration,
};

pub const VirtualCall = struct {
    handle: *const SGNode,
    input: *const SGNode,
    self_input_index: u32,
    method_index: u32,
    method_count: u32,
    method_name: []const u8,
    input_type: *const StructType,
    output_type: *const StructType,
    self_permission: syn.PointerMutability,
};

pub const ReachDirective = struct {
    alternatives: []const ReachAlternative,
};

pub const ReachAlternative = struct {
    segments: []const []const u8,
};

//
// Operators

pub const BinaryOperation = struct {
    operator: tok.BinaryOperator,
    left: *const SGNode,
    right: *const SGNode,
};

pub const Comparison = struct {
    operator: tok.ComparisonOperator,
    left: *const SGNode,
    right: *const SGNode,
};

pub const LogicalOperator = syn.LogicalOperator;

pub const LogicalOperation = struct {
    operator: LogicalOperator,
    left: *const SGNode,
    right: *const SGNode,
};

//
//Control Flow Statements

pub const ReturnStatement = struct {
    expression: ?*const SGNode,
    cleanup_nodes: []const *SGNode,
};

pub const IfStatement = struct {
    condition: *const SGNode,
    then_block: *const CodeBlock,
    else_block: ?*const CodeBlock,
};

pub const WhileStatement = struct {
    condition: *const SGNode,
    body: *const CodeBlock,
};

pub const ForStatement = struct {
    init: ?*const SGNode,
    condition: *const SGNode,
    increment: ?*const SGNode,
    body: *const CodeBlock,
};

pub const SwitchStatement = struct {
    expression: *const SGNode,
    cases: []const SwitchCase,
    default_case: ?*const CodeBlock,
};

pub const SwitchCase = struct {
    value: *const SGNode,
    body: *const CodeBlock,
};

//
// Pointers
pub const Dereference = struct {
    pointer: *const SGNode,
    ty: Type,
    pointer_type: *const PointerType,
};

pub const PointerAssignment = struct {
    pointer: *const SGNode, // expresión que produce &T
    value: *const SGNode, // Value to assign
};

pub const TypeInitializer = struct {
    type_decl: *const TypeDeclaration,
    init_fn: *const FunctionDeclaration,
    args: *const SGNode,
};

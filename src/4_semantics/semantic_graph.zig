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
    type_declaration: *TypeDeclaration,
    function_declaration: *FunctionDeclaration,

    binding_declaration: *BindingDeclaration,
    binding_use: *BindingDeclaration,
    reach_directive: *const ReachDirective,
    move_value: *const SGNode,
    binding_assignment: *Assignment,
    auto_deinit_binding: *AutoDeinitBinding,

    function_call: *FunctionCall,
    code_block: *CodeBlock,
    value_literal: ValueLiteral,
    choice_literal: *const ChoiceLiteral,
    list_literal: *const ListLiteral,
    struct_value_literal: *const StructValueLiteral,
    struct_field_access: *const StructFieldAccess,
    choice_payload_access: *const ChoicePayloadAccess,
    array_literal: *const ArrayLiteral,
    array_index: ArrayIndex,
    array_store: ArrayStore,
    struct_field_store: StructFieldStore,
    binary_operation: BinaryOperation,
    comparison: Comparison,
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
};

pub const ChoiceVariant = struct {
    name: []const u8,
    value: i32,
    payload_type: ?Type = null,
};

pub const ChoiceLiteral = struct {
    variant_name: []const u8,
    choice_type: *const ChoiceType,
    variant_index: u32,
    payload: ?*const SGNode,
};

pub const ChoicePayloadAccess = struct {
    choice_value: *const SGNode,
    variant_index: u32,
    payload_type: Type,
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
    Type,
    Any,
};

pub const StructType = struct {
    fields: []const StructTypeField,
    identity: ?TypeIdentity = null,
};

pub const TypeIdentity = union(enum) {
    generic: *const GenericTypeIdentity,
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

//
// Declarations

pub const TypeDeclaration = struct {
    name: []const u8,
    origin_file: []const u8,
    ty: Type,
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    location: tok.Location,
    is_once: bool,
    input: StructType, // Arguments
    output: StructType, // Named return params
    body: ?*const CodeBlock,

    pub fn isExtern(self: *const FunctionDeclaration) bool {
        return self.body == null;
    }
};

pub const BindingDeclaration = struct {
    name: []const u8,
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
    deinit_fn: *const FunctionDeclaration,
};

//
// Function Calls

pub const FunctionCall = struct {
    callee: *const FunctionDeclaration,
    input: *const SGNode, // Arguments
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

//
//Control Flow Statements

pub const ReturnStatement = struct {
    expression: ?*const SGNode,
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

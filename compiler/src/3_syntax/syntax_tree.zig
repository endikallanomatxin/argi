const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("syntax_tree.zig");

// Types used from token.zig

pub const ST = struct {
    nodes: []const *STNode,
};

pub const STNode = struct {
    location: tok.Location,
    content: Content,
};

pub const Name = struct {
    string: []const u8,
    location: tok.Location,
    // Location is used mainly for the lsp
};

pub const Content = union(enum) {
    symbol_declaration: SymbolDeclaration,
    type_declaration: TypeDeclaration,

    // Abstract type features
    abstract_declaration: AbstractDeclaration,
    abstract_canbe: AbstractCanBe,
    abstract_defaultsto: AbstractDefault,
    function_declaration: FunctionDeclaration,
    assignment: Assignment,
    expression_statement: *STNode,
    identifier: []const u8,
    pipe_placeholder: struct {},
    move_expression: *STNode,
    function_call: FunctionCall,
    pipe_expression: PipeExpression,
    code_block: CodeBlock,

    // Literals
    // (Not parsed until the type is known)
    literal: tok.Literal,
    list_literal: ListLiteral,
    struct_type_literal: StructTypeLiteral,
    choice_type_literal: ChoiceTypeLiteral,
    struct_value_literal: StructValueLiteral,
    choice_literal: ChoiceLiteral,

    struct_field_access: StructFieldAccess,
    choice_payload_access: ChoicePayloadAccess,
    index_access: IndexAccess,

    return_statement: ReturnStatement,
    binary_operation: BinaryOperation,
    comparison: Comparison,
    if_statement: IfStatement,
    match_statement: MatchStatement,
    import_statement: ImportStatement,
    defer_statement: *STNode,
    index_assignment: IndexAssignment,
    address_of: AddressOf,
    dereference: *STNode,
    pointer_assignment: PointerAssignment,
};

pub const PointerMutability = enum {
    read_only,
    read_write,
};

pub const Type = union(enum) {
    type_name: Name,
    struct_type_literal: StructTypeLiteral,
    pointer_type: *PointerType,
    generic_type_instantiation: struct {
        base_name: Name,
        args: StructTypeLiteral,
    },
    array_type: *ArrayType,
};

pub const PointerType = struct {
    mutability: PointerMutability,
    child: *Type,
};

pub const ArrayType = struct {
    length: usize,
    element: *Type,
};

pub const AddressOf = struct {
    value: *STNode,
    mutability: PointerMutability,
};

pub const SymbolDeclaration = struct {
    name: Name,
    type: ?Type,
    mutability: Mutability,
    value: ?*STNode,
};

pub const TypeDeclaration = struct {
    name: Name,
    generic_params: []const []const u8,
    value: *STNode,
};

// Abstract type declarations (interface-like)
pub const AbstractDeclaration = struct {
    name: Name,
    generic_params: []const []const u8,
    // Composed abstracts (by name)
    requires_abstracts: []const []const u8,
    // Function requirements
    requires_functions: []const AbstractFunctionRequirement,
};

// "Name canbe Type" implementation relation
pub const AbstractCanBe = struct {
    name: []const u8,
    generic_params: []const []const u8,
    ty: Type,
};

// "Name defaultsto Type" default concrete backing type
pub const AbstractDefault = struct {
    name: Name,
    generic_params: []const []const u8,
    ty: Type,
};

pub const AbstractFunctionRequirement = struct {
    name: Name,
    input: StructTypeLiteral,
    output: StructTypeLiteral,
};

pub const FunctionDeclaration = struct {
    name: Name,
    generic_params: []const []const u8,
    input: StructTypeLiteral, // Arguments
    output: StructTypeLiteral, // Named return params
    body: ?*STNode, // CodeBlock
    // If it has no body, it is an extern function.
};

pub const Assignment = struct {
    name: Name,
    value: *STNode,
};

pub const FunctionCall = struct {
    callee: []const u8,
    callee_loc: tok.Location,
    module_qualifier: ?[]const u8,
    // Optional explicit type arguments on call site (e.g. foo[Int32, &Char])
    type_arguments: ?[]const Type,
    // Alternative syntax: named type arguments via struct-like block: #(.T: Int32)
    type_arguments_struct: ?StructTypeLiteral,
    input: *const STNode, // Arguments
};

pub const PipeExpression = struct {
    left: *STNode,
    right: *STNode,
};

pub const Mutability = enum {
    constant,
    variable,
};

pub const CodeBlock = struct {
    items: []const *STNode,
    // Return args in the future.
};

pub const ListLiteral = struct {
    element_type: ?Type, // Optional explicit type
    elements: []const *STNode,
};

pub const StructTypeLiteral = struct {
    fields: []const StructTypeLiteralField,
};

pub const StructTypeLiteralField = struct {
    name: Name,
    type: ?Type,
    default_value: ?*STNode, // Optional default value for the field
};

pub const StructValueLiteral = struct {
    fields: []const StructValueLiteralField,
};

pub const ChoiceTypeLiteral = struct {
    variants: []const ChoiceTypeLiteralVariant,
};

pub const ChoiceTypeLiteralVariant = struct {
    name: Name,
    is_default: bool,
    payload_type: ?StructTypeLiteral = null,
};

pub const ChoiceLiteral = struct {
    name: Name,
    payload: ?*STNode,
};

pub const StructValueLiteralField = struct {
    name: Name,
    value: *STNode,
};

pub const StructFieldAccess = struct {
    struct_value: *STNode,
    field_name: Name,
};

pub const ChoicePayloadAccess = struct {
    choice_value: *STNode,
    variant_name: Name,
};

pub const IndexAccess = struct {
    value: *STNode,
    index: *STNode,
};

pub const IndexAssignment = struct {
    target: *STNode,
    value: *STNode,
};

pub const BinaryOperation = struct {
    operator: tok.BinaryOperator,
    left: *STNode,
    right: *STNode,
};

pub const Comparison = struct {
    operator: tok.ComparisonOperator,
    left: *STNode,
    right: *STNode,
};

pub const IfStatement = struct {
    condition: *STNode,
    then_block: *STNode,
    else_block: ?*STNode,
};

pub const MatchStatement = struct {
    value: *STNode,
    cases: []const MatchCase,
};

pub const MatchCase = struct {
    variant_name: Name,
    payload_binding: ?Name,
    body: *STNode,
};

pub const ReturnStatement = struct {
    expression: ?*STNode,
};

pub const ImportStatement = struct {
    path: []const u8,
};

pub const PointerAssignment = struct {
    target: *STNode, // Dereference node
    value: *STNode, // Value to assign
};

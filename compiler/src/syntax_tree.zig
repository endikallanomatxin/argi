const std = @import("std");
const tok = @import("token.zig");
const syn = @import("syntax_tree.zig");

// Types used from token.zig

pub const ST = struct {
    nodes: []const *STNode,
};

pub const STNode = struct {
    location: tok.Location,
    content: Content,
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
    identifier: []const u8,
    function_call: FunctionCall,
    code_block: CodeBlock,
    literal: tok.Literal, // literals are not parsed until the type is known.
    struct_type_literal: StructTypeLiteral,
    struct_value_literal: StructValueLiteral,
    struct_field_access: StructFieldAccess,
    return_statement: ReturnStatement,
    binary_operation: BinaryOperation,
    comparison: Comparison,
    if_statement: IfStatement,
    address_of: AddressOf,
    dereference: *STNode,
    pointer_assignment: PointerAssignment,
};

pub const PointerMutability = enum {
    read_only,
    read_write,
};

pub const Type = union(enum) {
    type_name: []const u8,
    struct_type_literal: StructTypeLiteral,
    pointer_type: *PointerType,
    generic_type_instantiation: struct {
        base_name: []const u8,
        args: StructTypeLiteral,
    },
};

pub const PointerType = struct {
    mutability: PointerMutability,
    child: *Type,
};

pub const AddressOf = struct {
    value: *STNode,
    mutability: PointerMutability,
};

pub const SymbolDeclaration = struct {
    name: []const u8,
    type: ?Type,
    mutability: Mutability,
    value: ?*STNode,
};

pub const TypeDeclaration = struct {
    name: []const u8,
    generic_params: []const []const u8,
    value: *STNode, // StructTypeLiteral
};

// Abstract type declarations (interface-like)
pub const AbstractDeclaration = struct {
    name: []const u8,
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
    name: []const u8,
    generic_params: []const []const u8,
    ty: Type,
};

pub const AbstractFunctionRequirement = struct {
    name: []const u8,
    input: StructTypeLiteral,
    output: StructTypeLiteral,
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    // Optional generic parameters: names only (e.g. foo[T, U])
    generic_params: []const []const u8,
    input: StructTypeLiteral, // Arguments
    output: StructTypeLiteral, // Named return params
    body: ?*STNode, // CodeBlock
    // If it has no body, it is an extern function.
};

pub const Assignment = struct {
    name: []const u8,
    value: *STNode,
};

pub const FunctionCall = struct {
    callee: []const u8,
    // Optional explicit type arguments on call site (e.g. foo[Int32, &Char])
    type_arguments: ?[]const Type,
    // Alternative syntax: named type arguments via struct-like block: #(.T: Int32)
    type_arguments_struct: ?StructTypeLiteral,
    input: *const STNode, // Arguments
};

pub const Mutability = enum {
    constant,
    variable,
};

pub const CodeBlock = struct {
    items: []const *STNode,
    // Return args in the future.
};

pub const StructTypeLiteral = struct {
    fields: []const StructTypeLiteralField,
};

pub const StructTypeLiteralField = struct {
    name: []const u8,
    type: ?Type,
    default_value: ?*STNode, // Optional default value for the field
};

pub const StructValueLiteral = struct {
    fields: []const StructValueLiteralField,
};

pub const StructValueLiteralField = struct {
    name: []const u8,
    value: *STNode,
};

pub const StructFieldAccess = struct {
    struct_value: *STNode,
    field_name: []const u8,
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

pub const ReturnStatement = struct {
    expression: ?*STNode,
};

pub const PointerAssignment = struct {
    target: *STNode, // Dereference node
    value: *STNode, // Value to assign
};

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
    if_statement: IfStatement,
};

pub const Type = union(enum) {
    type_name: []const u8,
    struct_type_literal: StructTypeLiteral,
};

pub const SymbolDeclaration = struct {
    name: []const u8,
    type: ?Type,
    mutability: Mutability,
    value: ?*STNode,
};

pub const TypeDeclaration = struct {
    name: []const u8,
    value: *STNode, // StructTypeLiteral
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    input: StructTypeLiteral, // Arguments
    output: StructTypeLiteral, // Named return params
    body: *STNode, // CodeBlock
};

pub const Assignment = struct {
    name: []const u8,
    value: *STNode,
};

pub const FunctionCall = struct {
    callee: []const u8,
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

pub const IfStatement = struct {
    condition: *STNode,
    then_block: *STNode,
    else_block: ?*STNode,
};

pub const ReturnStatement = struct {
    expression: ?*STNode,
};

const std = @import("std");
const tok = @import("token.zig");
const syn = @import("syntax_tree.zig");

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

pub const SGNode = union(enum) {
    type_declaration: *TypeDeclaration,
    function_declaration: *FunctionDeclaration,

    binding_declaration: *BindingDeclaration,
    binding_use: *BindingDeclaration,
    binding_assignment: *Assignment,

    function_call: *FunctionCall,
    code_block: *CodeBlock,
    value_literal: ValueLiteral,
    struct_value_literal: *const StructValueLiteral,
    struct_field_access: *const StructFieldAccess,
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
    dereference: *const Dereference,
};

//
// Types

pub const Type = union(enum) {
    builtin: BuiltinType,
    struct_type: *const StructType,
    pointer_type: *const Type,
};

pub const BuiltinType = enum {
    Int8,
    Int16,
    Int32,
    Int64,
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
};

pub const StructType = struct {
    fields: []const StructTypeField,
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
};

pub const StructValueLiteral = struct {
    fields: []const StructValueLiteralField,
    ty: Type,
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

//
// Declarations

pub const TypeDeclaration = struct {
    name: []const u8,
    ty: Type,
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    input: StructType, // Arguments
    output: StructType, // Named return params
    body: ?*const CodeBlock,
};

pub const BindingDeclaration = struct {
    name: []const u8,
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

//
// Function Calls

pub const FunctionCall = struct {
    callee: *const FunctionDeclaration,
    input: *const SGNode, // Arguments
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
};

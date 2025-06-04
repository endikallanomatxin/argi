const std = @import("std");
const tok = @import("token.zig");
const syn = @import("syntax_tree.zig");

pub const SemanticGraph = struct {
    allocator: *const std.mem.Allocator,
    mainScope: *const Scope,
};

pub const Scope = struct {
    parent: ?*Scope,
    nodes: std.ArrayList(SGNode), // index == NodeId

    // These lists point to specific nodes in the `nodes` array.
    type_declarations: std.ArrayList(*TypeDeclaration), // index == TypeId
    function_declarations: std.ArrayList(*FunctionDeclaration), // index == FuncId
    binding_declarations: std.ArrayList(*BindingDeclaration), // index == SymId
};

pub const SGNode = union(enum) {
    type_declaration: *TypeDeclaration,
    function_declaration: *FunctionDeclaration,
    binding_declaration: *BindingDeclaration,

    binding_assignment: *Assignment,
    function_call: *FunctionCall,
    code_block: *CodeBlock,
    value_literal: ValueLiteral,
    binary_operation: BinaryOperation,
    return_statement: *ReturnStatement,
    if_statement: *IfStatement,
    while_statement: *WhileStatement,
    for_statement: *ForStatement,
    switch_statement: *SwitchStatement,
    break_statement: struct {},
    continue_statement: struct {},
};

pub const Type = union(enum) {
    builtin: BuiltinType, // tipos primitivos
    custom: *const TypeDeclaration, // tipos definidos por el usuario (structs, enums, etc.)
};

pub const TypeDeclaration = struct {
    name: []const u8,
    ty: Type, // enum, struct, union, etc.
    args: std.ArrayList(*BindingDeclaration), // index == TypeId
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    params: std.ArrayList(*BindingDeclaration), // index == ParamId
    return_type: ?Type, // null si no hay retorno
    body: *const CodeBlock,
};

pub const BindingDeclaration = struct {
    name: []const u8,
    mutability: syn.Mutability,
    ty: Type,
};

pub const Assignment = struct {
    sym_id: *const BindingDeclaration, // variable a la que asignamos
    value: *const SGNode,
};

pub const FunctionCall = struct {
    callee: *const FunctionDeclaration, // función llamada
    args: []const SGNode, // argumentos pasados
};

pub const CodeBlock = struct {
    nodes: std.ArrayList(*SGNode), // nodos del bloque, index == NodeId
    ret_val: ?*SGNode, // valor de retorno (si aplica)
};

pub const BuiltinType = enum {
    Int8,
    Int16,
    Int32,
    Int64,
    Float8,
    Float16,
    Float32,
    Float64,
    Char,
    Bool,
    String,
    Array,
    Struct,
    Enum,
    Union,
    Pointer,
    Function,
    Void, // tipo vacío, usado para funciones sin retorno
};

pub const ValueLiteral = union(enum) {
    int_literal: i64,
    float_literal: f64,
    char_literal: u8,
    string_literal: []const u8,
};

pub const BinaryOperation = struct {
    operator: tok.BinaryOperator,
    left: *const SGNode, // izquierdo
    right: *const SGNode, // derecho
};

pub const ReturnStatement = struct {
    expression: ?*const SGNode, // expresión a retornar (null si no hay)
};

pub const IfStatement = struct {
    condition: *const SGNode, // condición del if
    then_block: *const CodeBlock, // bloque si la condición es verdadera
    else_block: ?*const CodeBlock, // bloque si la condición es falsa (null si no hay)
};

pub const WhileStatement = struct {
    condition: *const SGNode, // condición del while
    body: *const CodeBlock, // bloque del cuerpo del while
};

pub const ForStatement = struct {
    init: ?*const SGNode, // inicialización (null si no hay)
    condition: *const SGNode, // condición del for
    increment: ?*const SGNode, // incremento (null si no hay)
    body: *const CodeBlock, // bloque del cuerpo del for
};

pub const SwitchStatement = struct {
    expression: *const SGNode, // expresión a evaluar
    cases: std.ArrayList(SwitchCase), // casos del switch
    default_case: ?*const CodeBlock, // bloque por defecto (null si no hay)
};

pub const SwitchCase = struct {
    value: *const SGNode, // valor del caso
    body: *const CodeBlock, // bloque del caso
};

const std = @import("std");
const syn = @import("syntax_tree.zig");

pub const SemanticGraph = struct {
    allocator: *const std.mem.Allocator,
    mainScope: *const Scope,
};

pub const Scope = struct {
    nodes: std.ArrayList(SGNode), // index == NodeId

    // These lists point to specific nodes in the `nodes` array.
    typeDeclarations: std.ArrayList(*TypeDeclaration), // index == TypeId
    functionDeclarations: std.ArrayList(*FunctionDeclaration), // index == FuncId
    bindingDeclarations: std.ArrayList(*BindingDeclaration), // index == SymId
};

pub const SGNode = union(enum) {
    typeDeclaration: *TypeDeclaration,
    functionDeclaration: *FunctionDeclaration,
    bindingDeclaration: *BindingDeclaration,

    bindingAssignment: *Assignment,
    functionCall: *FunctionCall,
    codeBlock: *CodeBlock,
    valueLiteral: syn.ValueLiteral, // int, float, char, string
    binaryOperation: BinaryOperation,
    returnStatement: *ReturnStatement,
    ifStatement: *IfStatement,
    whileStatement: *WhileStatement,
    forStatement: *ForStatement,
    switchStatement: *SwitchStatement,
    breakStatement: struct {},
    continueStatement: struct {},
};

pub const TypeDeclaration = struct {
    name: []const u8,
    ty: syn.Type, // enum, struct, union, etc.
    args: std.ArrayList(*BindingDeclaration), // index == TypeId
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    params: std.ArrayList(*BindingDeclaration), // index == ParamId
    returnType: ?syn.Type, // null si no hay retorno
    body: *const CodeBlock,
};

pub const BindingDeclaration = struct {
    name: []const u8,
    mutability: syn.Mutability,
    ty: syn.Type,
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
    nodes: std.ArrayList(SGNode), // nodos del bloque, index == NodeId
    ret_val: ?SGNode, // valor de retorno (si aplica)
};

pub const BuiltinTypes = enum {
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
};

pub const ValueLiteral = union(enum) {
    intLiteral: i64,
    floatLiteral: f64,
    charLiteral: u8,
    stringLiteral: []const u8,
};

pub const BinaryOperation = struct {
    operator: syn.BinaryOperator,
    left: *const SGNode, // izquierdo
    right: *const SGNode, // derecho
};

pub const ReturnStatement = struct {
    expression: ?*const SGNode, // expresión a retornar (null si no hay)
};

pub const IfStatement = struct {
    condition: *const SGNode, // condición del if
    thenBlock: *const CodeBlock, // bloque si la condición es verdadera
    elseBlock: ?*const CodeBlock, // bloque si la condición es falsa (null si no hay)
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
    defaultCase: ?*const CodeBlock, // bloque por defecto (null si no hay)
};

pub const SwitchCase = struct {
    value: *const SGNode, // valor del caso
    body: *const CodeBlock, // bloque del caso
};

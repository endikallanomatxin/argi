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
    declaration: Declaration,
    assignment: Assignment,
    identifier: []const u8,
    function_call: FunctionCall,
    code_block: CodeBlock,
    literal: tok.Literal, // literals are not parsed until the type is known.
    type_name: TypeName,
    return_statement: ReturnStatement,
    binary_operation: BinaryOperation,
    if_statement: IfStatement,
};

pub const SymbolKind = enum {
    // Always const
    function,
    type,
    // Can be const or var
    binding,
    // Pero es importante que el error no lo de aquí sino más adelante,
    // para que puedan darse la mayor cantidad de errores en paralelo.
};

pub const Declaration = struct {
    kind: SymbolKind,
    name: []const u8,
    type: ?TypeName,
    mutability: Mutability,
    args: ?[]const Argument,
    value: ?*STNode,

    pub fn isFunction(self: Declaration) bool {
        const v = self.value orelse return false;
        // if the value points to a code block, then it's a function
        switch (v.*) {
            STNode.codeBlock => return true,
            else => return false,
        }
    }
};

pub const Assignment = struct {
    name: []const u8,
    value: *STNode,
};

pub const FunctionCall = struct {
    callee: []const u8,
    args: []const *STNode,
};

pub const Mutability = enum {
    constant,
    variable,
};

pub const CodeBlock = struct {
    items: []const *STNode,
    // Return args in the future.
};

pub const Argument = struct {
    name: []const u8,
    mutability: Mutability,
    type: ?TypeName,
};

pub const TypeName = struct {
    name: []const u8,
};

pub const ReturnStatement = struct {
    expression: ?*STNode,
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

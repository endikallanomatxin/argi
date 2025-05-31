const std = @import("std");
const tok = @import("token.zig");

const Location = tok.Location;

pub const ST = struct {
    nodes: []const *STNode,
};

pub const STNode = struct {
    location: Location,
    content: Content,
};

pub const Content = union(enum) {
    declaration: Declaration,
    assignment: Assignment,
    identifier: []const u8,
    code_block: CodeBlock,
    value_literal: tok.Literal,
    type_literal: TypeLiteral,
    return_statement: ReturnStatement,
    binary_operation: BinaryOperation,
};

pub const SymbolKind = enum {
    // Always const
    Function,
    Type,
    // Can be const or var
    Binding,
    // Pero es importante que el error no lo de aquí sino más adelante,
    // para que puedan darse la mayor cantidad de errores en paralelo.
};

pub const Declaration = struct {
    kind: SymbolKind,
    name: []const u8,
    type: ?TypeLiteral,
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
    type: ?TypeLiteral,
};

pub const TypeLiteral = struct {
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

const std = @import("std");
const tok = @import("token.zig");

pub const ST = struct {
    nodes: []const *STNode,
};

pub const STNode = union(enum) {
    declaration: *Declaration,
    assignment: *Assignment,
    identifier: []const u8,
    codeBlock: *CodeBlock,
    valueLiteral: *ValueLiteral,
    typeLiteral: *TypeLiteral,
    returnStmt: *ReturnStmt,
    binaryOperation: *BinaryOperation,

    pub fn print(self: STNode, indent: usize) void {
        printIndent(indent);
        switch (self) {
            STNode.declaration => |decl| {
                std.debug.print("Declaration {s} ({s}) =\n", .{ decl.*.name, if (decl.*.mutability == Mutability.Var) "var" else "const" });
                // Se incrementa el nivel de indentación para el nodo hijo.
                if (decl.*.value) |v| {
                    v.print(indent + 1);
                }
            },
            STNode.assignment => |assign| {
                std.debug.print("Assignment {s} =\n", .{assign.*.name});
                // Se incrementa el nivel de indentación para el nodo hijo.
                assign.*.value.print(indent + 1);
            },
            STNode.identifier => |ident| {
                std.debug.print("identifier: {s}\n", .{ident});
            },
            STNode.codeBlock => |codeBlock| {
                std.debug.print("code block:\n", .{});
                for (codeBlock.*.items) |item| {
                    item.print(indent + 1);
                }
            },
            STNode.valueLiteral => |valueLiteral| {
                switch (valueLiteral.*) {
                    ValueLiteral.intLiteral => |intLit| {
                        std.debug.print("IntLiteral {d}\n", .{intLit.value});
                    },
                    ValueLiteral.floatLiteral => |floatLit| {
                        std.debug.print("FloatLiteral {}\n", .{floatLit.value});
                    },
                    ValueLiteral.doubleLiteral => |doubleLit| {
                        std.debug.print("DoubleLiteral {}\n", .{doubleLit.value});
                    },
                    ValueLiteral.charLiteral => |charLit| {
                        std.debug.print("CharLiteral {c}\n", .{charLit.value});
                    },
                    ValueLiteral.boolLiteral => |boolLit| {
                        std.debug.print("BoolLiteral {}\n", .{boolLit.value});
                    },
                    ValueLiteral.stringLiteral => |stringLit| {
                        std.debug.print("StringLiteral {s}\n", .{stringLit.value});
                    },
                }
            },
            STNode.typeLiteral => |typeLiteral| {
                std.debug.print("TypeLiteral {s}\n", .{typeLiteral.*.name});
            },
            STNode.returnStmt => |returnStmt| {
                std.debug.print("return\n", .{});
                if (returnStmt.expression) |expr| {
                    // Se incrementa la indentación para la expresión retornada.
                    expr.print(indent + 1);
                }
            },
            STNode.binaryOperation => |binOp| {
                std.debug.print("BinaryOperation\n", .{});
                binOp.left.print(indent + 1);
                binOp.right.print(indent + 1);
            },
        }
    }
};

// TODO: Implement this for stack traces
pub const Location = struct {
    file: []const u8,
    offset: usize,
    line: usize,
    column: usize,
    // This sounds bit redundant but it's for efficiency
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
    Const,
    Var,
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

pub const ValueLiteral = union(enum) {
    intLiteral: *IntLiteral,
    floatLiteral: *FloatLiteral,
    doubleLiteral: *DoubleLiteral,
    charLiteral: *CharLiteral,
    boolLiteral: *BoolLiteral,
    stringLiteral: *StringLiteral,
};

pub const IntLiteral = struct {
    value: i64,
};

pub const FloatLiteral = struct {
    value: f32,
};

pub const DoubleLiteral = struct {
    value: f64,
};

pub const CharLiteral = struct {
    value: u8,
};

pub const BoolLiteral = struct {
    value: bool,
};

pub const StringLiteral = struct {
    value: []const u8,
};

pub const ReturnStmt = struct {
    expression: ?*STNode,
};

pub const BinaryOperation = struct {
    operator: tok.BinaryOperator,
    left: *STNode,
    right: *STNode,
};

/// Función auxiliar para imprimir espacios de indentación.
fn printIndent(indent: usize) void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        std.debug.print("  ", .{}); // 2 espacios por nivel
    }
}

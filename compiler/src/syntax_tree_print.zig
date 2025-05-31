const std = @import("std");
const syn = @import("syntax_tree.zig");

/// Función auxiliar para imprimir espacios de indentación.
fn printIndent(indent: usize) void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        std.debug.print("  ", .{}); // 2 espacios por nivel
    }
}

pub fn printNode(node: syn.STNode, indent: usize) void {
    std.debug.print("STNode at {s}:{d}:{d}:\n", .{ node.location.file, node.location.line, node.location.column });
    printIndent(indent);
    node.content.print(indent);
}

pub fn printContent(content: syn.Content, indent: usize) void {
    switch (content) {
        .declaration => |decl| {
            std.debug.print("Declaration {s} ({s}) =\n", .{ decl.*.name, if (decl.*.mutability == .Var) "var" else "const" });
            // Se incrementa el nivel de indentación para el nodo hijo.
            if (decl.*.value) |v| {
                v.print(indent + 1);
            }
        },
        .assignment => |assign| {
            std.debug.print("Assignment {s} =\n", .{assign.*.name});
            // Se incrementa el nivel de indentación para el nodo hijo.
            assign.*.value.print(indent + 1);
        },
        .identifier => |ident| {
            std.debug.print("identifier: {s}\n", .{ident});
        },
        .codeBlock => |codeBlock| {
            std.debug.print("code block:\n", .{});
            for (codeBlock.*.items) |item| {
                item.print(indent + 1);
            }
        },
        .valueLiteral => |valueLiteral| {
            switch (valueLiteral.*) {
                .intLiteral => |intLit| {
                    std.debug.print("IntLiteral {d}\n", .{intLit.value});
                },
                .floatLiteral => |floatLit| {
                    std.debug.print("FloatLiteral {}\n", .{floatLit.value});
                },
                .doubleLiteral => |doubleLit| {
                    std.debug.print("DoubleLiteral {}\n", .{doubleLit.value});
                },
                .charLiteral => |charLit| {
                    std.debug.print("CharLiteral {c}\n", .{charLit.value});
                },
                .boolLiteral => |boolLit| {
                    std.debug.print("BoolLiteral {}\n", .{boolLit.value});
                },
                .stringLiteral => |stringLit| {
                    std.debug.print("StringLiteral {s}\n", .{stringLit.value});
                },
            }
        },
        .typeLiteral => |typeLiteral| {
            std.debug.print("TypeLiteral {s}\n", .{typeLiteral.*.name});
        },
        .returnStmt => |returnStmt| {
            std.debug.print("return\n", .{});
            if (returnStmt.expression) |expr| {
                // Se incrementa la indentación para la expresión retornada.
                expr.print(indent + 1);
            }
        },
        .binaryOperation => |binOp| {
            std.debug.print("BinaryOperation\n", .{});
            binOp.left.print(indent + 1);
            binOp.right.print(indent + 1);
        },
    }
}

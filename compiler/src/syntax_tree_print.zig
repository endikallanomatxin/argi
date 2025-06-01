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
    printIndent(indent);
    printContent(node.content, indent);
}

pub fn printContent(content: syn.Content, indent: usize) void {
    switch (content) {
        .declaration => |decl| {
            std.debug.print("Declaration {s} ({s}, {s}, {s}) =\n", .{
                decl.name, if (decl.mutability == .variable) "var" else "const",
                switch (decl.kind) {
                    .function => "function",
                    .type => "type",
                    .binding => "binding",
                },
                // Type
                if (decl.type) |typeName| typeName.name else "unknown type",
            });
            if (decl.value) |v| {
                printNode(v.*, indent + 1);
            }
        },
        .assignment => |assign| {
            std.debug.print("Assignment {s} =\n", .{assign.name});
            // Se incrementa el nivel de indentación para el nodo hijo.
            printNode(assign.value.*, indent + 1);
        },
        .identifier => |ident| {
            std.debug.print("identifier: {s}\n", .{ident});
        },
        .code_block => |code_block| {
            std.debug.print("code block:\n", .{});
            for (code_block.items) |item| {
                printNode(item.*, indent + 1);
            }
        },
        .literal => |literal| {
            std.debug.print("literal: ", .{});
            switch (literal) {
                .bool_literal => |val| {
                    std.debug.print("bool {s}\n", .{if (val) "true" else "false"});
                },
                .decimal_int_literal => |val| std.debug.print("int {s}\n", .{val}),
                .hexadecimal_int_literal => |val| std.debug.print("hex int {s}\n", .{val}),
                .octal_int_literal => |val| std.debug.print("octal int {s}\n", .{val}),
                .binary_int_literal => |val| std.debug.print("binary int {s}\n", .{val}),
                .regular_float_literal => |val| std.debug.print("float {s}\n", .{val}),
                .scientific_float_literal => |val| std.debug.print("scientific float {s}\n", .{val}),
                .char_literal => |val| std.debug.print("char '{c}'\n", .{val}),
                .string_literal => |val| std.debug.print("string \"{s}\"\n", .{val}),
            }
        },
        .type_name => |type_name| {
            std.debug.print("type_name {s}\n", .{type_name.name});
        },
        .return_statement => |returnStmt| {
            std.debug.print("return\n", .{});
            if (returnStmt.expression) |expr| {
                // Se incrementa la indentación para la expresión retornada.
                printNode(expr.*, indent + 1);
            }
        },
        .binary_operation => |binOp| {
            std.debug.print("BinaryOperation\n", .{});
            printNode(binOp.left.*, indent + 1);
            printNode(binOp.right.*, indent + 1);
        },
    }
}

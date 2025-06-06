const std = @import("std");
const syn = @import("syntax_tree.zig");
const tok = @import("token.zig");

/// Imprime `lvl` niveles de indentación (dos espacios cada nivel).
fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

/// Formatea el contenido de un literal para imprimirlo con su tipo.
fn printLiteral(lit: tok.Literal) void {
    switch (lit) {
        .bool_literal => |val| {
            std.debug.print("bool: {s}\n", .{if (val) "true" else "false"});
        },
        .decimal_int_literal => |val| {
            std.debug.print("int (decimal): {s}\n", .{val});
        },
        .hexadecimal_int_literal => |val| {
            std.debug.print("int (hex): {s}\n", .{val});
        },
        .octal_int_literal => |val| {
            std.debug.print("int (octal): {s}\n", .{val});
        },
        .binary_int_literal => |val| {
            std.debug.print("int (binary): {s}\n", .{val});
        },
        .regular_float_literal => |val| {
            std.debug.print("float (normal): {s}\n", .{val});
        },
        .scientific_float_literal => |val| {
            std.debug.print("float (scientific): {s}\n", .{val});
        },
        .char_literal => |val| {
            std.debug.print("char: '{c}'\n", .{val});
        },
        .string_literal => |val| {
            std.debug.print("string: \"{s}\"\n", .{val});
        },
    }
}

/// Imprime un nodo STNode recursivamente, mostrando tipo y detalles.
pub fn printNode(node: syn.STNode, lvl: usize) void {
    indent(lvl);
    switch (node.content) {
        .declaration => |decl| {
            const mut_str = if (decl.mutability == syn.Mutability.variable) "var" else "const";
            const kind_str = switch (decl.kind) {
                .function => "function",
                .type => "type",
                .binding => "binding",
            };
            const type_str = if (decl.type) |t| t.name else "<?>";

            std.debug.print("Declaration: \"{s}\" {s} {s} {s}\n", .{ decl.name, kind_str, mut_str, type_str });

            if (decl.value) |v| {
                printNode(v.*, lvl + 1);
            }
        },
        .assignment => |assign| {
            std.debug.print("Assignment: \"{s}\"\n", .{assign.name});
            printNode(assign.value.*, lvl + 1);
        },
        .identifier => |ident| {
            std.debug.print("Identifier: \"{s}\"\n", .{ident});
        },
        .literal => |lit| {
            printLiteral(lit);
        },
        .code_block => |code_block| {
            std.debug.print("CodeBlock:\n", .{});
            for (code_block.items) |child| {
                printNode(child.*, lvl + 1);
            }
        },
        .return_statement => |retStmt| {
            std.debug.print("ReturnStatement\n", .{});
            if (retStmt.expression) |expr| {
                printNode(expr.*, lvl + 1);
            }
        },
        .binary_operation => |binOp| {
            const op_str = switch (binOp.operator) {
                .addition => "+",
                .subtraction => "-",
                .multiplication => "*",
                .division => "/",
                .modulo => "%",
            };
            std.debug.print("BinaryOperation: \"{s}\"\n", .{op_str});
            indent(lvl + 1);
            std.debug.print("Left:\n", .{});
            printNode(binOp.left.*, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Right:\n", .{});
            printNode(binOp.right.*, lvl + 2);
        },

        else => {
            // Cualquier otro caso que no se haya manejado
            std.debug.print("Unknown AST node: {any}\n", .{node.content});
        },
    }
}

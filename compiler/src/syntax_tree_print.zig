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

fn printType(tn: syn.TypeName) void {
    return switch (tn) {
        .identifier => |id| {
            std.debug.print("{s}", .{id});
        },
        .struct_type => |st| {
            std.debug.print("struct (", .{});
            for (st.fields) |f| {
                std.debug.print(".{s} : ", .{f.name});
                printType(f.type);
                std.debug.print(" ", .{});
                if (f.default_value) |dv| {
                    std.debug.print("= ", .{});
                    printNode(dv.*, 0);
                }
            }
            std.debug.print(")", .{});
        },
    };
}

/// Formatea el contenido de un literal para imprimirlo con su tipo.
fn printLiteral(lit: tok.Literal) void {
    switch (lit) {
        .bool_literal => |val| {
            std.debug.print("bool:{s}", .{if (val) "true" else "false"});
        },
        .decimal_int_literal => |val| {
            std.debug.print("int:{s}", .{val});
        },
        .hexadecimal_int_literal => |val| {
            std.debug.print("int(hex): {s}", .{val});
        },
        .octal_int_literal => |val| {
            std.debug.print("int(oct): {s}", .{val});
        },
        .binary_int_literal => |val| {
            std.debug.print("int(bin): {s}", .{val});
        },
        .regular_float_literal => |val| {
            std.debug.print("float: {s}", .{val});
        },
        .scientific_float_literal => |val| {
            std.debug.print("float(sci): {s}", .{val});
        },
        .char_literal => |val| {
            std.debug.print("char: '{c}'", .{val});
        },
        .string_literal => |val| {
            std.debug.print("string: \"{s}\"", .{val});
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
            std.debug.print("Declaration: \"{s}\" {s} {s}", .{ decl.name, kind_str, mut_str });
            if (decl.type) |t| {
                std.debug.print(" : ", .{});
                printType(t);
            } else {
                std.debug.print(" : unknown type", .{});
            }

            if (decl.kind == .function) {
                indent(lvl + 1);
                std.debug.print("Arguments:\n", .{});
                for (decl.args.?) |arg| {
                    indent(lvl + 2);
                    std.debug.print("- {s} : ", .{arg.name});
                    printType(arg.type.?);
                    std.debug.print(" ({s})\n", .{if (arg.mutability == syn.Mutability.variable) "var" else "const"});
                }
            }

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
        .struct_literal => |sl| {
            std.debug.print("\n", .{});
            indent(lvl + 1);
            std.debug.print("StructLiteral:\n", .{});
            for (sl.fields) |f| {
                indent(lvl + 2);
                std.debug.print(".{s}:", .{f.name});
                printNode(f.value.*, lvl + 2);
                std.debug.print("\n", .{});
            }
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
                .equals => "==",
                .not_equals => "!=",
            };
            std.debug.print("BinaryOperation: \"{s}\"\n", .{op_str});
            indent(lvl + 1);
            std.debug.print("Left:\n", .{});
            printNode(binOp.left.*, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Right:\n", .{});
            printNode(binOp.right.*, lvl + 2);
        },
        .function_call => |fc| {
            std.debug.print("FunctionCall: {s}\n", .{fc.callee});
            for (fc.args) |a| {
                indent(lvl + 1);
                if (a.name) |n|
                    std.debug.print("{s}:\n", .{n})
                else
                    std.debug.print("arg:\n", .{});
                printNode(a.value.*, lvl + 2);
            }
        },

        else => {
            // Cualquier otro caso que no se haya manejado
            std.debug.print("Unknown AST node: {any}\n", .{node.content});
        },
    }
}

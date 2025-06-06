const std = @import("std");
const sem = @import("semantic_graph.zig");
const tok = @import("token.zig"); // Solo para constantes de estilo, si las necesitas

/// Imprime `lvl` niveles de indentación (dos espacios cada nivel).
fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

/// Obtiene la representación textual de un tipo `sem.Type`.
fn typeToString(t: sem.Type) []const u8 {
    return switch (t) {
        .builtin => |b| @tagName(b),
        .custom => |_| "custom", // Si soportas tipos definidos por usuario, reemplaza aquí
    };
}

/// Imprime un literal desde el ASG (ValueLiteral).
fn printValueLiteral(lit: *const sem.ValueLiteral, lvl: usize) void {
    indent(lvl);
    switch (lit.*) {
        .int_literal => |v| {
            std.debug.print("Literal int: {d}\n", .{v});
        },
        .float_literal => |f| {
            std.debug.print("Literal float: {d}\n", .{f});
        },
        .char_literal => |c| {
            std.debug.print("Literal char: '{c}'\n", .{c});
        },
        .string_literal => |s| {
            std.debug.print("Literal string: \"{s}\"\n", .{s});
        },
    }
}

/// Imprime un nodo SGNode completo, mostrando tipo, nombre, mutabilidad, etc.
pub fn printNode(node: *const sem.SGNode, lvl: usize) void {
    indent(lvl);
    switch (node.*) {
        // ─────────────────────────────────────────────────────────── declaraciones de variable
        .binding_declaration => |b| {
            const mut_str = if (b.mutability == .variable) "var" else "const";
            const ty_str = typeToString(b.ty);
            std.debug.print("Decl: \"{s}\" {s} : {s}\n", .{ b.name, mut_str, ty_str });

            // Si hay inicialización, imprimirla
            // if (b.initialization) |init_node| {
            //     indent(lvl + 1);
            //     std.debug.print("Initial value:\n", .{});
            //     printNode(init_node, lvl + 2);
            // }
        },

        // ─────────────────────────────────────────────────────────── declaraciones de función
        .function_declaration => |f| {
            const ret_str = if (f.return_type) |rt| typeToString(rt) else "void";
            std.debug.print("Function: \"{s}\" -> {s}\n", .{ f.name, ret_str });

            // Cuerpo (CodeBlock)
            indent(lvl + 1);
            std.debug.print("Body:\n", .{});
            // Envolvemos el *CodeBlock en un SGNode temporal para imprimir
            const tmp: sem.SGNode = .{ .code_block = @constCast(f.body) };
            printNode(&tmp, lvl + 2);
        },

        // ───────────────────────────────────────────────────────────── asignaciones
        .binding_assignment => |a| {
            const var_name = a.sym_id.name;
            const var_ty = typeToString(a.sym_id.ty);
            std.debug.print("Assign: \"{s}\" ({s}) =\n", .{ var_name, var_ty });
            printNode(a.value, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── identificadores
        .binding_use => |b| {
            std.debug.print("Use: \"{s}\" ({s})\n", .{ b.name, typeToString(b.ty) });
        },

        // ───────────────────────────────────────────────────────────── llamadas a función (aún no implementado completamente)
        .function_call => |fc| {
            std.debug.print("FunctionCall -> \"{s}\"\n", .{fc.callee.name});
            if (fc.args.len > 0) {
                indent(lvl + 1);
                std.debug.print("Args:\n", .{});
                for (fc.args) |arg| {
                    printNode(&arg, lvl + 2);
                }
            }
        },

        // ───────────────────────────────────────────────────────────── bloque de código
        .code_block => |blk| {
            std.debug.print("Block:\n", .{});
            for (blk.nodes.items) |child| {
                printNode(child, lvl + 1);
            }
        },

        // ───────────────────────────────────────────────────────────── literales
        .value_literal => |lit| {
            printValueLiteral(&lit, lvl);
        },

        // ───────────────────────────────────────────────────────────── operación binaria
        .binary_operation => |bo| {
            const op_str = switch (bo.operator) {
                .addition => "+",
                .subtraction => "-",
                .multiplication => "*",
                .division => "/",
                .modulo => "%",
                .equals => "==",
                .not_equals => "!=",
            };
            std.debug.print("BinaryOp: \"{s}\"\n", .{op_str});
            indent(lvl + 1);
            std.debug.print("Left:\n", .{});
            printNode(bo.left, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Right:\n", .{});
            printNode(bo.right, lvl + 2);
        },

        // ───────────────────────────────────────────────────────────── return
        .return_statement => |r| {
            std.debug.print("ReturnStatement\n", .{});
            if (r.expression) |expr| {
                printNode(expr, lvl + 1);
            }
        },

        // ───────────────────────────────────────────────────────────── otros casos
        .if_statement => |ifs| {
            std.debug.print("IfStatement:\n", .{});
            indent(lvl + 1);
            std.debug.print("Condition:\n", .{});
            printNode(ifs.condition, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Then:\n", .{});
            const then_tmp: sem.SGNode = .{ .code_block = @constCast(ifs.then_block) };
            printNode(&then_tmp, lvl + 2);
            if (ifs.else_block) |else_blk| {
                indent(lvl + 1);
                std.debug.print("Else:\n", .{});
                const else_tmp: sem.SGNode = .{ .code_block = @constCast(else_blk) };
                printNode(&else_tmp, lvl + 2);
            }
        },
        .while_statement => |wh| {
            std.debug.print("WhileStatement:\n", .{});
            indent(lvl + 1);
            std.debug.print("Condition:\n", .{});
            printNode(wh.condition, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Body:\n", .{});
            const body_tmp: sem.SGNode = .{ .code_block = @constCast(wh.body) };
            printNode(&body_tmp, lvl + 2);
        },
        .for_statement => |fr| {
            std.debug.print("ForStatement:\n", .{});
            if (fr.init) |init| {
                indent(lvl + 1);
                std.debug.print("Init:\n", .{});
                printNode(init, lvl + 2);
            }
            indent(lvl + 1);
            std.debug.print("Condition:\n", .{});
            printNode(fr.condition, lvl + 2);
            if (fr.increment) |inc| {
                indent(lvl + 1);
                std.debug.print("Increment:\n", .{});
                printNode(inc, lvl + 2);
            }
            indent(lvl + 1);
            std.debug.print("Body:\n", .{});
            const body_tmp: sem.SGNode = .{ .code_block = @constCast(fr.body) };
            printNode(&body_tmp, lvl + 2);
        },
        .switch_statement => |sw| {
            std.debug.print("SwitchStatement:\n", .{});
            indent(lvl + 1);
            std.debug.print("Expression:\n", .{});
            printNode(sw.expression, lvl + 2);
            for (sw.cases.items) |case| {
                indent(lvl + 1);
                std.debug.print("Case:\n", .{});
                indent(lvl + 2);
                std.debug.print("Value:\n", .{});
                printNode(case.value, lvl + 3);
                indent(lvl + 2);
                std.debug.print("Body:\n", .{});
                const case_tmp: sem.SGNode = .{ .code_block = @constCast(case.body) };
                printNode(&case_tmp, lvl + 3);
            }
            if (sw.default_case) |dflt| {
                indent(lvl + 1);
                std.debug.print("Default:\n", .{});
                const dflt_tmp: sem.SGNode = .{ .code_block = @constCast(dflt) };
                printNode(&dflt_tmp, lvl + 2);
            }
        },

        .break_statement => |_| {
            std.debug.print("BreakStatement\n", .{});
        },
        .continue_statement => |_| {
            std.debug.print("ContinueStatement\n", .{});
        },

        // ───────────────────────────────────────────────────────────── caso por defecto
        else => {
            std.debug.print("Unknown ASG node: {any}\n", .{node.*});
        },
    }
}

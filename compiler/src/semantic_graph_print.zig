const std = @import("std");
const sem = @import("semantic_graph.zig");

/// Imprime `lvl` niveles de indentación (dos espacios cada nivel).
fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

/// Punto de entrada: imprime un nodo SGNode (y recursivamente sus hijos).
pub fn printNode(node: *const sem.SGNode, lvl: usize) void {
    indent(lvl);
    switch (node.*) {
        // ─────────────────────────────────────────────────────────── declaraciones
        .binding_declaration => |b| {
            std.debug.print("Decl {s} ({s})\n", .{
                b.name,
                if (b.mutability == .variable) "var" else "const",
            });
        },

        .function_declaration => |f| {
            // 1) Imprime la firma de la función
            std.debug.print("Function {s} -> {s}\n", .{
                f.name,
                if (f.return_type) |rt|
                    switch (rt) {
                        .builtin => @tagName(rt.builtin),
                        else => "custom",
                    }
                else
                    "void",
            });

            // 2) Para imprimir el cuerpo (un *CodeBlock), envolvemos en un SGNode local
            const tmp_node: sem.SGNode = .{ .code_block = @constCast(f.body) };
            printNode(&tmp_node, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── asignaciones
        .binding_assignment => |a| {
            std.debug.print("Assign {s} ({s}) =\n", .{
                a.sym_id.name,
                @tagName(a.sym_id.ty.builtin),
            });
            printNode(a.value, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── bloque de código
        .code_block => |blk| {
            std.debug.print("Block\n", .{});
            for (blk.nodes.items) |child| {
                printNode(child, lvl + 1);
            }
        },

        // ───────────────────────────────────────────────────────────── expresiones
        .value_literal => |lit| {
            switch (lit) {
                .int_literal => |v| std.debug.print("int {d}\n", .{v}),
                .float_literal => |v| std.debug.print("float {d}\n", .{v}),
                else => std.debug.print("literal …\n", .{}),
            }
        },

        .binary_operation => |bo| {
            std.debug.print("BinaryOp ({s})\n", .{@tagName(bo.operator)});
            printNode(bo.left, lvl + 1);
            printNode(bo.right, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── flujo
        .return_statement => |r| {
            std.debug.print("return\n", .{});
            if (r.expression) |e| {
                printNode(e, lvl + 1);
            }
        },

        // ───────────────────────────────────────────────────────────── caso por defecto
        else => std.debug.print("{s}\n", .{@tagName(node.*)}),
    }
}

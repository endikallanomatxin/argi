const std = @import("std");
const syn = @import("syntax_tree.zig");
const tok = @import("token.zig");

//──────────────────────────────────────────────────────────────────────────────
// Utilidades
//──────────────────────────────────────────────────────────────────────────────

fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) std.debug.print("  ", .{});
}

// ── impresión de tipos ──────────────────────────────────────────────────────
fn printType(t: syn.Type, lvl: usize) void {
    switch (t) {
        .type_name => |id| std.debug.print("{s}", .{id}),
        .struct_type_literal => |st| printStructTypeLiteral(st, lvl),
    }
}

fn printStructTypeLiteral(st: syn.StructTypeLiteral, lvl: usize) void {
    std.debug.print("struct (\n", .{});
    for (st.fields) |f| {
        indent(lvl + 1);
        std.debug.print(".{s}", .{f.name});

        if (f.type) |fty| {
            std.debug.print(" : ", .{});
            printType(fty, lvl + 1);
        }

        if (f.default_value) |dv| {
            std.debug.print(" = ", .{});
            printNode(dv.*, 0);
        }
        std.debug.print("\n", .{});
    }
    indent(lvl);
    std.debug.print(")", .{});
}

// ── impresión de literales de valor ─────────────────────────────────────────
fn printStructValueLiteral(sl: syn.StructValueLiteral, lvl: usize) void {
    std.debug.print("(\n", .{});
    for (sl.fields) |f| {
        indent(lvl + 1);
        std.debug.print(".{s} = ", .{f.name});
        printNode(f.value.*, lvl + 1);
        std.debug.print("\n", .{});
    }
    indent(lvl);
    std.debug.print(")", .{});
}

fn printLiteral(lit: tok.Literal) void {
    switch (lit) {
        .bool_literal => |v| std.debug.print("bool:{s}", .{if (v) "true" else "false"}),
        .decimal_int_literal => |v| std.debug.print("int:{s}", .{v}),
        .hexadecimal_int_literal => |v| std.debug.print("int(hex):{s}", .{v}),
        .octal_int_literal => |v| std.debug.print("int(oct):{s}", .{v}),
        .binary_int_literal => |v| std.debug.print("int(bin):{s}", .{v}),
        .regular_float_literal => |v| std.debug.print("float:{s}", .{v}),
        .scientific_float_literal => |v| std.debug.print("float(sci):{s}", .{v}),
        .char_literal => |c| std.debug.print("char:'{c}'", .{c}),
        .string_literal => |s| std.debug.print("string:\"{s}\"", .{s}),
    }
}

//──────────────────────────────────────────────────────────────────────────────
//  VISOR PRINCIPAL
//──────────────────────────────────────────────────────────────────────────────
pub fn printNode(node: syn.STNode, lvl: usize) void {
    indent(lvl);

    switch (node.content) {
        // ── SYMBOL DECLARATION ────────────────────────────────────────────
        .symbol_declaration => |d| {
            const mut = if (d.mutability == .variable) "var" else "const";
            std.debug.print("SymbolDecl \"{s}\" ({s})", .{ d.name, mut });

            if (d.type) |ty| {
                std.debug.print(" : ", .{});
                printType(ty, lvl);
            } else {
                std.debug.print(" : ?", .{});
            }
            std.debug.print("\n", .{});

            if (d.value) |v| {
                printNode(v.*, lvl + 1);
                std.debug.print("\n", .{});
            }
        },

        // ── TYPE DECLARATION ──────────────────────────────────────────────
        .type_declaration => |td| {
            std.debug.print("TypeDecl  \"{s}\"\n", .{td.name});
            printNode(td.value.*, lvl + 1); // el valor es un struct_type_literal
        },

        // ── FUNCTION DECLARATION ──────────────────────────────────────────
        .function_declaration => |fd| {
            std.debug.print("FuncDecl \"{s}\"\n", .{fd.name});

            indent(lvl + 1);
            std.debug.print("input : ", .{});
            printStructTypeLiteral(fd.input, lvl + 1);
            std.debug.print("\n", .{});

            indent(lvl + 1);
            std.debug.print("output: ", .{});
            printStructTypeLiteral(fd.output, lvl + 1);
            std.debug.print("\n", .{});

            indent(lvl + 1);
            std.debug.print("body  :\n", .{});
            printNode(fd.body.*, lvl + 2);
        },

        // ── ASSIGNMENT ────────────────────────────────────────────────────
        .assignment => |a| {
            std.debug.print("Assignment \"{s}\"\n", .{a.name});
            printNode(a.value.*, lvl + 1);
        },

        // ── IDENTIFIER & LITERAL ─────────────────────────────────────────
        .identifier => |id| std.debug.print("Identifier \"{s}\"\n", .{id}),
        .literal => |lit| printLiteral(lit),

        // ── STRUCT TYPE LITERAL (stand-alone) ────────────────────────────
        .struct_type_literal => |st| {
            std.debug.print("StructTypeLiteral ", .{});
            printStructTypeLiteral(st, lvl);
            std.debug.print("\n", .{});
        },

        // ── STRUCT VALUE LITERAL ─────────────────────────────────────────
        .struct_value_literal => |sv| {
            std.debug.print("StructValueLiteral ", .{});
            printStructValueLiteral(sv, lvl);
            std.debug.print("\n", .{});
        },

        // ── STRUCT FIELD ACCESS ──────────────────────────────────────────
        .struct_field_access => |sfa| {
            std.debug.print("StructFieldAccess \n", .{});
            indent(lvl + 1);
            std.debug.print("Struct: ", .{});
            printNode(sfa.struct_value.*, 0);
            indent(lvl + 1);
            std.debug.print("Field:  .{s}\n", .{sfa.field_name});
        },

        // ── CODE-BLOCK ───────────────────────────────────────────────────
        .code_block => |cb| {
            std.debug.print("CodeBlock\n", .{});
            for (cb.items) |n| printNode(n.*, lvl + 1);
        },

        // ── RETURN ───────────────────────────────────────────────────────
        .return_statement => |ret| {
            std.debug.print("Return\n", .{});
            if (ret.expression) |e| printNode(e.*, lvl + 1);
        },

        // ── IF ───────────────────────────────────────────────────────────
        .if_statement => |ifs| {
            std.debug.print("If\n", .{});
            indent(lvl + 1);
            std.debug.print("cond:\n", .{});
            printNode(ifs.condition.*, lvl + 2);
            indent(lvl + 1);
            std.debug.print("then:\n", .{});
            printNode(ifs.then_block.*, lvl + 2);
            if (ifs.else_block) |eb| {
                indent(lvl + 1);
                std.debug.print("else:\n", .{});
                printNode(eb.*, lvl + 2);
            }
        },

        // ── BINARY OP ────────────────────────────────────────────────────
        .binary_operation => |bo| {
            const op = switch (bo.operator) {
                .addition => "+",
                .subtraction => "-",
                .multiplication => "*",
                .division => "/",
                .modulo => "%",
                .equals => "==",
                .not_equals => "!=",
            };
            std.debug.print("BinaryOp \"{s}\"\n", .{op});
            indent(lvl + 1);
            std.debug.print("lhs:\n", .{});
            printNode(bo.left.*, lvl + 2);
            indent(lvl + 1);
            std.debug.print("rhs:\n", .{});
            printNode(bo.right.*, lvl + 2);
        },

        // ── FUNCTION CALL ────────────────────────────────────────────────
        .function_call => |fc| {
            std.debug.print("Call {s}\n", .{fc.callee});
            indent(lvl + 1);
            std.debug.print("input:\n", .{});
            printNode(fc.input.*, lvl + 2);
        },
    }
}

const std = @import("std");
const sem = @import("semantic_graph.zig");

fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) std.debug.print("  ", .{});
}

fn typeToString(t: sem.Type) []const u8 {
    return switch (t) {
        .builtin => |b| @tagName(b),
        .struct_type => |_| "struct",
        .pointer_type => |_| "&",
    };
}

fn printValueLiteral(lit: *const sem.ValueLiteral, lvl: usize) void {
    indent(lvl);
    switch (lit.*) {
        .int_literal => |v| std.debug.print("Literal int: {d}\n", .{v}),
        .float_literal => |f| std.debug.print("Literal float: {d}\n", .{f}),
        .char_literal => |c| std.debug.print("Literal char: '{c}'\n", .{c}),
        .string_literal => |s| std.debug.print("Literal string: \"{s}\"\n", .{s}),
        .bool_literal => |b| std.debug.print("Literal bool: {s}\n", .{if (b) "true" else "false"}),
    }
}

pub fn printNode(node: *const sem.SGNode, lvl: usize) void {
    indent(lvl);
    switch (node.content) {
        .binding_declaration => |b| {
            const mut = if (b.mutability == .variable) "var" else "const";
            std.debug.print("Decl \"{s}\" {s} : {s}\n", .{ b.name, mut, typeToString(b.ty) });
        },

        .function_declaration => |f| {
            std.debug.print("Function \"{s}\"\n", .{f.name});

            indent(lvl + 1);
            std.debug.print("Input:\n", .{});
            for (f.input.fields) |fld| {
                indent(lvl + 2);
                std.debug.print(".{s} : {s}\n", .{ fld.name, typeToString(fld.ty) });
            }

            indent(lvl + 1);
            std.debug.print("Output:\n", .{});
            for (f.output.fields) |fld| {
                indent(lvl + 2);
                std.debug.print(".{s} : {s}\n", .{ fld.name, typeToString(fld.ty) });
            }

            indent(lvl + 1);
            std.debug.print("Body:\n", .{});
            if (f.body) |cb| {
                const tmp: sem.SGNode = .{ .location = node.location, .content = .{ .code_block = @constCast(cb) } };
                printNode(&tmp, lvl + 2);
            } else {
                indent(lvl + 2);
                std.debug.print("(extern function)\n", .{});
            }
        },

        .binding_assignment => |a| {
            std.debug.print("Assign \"{s}\" ({s}) =\n", .{ a.sym_id.name, typeToString(a.sym_id.ty) });
            printNode(a.value, lvl + 1);
        },

        .binding_use => |b| {
            std.debug.print("Use \"{s}\" ({s})\n", .{ b.name, typeToString(b.ty) });
        },

        .function_call => |fc| {
            std.debug.print("Call \"{s}\"\n", .{fc.callee.name});
            printNode(fc.input, lvl + 1);
        },

        .code_block => |blk| {
            std.debug.print("Block:\n", .{});
            for (blk.nodes) |n| printNode(n, lvl + 1);
        },

        .value_literal => |v| printValueLiteral(&v, lvl),

        .struct_value_literal => |sl| {
            std.debug.print("StructLiteral\n", .{});
            for (sl.fields) |f| {
                indent(lvl + 1);
                std.debug.print(".{s}:\n", .{f.name});
                printNode(f.value, lvl + 2);
            }
        },

        .struct_field_access => |sfa| {
            std.debug.print("FieldAccess \"{s}\" (index: {d})\n", .{ sfa.field_name, sfa.field_index });
            indent(lvl + 1);
            std.debug.print("Struct:\n", .{});
            printNode(sfa.struct_value, lvl + 2);
        },

        .binary_operation => |bo| {
            const op = switch (bo.operator) {
                .addition => "+",
                .subtraction => "-",
                .multiplication => "*",
                .division => "/",
                .modulo => "%",
            };
            std.debug.print("BinaryOp \"{s}\"\n", .{op});
            indent(lvl + 1);
            std.debug.print("Left:\n", .{});
            printNode(bo.left, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Right:\n", .{});
            printNode(bo.right, lvl + 2);
        },

        .comparison => |c| {
            const op = switch (c.operator) {
                .equal => "==",
                .not_equal => "!=",
                .less_than => "<",
                .greater_than => ">",
                .less_than_or_equal => "<=",
                .greater_than_or_equal => ">=",
            };
            std.debug.print("Comparison \"{s}\"\n", .{op});
            indent(lvl + 1);
            std.debug.print("Left:\n", .{});
            printNode(c.left, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Right:\n", .{});
            printNode(c.right, lvl + 2);
        },

        .return_statement => |r| {
            std.debug.print("Return\n", .{});
            if (r.expression) |e| printNode(e, lvl + 1);
        },

        .if_statement => |ifs| {
            std.debug.print("If\n", .{});
            indent(lvl + 1);
            std.debug.print("Cond:\n", .{});
            printNode(ifs.condition, lvl + 2);
            indent(lvl + 1);
            std.debug.print("Then:\n", .{});
            const t: sem.SGNode = .{
                .location = node.location,
                .content = .{ .code_block = @constCast(ifs.then_block) },
            };
            printNode(&t, lvl + 2);
            if (ifs.else_block) |eb| {
                indent(lvl + 1);
                std.debug.print("Else:\n", .{});
                const e: sem.SGNode = .{
                    .location = node.location,
                    .content = .{ .code_block = @constCast(eb) },
                };
                printNode(&e, lvl + 2);
            }
        },

        .while_statement => |_| std.debug.print("WhileStatement\n", .{}),
        .for_statement => |_| std.debug.print("ForStatement\n", .{}),
        .switch_statement => |_| std.debug.print("SwitchStatement\n", .{}),
        .break_statement => |_| std.debug.print("Break\n", .{}),
        .continue_statement => |_| std.debug.print("Continue\n", .{}),

        .address_of => |ao| {
            std.debug.print("AddressOf\n", .{});
            printNode(ao, lvl + 1);
        },

        .dereference => |d| {
            std.debug.print("Dereference\n", .{});
            indent(lvl + 1);
            std.debug.print("result_ty: {s}\n", .{@tagName(d.ty)});
            printNode(d.pointer, lvl + 2);
        },
        .pointer_assignment => |pa| {
            std.debug.print("PointerAssignment\n", .{});
            indent(lvl + 1);
            std.debug.print("pointer:\n", .{});
            printNode(pa.pointer, lvl + 2);
            indent(lvl + 1);
            std.debug.print("value:\n", .{});
            printNode(pa.value, lvl + 2);
        },

        else => std.debug.print("Unknown SG node\n", .{}),
    }
}

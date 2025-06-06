const std = @import("std");
const sem = @import("semantic_graph.zig");

/// Print `indent` levels of two-space padding.
fn indent(ind: usize) void {
    var i: usize = 0;
    while (i < ind) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

/// Public entry-point.
/// Print one node (and its children, if any) with the given indentation level.
pub fn printNode(node: *const sem.SGNode, lvl: usize) void {
    indent(lvl);

    switch (node.*) {
        // ─────────────────────────────────────────────────────────── declarations
        .binding_declaration => |b| {
            std.debug.print("Decl {s} ({s})\n", .{
                b.name,
                if (b.mutability == .variable) "var" else "const",
            });
        },
        .function_declaration => |f| {
            std.debug.print("Function {s} -> {s}\n", .{
                f.name,
                if (f.return_type) |rt|
                    switch (rt) {
                        .builtin => |bt| @tagName(bt),
                        else => "custom",
                    }
                else
                    "void",
            });
            // TODO:
            // std.debug.print("  Body:\n", .{});
            // const sg_node = sem.SGNode{
            //     .code_block = @constCast(f.body),
            // };
            // printNode(&sg_node, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── assignments
        .binding_assignment => |a| {
            std.debug.print("Assign → {s}\n", .{a.sym_id.name});
            printNode(a.value, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── code block
        .code_block => |blk| {
            std.debug.print("Block\n", .{});
            for (blk.nodes.items) |child|
                printNode(child, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── expressions
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

        // ───────────────────────────────────────────────────────────── control-flow
        .return_statement => |r| {
            std.debug.print("return\n", .{});
            if (r.expression) |e| printNode(e, lvl + 1);
        },

        // ───────────────────────────────────────────────────────────── fallback
        else => std.debug.print("{s}\n", .{@tagName(node.*)}),
    }
}

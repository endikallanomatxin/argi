const std = @import("std");
const syn = @import("syntax_tree.zig");

pub fn printNode(tree: *const syn.SyntaxFile, node: syn.NodeIndex, level: usize) void {
    for (0..level) |_| std.debug.print("  ", .{});
    std.debug.print("{s} @{d}\n", .{ @tagName(tree.tag(node)), tree.location(node).offset });
}



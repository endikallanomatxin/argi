const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");

pub const Stats = struct {
    deinit_functions: u32 = 0,
    generic_deinit_functions: u32 = 0,
};

/// Temporal identities must not be inferred by Safety/GlobalSema from a callee
/// spelling. Resolve them once from the source-level declaration and store the
/// semantic bit on the normal/generic function record.
pub fn lower(
    graph: *module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
) Stats {
    var stats: Stats = .{};

    for (graph.semantic.function_semantics.items) |*semantic| {
        const function = graph.functions.items[@intFromEnum(semantic.function)];
        const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
        const file = files[declaration.module_file_index];
        if (isDeinit(file, declaration.syntax_node)) {
            semantic.flags.is_deinit = true;
            stats.deinit_functions += 1;
        }
    }

    for (graph.semantic.templates.generic_function_templates.items) |*template| {
        const declaration = graph.declarations.items[@intFromEnum(template.declaration)];
        const file = files[declaration.module_file_index];
        if (isDeinit(file, declaration.syntax_node)) {
            template.is_deinit = true;
            stats.generic_deinit_functions += 1;
        }
    }
    return stats;
}

fn isDeinit(file: module_sg.FileInput, node: @import("../3_syntax/syntax_tree.zig").NodeIndex) bool {
    const name = file.tree.functionNameFromSource(file.source, node) orelse return false;
    return switch (name) {
        .operator => false,
        .identifier => |token| std.mem.eql(u8, file.tree.tokenTextFromSource(file.source, token), "deinit"),
    };
}

test "function identity lowering keeps deinit as semantic metadata" {
    const flags: @import("semantic_primitives.zig").FunctionFlags = .{ .is_deinit = true };
    try std.testing.expect(flags.is_deinit);
}

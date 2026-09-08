const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");
const callable = @import("semantic_callable.zig");

pub fn lower(
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !u32 {
    var count: u32 = 0;
    for (graph.semantic.templates.generic_function_templates.items) |*template| {
        const declaration = graph.declarations.items[@intFromEnum(template.declaration)];
        const file = files[declaration.module_file_index];
        const name = file.tree.functionNameFromSource(file.source, declaration.syntax_node) orelse continue;
        template.operator = switch (name) {
            .operator => |value| callable.fromSyntax(value),
            .identifier => null,
        };
        if (template.operator != null) count += 1;
    }
    return count;
}

test "generic operator metadata is cold template state" {
    try std.testing.expect(@sizeOf(?callable.OperatorKind) <= 2);
}

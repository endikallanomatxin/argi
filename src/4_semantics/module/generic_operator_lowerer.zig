const std = @import("std");
const graph_mod = @import("graph.zig");
const callable = @import("../primitives/callable.zig");

pub fn lower(
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !u32 {
    var count: u32 = 0;
    for (graph.semantic.parameterized_storage.parameterized_functions.items) |*parameterized| {
        const declaration = graph.declarations.items[@intFromEnum(parameterized.declaration)];
        const file = files[declaration.module_file_index];
        const declaration_node = graph_mod.declarationSyntaxNode(files, declaration) orelse continue;
        const name = file.tree.functionNameFromSource(file.source, declaration_node) orelse continue;
        parameterized.operator = switch (name) {
            .operator => |value| graph_mod.operatorKindFromSyntax(value),
            .identifier => null,
        };
        if (parameterized.operator != null) count += 1;
    }
    return count;
}

test "generic operator metadata is cold parameterized state" {
    try std.testing.expect(@sizeOf(?callable.OperatorKind) <= 2);
}

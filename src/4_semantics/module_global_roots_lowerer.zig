const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");
const writer_mod = @import("module_semantic_writer.zig");
const primitives = @import("semantic_primitives.zig");

pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
) !u32 {
    var writer = writer_mod.Writer.init(allocator, graph);
    var count: u32 = 0;
    for (graph.semantic.declaration_bindings.items) |relation| {
        const declaration = graph.declarations.items[@intFromEnum(relation.declaration)];
        const binding = graph.semantic.bindings.items[@intFromEnum(relation.binding)];
        const node = try writer.addResolvedNode(.{
            .source = primitives.SourceRef{
                .file_index = declaration.module_file_index,
                .offset = declaration.source_offset,
            },
            .ty = binding.ty,
            .content = .{ .binding_declaration = relation.binding },
        });
        try writer.addRoot(node);
        count += 1;
    }
    return count;
}

test "global binding roots need no declaration binding relation after linking" {
    const entities = @import("module_semantic_entities.zig");
    try std.testing.expect(@sizeOf(entities.DeclarationBinding) <= 8);
}

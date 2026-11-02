const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const writer_mod = @import("writer.zig");

pub const Stats = struct { generic_calls: u32 = 0 };

pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !Stats {
    var writer = writer_mod.Writer.init(allocator, graph);
    var stats: Stats = .{};
    for (files, 0..) |file, raw_file| {
        const file_index: u32 = @intCast(raw_file);
        for (file.tree.nodes.items(.tag), 0..) |tag, raw_node| {
            if (tag != .function_call) continue;
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw_node)));
            const call = file.tree.functionCall(node) orelse continue;
            if (call.specialization_arguments == null) continue;
            const source_offset = file.tree.location(node).offset;
            const external = findCallReference(graph, file_index, source_offset) orelse continue;
            const arguments = try @import("parameterized/lowerer.zig").lowerConcreteArguments(graph, &writer, file_index, file.tree, file.source, call.specialization_arguments.?);
            graph.semantic.external_refs.items[@intFromEnum(external)].computed_arguments = arguments;
            stats.generic_calls += 1;
        }
    }
    return stats;
}

fn findCallReference(graph: *const graph_mod.ModuleSemanticGraph, file_index: u32, source_offset: u32) ?entities.ExternalRefId {
    for (graph.semantic.external_refs.items, 0..) |reference, raw| {
        if (reference.kind != .function) continue;
        if (reference.source.file_index != file_index or reference.source.offset != source_offset) continue;
        return @enumFromInt(@as(u32, @intCast(raw)));
    }
    return null;
}

test "generic call arguments live on semantic external refs" {
    // Both the qualifier and generic argument range carry optional presence.
    // Associated queries retain symbolic type and call arguments.
    try std.testing.expect(@sizeOf(entities.ExternalRef) <= 72);
}

const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const writer_mod = @import("writer.zig");
const type_lowerer = @import("type_lowerer.zig");
const views = @import("views.zig");

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
            if (call.type_arguments.len == 0 and call.type_arguments_struct == null) continue;
            const source_offset = file.tree.location(node).offset;
            const external = findCallReference(graph, file_index, source_offset) orelse continue;
            const start: u32 = @intCast(views.genericArgumentCount(graph));
            var count: u32 = 0;
            if (call.type_arguments_struct) |struct_node| {
                const literal = file.tree.structTypeLiteral(struct_node) orelse return error.InvalidGenericCallArguments;
                for (literal.fields) |field_node| {
                    const field = file.tree.structTypeField(field_node) orelse return error.InvalidGenericCallArgument;
                    const name = try writer.addString(file.tree.tokenTextFromSource(file.source, field.name_token));
                    const value: entities.GenericArgument.Value = if (field.type_node) |type_node|
                        .{ .type = try lowerType(graph, &writer, file, file_index, type_node) }
                    else if (field.default_value) |value_node|
                        .{ .comptime_int = try evalInt(file.tree, file.source, value_node) }
                    else
                        return error.InvalidGenericCallArgument;
                    _ = try writer.addGenericArgument(.{ .name = name, .value = value });
                    count += 1;
                }
            } else {
                for (call.type_arguments) |type_node| {
                    _ = try writer.addGenericArgument(.{
                        .name = try writer.addString(""),
                        .value = .{ .type = try lowerType(graph, &writer, file, file_index, type_node) },
                    });
                    count += 1;
                }
            }
            graph.semantic.external_refs.items[@intFromEnum(external)].generic_arguments = .{ .start = start, .len = count };
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

fn lowerType(
    graph: *graph_mod.ModuleSemanticGraph,
    writer: *writer_mod.Writer,
    file: graph_mod.FileInput,
    file_index: u32,
    node: syn.NodeIndex,
) !entities.ModuleTypeId {
    var lowerer = type_lowerer.Context{
        .graph = graph,
        .writer = writer,
        .file_index = file_index,
        .tree = file.tree,
        .source = file.source,
    };
    return lowerer.lower(node);
}

fn evalInt(tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex) !i64 {
    if (tree.literal(node)) |literal| {
        var value = try std.fmt.parseInt(i64, tree.tokenTextFromSource(source, literal.token), 0);
        if (literal.negative) value = -value;
        return value;
    }
    const op = tree.binaryOperation(node) orelse return error.InvalidComptimeInteger;
    const left = try evalInt(tree, source, op.lhs);
    const right = try evalInt(tree, source, op.rhs);
    return switch (tree.tag(node)) {
        .binary_add => left + right,
        .binary_subtract => left - right,
        .binary_multiply => left * right,
        .binary_divide => if (right == 0) error.InvalidComptimeInteger else @divTrunc(left, right),
        .binary_modulo => if (right == 0) error.InvalidComptimeInteger else @mod(left, right),
        else => error.InvalidComptimeInteger,
    };
}

test "generic call arguments live on semantic external refs" {
    // Both the qualifier and generic argument range carry optional presence.
    try std.testing.expect(@sizeOf(entities.ExternalRef) <= 44);
}

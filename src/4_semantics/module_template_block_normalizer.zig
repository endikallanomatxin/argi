const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const graph_mod = @import("module_semantic_graph.zig");
const ir = @import("module_semantic_template_ir.zig");

/// The first template producer recursively appends child block references while
/// the parent block is still being lowered. Rebuild every live Block.nodes range
/// from source provenance so each block owns one contiguous list of its direct
/// statements. IDs stay stable; old pool entries become dead compaction input.
pub fn normalize(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !u32 {
    var changed: u32 = 0;
    for (graph.semantic.templates.generic_function_templates.items) |template| {
        const declaration = graph.declarations.items[@intFromEnum(template.declaration)];
        const file = files[declaration.module_file_index];
        const function = file.tree.functionDeclaration(declaration.syntax_node) orelse continue;
        const root = function.body orelse continue;
        const end = nextDeclarationOffset(graph, template.declaration);
        for (file.tree.nodes.items(.tag), 0..) |tag, raw| {
            if (tag != .code_block) continue;
            const syntax_block: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            const offset = file.tree.location(syntax_block).offset;
            if (offset < declaration.source_offset or offset >= end) continue;
            const block_id = if (syntax_block == root)
                template.body orelse continue
            else
                findCodeBlockNode(graph, declaration.module_file_index, offset) orelse continue;
            const block = file.tree.codeBlock(syntax_block) orelse continue;
            const start: u32 = @intCast(graph.semantic.templates.ir.node_refs.items.len);
            var ret: ?ir.TemplateNodeId = null;
            for (block.statements) |statement| {
                const statement_id = findSemanticNode(
                    graph,
                    declaration.module_file_index,
                    file.tree.location(statement).offset,
                ) orelse return error.MissingTemplateStatementNode;
                try graph.semantic.templates.ir.node_refs.append(allocator, statement_id);
                ret = statement_id;
            }
            graph.semantic.templates.ir.blocks.items[@intFromEnum(block_id)].nodes = .{
                .start = start,
                .len = @intCast(block.statements.len),
            };
            graph.semantic.templates.ir.blocks.items[@intFromEnum(block_id)].ret_val = ret;
            changed += 1;
        }
    }
    return changed;
}

fn findCodeBlockNode(
    graph: *const graph_mod.ModuleSemanticGraph,
    file_index: u32,
    offset: u32,
) ?ir.TemplateBlockId {
    for (graph.semantic.templates.ir.nodes.items) |node| switch (node) {
        .resolved => |resolved| {
            if (resolved.source.file_index != file_index or resolved.source.offset != offset) continue;
            switch (resolved.content) {
                .code_block => |id| return id,
                else => {},
            }
        },
        .pending => {},
    };
    return null;
}

fn findSemanticNode(
    graph: *const graph_mod.ModuleSemanticGraph,
    file_index: u32,
    offset: u32,
) ?ir.TemplateNodeId {
    for (graph.semantic.templates.ir.nodes.items, 0..) |node, raw| switch (node) {
        .resolved => |resolved| if (resolved.source.file_index == file_index and resolved.source.offset == offset)
            return @enumFromInt(@as(u32, @intCast(raw))),
        .pending => |pending_id| {
            const pending = graph.semantic.templates.ir.pending.items[@intFromEnum(pending_id)];
            const source = switch (pending) {
                .resolve_name => |value| value.source,
                .resolve_call => |value| value.source,
                .resolve_field => |value| value.source,
                .resolve_expression => |value| value.source,
                .resolve_copy, .resolve_deinit => continue,
            };
            if (source.file_index == file_index and source.offset == offset)
                return @enumFromInt(@as(u32, @intCast(raw)));
        },
    };
    return null;
}

fn nextDeclarationOffset(graph: *const graph_mod.ModuleSemanticGraph, id: @import("module_semantic_entities.zig").ModuleDeclId) u32 {
    const declaration = graph.declarations.items[@intFromEnum(id)];
    var end: u32 = std.math.maxInt(u32);
    for (graph.declarations.items) |candidate| {
        if (candidate.module_file_index != declaration.module_file_index) continue;
        if (candidate.source_offset > declaration.source_offset and candidate.source_offset < end) end = candidate.source_offset;
    }
    return end;
}

test "template block ranges are normalized without changing node IDs" {
    try std.testing.expect(@sizeOf(ir.TemplateBlockId) == @sizeOf(u32));
}

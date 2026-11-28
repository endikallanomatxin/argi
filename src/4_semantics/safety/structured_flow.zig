//! Structured statement edges in the specialized semantic graph.
//! Expression transfers are lowered separately, including short circuit
//! evaluation and exceptional exits inside expressions.
const std = @import("std");
const graph = @import("../global/graph.zig");
const SemanticLoop = @import("finite_dataflow.zig").SemanticLoop;

pub const Flow = struct {
    pub const Block = struct {
        action: union(enum) {
            none,
            statement: graph.GlobalNodeId,
            condition: struct { expression: graph.GlobalNodeId, statement: graph.GlobalNodeId },
        },
        // A condition has true and false destinations in that order.
        successors: [2]?usize,
    };

    blocks: []const Block,
    entry: usize,

    pub fn lower(allocator: std.mem.Allocator, semantic: *const graph.GlobalSemanticGraph, body: graph.GlobalBlockId) !Flow {
        var builder: Builder = .{ .allocator = allocator, .semantic = semantic };
        defer builder.blocks.deinit(allocator);
        const exit = try builder.append(.{ .action = .none, .successors = .{ null, null } });
        const entry = try builder.lowerBlock(body, exit, null);
        return .{ .blocks = try builder.blocks.toOwnedSlice(allocator), .entry = entry };
    }

    pub fn deinit(self: Flow, allocator: std.mem.Allocator) void {
        allocator.free(self.blocks);
    }
};

const Builder = struct {
    allocator: std.mem.Allocator,
    semantic: *const graph.GlobalSemanticGraph,
    blocks: std.ArrayList(Flow.Block) = .empty,

    const LoopTargets = struct { on_break: usize, on_continue: usize };

    fn append(self: *Builder, block: Flow.Block) !usize {
        const index = self.blocks.items.len;
        try self.blocks.append(self.allocator, block);
        return index;
    }

    fn lowerBlock(self: *Builder, id: graph.GlobalBlockId, exit: usize, loop: ?LoopTargets) anyerror!usize {
        const block = self.semantic.blocks.items[@intFromEnum(id)];
        const nodes = self.semantic.node_refs.items[block.nodes.start..][0..block.nodes.len];
        var next = exit;
        var index = nodes.len;
        while (index != 0) {
            index -= 1;
            next = try self.lowerNode(nodes[index], next, loop);
        }
        return next;
    }

    fn lowerNode(self: *Builder, id: graph.GlobalNodeId, next: usize, parent: ?LoopTargets) anyerror!usize {
        const node = self.semantic.node(id);
        switch (node.content) {
            .while_statement, .for_statement => {
                const loop = SemanticLoop.fromNode(node);
                const header = try self.append(.{ .action = .{ .condition = .{ .expression = loop.control.condition, .statement = id } }, .successors = .{ null, next } });
                const increment = if (loop.control.increment) |advance| try self.lowerNode(advance, header, parent) else header;
                const body = try self.lowerBlock(loop.body, increment, .{ .on_break = next, .on_continue = increment });
                self.blocks.items[header].successors[0] = body;
                return if (loop.initializer) |init| self.lowerNode(init, header, parent) else header;
            },
            .if_statement => |branch| {
                const take = try self.lowerBlock(branch.then_block, next, parent);
                const skip = if (branch.else_block) |other| try self.lowerBlock(other, next, parent) else next;
                return self.append(.{ .action = .{ .condition = .{ .expression = branch.condition, .statement = id } }, .successors = .{ take, skip } });
            },
            .code_block => |block| return self.lowerBlock(block, next, parent),
            .break_statement => return (parent orelse return error.InvalidLoopControl).on_break,
            .continue_statement => return (parent orelse return error.InvalidLoopControl).on_continue,
            .return_statement, .abort_statement => return self.append(.{ .action = .{ .statement = id }, .successors = .{ null, null } }),
            .switch_statement => return error.UnsupportedStructuredFlow,
            else => return self.append(.{ .action = .{ .statement = id }, .successors = .{ next, null } }),
        }
    }
};

test "safety structured flow routes continue through the increment and break past the loop" {
    const a = std.testing.allocator;
    var semantic: graph.GlobalSemanticGraph = .{};
    defer semantic.deinit(a);
    const source: @FieldType(graph.Node, "source") = .{ .file_index = 0, .offset = 0 };
    try semantic.nodes.appendSlice(a, &.{
        .{ .ty = null, .source = source, .content = .{ .bool_literal = true } },
        .{ .ty = null, .source = source, .content = .{ .bool_literal = false } },
        .{ .ty = null, .source = source, .content = .continue_statement },
        .{ .ty = null, .source = source, .content = .break_statement },
        .{ .ty = null, .source = source, .content = .{ .if_statement = .{
            .condition = @enumFromInt(0),
            .then_block = @enumFromInt(2),
            .else_block = @enumFromInt(3),
        } } },
        .{ .ty = null, .source = source, .content = .{ .for_statement = .{
            .init = null,
            .condition = @enumFromInt(0),
            .increment = @enumFromInt(1),
            .body = @enumFromInt(1),
        } } },
    });
    try semantic.node_refs.appendSlice(a, &.{ @enumFromInt(5), @enumFromInt(4), @enumFromInt(2), @enumFromInt(3) });
    for (0..4) |index| try semantic.blocks.append(a, .{ .nodes = .{ .start = @intCast(index), .len = 1 } });
    const flow = try Flow.lower(a, &semantic, @enumFromInt(0));
    defer flow.deinit(a);
    const header = flow.blocks[flow.entry];
    const branch = flow.blocks[header.successors[0].?];
    const increment = flow.blocks[branch.successors[0].?];
    try std.testing.expectEqual(@as(graph.GlobalNodeId, @enumFromInt(1)), increment.action.statement);
    try std.testing.expectEqual(flow.entry, increment.successors[0].?);
    try std.testing.expectEqual(header.successors[1], branch.successors[1]);
}

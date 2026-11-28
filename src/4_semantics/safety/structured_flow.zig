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
            switch_value: graph.GlobalSwitchId,
            switch_case: struct { selection: graph.GlobalSwitchId, case: graph.GlobalSwitchCaseId },
        },
        // Tests have matching and nonmatching destinations in that order.
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
                const header = try self.append(.{ .action = .none, .successors = .{ null, null } });
                const increment = if (loop.control.increment) |advance| try self.lowerNode(advance, header, parent) else header;
                const body = try self.lowerBlock(loop.body, increment, .{ .on_break = next, .on_continue = increment });
                const condition = try self.lowerCondition(loop.control.condition, id, body, next);
                self.blocks.items[header].successors[0] = condition;
                return if (loop.initializer) |init| self.lowerNode(init, header, parent) else header;
            },
            .if_statement => |branch| {
                const take = try self.lowerBlock(branch.then_block, next, parent);
                const skip = if (branch.else_block) |other| try self.lowerBlock(other, next, parent) else next;
                return self.lowerCondition(branch.condition, id, take, skip);
            },
            .code_block => |block| return self.lowerBlock(block, next, parent),
            .break_statement => return (parent orelse return error.InvalidLoopControl).on_break,
            .continue_statement => return (parent orelse return error.InvalidLoopControl).on_continue,
            .return_statement, .abort_statement => return self.append(.{ .action = .{ .statement = id }, .successors = .{ null, null } }),
            .switch_statement => |selection| return self.lowerSwitch(selection, next, parent),
            else => return self.append(.{ .action = .{ .statement = id }, .successors = .{ next, null } }),
        }
    }

    fn lowerCondition(self: *Builder, expression: graph.GlobalNodeId, statement: graph.GlobalNodeId, take: usize, skip: usize) anyerror!usize {
        switch (self.semantic.node(expression).content) {
            .logical_operation => |logic| {
                const right = try self.lowerCondition(logic.right, statement, take, skip);
                return switch (logic.operator) {
                    .and_ => self.lowerCondition(logic.left, statement, right, skip),
                    .or_ => self.lowerCondition(logic.left, statement, take, right),
                };
            },
            else => return self.append(.{
                .action = .{ .condition = .{ .expression = expression, .statement = statement } },
                .successors = .{ take, skip },
            }),
        }
    }

    fn lowerSwitch(self: *Builder, id: graph.GlobalSwitchId, next: usize, parent: ?LoopTargets) anyerror!usize {
        const selection = self.semantic.switches.items[@intFromEnum(id)];
        var unmatched: ?usize = if (selection.default_block) |default|
            try self.lowerBlock(default, next, parent)
        else if (selection.exhaustive)
            null
        else
            next;
        var remaining = selection.cases.len;
        while (remaining != 0) {
            remaining -= 1;
            const index = selection.cases.start + remaining;
            const case = self.semantic.switch_cases.items[index];
            const matched = try self.lowerBlock(case.body, next, parent);
            unmatched = try self.append(.{
                .action = .{ .switch_case = .{ .selection = id, .case = @enumFromInt(index) } },
                .successors = .{ matched, unmatched },
            });
        }
        return self.append(.{ .action = .{ .switch_value = id }, .successors = .{ unmatched, null } });
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
    const header = flow.blocks[flow.blocks[flow.entry].successors[0].?];
    const branch = flow.blocks[header.successors[0].?];
    const increment = flow.blocks[branch.successors[0].?];
    try std.testing.expectEqual(@as(graph.GlobalNodeId, @enumFromInt(1)), increment.action.statement);
    try std.testing.expectEqual(flow.entry, increment.successors[0].?);
    try std.testing.expectEqual(header.successors[1], branch.successors[1]);
}

test "safety structured switch preserves case identity and evaluates its subject once" {
    const a = std.testing.allocator;
    var semantic: graph.GlobalSemanticGraph = .{};
    defer semantic.deinit(a);
    const source: @FieldType(graph.Node, "source") = .{ .file_index = 0, .offset = 0 };
    try semantic.nodes.appendSlice(a, &.{
        .{ .ty = null, .source = source, .content = .{ .bool_literal = true } },
        .{ .ty = null, .source = source, .content = .{ .switch_statement = @enumFromInt(0) } },
        .{ .ty = null, .source = source, .content = .abort_statement },
    });
    try semantic.node_refs.appendSlice(a, &.{ @enumFromInt(1), @enumFromInt(2) });
    try semantic.blocks.appendSlice(a, &.{
        .{ .nodes = .{ .start = 0, .len = 1 } },
        .{ .nodes = .{ .start = 1, .len = 1 } },
    });
    try semantic.switch_cases.append(a, .{
        .value = @enumFromInt(0),
        .variant = @enumFromInt(0),
        .body = @enumFromInt(1),
        .payload_binding = @enumFromInt(0),
    });
    try semantic.switches.append(a, .{
        .expression = @enumFromInt(0),
        .cases = .{ .start = 0, .len = 1 },
        .default_block = null,
        .exhaustive = true,
    });
    const flow = try Flow.lower(a, &semantic, @enumFromInt(0));
    defer flow.deinit(a);
    const entry = flow.blocks[flow.entry];
    const case = flow.blocks[entry.successors[0].?];
    try std.testing.expectEqual(@as(graph.GlobalSwitchId, @enumFromInt(0)), entry.action.switch_value);
    try std.testing.expectEqual(@as(graph.GlobalSwitchCaseId, @enumFromInt(0)), case.action.switch_case.case);
    try std.testing.expectEqual(null, case.successors[1]);
    try std.testing.expectEqual(@as(graph.GlobalNodeId, @enumFromInt(2)), flow.blocks[case.successors[0].?].action.statement);
}

test "safety structured conditions route short circuit edges around the right operand" {
    const a = std.testing.allocator;
    var semantic: graph.GlobalSemanticGraph = .{};
    defer semantic.deinit(a);
    const source: @FieldType(graph.Node, "source") = .{ .file_index = 0, .offset = 0 };
    try semantic.nodes.appendSlice(a, &.{
        .{ .ty = null, .source = source, .content = .{ .bool_literal = true } },
        .{ .ty = null, .source = source, .content = .{ .bool_literal = false } },
        .{ .ty = null, .source = source, .content = .{ .logical_operation = .{ .operator = .and_, .left = @enumFromInt(0), .right = @enumFromInt(1) } } },
    });
    var builder: Builder = .{ .allocator = a, .semantic = &semantic };
    defer builder.blocks.deinit(a);
    const take = try builder.append(.{ .action = .none, .successors = .{ null, null } });
    const skip = try builder.append(.{ .action = .none, .successors = .{ null, null } });
    for ([_]bool{ true, false }) |is_and| {
        semantic.nodes.items[2].content.logical_operation.operator = if (is_and) .and_ else .or_;
        const entry = try builder.lowerCondition(@enumFromInt(2), @enumFromInt(2), take, skip);
        const left = builder.blocks.items[entry];
        const right = builder.blocks.items[left.successors[if (is_and) 0 else 1].?];
        try std.testing.expectEqual(@as(graph.GlobalNodeId, @enumFromInt(0)), left.action.condition.expression);
        try std.testing.expectEqual(@as(graph.GlobalNodeId, @enumFromInt(1)), right.action.condition.expression);
        try std.testing.expectEqual(if (is_and) skip else take, left.successors[if (is_and) 1 else 0].?);
        try std.testing.expectEqual([2]?usize{ take, skip }, right.successors);
    }
}

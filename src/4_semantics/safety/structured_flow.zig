//! Structured statement edges in the specialized semantic graph.
//! Expression transfers are lowered separately, including short circuit
//! evaluation and exceptional exits inside expressions.
const std = @import("std");
const primitives = @import("../primitives/schema.zig");
const types = @import("../global/types.zig");
const graph = @import("../global/graph.zig");
const SemanticLoop = @import("finite_dataflow.zig").SemanticLoop;

pub const Flow = struct {
    pub const Block = struct {
        pub const Action = union(enum) {
            none,
            statement: graph.GlobalNodeId,
            condition: struct {
                expression: graph.GlobalNodeId,
                statement: graph.GlobalNodeId,
                choice_test: ?primitives.ChoiceTagTest(graph.Ids) = null,
            },
            switch_value: graph.GlobalSwitchId,
            switch_case: struct { selection: graph.GlobalSwitchId, case: graph.GlobalSwitchCaseId },
        };
        action: Action,
        // Tests have matching and nonmatching destinations in that order.
        successors: [2]?usize,
    };

    pub const Edge = struct {
        destination: usize,
        outcome: enum { unconditional, matched, unmatched },
    };

    /// Keep edge polarity even when one branch is absent. In particular,
    /// an exhaustive switch's final test has no unmatched continuation.
    pub fn edges(self: Flow, index: usize, buffer: *[2]Edge) []const Edge {
        const block = self.blocks[index];
        const conditional = switch (block.action) {
            .condition, .switch_case => true,
            else => false,
        };
        var len: usize = 0;
        for (block.successors, 0..) |target, ordinal| {
            const destination = target orelse continue;
            buffer[len] = .{
                .destination = destination,
                .outcome = if (!conditional) .unconditional else if (ordinal == 0) .matched else .unmatched,
            };
            len += 1;
        }
        return buffer[0..len];
    }

    blocks: []const Block,
    entry: usize,

    pub fn lower(allocator: std.mem.Allocator, semantic: *const graph.GlobalSemanticGraph, body: graph.GlobalBlockId) !Flow {
        var builder: Builder = .{ .allocator = allocator, .semantic = semantic };
        defer builder.blocks.deinit(allocator);
        const exit = try builder.append(.{ .action = .none, .successors = .{ null, null } });
        const entry = try builder.lowerBlock(body, exit, null);
        return .{ .blocks = try builder.blocks.toOwnedSlice(allocator), .entry = entry };
    }

    /// Solve a lowered body using the operation semantics of a finite
    /// domain. The transfer receives the selected edge, including its
    /// polarity, and can omit an infeasible successor.
    pub fn solve(self: Flow, comptime Domain: type, allocator: std.mem.Allocator, headers: []?Domain.State, initial: Domain.State, domain: Domain) !void {
        const Adapter = struct {
            const Self = @This();
            pub const State = Domain.State;

            flow: Flow,
            semantics: Domain,
            buffer: *[2]Edge,

            pub fn successors(adapter: Self, block: usize) []const Edge {
                return adapter.flow.edges(block, adapter.buffer);
            }

            pub fn target(_: Self, edge: Edge) usize {
                return edge.destination;
            }

            pub fn transfer(adapter: Self, block: usize, edge: Edge, state: State) !?State {
                return adapter.semantics.transfer(adapter.flow.blocks[block].action, edge, state);
            }

            pub fn covers(adapter: Self, left: State, right: State) bool {
                return adapter.semantics.covers(left, right);
            }

            pub fn include(adapter: Self, left: *State, right: State) !void {
                try adapter.semantics.include(left, right);
            }

            pub fn release(adapter: Self, state: State) void {
                adapter.semantics.release(state);
            }
        };
        if (headers.len != self.blocks.len or self.entry >= headers.len) {
            domain.release(initial);
            return error.InvalidFiniteGraph;
        }
        for (headers) |header| if (header != null) {
            domain.release(initial);
            return error.InvalidFiniteGraph;
        };
        var buffer: [2]Edge = undefined;
        const adapter: Adapter = .{ .flow = self, .semantics = domain, .buffer = &buffer };
        try @import("finite_dataflow.zig").solve(Adapter, allocator, headers, self.entry, initial, adapter);
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
            .return_statement, .abort_statement => {
                // Even without a lexical continuation, the statement can
                // evaluate a value and perform cleanup. Its private exit
                // keeps that transfer separate from normal fallthrough.
                const terminal = try self.append(.{ .action = .none, .successors = .{ null, null } });
                return self.append(.{ .action = .{ .statement = id }, .successors = .{ terminal, null } });
            },
            .switch_statement => |selection| return self.lowerSwitch(selection, next, parent),
            else => return self.append(.{ .action = .{ .statement = id }, .successors = .{ next, null } }),
        }
    }

    fn lowerCondition(self: *Builder, expression: graph.GlobalNodeId, statement: graph.GlobalNodeId, take: usize, skip: usize) anyerror!usize {
        switch (self.semantic.node(expression).content) {
            .bool_literal => |value| return if (value) take else skip,
            .logical_operation => |logic| {
                const right = try self.lowerCondition(logic.right, statement, take, skip);
                return switch (logic.operator) {
                    .and_ => self.lowerCondition(logic.left, statement, right, skip),
                    .or_ => self.lowerCondition(logic.left, statement, take, right),
                };
            },
            else => return self.append(.{
                .action = .{ .condition = .{
                    .expression = expression,
                    .statement = statement,
                    .choice_test = self.conditionChoiceTest(expression, statement),
                } },
                .successors = .{ take, skip },
            }),
        }
    }

    fn conditionChoiceTest(self: *Builder, expression: graph.GlobalNodeId, statement: graph.GlobalNodeId) ?primitives.ChoiceTagTest(graph.Ids) {
        if (self.semantic.node(statement).content == .if_statement) {
            const branch = self.semantic.node(statement).content.if_statement;
            if (branch.condition == expression) if (branch.choice_test) |test_info| return test_info;
        }
        return choiceTestFromCondition(self.semantic, expression);
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

pub fn choiceTestFromCondition(semantic: *const graph.GlobalSemanticGraph, node_id: graph.GlobalNodeId) ?primitives.ChoiceTagTest(graph.Ids) {
    const comparison = switch (semantic.nodes.items[@intFromEnum(node_id)].content) {
        .comparison => |value| value,
        else => return null,
    };
    if (comparison.operator != .equal and comparison.operator != .not_equal) return null;

    var choice_node = comparison.left;
    var tag_node = comparison.right;
    const tag = switch (semantic.nodes.items[@intFromEnum(tag_node)].content) {
        .int_literal => |value| value,
        else => blk: {
            choice_node = comparison.right;
            tag_node = comparison.left;
            break :blk switch (semantic.nodes.items[@intFromEnum(tag_node)].content) {
                .int_literal => |value| value,
                else => return null,
            };
        },
    };

    const choice_type = semantic.nodes.items[@intFromEnum(choice_node)].ty orelse return null;
    const variants = types.variants(semantic, choice_type) orelse return null;
    for (0..variants.len) |offset| {
        const raw = variants.start + @as(u32, @intCast(offset));
        if (semantic.variants.items[raw].value != tag) continue;
        return .{
            .choice_value = choice_node,
            .choice_type = choice_type,
            .variant = @enumFromInt(raw),
            .then_has_variant = comparison.operator == .equal,
        };
    }
    return null;
}

test "safety structured flow routes continue through the increment and break past the loop" {
    const a = std.testing.allocator;
    var semantic: graph.GlobalSemanticGraph = .{};
    defer semantic.deinit(a);
    const source: @FieldType(graph.Node, "source") = .{ .file_index = 0, .offset = 0 };
    try semantic.nodes.appendSlice(a, &.{
        .{ .ty = null, .source = source, .content = .{ .binding_use = @enumFromInt(0) } },
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
    var edge_buffer: [2]Flow.Edge = undefined;
    const dispatch_edges = flow.edges(flow.entry, &edge_buffer);
    try std.testing.expectEqual(@as(usize, 1), dispatch_edges.len);
    try std.testing.expectEqual(.unconditional, dispatch_edges[0].outcome);
    const case_edges = flow.edges(entry.successors[0].?, &edge_buffer);
    try std.testing.expectEqual(@as(usize, 1), case_edges.len);
    try std.testing.expectEqual(.matched, case_edges[0].outcome);
    try std.testing.expectEqual(null, case.successors[1]);
    const abort = flow.blocks[case.successors[0].?];
    try std.testing.expectEqual(@as(graph.GlobalNodeId, @enumFromInt(2)), abort.action.statement);
    try std.testing.expect(abort.successors[0].? != 0);
    try std.testing.expectEqual([2]?usize{ null, null }, flow.blocks[abort.successors[0].?].successors);
}

test "safety structured conditions route short circuit edges around the right operand" {
    const a = std.testing.allocator;
    var semantic: graph.GlobalSemanticGraph = .{};
    defer semantic.deinit(a);
    const source: @FieldType(graph.Node, "source") = .{ .file_index = 0, .offset = 0 };
    try semantic.nodes.appendSlice(a, &.{
        .{ .ty = null, .source = source, .content = .{ .binding_use = @enumFromInt(0) } },
        .{ .ty = null, .source = source, .content = .{ .binding_use = @enumFromInt(1) } },
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

test "safety structured false conjunction bypasses an unreachable right operand" {
    const a = std.testing.allocator;
    var semantic: graph.GlobalSemanticGraph = .{};
    defer semantic.deinit(a);
    const source: @FieldType(graph.Node, "source") = .{ .file_index = 0, .offset = 0 };
    try semantic.nodes.appendSlice(a, &.{
        .{ .ty = null, .source = source, .content = .{ .bool_literal = false } },
        .{ .ty = null, .source = source, .content = .{ .binding_use = @enumFromInt(0) } },
        .{ .ty = null, .source = source, .content = .{ .logical_operation = .{ .operator = .and_, .left = @enumFromInt(0), .right = @enumFromInt(1) } } },
    });
    var builder: Builder = .{ .allocator = a, .semantic = &semantic };
    defer builder.blocks.deinit(a);
    const take = try builder.append(.{ .action = .none, .successors = .{ null, null } });
    const skip = try builder.append(.{ .action = .none, .successors = .{ null, null } });
    try std.testing.expectEqual(skip, try builder.lowerCondition(@enumFromInt(2), @enumFromInt(2), take, skip));
}

test "safety structured flow solves only feasible branch edges" {
    const Domain = struct {
        pub const State = u8;

        fn transfer(_: @This(), action: Flow.Block.Action, edge: Flow.Edge, state: State) error{}!?State {
            if (action == .condition and edge.outcome == .unmatched) return null;
            return state | 2;
        }

        fn covers(_: @This(), left: State, right: State) bool {
            return left & right == right;
        }

        fn include(_: @This(), left: *State, right: State) error{}!void {
            left.* |= right;
        }

        fn release(_: @This(), _: State) void {}
    };
    const flow: Flow = .{ .entry = 0, .blocks = &.{
        .{ .action = .{ .condition = .{ .expression = @enumFromInt(0), .statement = @enumFromInt(1) } }, .successors = .{ 1, 2 } },
        .{ .action = .none, .successors = .{ 0, null } },
        .{ .action = .none, .successors = .{ null, null } },
    } };
    var headers: [3]?Domain.State = @splat(null);
    try flow.solve(Domain, std.testing.allocator, &headers, 1, .{});
    try std.testing.expectEqual([3]?Domain.State{ 3, 3, null }, headers);
}

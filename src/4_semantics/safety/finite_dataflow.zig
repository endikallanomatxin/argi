//! Forward solver for finite safety domains. A domain supplies a monotone
//! edge transfer, coverage and a least upper bound on states.
const std = @import("std");

/// The control transfers of a structured loop. Entry has already
/// executed any initializer. Only fallthrough and continue run the
/// increment and re-test. A break bypasses both.
pub fn LoopControl(comptime Node: type) type {
    return struct {
        condition: Node,
        increment: ?Node = null,

        pub const Edge = enum { entry, backedge, loop_break };
        pub const Step = union(enum) { none, increment: Node, condition: Node };

        pub fn steps(self: @This(), edge: Edge) [2]Step {
            return switch (edge) {
                .entry => .{ .none, .{ .condition = self.condition } },
                .backedge => .{
                    if (self.increment) |node| .{ .increment = node } else .none,
                    .{ .condition = self.condition },
                },
                .loop_break => .{ .none, .none },
            };
        }
    };
}

/// Structure and evaluation order from the specialized semantic graph.
pub const SemanticLoop = struct {
    const graph = @import("../global/graph.zig");
    initializer: ?graph.GlobalNodeId = null,
    body: graph.GlobalBlockId,
    control: LoopControl(graph.GlobalNodeId),

    pub fn fromNode(node: graph.Node) SemanticLoop {
        return switch (node.content) {
            .while_statement => |loop| .{ .body = loop.body, .control = .{ .condition = loop.condition } },
            .for_statement => |loop| .{
                .initializer = loop.init,
                .body = loop.body,
                .control = .{ .condition = loop.condition, .increment = loop.increment },
            },
            else => unreachable,
        };
    }
};

test "safety loop control separates entry, backedge and break effects" {
    const loop: LoopControl(u8) = .{ .condition = 5, .increment = 7 };
    try std.testing.expectEqualDeep([2]@TypeOf(loop).Step{ .none, .{ .condition = 5 } }, loop.steps(.entry));
    try std.testing.expectEqualDeep([2]@TypeOf(loop).Step{ .{ .increment = 7 }, .{ .condition = 5 } }, loop.steps(.backedge));
    try std.testing.expectEqualDeep([2]@TypeOf(loop).Step{ .none, .none }, loop.steps(.loop_break));
}

/// Reachability is represented by optional headers. The caller supplies
/// empty headers, an entry state, and fixed successors for each block.
/// Transfer takes a read-only snapshot and returns an independently
/// owned state. Inclusion updates a destination with the least upper
/// bound of both states. The domain releases
/// discarded states. The caller owns every published header, including
/// the entry state and any headers published before an error.
pub fn solve(
    comptime Domain: type,
    allocator: std.mem.Allocator,
    headers: []?Domain.State,
    entry: usize,
    initial: Domain.State,
    domain: Domain,
) !void {
    headers[entry] = initial;
    const queued = try allocator.alloc(bool, headers.len);
    defer allocator.free(queued);
    @memset(queued, false);
    const pending = try allocator.alloc(usize, headers.len);
    defer allocator.free(pending);
    var count: usize = 1;
    pending[0] = entry;
    queued[entry] = true;

    while (count != 0) {
        count -= 1;
        const block = pending[count];
        queued[block] = false;
        const input = headers[block].?;
        var replaced_input = false;
        defer if (replaced_input) domain.release(input);
        for (domain.successors(block)) |edge| {
            const successor = domain.target(edge);
            var next = (try domain.transfer(block, edge, input)) orelse continue;
            var next_owned = true;
            defer if (next_owned) domain.release(next);
            if (headers[successor]) |*previous| {
                if (domain.covers(previous.*, next)) continue;
                if (successor == block and !replaced_input) {
                    // Other edges still read the original header. Reuse
                    // the incoming allocation as its replacement.
                    try domain.include(&next, previous.*);
                    previous.* = next;
                    next_owned = false;
                    replaced_input = true;
                } else {
                    try domain.include(previous, next);
                }
            } else {
                headers[successor] = next;
                next_owned = false;
            }
            if (queued[successor]) continue;
            pending[count] = successor;
            queued[successor] = true;
            count += 1;
        }
    }
}

test "finite safety worklist covers a backedge and preserves its stale observation" {
    const Observation = @import("loop_observation.zig").Observation;
    const Initialization = @import("value_state.zig").Initialization;
    const Domain = struct {
        const State = struct {
            saved: Observation = .{},
            current: Observation = .{},
            slot: Initialization = .{ .deinitialized = true },
        };

        fn release(_: @This(), _: State) void {}

        fn successors(_: @This(), block: usize) []const usize {
            return switch (block) {
                0 => &.{1},
                1 => &.{ 1, 2 },
                else => &.{},
            };
        }

        fn target(_: @This(), successor: usize) usize {
            return successor;
        }

        fn transfer(_: @This(), block: usize, destination: usize, input: State) error{}!?State {
            if (block == 1 and destination == 2) return input;
            return .{
                .saved = input.saved.join(input.current).age(),
                .current = .{ .current_live = true },
                .slot = input.slot.weakWrite(.{ .initialized = true }),
            };
        }

        fn covers(_: @This(), left: State, right: State) bool {
            return left.saved.covers(right.saved) and left.current.covers(right.current) and left.slot.covers(right.slot);
        }

        fn include(_: @This(), left: *State, right: State) error{}!void {
            left.* = .{
                .saved = left.saved.join(right.saved),
                .current = left.current.join(right.current),
                .slot = left.slot.join(right.slot),
            };
        }
    };

    var headers: [3]?Domain.State = @splat(null);
    const domain: Domain = .{};
    try solve(Domain, std.testing.allocator, &headers, 0, .{}, domain);
    const header = headers[1].?;
    const after = headers[2].?;
    try std.testing.expect(domain.covers(header, (try domain.transfer(1, 1, header)).?));
    try std.testing.expectEqual(header, after);
    try std.testing.expect(after.saved.historical);
    try std.testing.expect(!after.saved.provesCurrent());
    try std.testing.expect(after.current.provesCurrent());
    try std.testing.expect(after.slot.initialized and after.slot.deinitialized);
    try std.testing.expect(!after.slot.definitelyInitialized());
}

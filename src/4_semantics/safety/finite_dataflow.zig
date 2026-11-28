//! Forward solver for finite safety domains. A domain supplies a monotone
//! edge transfer, coverage and a least upper bound on states.
const std = @import("std");

/// Reachability is represented by optional headers. The caller supplies
/// empty headers, an entry state, and fixed successors for each block.
/// State payloads must be immutable so edge transfers can read a snapshot,
/// including on self edges.
pub fn solve(
    comptime Domain: type,
    allocator: std.mem.Allocator,
    headers: []?Domain.State,
    entry: usize,
    initial: Domain.State,
    domain: Domain,
) !void {
    const queued = try allocator.alloc(bool, headers.len);
    defer allocator.free(queued);
    @memset(queued, false);
    const pending = try allocator.alloc(usize, headers.len);
    defer allocator.free(pending);
    var count: usize = 1;
    pending[0] = entry;
    queued[entry] = true;
    headers[entry] = initial;

    while (count != 0) {
        count -= 1;
        const block = pending[count];
        queued[block] = false;
        const input = headers[block].?;
        for (domain.successors(block)) |successor| {
            const next = (try domain.transfer(block, successor, input)) orelse continue;
            if (headers[successor]) |previous| {
                if (domain.covers(previous, next)) continue;
                headers[successor] = try domain.join(previous, next);
            } else {
                headers[successor] = next;
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

        fn successors(_: @This(), block: usize) []const usize {
            return switch (block) {
                0 => &.{1},
                1 => &.{ 1, 2 },
                else => &.{},
            };
        }

        fn transfer(_: @This(), block: usize, target: usize, input: State) error{}!?State {
            if (block == 1 and target == 2) return input;
            return .{
                .saved = input.saved.join(input.current).age(),
                .current = .{ .current_live = true },
                .slot = input.slot.weakWrite(.{ .initialized = true }),
            };
        }

        fn covers(_: @This(), left: State, right: State) bool {
            return left.saved.covers(right.saved) and left.current.covers(right.current) and left.slot.covers(right.slot);
        }

        fn join(_: @This(), left: State, right: State) error{}!State {
            return .{
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

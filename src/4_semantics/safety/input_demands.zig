const std = @import("std");
const facts = @import("facts.zig");

// Summaries already describe input observations and effects, including paths
// forwarded through local copies. Seed only their array projections, never
// every element of a compile-time dimension. Shared summary DAGs are visited once.
pub fn arrayIndices(allocator: std.mem.Allocator, summary: *const facts.SafetySummary, prefix: facts.InputPath, length: u64) ![]u32 {
    var scan: Scan = .{ .allocator = allocator, .prefix = prefix, .length = length };
    defer scan.seen.deinit(allocator);
    errdefer scan.indices.deinit(allocator);
    try scan.walk(facts.SafetySummary, summary.*);
    return scan.indices.toOwnedSlice(allocator);
}

const Scan = struct {
    allocator: std.mem.Allocator,
    prefix: facts.InputPath,
    length: u64,
    indices: std.ArrayList(u32) = .empty,
    seen: std.AutoHashMapUnmanaged(struct { address: usize, kind: enum { summary, effect } }, void) = .empty,

    fn path(self: *Scan, value: facts.InputPath) !void {
        if (value.input_index != self.prefix.input_index or value.projections.len <= self.prefix.projections.len) return;
        for (self.prefix.projections, value.projections[0..self.prefix.projections.len]) |wanted, actual| {
            if (wanted.eql(actual)) continue;
            if (wanted == .static_index and actual == .dynamic_index) continue;
            return;
        }
        const index: u64 = switch (value.projections[self.prefix.projections.len]) {
            .static_index => |index| index,
            // Unknown indices may alias any observed element. One additional
            // representative suffices; it proves no separation from index zero.
            .dynamic_index => 0,
            else => return,
        };
        if (index >= self.length) return;
        const ordinal = std.math.cast(u32, index) orelse return error.UnsupportedInputReferenceIndex;
        if (std.mem.indexOfScalar(u32, self.indices.items, ordinal) == null) try self.indices.append(self.allocator, ordinal);
    }

    fn walk(self: *Scan, comptime T: type, value: T) anyerror!void {
        if (T == facts.InputPath) return self.path(value);
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".fields) |field| try self.walk(field.type, @field(value, field.name)),
            .optional => |optional| if (value) |present| try self.walk(optional.child, present),
            .pointer => |pointer| switch (pointer.size) {
                .slice => for (value) |item| try self.walk(pointer.child, item),
                .one => if (pointer.child == facts.SafetySummary or pointer.child == facts.ValueEffect) {
                    const visited = try self.seen.getOrPut(self.allocator, .{ .address = @intFromPtr(value), .kind = if (pointer.child == facts.SafetySummary) .summary else .effect });
                    if (!visited.found_existing) try self.walk(pointer.child, value.*);
                },
                else => {},
            },
            else => {},
        }
    }
};

test "array input demands traverse shared guards and returned effects without expanding dimensions" {
    const a = std.testing.allocator;
    const returned: facts.ValueEffect = .{ .input_dependencies = &.{.{ .path = .{ .input_index = 0, .projections = &.{.{ .static_index = 999_999 }} } }} };
    const shared: facts.SafetySummary = .{ .outputs = &.{returned} };
    const summary: facts.SafetySummary = .{
        .required_live_inputs = &.{.{ .input_index = 0, .projections = &.{.{ .static_index = 0 }} }},
        .guarded_effects = &.{ .{ .conditions = .{}, .effects = &shared }, .{ .conditions = .{}, .effects = &shared } },
    };
    const selected = try arrayIndices(a, &summary, .{ .input_index = 0 }, 1_000_000);
    defer a.free(selected);
    try std.testing.expectEqual(@as(usize, 2), selected.len);
    try std.testing.expect(std.mem.indexOfScalar(u32, selected, 0) != null);
    try std.testing.expect(std.mem.indexOfScalar(u32, selected, 999_999) != null);
}

test "nested dynamic input demands retain a conservative representative" {
    const a = std.testing.allocator;
    const summary: facts.SafetySummary = .{ .required_live_inputs = &.{
        .{ .input_index = 0, .projections = &.{ .{ .field = 1 }, .{ .static_index = 7 } } },
        .{ .input_index = 0, .projections = &.{ .{ .field = 1 }, .dynamic_index } },
        .{ .input_index = 1, .projections = &.{ .{ .field = 1 }, .{ .static_index = 3 } } },
    } };
    const selected = try arrayIndices(a, &summary, .{ .input_index = 0, .projections = &.{.{ .field = 1 }} }, 8);
    defer a.free(selected);
    try std.testing.expectEqual(@as(usize, 2), selected.len);
    try std.testing.expect(std.mem.indexOfScalar(u32, selected, 7) != null);
    try std.testing.expect(std.mem.indexOfScalar(u32, selected, 0) != null);
    const empty = try arrayIndices(a, &summary, .{ .input_index = 0, .projections = &.{.{ .field = 1 }} }, 0);
    defer a.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

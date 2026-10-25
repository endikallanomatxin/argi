const std = @import("std");

/// Projection vocabulary is independent of the graph representation.
pub const Projection = union(enum) {
    field: u32,
    variant: u32,
    static_index: usize,
    dynamic_index,
    dereference,

    pub fn eql(left: Projection, right: Projection) bool {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        return switch (left) {
            .field => |index| index == right.field,
            .variant => |index| index == right.variant,
            .static_index => |index| index == right.static_index,
            .dynamic_index, .dereference => true,
        };
    }
};

/// A Place names stable program storage. `Root` is the semantic identity of a
/// binding. The indexed compiler instantiates this with GlobalBindingId.
pub fn PlaceFor(comptime Root: type) type {
    return struct {
        root: Root,
        projections: []const Projection = &.{},

        const Self = @This();

        pub fn eql(left: Self, right: Self) bool {
            if (left.root != right.root or left.projections.len != right.projections.len) return false;
            for (left.projections, right.projections) |a, b| if (!a.eql(b)) return false;
            return true;
        }

        /// Conservative overlap of logical storage, independent of addresses.
        /// Unresolved dereferences and runtime indices cannot prove separation.
        pub fn mayOverlap(left: Self, right: Self) bool {
            for (left.projections) |projection| if (projection == .dereference) return true;
            for (right.projections) |projection| if (projection == .dereference) return true;
            if (left.root != right.root) return false;
            const common = @min(left.projections.len, right.projections.len);
            for (left.projections[0..common], right.projections[0..common]) |a, b| {
                if (a.eql(b)) continue;
                if (a == .dynamic_index or b == .dynamic_index) return true;
                if (std.meta.activeTag(a) != std.meta.activeTag(b)) return true;
                return false;
            }
            return true;
        }

        pub fn isPrefixOf(prefix: Self, place: Self) bool {
            if (prefix.root != place.root or prefix.projections.len > place.projections.len) return false;
            for (prefix.projections, place.projections[0..prefix.projections.len]) |a, b| if (!a.eql(b)) return false;
            return true;
        }
    };
}

test "generic Places preserve root identity and structural prefixes" {
    const Id = enum(u32) { _ };
    const IndexedPlace = PlaceFor(Id);
    const root: Id = @enumFromInt(3);
    const child = [_]Projection{.{ .field = 1 }};
    const a = IndexedPlace{ .root = root };
    const b = IndexedPlace{ .root = root, .projections = &child };
    try std.testing.expect(a.isPrefixOf(b));
    try std.testing.expect(!b.isPrefixOf(a));
}

test "logical storage overlap retains uncertain indices and indirect targets" {
    const P = PlaceFor(u32);
    const whole = P{ .root = 0 };
    const first = P{ .root = 0, .projections = &.{.{ .field = 0 }} };
    const sibling = P{ .root = 0, .projections = &.{.{ .field = 1 }} };
    try std.testing.expect(whole.mayOverlap(first));
    try std.testing.expect(!first.mayOverlap(sibling));
    try std.testing.expect(!whole.mayOverlap(.{ .root = 1 }));
    const element = P{ .root = 0, .projections = &.{.{ .static_index = 4 }} };
    try std.testing.expect(element.mayOverlap(.{ .root = 0, .projections = &.{.dynamic_index} }));
    try std.testing.expect(!element.mayOverlap(.{ .root = 0, .projections = &.{.{ .static_index = 5 }} }));
    try std.testing.expect(first.mayOverlap(.{ .root = 1, .projections = &.{.dereference} }));
    try std.testing.expect((P{ .root = 0, .projections = &.{ .{ .field = 0 }, .dereference } }).mayOverlap(
        .{ .root = 0, .projections = &.{ .{ .field = 1 }, .dereference } },
    ));
}

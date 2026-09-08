const std = @import("std");

/// Projection vocabulary is independent of the graph representation.
pub const Projection = union(enum) {
    field: u32,
    static_index: usize,
    dynamic_index,
    dereference,

    pub fn eql(left: Projection, right: Projection) bool {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        return switch (left) {
            .field => |index| index == right.field,
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

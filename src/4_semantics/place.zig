const std = @import("std");
const sg = @import("semantic_graph.zig");

/// A Place names stable program storage. It does not name the value currently
/// stored there and therefore survives replacement of that value.
pub const Place = struct {
    root: *const sg.BindingDeclaration,
    projections: []const Projection = &.{},

    pub fn eql(left: Place, right: Place) bool {
        if (left.root != right.root or left.projections.len != right.projections.len) return false;
        for (left.projections, right.projections) |a, b| if (!a.eql(b)) return false;
        return true;
    }

    pub fn isPrefixOf(prefix: Place, place: Place) bool {
        if (prefix.root != place.root or prefix.projections.len > place.projections.len) return false;
        for (prefix.projections, place.projections[0..prefix.projections.len]) |a, b| if (!a.eql(b)) return false;
        return true;
    }
};

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

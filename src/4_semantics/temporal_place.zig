const std = @import("std");

const sg = @import("semantic_graph.zig");

pub const Projection = union(enum) {
    field: u32,
    choice_payload: u32,
    array_index: ?i64,
    dereference,
};

/// A spatial location whose temporal identity can be captured or invalidated.
/// Bindings are compared by semantic identity rather than spelling so shadowed
/// names cannot alias accidentally.
pub const Place = struct {
    root: *const sg.BindingDeclaration,
    projections: []const Projection,

    pub fn fromNode(node: *const sg.SGNode, allocator: *const std.mem.Allocator) !?Place {
        var reverse = std.array_list.Managed(Projection).init(allocator.*);
        defer reverse.deinit();

        const root = try collectReverse(node, &reverse) orelse return null;
        std.mem.reverse(Projection, reverse.items);
        return .{
            .root = root,
            .projections = try allocator.dupe(Projection, reverse.items),
        };
    }

    pub fn mayOverlap(left: Place, right: Place) bool {
        if (left.root != right.root) return false;

        const shared_len = @min(left.projections.len, right.projections.len);
        for (left.projections[0..shared_len], right.projections[0..shared_len]) |l, r| {
            if (!projectionsMayOverlap(l, r)) return false;
        }

        // A place overlaps every one of its subobjects.
        return true;
    }

    pub fn eql(left: Place, right: Place) bool {
        if (left.root != right.root) return false;
        if (left.projections.len != right.projections.len) return false;
        for (left.projections, right.projections) |left_projection, right_projection| {
            if (!std.meta.eql(left_projection, right_projection)) return false;
        }
        return true;
    }

    pub fn withProjection(
        place: Place,
        projection: Projection,
        allocator: *const std.mem.Allocator,
    ) !Place {
        const projections = try allocator.alloc(Projection, place.projections.len + 1);
        @memcpy(projections[0..place.projections.len], place.projections);
        projections[place.projections.len] = projection;
        return .{ .root = place.root, .projections = projections };
    }
};

fn collectReverse(
    node: *const sg.SGNode,
    reverse: *std.array_list.Managed(Projection),
) !?*const sg.BindingDeclaration {
    return switch (node.content) {
        .binding_use => |binding| binding,
        .struct_field_access => |access| blk: {
            try reverse.append(.{ .field = access.field_index });
            break :blk try collectReverse(access.struct_value, reverse);
        },
        .choice_payload_access => |access| blk: {
            try reverse.append(.{ .choice_payload = access.variant_index });
            break :blk try collectReverse(access.choice_value, reverse);
        },
        .array_index => |access| blk: {
            try reverse.append(.{ .array_index = constantIndex(access.index) });
            break :blk try collectReverse(access.array_ptr, reverse);
        },
        .dereference => |deref| blk: {
            try reverse.append(.dereference);
            break :blk try collectReverse(deref.pointer, reverse);
        },
        // Array indexing stores an implicit address-of node for codegen. It is
        // not a user-visible projection and retains the underlying root.
        .address_of => |inner| try collectReverse(inner, reverse),
        else => null,
    };
}

fn constantIndex(node: *const sg.SGNode) ?i64 {
    if (node.content != .value_literal) return null;
    if (node.content.value_literal != .int_literal) return null;
    return node.content.value_literal.int_literal;
}

fn projectionsMayOverlap(left: Projection, right: Projection) bool {
    return switch (left) {
        .field => |left_index| switch (right) {
            .field => |right_index| left_index == right_index,
            else => true,
        },
        .choice_payload => switch (right) {
            // Changing the active choice payload is a transition of the same
            // storage envelope, so distinct variants remain conservative.
            .choice_payload => true,
            else => true,
        },
        .array_index => |left_index| switch (right) {
            .array_index => |right_index| if (left_index != null and right_index != null)
                left_index.? == right_index.?
            else
                true,
            else => true,
        },
        .dereference => true,
    };
}

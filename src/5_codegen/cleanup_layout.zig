const g = @import("../4_semantics/global/graph.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const types = @import("../4_semantics/global/types.zig");

pub const Projection = union(enum) { field: u32, variant: g.GlobalVariantId };
pub const Child = struct { projection: Projection, ty: g.GlobalTypeId };

// This is a view of checked storage structure, not destructor selection. Both
// backends attach their concrete flags to the same field/variant identities.
// Physical addresses are insufficient: zero-sized siblings can share one.
// Reference leaves never include the state of their referents, and variants
// without payloads have no child storage. Arrays retain the current whole-value
// state until indexed ownership transitions are represented by the frontend.
pub const Shape = union(enum) {
    leaf,
    fields: p.Range(g.GlobalFieldId),
    variants: p.Range(g.GlobalVariantId),

    pub fn of(graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) Shape {
        if (types.variants(graph, ty)) |range| return .{ .variants = range };
        if (types.fields(graph, ty)) |range| return .{ .fields = range };
        return .leaf;
    }

    pub fn len(self: Shape) usize {
        return switch (self) {
            .leaf => 0,
            .fields => |range| range.len,
            .variants => |range| range.len,
        };
    }

    pub fn child(self: Shape, graph: *const g.GlobalSemanticGraph, index: usize) ?Child {
        if (index >= self.len()) return null;
        return switch (self) {
            .leaf => null,
            .fields => |range| .{
                .projection = .{ .field = @intCast(index) },
                .ty = graph.fields.items[range.start + index].ty,
            },
            .variants => |range| .{
                .projection = .{ .variant = @enumFromInt(range.start + index) },
                .ty = graph.variants.items[range.start + index].payload_type orelse return null,
            },
        };
    }
};

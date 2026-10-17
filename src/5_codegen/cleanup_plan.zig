const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");

// Views of finalized cleanup plans. They neither select destructors nor copy
// the plan into another IR; backends retain their own addresses and emission.
pub const Child = struct {
    ty: g.GlobalTypeId,
    variant: ?g.GlobalVariantId = null,
};

pub fn child(graph: *const g.GlobalSemanticGraph, parent: g.GlobalTypeId, field: g.AutoDeinitField) !Child {
    if (field.is_variant) {
        const variants = types.variants(graph, parent) orelse return error.InvalidCleanupPlan;
        if (field.field_index >= variants.len) return error.InvalidCleanupPlan;
        const variant: g.GlobalVariantId = @enumFromInt(variants.start + field.field_index);
        return .{
            .ty = graph.variants.items[@intFromEnum(variant)].payload_type orelse return error.InvalidCleanupPlan,
            .variant = variant,
        };
    }
    const fields = types.fields(graph, parent) orelse return error.InvalidCleanupPlan;
    if (field.field_index >= fields.len) return error.InvalidCleanupPlan;
    return .{ .ty = graph.fields.items[fields.start + field.field_index].ty };
}

// Non-receiver arguments retain the selected lexical input, falling back to
// the function field's default. The backend only evaluates the chosen node.
pub fn argument(graph: *const g.GlobalSemanticGraph, input: ?g.GlobalNodeId, field: g.Field) !g.GlobalNodeId {
    if (input) |node| {
        const content = graph.node(node).content;
        if (content == .struct_value_literal) {
            const fields = content.struct_value_literal.fields;
            for (graph.value_fields.items[fields.start..][0..fields.len]) |supplied| {
                if (std.mem.eql(u8, graph.text(supplied.name), graph.text(field.name))) return supplied.value;
            }
        }
    }
    return field.default_value orelse error.InvalidCleanupPlan;
}

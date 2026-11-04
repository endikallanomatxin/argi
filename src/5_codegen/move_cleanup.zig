//! Indirect moves consume the evaluated referent's cleanup evidence, never
//! the flags belonging to a binding that happens to contain its reference.
const g = @import("../4_semantics/global/graph.zig");

pub fn usesReferentStorage(graph: *const g.GlobalSemanticGraph, node: g.GlobalNodeId) bool {
    return switch (graph.node(node).content) {
        .dereference, .array_index => true,
        .struct_field_access => |field| usesReferentStorage(graph, field.value),
        .choice_payload_access => |payload| usesReferentStorage(graph, payload.value),
        else => false,
    };
}

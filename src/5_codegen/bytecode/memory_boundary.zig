const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");

pub const Operation = union(enum) { allocate: struct { size: usize, alignment: ?usize }, release };

/// Runtime adapters for selected bundled-core declarations, never name-based
/// dispatch for user functions. Keep logical ffi inputs in the checked call.
pub fn classify(graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId) ?Operation {
    const function = graph.function(id);
    @import("host_signature.zig").validate(graph, id) catch return null;
    const fields = graph.fields.items[function.input.start..][0 .. function.input.len - 1];
    for (fields) |field| if (!types.isBuiltin(graph, field.ty, .UIntNative)) return null;
    if (function.safety_primitive == .raw_allocated_storage) {
        if (function.output.len != 1 or !types.isBuiltin(graph, graph.fields.items[function.output.start].ty, .UIntNative)) return null;
        if (fields.len == 1) return .{ .allocate = .{ .size = 0, .alignment = null } };
        if (fields.len == 2) return .{ .allocate = .{ .size = 1, .alignment = 0 } };
        return null;
    }
    if (function.safety_primitive == .raw_released_storage and fields.len == 1 and function.output.len == 0) return .release;
    return null;
}

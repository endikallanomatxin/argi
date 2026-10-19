const std = @import("std");
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
        if (fields.len == 1 and std.mem.eql(u8, graph.text(fields[0].name), "size")) return .{ .allocate = .{ .size = 0, .alignment = null } };
        if (fields.len == 2 and std.mem.eql(u8, graph.text(fields[0].name), "alignment") and std.mem.eql(u8, graph.text(fields[1].name), "size")) return .{ .allocate = .{ .size = 1, .alignment = 0 } };
        return null;
    }
    if (fields.len != 1 or function.output.len != 0 or !std.mem.eql(u8, graph.text(fields[0].name), "address")) return null;
    const source = graph.declaration(function.declaration).source;
    if (source.file_index >= graph.files.items.len) return null;
    const file = graph.files.items[source.file_index];
    if (!graph.modules.items[@intFromEnum(file.module)].is_bundled_core or !std.mem.eql(u8, graph.text(file.path), "libc.rg")) return null;
    const name = graph.text(graph.declaration(function.declaration).name);
    return if (std.mem.eql(u8, name, "_free") or std.mem.eql(u8, name, "_aligned_free")) .release else null;
}

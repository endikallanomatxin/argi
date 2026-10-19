const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");
const b = @import("bytecode.zig");

pub const max_values = 32;

// A selected foreign declaration keeps its logical ffi input. Only the
// physical integer arguments/results cross the initial host boundary.
pub fn validate(graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId) !void {
    if (@intFromEnum(id) >= graph.functions.items.len) return error.UnsupportedHostSignature;
    const function = graph.function(id);
    if (!function.flags.is_c_abi or function.flags.has_declared_body or
        !function.flags.has_foreign_capability or function.flags.is_c_function_pointer or
        function.input.len == 0 or function.input.len > max_values + 1 or function.output.len > max_values)
        return error.UnsupportedHostSignature;
    const inputs = graph.fields.items[function.input.start..][0..function.input.len];
    const capability = inputs[inputs.len - 1];
    if (!std.mem.eql(u8, graph.text(capability.name), "ffi")) return error.UnsupportedHostSignature;
    const pointer = graph.semanticType(capability.ty);
    if (pointer != .pointer or pointer.pointer.mutability != .read_write) return error.UnsupportedHostSignature;
    const child = graph.semanticType(pointer.pointer.child);
    if (child != .declared) return error.UnsupportedHostSignature;
    const owner = types.nominalTypeOwner(graph, pointer.pointer.child) orelse return error.UnsupportedHostSignature;
    if (!graph.modules.items[@intFromEnum(owner)].is_bundled_core or
        !std.mem.eql(u8, graph.text(graph.declaration(child.declared).name), "ForeignFunctionInterface"))
        return error.UnsupportedHostSignature;
    for (inputs[0 .. inputs.len - 1]) |field|
        if (b.integerBounds(graph, field.ty) == null) return error.UnsupportedHostSignature;
    for (graph.fields.items[function.output.start..][0..function.output.len]) |field|
        if (b.integerBounds(graph, field.ty) == null) return error.UnsupportedHostSignature;
}

pub fn symbol(graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId) []const u8 {
    const function = graph.function(id);
    return graph.text(function.foreign_symbol orelse graph.declaration(function.declaration).name);
}

const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");
const b = @import("bytecode.zig");
const p = @import("../../4_semantics/primitives/schema.zig");

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

// Lower the checked ABI once. Execution links this descriptor without reading
// semantic fields or interpreting types; verification checks it against them.
pub fn describe(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId) !b.HostFunction {
    try validate(graph, id);
    const function = graph.function(id);
    const inputs = try allocator.alloc(p.IntegerRange, function.input.len - 1);
    errdefer allocator.free(inputs);
    const outputs = try allocator.alloc(p.IntegerRange, function.output.len);
    errdefer allocator.free(outputs);
    for (inputs, graph.fields.items[function.input.start..][0..inputs.len]) |*range, field| range.* = b.integerBounds(graph, field.ty).?;
    for (outputs, graph.fields.items[function.output.start..][0..outputs.len]) |*range, field| range.* = b.integerBounds(graph, field.ty).?;
    return .{ .function = id, .source = graph.declaration(function.declaration).source, .symbol = symbol(graph, id), .inputs = inputs, .outputs = outputs };
}

pub fn matches(graph: *const g.GlobalSemanticGraph, descriptor: b.HostFunction) bool {
    validate(graph, descriptor.function) catch return false;
    const function = graph.function(descriptor.function);
    if (!std.mem.eql(u8, descriptor.symbol, symbol(graph, descriptor.function)) or
        !std.meta.eql(descriptor.source, graph.declaration(function.declaration).source) or
        descriptor.inputs.len + 1 != function.input.len or descriptor.outputs.len != function.output.len) return false;
    for (descriptor.inputs, graph.fields.items[function.input.start..][0..descriptor.inputs.len]) |range, field|
        if (!std.meta.eql(range, b.integerBounds(graph, field.ty).?)) return false;
    for (descriptor.outputs, graph.fields.items[function.output.start..][0..descriptor.outputs.len]) |range, field|
        if (!std.meta.eql(range, b.integerBounds(graph, field.ty).?)) return false;
    return true;
}

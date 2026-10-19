const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const b = @import("../5_codegen/bytecode/bytecode.zig");

const signature = @import("../5_codegen/bytecode/host_signature.zig");
pub const max_values = signature.max_values;
pub const symbol = signature.symbol;
pub const Integer = p.IntegerRange;

/// Explicit execution-environment adapters, not native function addresses.
/// The environment and callbacks must outlive all contexts borrowing them and
/// remain immutable during execution. Callbacks receive scalar copies only.
pub const Binding = struct {
    symbol: []const u8,
    inputs: []const Integer,
    outputs: []const Integer,
    data: ?*anyopaque = null,
    call: *const fn (?*anyopaque, []const i128, []i128) anyerror!void,
};

pub fn resolve(graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId, bindings: []const Binding) !*const Binding {
    try signature.validate(graph, id);
    const function = graph.function(id);
    var selected: ?*const Binding = null;
    var found_symbol = false;
    for (bindings) |*binding| {
        if (!std.mem.eql(u8, binding.symbol, symbol(graph, id))) continue;
        found_symbol = true;
        if (binding.inputs.len + 1 != function.input.len or binding.outputs.len != function.output.len) continue;
        var matches = true;
        for (binding.inputs, graph.fields.items[function.input.start..][0..binding.inputs.len]) |expected, field|
            if (!std.meta.eql(expected, b.integerBounds(graph, field.ty).?)) {
                matches = false;
            };
        for (binding.outputs, graph.fields.items[function.output.start..][0..binding.outputs.len]) |expected, field|
            if (!std.meta.eql(expected, b.integerBounds(graph, field.ty).?)) {
                matches = false;
            };
        if (!matches) continue;
        if (selected != null) return error.AmbiguousHostBinding;
        selected = binding;
    }
    return selected orelse if (found_symbol) error.IncompatibleHostBinding else error.MissingHostBinding;
}

pub const Failure = struct { function: g.GlobalFunctionId, source: p.SourceRef, reason: anyerror };

pub fn findFailure(program: b.Program, bindings: []const Binding) ?Failure {
    for (program.host_functions, 0..) |function, index| {
        _ = resolve(program.graph, function, bindings) catch |err| {
            var source = program.graph.declaration(program.graph.function(function).declaration).source;
            const host_index: u32 = @intCast(index);
            const call_source = found: {
                if (program.expression) |expression| if (findCall(expression.*, host_index)) |location| break :found location;
                for (program.functions) |candidate| if (candidate) |body| if (findCall(body, host_index)) |location| break :found location;
                for (program.globals) |global| if (findCall(global.initializer, host_index)) |location| break :found location;
                break :found null;
            };
            if (call_source) |location| source = location;
            return .{ .function = function, .source = source, .reason = err };
        };
    }
    return null;
}

pub fn preflight(program: b.Program, bindings: []const Binding) !void {
    if (findFailure(program, bindings)) |failure| return failure.reason;
}

fn findCall(function: b.Function, index: u32) ?p.SourceRef {
    for (function.code) |instruction|
        if (instruction.op == .host_call and instruction.op.host_call.function == index) return instruction.source;
    return null;
}

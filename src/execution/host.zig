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

fn resolve(graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId, bindings: []const Binding) !*const Binding {
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

// Link immutable code units to one execution environment before their first
// frame. Tables are temporary execution metadata, not retained session state.
// Matching by graph and declaration-table identity keeps equal function IDs in
// unrelated units separate. No user callback runs during linking.
pub const LinkedPrograms = struct {
    const Unit = struct {
        graph: *const g.GlobalSemanticGraph,
        declarations: []const g.GlobalFunctionId,
        bindings: []Binding,
    };
    units: std.ArrayList(Unit) = .empty,

    pub fn deinit(self: *LinkedPrograms, allocator: std.mem.Allocator) void {
        for (self.units.items) |unit| allocator.free(unit.bindings);
        self.units.deinit(allocator);
        self.* = .{};
    }

    pub fn get(self: *LinkedPrograms, allocator: std.mem.Allocator, program: *const b.Program, available: []const Binding) ![]const Binding {
        if (program.host_functions.len == 0) return &.{};
        for (self.units.items) |unit| {
            if (unit.graph == program.graph and unit.declarations.ptr == program.host_functions.ptr and
                unit.declarations.len == program.host_functions.len) return unit.bindings;
        }
        const linked = try allocator.alloc(Binding, program.host_functions.len);
        errdefer allocator.free(linked);
        for (program.host_functions, linked) |function, *binding|
            binding.* = (try resolve(program.graph, function, available)).*;
        try self.units.append(allocator, .{ .graph = program.graph, .declarations = program.host_functions, .bindings = linked });
        return linked;
    }
};

fn findCall(function: b.Function, index: u32) ?p.SourceRef {
    for (function.code) |instruction|
        if (instruction.op == .host_call and instruction.op.host_call.function == index) return instruction.source;
    return null;
}

fn failedHostLink(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(a, "host_step");
    const ffi = try graph.addString(a, "ffi");
    try graph.modules.append(a, .{ .dir = name, .is_bundled_core = true, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 2 } });
    try graph.declarations.appendSlice(a, &.{
        .{ .kind = .type, .name = try graph.addString(a, "ForeignFunctionInterface"), .source = source, .type_id = @enumFromInt(1) },
        .{ .kind = .function, .name = name, .source = source, .function_id = @enumFromInt(0) },
    });
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .declared = @enumFromInt(0) }, .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } } });
    try graph.fields.appendSlice(a, &.{
        .{ .name = name, .ty = @enumFromInt(0), .source = source },
        .{ .name = ffi, .ty = @enumFromInt(2), .source = source },
        .{ .name = name, .ty = @enumFromInt(0), .source = source },
    });
    try graph.functions.append(a, .{
        .declaration = @enumFromInt(1),
        .input = .{ .start = 0, .len = 2 },
        .output = .{ .start = 2, .len = 1 },
        .flags = .{ .is_c_abi = true, .has_foreign_capability = true },
    });
    const Adapter = struct {
        fn call(_: ?*anyopaque, inputs: []const i128, outputs: []i128) !void {
            outputs[0] = inputs[0];
        }
    };
    const range = comptime p.integerRangeForWidth(32, true);
    const available = [_]Binding{.{ .symbol = "host_step", .inputs = &.{range}, .outputs = &.{range}, .call = Adapter.call }};
    const program: b.Program = .{ .graph = &graph, .functions = &.{}, .host_functions = &.{@enumFromInt(0)} };
    var linked: LinkedPrograms = .{};
    defer linked.deinit(allocator);
    const table = linked.get(allocator, &program, &available) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), linked.units.items.len);
        return err;
    };
    const reused = try linked.get(allocator, &program, &available);
    try std.testing.expect(table.ptr == reused.ptr);
    try std.testing.expectEqual(@as(usize, 1), linked.units.items.len);
    var output: [1]i128 = undefined;
    try reused[0].call(reused[0].data, &.{42}, &output);
    try std.testing.expectEqual(@as(i128, 42), output[0]);
}

test "host linking publishes complete tables and releases failed allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedHostLink, .{});
}

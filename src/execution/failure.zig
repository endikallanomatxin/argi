const std = @import("std");
const vm = @import("vm.zig");
const g = @import("../4_semantics/global/graph.zig");
const diagnostics = @import("../1_base/diagnostic.zig");
const locations = @import("../4_semantics/global/source_location.zig");

// Compile-time execution owns only source identities after its checked graph
// and VM scratch are released. No executor pointer or value crosses that boundary.
pub const Trace = struct {
    sources: [vm.max_failure_frames]@import("../4_semantics/primitives/schema.zig").SourceRef = undefined,
    count: usize = 0,

    pub fn capture(self: *Trace, executor: *const vm.Vm) void {
        self.count = @min(self.sources.len, executor.failure_trace.items.len);
        for (self.sources[0..self.count], executor.failure_trace.items[0..self.count]) |*out, frame| out.* = frame.source;
    }
};

pub fn appendCaller(message: *std.array_list.Managed(u8), diags: *diagnostics.Diagnostics, graph: *const g.GlobalSemanticGraph, source: @import("../4_semantics/primitives/schema.zig").SourceRef) !void {
    const location = locations.location(graph, diags, source);
    const position = diags.lineColumn(location);
    try message.print("\n  called from {s}:{d}:{d}", .{ diags.path(location), position.line, position.column });
}

// Rendering belongs outside the executor. Code/source owners must remain alive
// while presenting the borrowed trace, just as while executing their bytecode.
pub fn report(a: std.mem.Allocator, diags: *diagnostics.Diagnostics, executor: *const vm.Vm, fallback: *const g.GlobalSemanticGraph, prefix: []const u8, err: anyerror) !void {
    var message = std.array_list.Managed(u8).init(a);
    defer message.deinit();
    try message.print("{s}: {s}", .{ prefix, @errorName(err) });
    const trace = executor.failure_trace.items;
    if (trace.len > 1) for (trace[1..]) |frame| {
        try appendCaller(&message, diags, frame.graph, frame.source);
    };
    const first: vm.FailureFrame = if (trace.len != 0) trace[0] else .{ .graph = fallback, .source = executor.source };
    try diags.add(locations.location(first.graph, diags, first.source), .codegen, "{s}", .{message.items});
}

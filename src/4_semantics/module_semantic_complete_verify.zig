const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");
const core = @import("module_semantic_verify.zig");
const template_state = @import("module_semantic_template_verify.zig");

pub fn verifyModule(graph: *const graph_mod.ModuleSemanticGraph) !void {
    try core.verifyModule(graph);
    try template_state.verifyTemplates(graph);
}

test "complete module verifier accepts an empty module" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "empty") };
    defer graph.deinit(allocator);
    try verifyModule(&graph);
}
const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");
const core = @import("module_semantic_verify.zig");
const template_state = @import("module_semantic_template_verify.zig");
const generic_instances = @import("module_generic_instance_verify.zig");
const views = @import("module_semantic_views.zig");
const verify = @import("semantic_verify.zig");

pub fn verifyModule(graph: *const graph_mod.ModuleSemanticGraph) !void {
    try core.verifyModule(graph);
    try template_state.verifyTemplates(graph);
    try generic_instances.verifyGenericInstances(graph, graph.semantic.local_semantics_complete);
    for (graph.semantic.external_refs.items) |reference| {
        if (reference.generic_arguments) |arguments| {
            if (!verify.rangeFits(arguments, views.genericArgumentCount(graph)))
                return error.InvalidModuleExternalGenericArguments;
        }
    }
}

test "complete module verifier accepts an empty module" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "empty") };
    defer graph.deinit(allocator);
    try verifyModule(&graph);
}

test "complete module verifier rejects dangling external generic arguments" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);
    try graph.semantic.external_refs.append(allocator, .{
        .kind = .type,
        .module_path = null,
        .name = .{ .start = 0, .len = 0 },
        .generic_arguments = .{ .start = 1, .len = 1 },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try std.testing.expectError(error.InvalidModuleSemanticGraph, verifyModule(&graph));
}

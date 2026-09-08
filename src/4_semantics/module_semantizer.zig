const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const body_lowerer = @import("module_body_lowerer.zig");
const complete_verify = @import("module_semantic_complete_verify.zig");

pub const BuildStats = struct {
    lowered_functions: u32 = 0,
    deferred_functions: u32 = 0,
    local_semantics_complete: bool = false,
};

pub const BuildResult = struct {
    graph: module_sg.ModuleSemanticGraph,
    stats: BuildStats,
};

/// Transitional ModuleSema orchestrator. The old discovery/interface builder is
/// only the bootstrap input; every new executable semantic fact is written to
/// canonical ModuleSG storage through Module* IDs.
pub fn build(
    allocator: std.mem.Allocator,
    module_dir: []const u8,
    files: []const module_sg.FileInput,
) !BuildResult {
    var graph = try module_sg.build(allocator, module_dir, files);
    errdefer graph.deinit(allocator);

    const bodies = try body_lowerer.lower(allocator, &graph, files);
    // Do not claim cache-complete semantics yet. Field defaults, generic and
    // abstract templates, and the remaining body forms still need their direct
    // ModuleSG lowering passes.
    graph.semantic.local_semantics_complete = false;
    try complete_verify.verifyModule(&graph);

    return .{
        .graph = graph,
        .stats = .{
            .lowered_functions = bodies.lowered_functions,
            .deferred_functions = bodies.deferred_functions,
            .local_semantics_complete = false,
        },
    };
}

test "module semantizer starts incomplete until every local pass is migrated" {
    const allocator = std.testing.allocator;
    var result = try build(allocator, "empty", &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expect(!result.graph.semantic.local_semantics_complete);
    try std.testing.expect(!result.stats.local_semantics_complete);
}

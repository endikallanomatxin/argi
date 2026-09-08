const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const body_lowerer = @import("module_body_lowerer.zig");
const fallback_lowerer = @import("module_fallback_lowerer.zig");
const complete_verify = @import("module_semantic_complete_verify.zig");

pub const BuildStats = struct {
    lowered_functions: u32 = 0,
    fallback_functions: u32 = 0,
    local_semantics_complete: bool = false,
};

pub const BuildResult = struct {
    graph: module_sg.ModuleSemanticGraph,
    stats: BuildStats,
};

/// Module-local semantic orchestration. Precise lowering is opportunistic, but
/// the fallback pass guarantees that every non-generic body is represented by
/// Module* IDs and semantic holes rather than retained syntax.
pub fn build(
    allocator: std.mem.Allocator,
    module_dir: []const u8,
    files: []const module_sg.FileInput,
) !BuildResult {
    var graph = try module_sg.build(allocator, module_dir, files);
    errdefer graph.deinit(allocator);

    const precise = try body_lowerer.lower(allocator, &graph, files);
    const fallback = try fallback_lowerer.lowerMissingFunctions(allocator, &graph, files);

    // Generic/abstract templates and defaults are the only remaining producers
    // that may still need FileST. Later passes flip this once those tables are
    // populated; non-generic bodies are already syntax-independent here.
    graph.semantic.local_semantics_complete = false;
    try complete_verify.verifyModule(&graph);

    return .{
        .graph = graph,
        .stats = .{
            .lowered_functions = precise.lowered_functions,
            .fallback_functions = fallback.lowered_functions,
            .local_semantics_complete = false,
        },
    };
}

test "module semantizer keeps completion false only for templates and defaults" {
    const allocator = std.testing.allocator;
    var result = try build(allocator, "empty", &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expect(!result.graph.semantic.local_semantics_complete);
    try std.testing.expectEqual(@as(u32, 0), result.stats.fallback_functions);
}

const std = @import("std");

const diagnostics = @import("../1_base/diagnostic.zig");
const sg = @import("semantic_graph.zig");

/// Runs after semantizing has produced complete function bodies and before any
/// consumer can hand the graph to codegen. Temporal properties intentionally
/// live here instead of being folded into type checking: source types describe
/// reference permissions, while this pass reasons about the identities those
/// references capture at particular program points.
pub const MemorySafetyAnalyzer = struct {
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,

    pub fn init(
        allocator: *const std.mem.Allocator,
        diags: *diagnostics.Diagnostics,
    ) MemorySafetyAnalyzer {
        return .{
            .allocator = allocator,
            .diags = diags,
        };
    }

    pub fn analyze(self: *MemorySafetyAnalyzer, nodes: []const *sg.SGNode) !void {
        for (nodes) |node| switch (node.content) {
            .function_declaration => |function| try self.analyzeFunction(function),
            .test_declaration => |test_decl| try self.analyzeFunction(test_decl.function),
            else => {},
        };
    }

    pub fn analyzeFunction(self: *MemorySafetyAnalyzer, function: *const sg.FunctionDeclaration) !void {
        _ = self;
        _ = function;
    }
};

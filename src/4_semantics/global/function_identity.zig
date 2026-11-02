const std = @import("std");
const g = @import("graph.zig");

/// Completed semantic identities stay stable while their pools grow. Consumer
/// hypotheses remain separate from this identity; it is not a body version.
pub const FunctionIdentity = struct {
    function: g.Function,
    block: ?g.Block,

    pub fn read(graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId) FunctionIdentity {
        const function = graph.function(id);
        return .{ .function = function, .block = if (function.body) |body| graph.blocks.items[@intFromEnum(body)] else null };
    }

    pub fn matches(self: FunctionIdentity, graph: *const g.GlobalSemanticGraph, id: g.GlobalFunctionId) bool {
        return @intFromEnum(id) < graph.functions.items.len and std.meta.eql(self, read(graph, id));
    }
};

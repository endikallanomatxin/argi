const std = @import("std");
const graph = @import("../4_semantics/global/graph.zig");
const diagnostics = @import("../1_base/diagnostic.zig");
const source = @import("../4_semantics/primitives/schema.zig");
const token = @import("../2_tokens/token.zig");

/// Resolve retained graph file identities before applying presentation maps.
/// Submitted source buffers may outnumber the graph's module-local files.
pub fn location(g: *const graph.GlobalSemanticGraph, bag: *const diagnostics.Diagnostics, ref: source.SourceRef) token.Location {
    if (ref.file_index < g.files.items.len) {
        const file = g.files.items[ref.file_index];
        const directory = g.text(g.modules.items[@intFromEnum(file.module)].dir);
        for (bag.source_files, 0..) |candidate, index| {
            if (std.mem.eql(u8, std.fs.path.basename(candidate.path), g.text(file.path)) and
                std.mem.eql(u8, std.fs.path.dirname(candidate.path) orelse ".", directory))
                return .{ .file = bag.source_db.fileId(index), .offset = ref.offset };
        }
    }
    return .{ .file = @enumFromInt(0), .offset = ref.offset };
}

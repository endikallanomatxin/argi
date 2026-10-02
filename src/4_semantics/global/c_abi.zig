const graph_mod = @import("graph.zig");
const types = @import("types.zig");

/// The supported foreign scalar boundary is deliberately narrower than ordinary
/// LLVM type lowering. Record layout alone does not establish how a platform's
/// C ABI classifies an aggregate argument or result. Extend this predicate only
/// alongside matching call lowering and cross-language executable tests.
pub fn supportsDirectValue(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return supportsValue(graph, ty, 0);
}

fn supportsValue(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) bool {
    if (depth >= 32) return false;
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .builtin => |builtin| switch (builtin) {
            .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64, .UIntNative, .Float32, .Float64, .Char, .Bool => true,
            else => false,
        },
        // Legacy bindings use references as pointer parameters. Their pointee
        // layout and foreign effects remain obligations of the binding.
        .pointer => true,
        .declared => |id| graph.declaration(id).choice_variants != null and
            graph.declaration(id).choice_layout == .c_enum,
        .structural_choice => |shape| shape.layout == .c_enum,
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .alias => |target| supportsValue(graph, target, depth + 1),
            .choice => |shape| shape.layout == .c_enum,
            else => false,
        } else false,
        else => false,
    };
}

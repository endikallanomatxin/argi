const std = @import("std");
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

/// Foreign imports have a logical reached capability argument. It participates
/// in ordinary dependency resolution and safety, but never in the C ABI. Add
/// it after relocation so its nominal identity comes from bundled core rather
/// than a user declaration with the same spelling.
pub fn prepareForeignCapabilities(allocator: std.mem.Allocator, graph: *graph_mod.GlobalSemanticGraph) !void {
    var capability: ?graph_mod.GlobalTypeId = null;
    for (graph.declarations.items, 0..) |declaration, index| {
        if (!std.mem.eql(u8, graph.text(declaration.name), "ForeignFunctionInterface")) continue;
        const owner = graph.moduleForDeclaration(@enumFromInt(index)) orelse continue;
        if (!graph.modules.items[@intFromEnum(owner)].is_bundled_core) continue;
        capability = declaration.type_id;
        break;
    }
    const child = capability orelse return;
    const pointer: graph_mod.GlobalTypeId = @enumFromInt(graph.types.items.len);
    try graph.types.append(allocator, .{ .pointer = .{ .child = child, .mutability = .read_write } });
    const name = try graph.addString(allocator, "ffi");
    for (graph.functions.items) |*function| {
        if (!function.flags.is_c_abi or function.flags.has_declared_body or function.flags.is_abstract_dispatch) continue;
        const source = graph.declaration(function.declaration).source;
        const segment_start: u32 = @intCast(graph.reach_segments.items.len);
        try graph.reach_segments.append(allocator, name);
        const alternative_start: u32 = @intCast(graph.reach_alternatives.items.len);
        try graph.reach_alternatives.append(allocator, .{ .segments = .{ .start = segment_start, .len = 1 } });
        const reach: graph_mod.GlobalReachId = @enumFromInt(graph.reaches.items.len);
        try graph.reaches.append(allocator, .{ .alternatives = .{ .start = alternative_start, .len = 1 } });
        const fallback: graph_mod.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
        try graph.nodes.append(allocator, .{ .source = source, .ty = pointer, .content = .{ .reach_directive = reach } });
        const old_fields = try allocator.dupe(graph_mod.Field, graph.fields.items[function.input.start..][0..function.input.len]);
        defer allocator.free(old_fields);
        const field_start: u32 = @intCast(graph.fields.items.len);
        try graph.fields.appendSlice(allocator, old_fields);
        try graph.fields.append(allocator, .{ .name = name, .ty = pointer, .source = source, .default_value = fallback });
        const old_bindings = try allocator.dupe(graph_mod.GlobalBindingId, graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]);
        defer allocator.free(old_bindings);
        const binding: graph_mod.GlobalBindingId = @enumFromInt(graph.bindings.items.len);
        try graph.bindings.append(allocator, .{ .name = name, .ty = pointer, .source = source, .mutability = .constant });
        const binding_start: u32 = @intCast(graph.binding_refs.items.len);
        try graph.binding_refs.appendSlice(allocator, old_bindings);
        try graph.binding_refs.append(allocator, binding);
        function.input = .{ .start = field_start, .len = function.input.len + 1 };
        function.input_bindings = .{ .start = binding_start, .len = function.input_bindings.len + 1 };
        function.flags.has_foreign_capability = true;
    }
}

pub fn physicalInputCount(function: graph_mod.Function) u32 {
    return function.input.len - @as(u32, if (function.flags.has_foreign_capability) 1 else 0);
}

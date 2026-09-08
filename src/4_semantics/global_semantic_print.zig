const std = @import("std");
const graph_mod = @import("global_semantic_graph.zig");
const types = @import("global_semantic_types.zig");

pub fn print(graph: *const graph_mod.GlobalSemanticGraph) void {
    std.debug.print("\nGLOBAL SEMANTIC GRAPH\n", .{});
    std.debug.print("modules={d} files={d} declarations={d} types={d} functions={d} bindings={d} nodes={d} roots={d}\n", .{
        graph.modules.items.len,
        graph.files.items.len,
        graph.declarations.items.len,
        graph.types.items.len,
        graph.functions.items.len,
        graph.bindings.items.len,
        graph.nodes.items.len,
        graph.roots.items.len,
    });

    for (graph.modules.items, 0..) |module, module_index| {
        std.debug.print("\nmodule %{d} {s}\n", .{ module_index, graph.text(module.dir) });
        for (graph.declarations.items[module.declarations.start..][0..module.declarations.len], module.declarations.start..) |decl, raw| {
            std.debug.print("  decl %{d} {s} {s}", .{ raw, @tagName(decl.kind), graph.text(decl.name) });
            if (decl.type_id) |ty| std.debug.print(" : t%{d}", .{@intFromEnum(ty)});
            if (decl.function_id) |function| std.debug.print(" -> f%{d}", .{@intFromEnum(function)});
            std.debug.print("\n", .{});
        }
    }

    std.debug.print("\nfunctions\n", .{});
    for (graph.functions.items, 0..) |function, raw| {
        const decl = graph.declarations.items[@intFromEnum(function.declaration)];
        std.debug.print("  f%{d} {s} in={d} out={d}", .{ raw, graph.text(decl.name), function.input.len, function.output.len });
        if (function.body) |body| std.debug.print(" body=b%{d}", .{@intFromEnum(body)}) else std.debug.print(" extern", .{});
        if (function.flags.is_generic_instantiation) std.debug.print(" generic", .{});
        if (function.flags.is_deinit) std.debug.print(" deinit", .{});
        std.debug.print("\n", .{});
    }

    std.debug.print("\nbindings\n", .{});
    for (graph.bindings.items, 0..) |binding, raw| {
        std.debug.print("  v%{d} {s} : t%{d}", .{ raw, graph.text(binding.name), @intFromEnum(binding.ty) });
        if (binding.initialization) |node| std.debug.print(" = n%{d}", .{@intFromEnum(node)});
        std.debug.print("\n", .{});
    }

    std.debug.print("\nnodes\n", .{});
    for (graph.nodes.items, 0..) |node, raw| {
        std.debug.print("  n%{d} {s}", .{ raw, @tagName(std.meta.activeTag(node.content)) });
        if (node.ty) |ty| {
            std.debug.print(" : t%{d}", .{@intFromEnum(ty)});
            if (types.fields(graph, ty)) |fields| std.debug.print(" fields={d}", .{fields.len});
            if (types.variants(graph, ty)) |variants| std.debug.print(" variants={d}", .{variants.len});
        }
        std.debug.print(" @{d}:{d}\n", .{ node.source.file_index, node.source.offset });
    }

    std.debug.print("\nroots", .{});
    for (graph.roots.items) |root| std.debug.print(" n%{d}", .{@intFromEnum(root)});
    std.debug.print("\n", .{});
}

test "global semantic print module depends only on indexed graph" {
    try std.testing.expect(@sizeOf(graph_mod.GlobalNodeId) == 4);
}

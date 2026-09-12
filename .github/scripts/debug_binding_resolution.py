from pathlib import Path

path = Path('src/4_semantics/global/semantizer.zig')
text = path.read_text()
anchor = '''    if (remaining != 0) {
        dumpUnresolved(modules, resolved);
        return error.UnsupportedGlobalSemantic;
    }
'''
replacement = '''    if (remaining != 0) {
        dumpUnresolved(modules, resolved);
        debugUnresolvedBindingTypes(&relocation.graph);
        return error.UnsupportedGlobalSemantic;
    }
'''
if replacement not in text:
    assert anchor in text
    text = text.replace(anchor, replacement, 1)

insert_anchor = '\nfn dumpUnresolved(modules: []const module_sg.ModuleSemanticGraph, resolved: []const bool) void {'
helper = '''
fn debugUnresolvedBindingTypes(graph: *const global_sg.GlobalSemanticGraph) void {
    var count: usize = 0;
    for (graph.bindings.items, 0..) |binding, raw| {
        const id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        if (!graph.isBindingTypeUnresolved(id)) continue;
        const init_ty = if (binding.initialization) |init| graph.nodes.items[@intFromEnum(init)].ty else null;
        std.debug.print(
            "unresolved binding: id={d} name={s} init={any} init_ty={any} source_file={d} source_off={d}\\n",
            .{ raw, graph.text(binding.name), binding.initialization, init_ty, binding.source.file_index, binding.source.offset },
        );
        var shown_uses: usize = 0;
        for (graph.nodes.items, 0..) |node, node_raw| switch (node.content) {
            .binding_use => |binding_id| if (binding_id == id and shown_uses < 6) {
                std.debug.print("  use node={d} ty={any} source_file={d} source_off={d}\\n", .{ node_raw, node.ty, node.source.file_index, node.source.offset });
                shown_uses += 1;
            },
            else => {},
        };
        count += 1;
        if (count == 20) break;
    }
    std.debug.print("unresolved binding debug count shown={d}\\n", .{count});
}
'''
if 'fn debugUnresolvedBindingTypes(' not in text:
    assert insert_anchor in text
    text = text.replace(insert_anchor, '\n' + helper + insert_anchor, 1)
path.write_text(text)
print('temporary unresolved-binding diagnostics enabled')

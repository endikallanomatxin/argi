from pathlib import Path

control = Path("src/4_semantics/global/control.zig")
text = control.read_text()

text = text.replace("    array_loops: u32 = 0,\n", "    for_loops: u32 = 0,\n")
text = text.replace("        self.stats.array_loops += 1;\n", "        self.stats.for_loops += 1;\n")

old = '''        const old_body = self.graph.blocks.items[@intFromEnum(globalizer.globalBlock(o, value.body))];
        const old_nodes = self.graph.node_refs.items[old_body.nodes.start..][0..old_body.nodes.len];
        const body_start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.append(self.allocator, item_declaration);
        try self.graph.node_refs.append(self.allocator, item_assignment);
        try self.graph.node_refs.appendSlice(self.allocator, old_nodes);
'''
new = '''        const old_body = self.graph.blocks.items[@intFromEnum(globalizer.globalBlock(o, value.body))];
        const old_nodes = try self.allocator.dupe(
            global_sg.GlobalNodeId,
            self.graph.node_refs.items[old_body.nodes.start..][0..old_body.nodes.len],
        );
        defer self.allocator.free(old_nodes);
        const body_start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.append(self.allocator, item_declaration);
        try self.graph.node_refs.append(self.allocator, item_assignment);
        try self.graph.node_refs.appendSlice(self.allocator, old_nodes);
'''
if text.count(old) != 1:
    raise RuntimeError(f"for body copy anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
control.write_text(text)

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/06_range_for "
    "-Dtest-filter=feature_tests/control_flow/07_range_step "
    "-Dtest-filter=feature_tests/control_flow/09_range_int64 "
    "-Dtest-filter=feature_tests/control_flow/10_range_default_start "
    "-Dtest-filter=feature_tests/control_flow/11_range_default_start_with_step\n"
)
Path(".git/semantic-refactor-message").write_text("Stabilize iterator for-each lowering\n")

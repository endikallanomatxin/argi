from pathlib import Path


codegen = Path("src/5_codegen/global_codegen.zig")
text = codegen.read_text()
old = """    fn genBlock(self: *CodeGenerator, block_id: graph_mod.GlobalBlockId) !?TypedValue {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| {
            const current = c.LLVMGetInsertBlock(self.builder);
            if (current != null and c.LLVMGetBasicBlockTerminator(current) != null) break;
            _ = try self.visitNode(node);
        }
        return if (block.ret_val) |node| self.visitNode(node) else null;
    }
"""
new = """    fn genBlock(self: *CodeGenerator, block_id: graph_mod.GlobalBlockId) !?TypedValue {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        var result: ?TypedValue = null;
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| {
            const current = c.LLVMGetInsertBlock(self.builder);
            if (current != null and c.LLVMGetBasicBlockTerminator(current) != null) break;
            const value = try self.visitNode(node);
            if (block.ret_val != null and node == block.ret_val.?) result = value;
        }
        return result;
    }
"""
if old in text:
    codegen.write_text(text.replace(old, new, 1))
else:
    assert new in text, "genBlock implementation did not match expected old or new form"

print("genBlock single-evaluation fix staged")

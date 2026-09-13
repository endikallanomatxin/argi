from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"expected anchor not found in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


replace(
    "src/4_semantics/global/core.zig",
    """                if (current == null or types.isBuiltin(self.graph, current.?, .Any)) {
                    self.graph.nodes.items[@intFromEnum(node)].ty = target;
                    return true;
                }
""",
    """                if (current == null) {
                    self.graph.nodes.items[@intFromEnum(node)].ty = target;
                    return true;
                }
""",
)

replace(
    "src/4_semantics/module/body_lowerer.zig",
    """    fn lowerBlockNode(self: *Context, node: syn.NodeIndex) !Lowered {
        const block = try self.lowerBlock(node);
        return self.resolved(node, try self.builtin(.Any), .{ .code_block = block });
    }
""",
    """    fn lowerBlockNode(self: *Context, node: syn.NodeIndex) !Lowered {
        const block = try self.lowerBlock(node);
        const body = self.graph.semantic.blocks.items[@intFromEnum(block)];
        const ty: ?entities.ModuleTypeId = if (body.ret_val) |ret_val|
            switch (self.graph.semantic.nodes.items[@intFromEnum(ret_val)]) {
                .resolved => |resolved| resolved.ty,
                .pending => null,
            }
        else
            try self.builtin(.Void);
        return self.resolved(node, ty, .{ .code_block = block });
    }
""",
)

replace(
    "src/4_semantics/module/parameterized/lowerer.zig",
    """                .string_literal => self.addResolvedNode(node, try self.parameterizedBuiltin(.Any), .{
                    .string_literal = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token)),
                }),
""",
    """                .string_literal => self.addResolvedNode(node, null, .{
                    .string_literal = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token)),
                }),
""",
)

replace(
    "src/4_semantics/module/parameterized/lowerer.zig",
    """    fn blockAsNode(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const block = try self.lowerBlock(node);
        return self.addResolvedNode(node, try self.parameterizedBuiltin(.Any), .{ .code_block = block });
    }
""",
    """    fn blockAsNode(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const block = try self.lowerBlock(node);
        const body = self.graph.semantic.parameterized_storage.ir.blocks.items[@intFromEnum(block)];
        const ty: ?ir.ParameterizedTypeId = if (body.ret_val) |ret_val|
            switch (self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(ret_val)]) {
                .resolved => |resolved| resolved.ty,
                .pending => null,
            }
        else
            try self.parameterizedBuiltin(.Void);
        return self.addResolvedNode(node, ty, .{ .code_block = block });
    }
""",
)

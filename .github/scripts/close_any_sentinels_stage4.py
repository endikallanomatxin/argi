from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old in text:
        p.write_text(text.replace(old, new, 1))
        return
    if new in text:
        return
    raise SystemExit(f"expected anchor not found in {path}: {old[:160]!r}")


# Untyped globals use the same explicit construction state as local bindings.
replace_once(
    "src/4_semantics/module/initializer_lowerer.zig",
    """            const declared_ty = if (syntax_decl.type_node) |node| try self.lowerType(node) else try self.builtin(.Any);
            const binding = try self.writer.addBinding(.{
                .name = decl.name,
                .source = self.sourceRef(declaration_node),
                .ty = declared_ty,
                .mutability = graph_mod.mutabilityFromSyntax(syntax_decl.mutability),
            });
""",
    """            const binding = if (syntax_decl.type_node) |node|
                try self.writer.addBinding(.{
                    .name = decl.name,
                    .source = self.sourceRef(declaration_node),
                    .ty = try self.lowerType(node),
                    .mutability = graph_mod.mutabilityFromSyntax(syntax_decl.mutability),
                })
            else
                try self.writer.addUnresolvedBinding(
                    decl.name,
                    self.sourceRef(declaration_node),
                    null,
                    graph_mod.mutabilityFromSyntax(syntax_decl.mutability),
                );
""",
)

replace_once(
    "src/4_semantics/module/initializer_lowerer.zig",
    """            const expected = self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty;
            const value = try body_lowerer.lowerInitializerExpression(
                self.allocator,
                self.graph,
                self.files,
                self.file_index,
                value_node,
                expected,
            );
            self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].initialization = value.node;
            if (self.isAny(expected)) {
                if (value.ty) |value_ty| {
                    if (!self.isAny(value_ty))
                        self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty = value_ty;
                }
            }
            try self.writer.addRoot(value.node);
""",
    """            const unresolved = views.bindingTypeUnresolved(self.graph, relation.binding);
            const expected: ?entities.ModuleTypeId = if (unresolved)
                null
            else
                self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty;
            const value = try body_lowerer.lowerInitializerExpression(
                self.allocator,
                self.graph,
                self.files,
                self.file_index,
                value_node,
                expected,
            );
            self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].initialization = value.node;
            if (unresolved) if (value.ty) |value_ty| {
                self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty = value_ty;
                var index: usize = 0;
                while (index < self.graph.semantic.unresolved_binding_types.items.len) : (index += 1) {
                    if (self.graph.semantic.unresolved_binding_types.items[index] != relation.binding) continue;
                    _ = self.graph.semantic.unresolved_binding_types.orderedRemove(index);
                    break;
                }
            };
            try self.writer.addRoot(value.node);
""",
)

# The old initializer-only Any helpers are no longer part of type inference.
replace_once(
    "src/4_semantics/module/initializer_lowerer.zig",
    """    fn isAny(self: *Context, id: entities.ModuleTypeId) bool {
        const value = views.typeView(self.graph, id) catch return false;
        return switch (value) {
            .resolved => |resolved_type| switch (resolved_type) {
                .builtin => |builtin_value| builtin_value == .Any,
                else => false,
            },
            .external => false,
        };
    }

""",
    "",
)

# Global relocation needs a payload for preallocated unresolved type slots, but
# that payload must be deliberately invalid rather than the language `Any`.
replace_once(
    "src/4_semantics/global/graph.zig",
    "const unresolved_type_poison_decl: GlobalDeclId = @enumFromInt(std.math.maxInt(u32));\n",
    "pub const unresolved_type_poison_decl: GlobalDeclId = @enumFromInt(std.math.maxInt(u32));\n",
)
replace_once(
    "src/4_semantics/global/globalizer.zig",
    "            .external => if (mode == .allow_holes) .{ .builtin = .Any } else return error.UnresolvedModuleSemantics,\n",
    "            .external => if (mode == .allow_holes) .{ .declared = global_sg.unresolved_type_poison_decl } else return error.UnresolvedModuleSemantics,\n",
)

# Keep the construction-state regression independent from the old semantic Any
# value: marking a slot unresolved must poison any previous payload.
replace_once(
    "src/4_semantics/global/graph.zig",
    "    try graph.types.append(allocator, .{ .builtin = .Any });\n    try graph.markTypeUnresolved(allocator, @enumFromInt(0));\n",
    "    try graph.types.append(allocator, .{ .builtin = .Int32 });\n    try graph.markTypeUnresolved(allocator, @enumFromInt(0));\n",
)

from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:140]!r}")
    file.write_text(text.replace(old, new, 1))


def replace_n(path: str, old: str, new: str, expected: int) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected} matches, found {count}: {old[:140]!r}")
    file.write_text(text.replace(old, new))


# A qualified name use is still a name lookup, but its module identity comes
# from a compile-time import path instead of the current/core namespace.
replace_once(
    "src/4_semantics/module/entities.zig",
    "    resolve_name_use: struct {\n        node: ModuleNodeId,\n        name: primitives.StringRange,\n    },\n",
    "    resolve_name_use: struct {\n        node: ModuleNodeId,\n        name: primitives.StringRange,\n        module_path: ?primitives.StringRange = null,\n    },\n",
)

# Type lowering can be nested inside a function body, where module aliases are
# lexical rather than durable module declarations. Rewrite those qualifiers to
# their import path while the lexical information is still available.
replace_once(
    "src/4_semantics/module/type_lowerer.zig",
    'const writer_mod = @import("writer.zig");\n',
    'const writer_mod = @import("writer.zig");\nconst primitives = @import("../primitives/schema.zig");\n\npub const LexicalModuleAlias = struct {\n    name: primitives.StringRange,\n    path: primitives.StringRange,\n};\n',
)
replace_once(
    "src/4_semantics/module/type_lowerer.zig",
    "    source: []const u8,\n\n    pub fn lower",
    "    source: []const u8,\n    module_aliases: []const LexicalModuleAlias = &.{},\n\n    pub fn lower",
)
replace_once(
    "src/4_semantics/module/type_lowerer.zig",
    "        const module_path = if (qualifier_token) |token_index|\n            try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))\n        else\n            null;\n",
    "        const module_path = if (qualifier_token) |token_index|\n            try self.modulePathForQualifier(token_index)\n        else\n            null;\n",
)
replace_once(
    "src/4_semantics/module/type_lowerer.zig",
    "    fn sourceRef(self: *const Context, node: syn.NodeIndex) @import(\"../primitives/schema.zig\").SourceRef {\n",
    "    fn modulePathForQualifier(self: *Context, token: syn.TokenIndex) !primitives.StringRange {\n        const spelling = self.tree.tokenTextFromSource(self.source, token);\n        var index = self.module_aliases.len;\n        while (index != 0) {\n            index -= 1;\n            const alias = self.module_aliases[index];\n            if (std.mem.eql(u8, self.graph.text(alias.name), spelling)) return alias.path;\n        }\n        return self.writer.addString(spelling);\n    }\n\n    fn sourceRef(self: *const Context, node: syn.NodeIndex) @import(\"../primitives/schema.zig\").SourceRef {\n",
)

# Local imports are compile-time namespace bindings. They participate in lexical
# scope but never allocate a runtime binding/node and therefore never generate
# resolve_import work.
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "const NamedBinding = struct {\n    name: primitives.StringRange,\n    id: entities.ModuleBindingId,\n    ty: ?entities.ModuleTypeId,\n};\n",
    "const NamedBinding = struct {\n    name: primitives.StringRange,\n    id: entities.ModuleBindingId,\n    ty: ?entities.ModuleTypeId,\n};\nconst ScopeMark = struct {\n    bindings: usize,\n    module_aliases: usize,\n};\n",
)
replace_n(
    "src/4_semantics/module/body_lowerer.zig",
    "        .bindings = std.array_list.Managed(NamedBinding).init(allocator),\n        .scope_marks = std.array_list.Managed(usize).init(allocator),\n",
    "        .bindings = std.array_list.Managed(NamedBinding).init(allocator),\n        .module_aliases = std.array_list.Managed(type_lowerer.LexicalModuleAlias).init(allocator),\n        .scope_marks = std.array_list.Managed(ScopeMark).init(allocator),\n",
    2,
)
replace_n(
    "src/4_semantics/module/body_lowerer.zig",
    "    defer context.bindings.deinit();\n    defer context.scope_marks.deinit();\n",
    "    defer context.bindings.deinit();\n    defer context.module_aliases.deinit();\n    defer context.scope_marks.deinit();\n",
    2,
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "    bindings: std.array_list.Managed(NamedBinding),\n    scope_marks: std.array_list.Managed(usize),\n",
    "    bindings: std.array_list.Managed(NamedBinding),\n    module_aliases: std.array_list.Managed(type_lowerer.LexicalModuleAlias),\n    scope_marks: std.array_list.Managed(ScopeMark),\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "    try context.seedGlobalBindings();\n    return context.lowerNode(node, expected);\n",
    "    try context.seedGlobalBindings();\n    try context.seedGlobalModuleAliases();\n    return context.lowerNode(node, expected);\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "            self.bindings.clearRetainingCapacity();\n            self.scope_marks.clearRetainingCapacity();\n            try self.pushScope();\n",
    "            self.bindings.clearRetainingCapacity();\n            self.module_aliases.clearRetainingCapacity();\n            self.scope_marks.clearRetainingCapacity();\n            try self.seedGlobalModuleAliases();\n            try self.pushScope();\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "        for (block.statements) |statement| {\n            const value = try self.lowerNode(statement, null);\n",
    "        for (block.statements) |statement| {\n            if (try self.lowerLocalModuleAlias(statement)) continue;\n            const value = try self.lowerNode(statement, null);\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "        const module_path = if (call.module_qualifier) |token_index|\n            try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))\n        else\n            null;\n",
    "        const module_path = if (call.module_qualifier) |token_index|\n            try self.modulePathForQualifier(token_index)\n        else\n            null;\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "    fn lowerField(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {\n        const access = self.tree.structFieldAccess(node).?;\n        const value = try self.lowerNode(access.value, null);\n        return self.pending(node, .{ .resolve_field = .{\n            .node = self.nextNodeId(),\n            .value = value.node,\n            .field_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)),\n        } }, expected);\n    }\n",
    "    fn lowerField(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {\n        const access = self.tree.structFieldAccess(node).?;\n        if (self.tree.tag(access.value) == .identifier) {\n            const qualifier = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(access.value));\n            if (self.lookupBinding(qualifier) == null) {\n                if (self.moduleAliasPath(qualifier)) |module_path| {\n                    return self.pending(node, .{ .resolve_name_use = .{\n                        .node = self.nextNodeId(),\n                        .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)),\n                        .module_path = module_path,\n                    } }, expected);\n                }\n            }\n        }\n        const value = try self.lowerNode(access.value, null);\n        return self.pending(node, .{ .resolve_field = .{\n            .node = self.nextNodeId(),\n            .value = value.node,\n            .field_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)),\n        } }, expected);\n    }\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "    fn lowerImport(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {\n",
    "    fn lowerLocalModuleAlias(self: *Context, node: syn.NodeIndex) !bool {\n        const declaration = self.tree.symbolDeclaration(node) orelse return false;\n        const value = declaration.value orelse return false;\n        if (self.tree.tag(value) != .import_statement) return false;\n        const statement = self.tree.importStatement(value).?;\n        try self.module_aliases.append(.{\n            .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, declaration.name_token)),\n            .path = try self.writer.addString(self.tree.tokenTextFromSource(self.source, statement.path_token)),\n        });\n        return true;\n    }\n\n    fn lowerImport(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "            .tree = self.tree,\n            .source = self.source,\n        };\n        return lowerer.lower(node);\n",
    "            .tree = self.tree,\n            .source = self.source,\n            .module_aliases = self.module_aliases.items,\n        };\n        return lowerer.lower(node);\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "    fn pushScope(self: *Context) !void {\n        try self.scope_marks.append(self.bindings.items.len);\n    }\n    fn popScope(self: *Context) void {\n        const mark = self.scope_marks.pop().?;\n        self.bindings.shrinkRetainingCapacity(mark);\n    }\n",
    "    fn seedGlobalModuleAliases(self: *Context) !void {\n        self.module_aliases.clearRetainingCapacity();\n        for (self.graph.semantic.module_aliases.items) |alias| {\n            const declaration = self.graph.declarations.items[@intFromEnum(alias.declaration)];\n            try self.module_aliases.append(.{ .name = declaration.name, .path = alias.path });\n        }\n    }\n\n    fn moduleAliasPath(self: *const Context, name: []const u8) ?primitives.StringRange {\n        var index = self.module_aliases.items.len;\n        while (index != 0) {\n            index -= 1;\n            const alias = self.module_aliases.items[index];\n            if (std.mem.eql(u8, self.graph.text(alias.name), name)) return alias.path;\n        }\n        return null;\n    }\n\n    fn modulePathForQualifier(self: *Context, token: syn.TokenIndex) !primitives.StringRange {\n        const spelling = self.tree.tokenTextFromSource(self.source, token);\n        return self.moduleAliasPath(spelling) orelse try self.writer.addString(spelling);\n    }\n\n    fn pushScope(self: *Context) !void {\n        try self.scope_marks.append(.{\n            .bindings = self.bindings.items.len,\n            .module_aliases = self.module_aliases.items.len,\n        });\n    }\n    fn popScope(self: *Context) void {\n        const mark = self.scope_marks.pop().?;\n        self.bindings.shrinkRetainingCapacity(mark.bindings);\n        self.module_aliases.shrinkRetainingCapacity(mark.module_aliases);\n    }\n",
)

# Module paths have one canonical resolver. Durable top-level aliases and raw
# lexical import paths must converge to the same GlobalModuleId algorithm.
replace_once(
    "src/4_semantics/global/module_linker.zig",
    "fn resolveImportPath(\n",
    "pub fn resolveImportPath(\n",
)
replace_once(
    "src/4_semantics/global/core.zig",
    'const globalizer = @import("globalizer.zig");\n',
    'const globalizer = @import("globalizer.zig");\nconst module_linker = @import("module_linker.zig");\n',
)
replace_once(
    "src/4_semantics/global/core.zig",
    "        // Transitional/compiler-generated qualifiers may still spell a module\n        // directly; source import aliases never take this fallback.\n        return self.findModuleBySpelling(qualifier);\n",
    "        // Local lexical imports are lowered to their original path spelling.\n        // Reuse the linker algorithm so every source import has one identity rule.\n        return module_linker.resolveImportPath(self.allocator, self.graph, self.modules, current_module, qualifier);\n",
)

# Qualified global values use the same module path resolution as qualified
# calls/types. Keep the lookup itself in the dedicated name-lookup layer.
replace_once(
    "src/4_semantics/global/name_lookup.zig",
    "fn bindingInModule(\n",
    "pub fn bindingInModule(\n",
)
replace_once(
    "src/4_semantics/global/expressions.zig",
    'const name_lookup = @import("name_lookup.zig");\n',
    'const name_lookup = @import("name_lookup.zig");\nconst module_linker = @import("module_linker.zig");\n',
)
replace_once(
    "src/4_semantics/global/expressions.zig",
    "pub const Resolver = struct {\n    graph: *global_sg.GlobalSemanticGraph,\n",
    "pub const Resolver = struct {\n    allocator: std.mem.Allocator,\n    graph: *global_sg.GlobalSemanticGraph,\n",
)
replace_once(
    "src/4_semantics/global/expressions.zig",
    "        _ = module;\n        return switch (operation) {\n            .resolve_name_use => |value| resolution.Result.fromBool(self.resolveNameUse(module_index, o, value)),\n",
    "        return switch (operation) {\n            .resolve_name_use => |value| resolution.Result.fromBool(try self.resolveNameUse(module_index, module, o, value)),\n",
)
replace_once(
    "src/4_semantics/global/expressions.zig",
    "    fn resolveNameUse(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) bool {\n        const name = self.modules[module_index].text(value.name);\n        if (name_lookup.binding(self.modules, self.offsets, module_index, name)) |binding|\n            return self.patchNameUse(o, value.node, binding);\n        return self.patchTypeExpression(module_index, o, value.node, name);\n    }\n",
    "    fn resolveNameUse(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {\n        const name = module.text(value.name);\n        if (value.module_path) |path| {\n            const target = module_linker.resolveImportPath(\n                self.allocator,\n                self.graph,\n                self.modules,\n                module_index,\n                module.text(path),\n            ) catch return false;\n            const target_index: usize = @intFromEnum(target);\n            if (target_index != module_index and std.mem.startsWith(u8, name, \"_\")) return false;\n            const binding = name_lookup.bindingInModule(self.modules, self.offsets, target_index, name) orelse return false;\n            return self.patchNameUse(o, value.node, binding);\n        }\n        if (name_lookup.binding(self.modules, self.offsets, module_index, name)) |binding|\n            return self.patchNameUse(o, value.node, binding);\n        return self.patchTypeExpression(module_index, o, value.node, name);\n    }\n",
)
replace_n(
    "src/4_semantics/global/expressions.zig",
    "    var resolver: Resolver = .{ .graph = &graph,",
    "    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph,",
    2,
)
replace_once(
    "src/4_semantics/global/semantizer.zig",
    "    var expressions = expression_mod.Resolver{\n        .graph = &relocation.graph,\n",
    "    var expressions = expression_mod.Resolver{\n        .allocator = allocator,\n        .graph = &relocation.graph,\n",
)

Path(".git/semantic-refactor-message").write_text("Lower local imports as lexical module aliases\n")

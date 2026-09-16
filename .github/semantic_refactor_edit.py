from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1))


def replace_count(path: str, old: str, new: str, expected: int) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected} matches, found {count}: {old[:120]!r}")
    file.write_text(text.replace(old, new))


# Qualified references carry both semantic module identity (module_path) and
# source provenance (the spelling the user wrote plus the exact source site).
# The former is for lookup; the latter is for deterministic diagnostics.
replace_once(
    "src/4_semantics/module/entities.zig",
    "pub const ExternalRef = struct {\n"
    "    kind: ExternalKind,\n"
    "    module_path: ?primitives.StringRange,\n"
    "    name: primitives.StringRange,\n"
    "    generic_arguments: ?GenericArgRange = null,\n"
    "    source: primitives.SourceRef,\n"
    "};\n",
    "pub const ExternalRef = struct {\n"
    "    kind: ExternalKind,\n"
    "    module_path: ?primitives.StringRange,\n"
    "    name: primitives.StringRange,\n"
    "    module_qualifier: ?primitives.StringRange = null,\n"
    "    generic_arguments: ?GenericArgRange = null,\n"
    "    source: primitives.SourceRef,\n"
    "};\n",
)
replace_once(
    "src/4_semantics/module/entities.zig",
    "    resolve_name_use: struct {\n"
    "        node: ModuleNodeId,\n"
    "        name: primitives.StringRange,\n"
    "        module_path: ?primitives.StringRange = null,\n"
    "    },\n",
    "    resolve_name_use: struct {\n"
    "        node: ModuleNodeId,\n"
    "        name: primitives.StringRange,\n"
    "        module_path: ?primitives.StringRange = null,\n"
    "        module_qualifier: ?primitives.StringRange = null,\n"
    "        source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 },\n"
    "    },\n",
)

replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "        return self.pending(node, .{ .resolve_name_use = .{\n"
    "            .node = self.nextNodeId(),\n"
    "            .name = try self.writer.addString(text),\n"
    "        } }, expected);\n",
    "        return self.pending(node, .{ .resolve_name_use = .{\n"
    "            .node = self.nextNodeId(),\n"
    "            .name = try self.writer.addString(text),\n"
    "            .source = self.sourceRef(node),\n"
    "        } }, expected);\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "        const module_path = if (call.module_qualifier) |token_index|\n"
    "            try self.modulePathForQualifier(token_index)\n"
    "        else\n"
    "            null;\n"
    "        const external = try self.writer.addExternalRef(.{\n"
    "            .kind = .function,\n"
    "            .module_path = module_path,\n"
    "            .name = try self.writer.addString(name_text),\n"
    "            .source = self.sourceRef(node),\n"
    "        });\n",
    "        const module_path = if (call.module_qualifier) |token_index|\n"
    "            try self.modulePathForQualifier(token_index)\n"
    "        else\n"
    "            null;\n"
    "        const module_qualifier = if (call.module_qualifier) |token_index|\n"
    "            try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))\n"
    "        else\n"
    "            null;\n"
    "        const external = try self.writer.addExternalRef(.{\n"
    "            .kind = .function,\n"
    "            .module_path = module_path,\n"
    "            .name = try self.writer.addString(name_text),\n"
    "            .module_qualifier = module_qualifier,\n"
    "            .source = self.sourceRef(node),\n"
    "        });\n",
)
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "                    return self.pending(node, .{ .resolve_name_use = .{\n"
    "                        .node = self.nextNodeId(),\n"
    "                        .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)),\n"
    "                        .module_path = module_path,\n"
    "                    } }, expected);\n",
    "                    return self.pending(node, .{ .resolve_name_use = .{\n"
    "                        .node = self.nextNodeId(),\n"
    "                        .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)),\n"
    "                        .module_path = module_path,\n"
    "                        .module_qualifier = try self.writer.addString(qualifier),\n"
    "                        .source = self.sourceRef(node),\n"
    "                    } }, expected);\n",
)

replace_once(
    "src/4_semantics/module/type_lowerer.zig",
    "        const module_path = if (qualifier_token) |token_index|\n"
    "            try self.modulePathForQualifier(token_index)\n"
    "        else\n"
    "            null;\n"
    "        const external = try self.writer.addExternalRef(.{\n"
    "            .kind = .type,\n"
    "            .module_path = module_path,\n"
    "            .name = name,\n"
    "            .generic_arguments = generic_arguments,\n"
    "            .source = self.sourceRef(node),\n"
    "        });\n",
    "        const module_path = if (qualifier_token) |token_index|\n"
    "            try self.modulePathForQualifier(token_index)\n"
    "        else\n"
    "            null;\n"
    "        const module_qualifier = if (qualifier_token) |token_index|\n"
    "            try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))\n"
    "        else\n"
    "            null;\n"
    "        const external = try self.writer.addExternalRef(.{\n"
    "            .kind = .type,\n"
    "            .module_path = module_path,\n"
    "            .name = name,\n"
    "            .module_qualifier = module_qualifier,\n"
    "            .generic_arguments = generic_arguments,\n"
    "            .source = self.sourceRef(node),\n"
    "        });\n",
)

# Once a name resolves, retain the real source site rather than the placeholder
# node location installed by global relocation for pending nodes.
replace_once(
    "src/4_semantics/global/expressions.zig",
    'const module_linker = @import("module_linker.zig");\n',
    'const module_linker = @import("module_linker.zig");\nconst primitives = @import("../primitives/schema.zig");\n',
)
replace_count(
    "src/4_semantics/global/expressions.zig",
    "return self.patchNameUse(o, value.node, binding);",
    "return self.patchNameUse(o, value.node, binding, value.source);",
    2,
)
replace_once(
    "src/4_semantics/global/expressions.zig",
    "    fn patchNameUse(\n"
    "        self: *Resolver,\n"
    "        o: globalizer.Offsets,\n"
    "        node: module_entities.ModuleNodeId,\n"
    "        binding: global_sg.GlobalBindingId,\n"
    "    ) bool {\n"
    "        const target = globalizer.globalNode(o, node);\n"
    "        const source = self.graph.nodes.items[@intFromEnum(target)].source;\n"
    "        const ty = if (self.graph.isBindingTypeUnresolved(binding)) null else self.graph.bindings.items[@intFromEnum(binding)].ty;\n"
    "        self.graph.nodes.items[@intFromEnum(target)] = .{\n"
    "            .source = source,\n",
    "    fn patchNameUse(\n"
    "        self: *Resolver,\n"
    "        o: globalizer.Offsets,\n"
    "        node: module_entities.ModuleNodeId,\n"
    "        binding: global_sg.GlobalBindingId,\n"
    "        local_source: primitives.SourceRef,\n"
    "    ) bool {\n"
    "        const target = globalizer.globalNode(o, node);\n"
    "        const source: primitives.SourceRef = .{ .file_index = o.file_base + local_source.file_index, .offset = local_source.offset };\n"
    "        const ty = if (self.graph.isBindingTypeUnresolved(binding)) null else self.graph.bindings.items[@intFromEnum(binding)].ty;\n"
    "        self.graph.nodes.items[@intFromEnum(target)] = .{\n"
    "            .source = source,\n",
)

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()

import_anchor = 'const module_views = @import("../module/views.zig");\n'
if text.count(import_anchor) != 1:
    raise RuntimeError("semantizer module_views import anchor changed")
text = text.replace(import_anchor, import_anchor + 'const primitives = @import("../primitives/schema.zig");\n', 1)

old_diag = (
    "        if (options.diagnostics) |diagnostics| {\n"
    "            if (try diagnoseUnresolvedChoice(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
)
new_diag = (
    "        if (options.diagnostics) |diagnostics| {\n"
    "            if (try diagnoseUnresolvedQualifiedTypes(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
    "            if (try diagnoseUnresolvedQualifiedNames(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
    "            if (try diagnoseUnresolvedChoice(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
)
if text.count(old_diag) != 1:
    raise RuntimeError("semantizer diagnostic sequence anchor changed")
text = text.replace(old_diag, new_diag, 1)

old_unresolved_types = (
    "    if (relocation.graph.hasUnresolvedTypes()) {\n"
    "        std.debug.print(\"global sema unresolved global type slots remain\\n\", .{});\n"
    "        return error.UnsupportedGlobalSemantic;\n"
    "    }\n"
)
new_unresolved_types = (
    "    if (relocation.graph.hasUnresolvedTypes()) {\n"
    "        if (options.diagnostics) |diagnostics|\n"
    "            if (try diagnoseUnresolvedQualifiedTypes(allocator, &relocation.graph, modules, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
    "        std.debug.print(\"global sema unresolved global type slots remain\\n\", .{});\n"
    "        return error.UnsupportedGlobalSemantic;\n"
    "    }\n"
)
if text.count(old_unresolved_types) != 1:
    raise RuntimeError("unresolved type fallback anchor changed")
text = text.replace(old_unresolved_types, new_unresolved_types, 1)

choice_marker = "fn diagnoseUnresolvedChoice(\n"
if text.count(choice_marker) != 1:
    raise RuntimeError("choice diagnostic marker changed")
helpers = r'''fn diagnoseUnresolvedQualifiedTypes(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    for (modules, 0..) |*module, module_index| {
        for (0..module_views.typeCount(module)) |raw| {
            const local_type: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            const external = switch (try module_views.typeView(module, local_type)) {
                .external => |id| id,
                .resolved => continue,
            };
            const global_type = globalizer.globalType(offsets[module_index], local_type);
            if (!graph.isTypeUnresolved(global_type)) continue;
            const reference = module.semantic.external_refs.items[@intFromEnum(external)];
            if (reference.kind != .type or reference.module_path == null) continue;
            const target = module_linker.resolveImportPath(
                allocator,
                graph,
                modules,
                module_index,
                module.text(reference.module_path.?),
            ) catch |err| switch (err) {
                error.UnknownModuleReference, error.AmbiguousModuleReference => continue,
                else => return err,
            };
            if (@intFromEnum(target) == module_index) continue;
            const name = module.text(reference.name);
            if (!std.mem.startsWith(u8, name, "_")) continue;
            if (!declarationNameExistsInModule(graph, target, name, &.{ .type, .abstract_type })) continue;
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], reference.source)),
                .semantic,
                "type '{s}' is private to its module",
                .{name},
            );
            return true;
        }
    }
    return false;
}

fn diagnoseUnresolvedQualifiedNames(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const value = switch (operation) {
                .resolve_name_use => |item| item,
                else => continue,
            };
            const path = value.module_path orelse continue;
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |item| globalizer.globalFunction(offsets[module_index], item) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;

            const target = module_linker.resolveImportPath(
                allocator,
                graph,
                modules,
                module_index,
                module.text(path),
            ) catch |err| switch (err) {
                error.UnknownModuleReference, error.AmbiguousModuleReference => continue,
                else => return err,
            };
            const target_index: usize = @intFromEnum(target);
            const name = module.text(value.name);
            if (moduleBindingNameExists(&modules[target_index], name)) {
                if (target_index == module_index or !std.mem.startsWith(u8, name, "_")) continue;
                try diagnostics.add(
                    diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], value.source)),
                    .semantic,
                    "value '{s}' is private to its module",
                    .{name},
                );
                return true;
            }
            try diagnostics.add(
                diagnosticLocation(graph, diagnostics, globalSource(offsets[module_index], value.source)),
                .semantic,
                "module '{s}' has no value '.{s}'",
                .{ moduleQualifierText(module, path, value.module_qualifier), name },
            );
            return true;
        }
    }
    return false;
}

fn globalSource(o: globalizer.Offsets, source: primitives.SourceRef) primitives.SourceRef {
    return .{ .file_index = o.file_base + source.file_index, .offset = source.offset };
}

fn moduleQualifierText(
    module: *const module_sg.ModuleSemanticGraph,
    path: primitives.StringRange,
    qualifier: ?primitives.StringRange,
) []const u8 {
    if (qualifier) |value| return module.text(value);
    const spelling = std.mem.trim(u8, module.text(path), "\"'");
    return std.fs.path.basename(spelling);
}

fn moduleBindingNameExists(module: *const module_sg.ModuleSemanticGraph, name: []const u8) bool {
    for (module.semantic.declaration_bindings.items) |relation| {
        const declaration = module.declarations.items[@intFromEnum(relation.declaration)];
        if (std.mem.eql(u8, module.text(declaration.name), name)) return true;
    }
    return false;
}

fn declarationNameExistsInModule(
    graph: *const global_sg.GlobalSemanticGraph,
    module: global_sg.GlobalModuleId,
    name: []const u8,
    kinds: []const primitives.DeclarationKind,
) bool {
    for (graph.declarations.items, 0..) |declaration, raw| {
        const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
        if (graph.moduleForDeclaration(id) != module) continue;
        if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        for (kinds) |kind| if (declaration.kind == kind) return true;
    }
    return false;
}

fn functionDeclarationVisibleForDiagnostic(
    graph: *const global_sg.GlobalSemanticGraph,
    current_module: usize,
    declaration: global_sg.GlobalDeclId,
    qualified_module: ?global_sg.GlobalModuleId,
) bool {
    const owner = graph.moduleForDeclaration(declaration) orelse return false;
    const own_module = @intFromEnum(owner) == current_module;
    const name = graph.text(graph.declarations.items[@intFromEnum(declaration)].name);
    if (!own_module and std.mem.startsWith(u8, name, "_")) return false;
    if (qualified_module) |wanted| return owner == wanted;
    return own_module or graph.modules.items[@intFromEnum(owner)].is_bundled_core;
}

fn visibleFunctionNameExists(
    graph: *const global_sg.GlobalSemanticGraph,
    current_module: usize,
    qualified_module: ?global_sg.GlobalModuleId,
    name: []const u8,
) bool {
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .function and declaration.kind != .test_function) continue;
        if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
        if (functionDeclarationVisibleForDiagnostic(graph, current_module, id, qualified_module)) return true;
    }
    return false;
}

'''
text = text.replace(choice_marker, helpers + choice_marker, 1)

start = text.index("fn diagnoseUnresolvedCall(\n")
end = text.index("fn appendValueShape(", start)
new_call = r'''fn diagnoseUnresolvedCall(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const call = switch (operation) {
                .resolve_call => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;

            const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
            const name = module.text(reference.name);
            const qualified_module: ?global_sg.GlobalModuleId = if (reference.module_path) |path|
                module_linker.resolveImportPath(allocator, graph, modules, module_index, module.text(path)) catch |err| switch (err) {
                    error.UnknownModuleReference, error.AmbiguousModuleReference => null,
                    else => return err,
                }
            else
                null;
            const location = diagnosticLocation(graph, diagnostics, .{
                .file_index = offsets[module_index].file_base + reference.source.file_index,
                .offset = reference.source.offset + @as(u32, @intCast(name.len)),
            });

            if (reference.module_path) |path| {
                const target = qualified_module orelse continue;
                const has_name = declarationNameExistsInModule(graph, target, name, &.{ .function, .test_function });
                if (has_name and @intFromEnum(target) != module_index and std.mem.startsWith(u8, name, "_")) {
                    try diagnostics.add(location, .semantic, "function '{s}' is private to its module", .{name});
                    return true;
                }
                if (!has_name) {
                    try diagnostics.add(
                        location,
                        .semantic,
                        "module '{s}' has no function named '{s}'",
                        .{ moduleQualifierText(module, path, reference.module_qualifier), name },
                    );
                    return true;
                }
            } else if (!visibleFunctionNameExists(graph, module_index, null, name)) {
                try diagnostics.add(location, .semantic, "no function named '{s}' exists", .{name});
                return true;
            }

            const input_id = globalizer.globalNode(offsets[module_index], call.input);
            const input = switch (graph.node(input_id).content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
            var input_complete = true;
            for (graph.value_fields.items[input.fields.start..][0..input.fields.len]) |field| {
                const ty = graph.node(field.value).ty orelse {
                    input_complete = false;
                    break;
                };
                if (graph.isTypeUnresolved(ty)) {
                    input_complete = false;
                    break;
                }
            }
            if (!input_complete) continue;

            var candidates: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer candidates.deinit(allocator);
            for (graph.functions.items, 0..) |function, raw| {
                const declaration = graph.declaration(function.declaration);
                if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
                if (!functionDeclarationVisibleForDiagnostic(graph, module_index, function.declaration, qualified_module)) continue;
                try candidates.append(allocator, @enumFromInt(@as(u32, @intCast(raw))));
            }
            if (candidates.items.len == 0) continue;

            var message = std.array_list.Managed(u8).init(allocator);
            defer message.deinit();
            try message.appendSlice("no overload of '");
            try message.appendSlice(name);
            try message.appendSlice("' accepts arguments ");
            try appendValueShape(&message, graph, input);
            try message.appendSlice(". Available signatures:");
            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                try message.appendSlice("\n  - ");
                try message.appendSlice(name);
                try message.append(' ');
                try appendFieldShape(&message, graph, function.input);
                try message.appendSlice(" -> ");
                try appendFieldShape(&message, graph, function.output);
            }
            try diagnostics.add(location, .semantic, "{s}", .{message.items});
            return true;
        }
    }
    return false;
}

'''
text = text[:start] + new_call + text[end:]
semantizer.write_text(text)

Path(".git/semantic-refactor-message").write_text("Diagnose unresolved imported symbols at their source\n")

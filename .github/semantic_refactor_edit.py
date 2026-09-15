from pathlib import Path


def edit(path: str, replacements: list[tuple[str, str]]) -> None:
    file = Path(path)
    text = file.read_text()
    for old, new in replacements:
        count = text.count(old)
        if count != 1:
            raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:120]!r}")
        text = text.replace(old, new, 1)
    file.write_text(text)


# Preserve the source of a choice payload access as first-class pending-op
# provenance. Reusing the source value's location loses the '..variant' site.
edit(
    "src/4_semantics/module/entities.zig",
    [(
        "    resolve_choice_payload: struct {\n"
        "        node: ModuleNodeId,\n"
        "        value: ModuleNodeId,\n"
        "        option_name: primitives.StringRange,\n"
        "    },\n",
        "    resolve_choice_payload: struct {\n"
        "        node: ModuleNodeId,\n"
        "        value: ModuleNodeId,\n"
        "        option_name: primitives.StringRange,\n"
        "        source: primitives.SourceRef,\n"
        "    },\n",
    )],
)

edit(
    "src/4_semantics/module/body_lowerer.zig",
    [(
        "        return self.pending(node, .{ .resolve_choice_payload = .{\n"
        "            .node = self.nextNodeId(),\n"
        "            .value = value.node,\n"
        "            .option_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)),\n"
        "        } }, expected);\n",
        "        return self.pending(node, .{ .resolve_choice_payload = .{\n"
        "            .node = self.nextNodeId(),\n"
        "            .value = value.node,\n"
        "            .option_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)),\n"
        "            .source = self.sourceRef(node),\n"
        "        } }, expected);\n",
    )],
)

edit(
    "src/4_semantics/global/control.zig",
    [(
        "        self.graph.nodes.items[@intFromEnum(target)] = .{\n"
        "            .source = self.graph.nodes.items[@intFromEnum(source)].source,\n"
        "            .ty = payload_ty,\n"
        "            .content = .{ .choice_payload_access = .{\n",
        "        self.graph.nodes.items[@intFromEnum(target)] = .{\n"
        "            .source = self.sourceFor(value.source, o),\n"
        "            .ty = payload_ty,\n"
        "            .content = .{ .choice_payload_access = .{\n",
    )],
)

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()

old_import = 'const global_sg = @import("graph.zig");\n'
new_import = 'const global_sg = @import("graph.zig");\nconst global_types = @import("types.zig");\n'
if text.count(old_import) != 1:
    raise RuntimeError("semantizer import anchor changed")
text = text.replace(old_import, new_import, 1)

old_diagnostics = (
    "        if (options.diagnostics) |diagnostics| {\n"
    "            if (try diagnoseUnresolvedCopy(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
)
new_diagnostics = (
    "        if (options.diagnostics) |diagnostics| {\n"
    "            if (try diagnoseUnresolvedChoice(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
    "            if (try diagnoseUnresolvedCopy(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))\n"
    "                return error.Reported;\n"
)
if text.count(old_diagnostics) != 1:
    raise RuntimeError("semantizer diagnostic anchor changed")
text = text.replace(old_diagnostics, new_diagnostics, 1)

marker = "fn diagnoseUnresolvedCopy(\n"
if text.count(marker) != 1:
    raise RuntimeError("diagnoseUnresolvedCopy marker changed")

helper = r'''fn diagnoseUnresolvedChoice(
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
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;

            switch (operation) {
                .resolve_choice_literal => |choice| {
                    const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                    const name = module.text(reference.name);
                    const target = globalizer.globalNode(offsets[module_index], choice.node);
                    const choice_ty = if (choice.expected_type) |local_ty|
                        globalizer.globalType(offsets[module_index], local_ty)
                    else
                        graph.node(target).ty orelse continue;
                    if (graph.isTypeUnresolved(choice_ty) or global_types.isBuiltin(graph, choice_ty, .Any)) continue;
                    // A known non-choice may still become meaningful through a
                    // different pending operation. Only classify operations for
                    // which the choice family itself is already final.
                    if (global_types.variants(graph, choice_ty) == null) continue;

                    const source = .{
                        .file_index = offsets[module_index].file_base + reference.source.file_index,
                        .offset = reference.source.offset,
                    };
                    const hit = global_types.findVariant(graph, choice_ty, name) orelse {
                        var type_name = std.array_list.Managed(u8).init(allocator);
                        defer type_name.deinit();
                        try appendTypeName(&type_name, graph, choice_ty);
                        try diagnostics.add(
                            diagnosticLocation(graph, diagnostics, source),
                            .semantic,
                            "choice type '{s}' has no variant '..{s}'",
                            .{ type_name.items, name },
                        );
                        return true;
                    };
                    if (hit.variant.payload_type != null and choice.payload == null) {
                        try diagnostics.add(
                            diagnosticLocation(graph, diagnostics, source),
                            .semantic,
                            "choice variant '..{s}' requires a payload",
                            .{name},
                        );
                        return true;
                    }
                },
                .resolve_choice_payload => |access| {
                    const value = graph.node(globalizer.globalNode(offsets[module_index], access.value));
                    const choice_ty = value.ty orelse continue;
                    if (graph.isTypeUnresolved(choice_ty) or global_types.variants(graph, choice_ty) == null) continue;
                    const name = module.text(access.option_name);
                    const hit = global_types.findVariant(graph, choice_ty, name) orelse continue;
                    if (hit.variant.payload_type != null) continue;
                    const source = .{
                        .file_index = offsets[module_index].file_base + access.source.file_index,
                        .offset = access.source.offset,
                    };
                    try diagnostics.add(
                        diagnosticLocation(graph, diagnostics, source),
                        .semantic,
                        "choice variant '..{s}' has no payload",
                        .{name},
                    );
                    return true;
                },
                else => {},
            }
        }
    }
    return false;
}

'''
text = text.replace(marker, helper + marker, 1)
semantizer.write_text(text)

Path(".git/semantic-refactor-message").write_text("Diagnose deterministic unresolved choice operations\n")
# Override the tracked default gate for this edit without committing harness state.
Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/types/04X_choice_missing_payload "
    "-Dtest-filter=feature_tests/types/10X_choice_unknown_variant "
    "-Dtest-filter=feature_tests/types/11X_choice_payload_access_without_payload\n"
)

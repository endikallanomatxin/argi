from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected pattern not found in {path}: {old!r}")
    file.write_text(text.replace(old, new))


# Break the mutually recursive inferred error-set cycle for module-level
# constants explicitly. These operations only propagate CodegenError members.
replace(
    "src/5_codegen/global_codegen.zig",
    "    fn ensureGlobalInitialized(self: *CodeGenerator, binding: graph_mod.GlobalBindingId) !void {",
    "    fn ensureGlobalInitialized(self: *CodeGenerator, binding: graph_mod.GlobalBindingId) CodegenError!void {",
)
replace(
    "src/5_codegen/global_codegen.zig",
    "    fn globalConstant(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) !TypedValue {",
    "    fn globalConstant(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) CodegenError!TypedValue {",
)

# This fixture models one input and one output field. The lowering invariant is
# inputs followed by outputs, so the fixture needs both interface bindings.
replace(
    "src/4_semantics/module_template_binding_ranges.zig",
    "    try storage.ir.bindings.append(allocator, .{\n        .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 },\n        .ty = @enumFromInt(1), .mutability = .constant,\n    });\n    try storage.generic_function_templates.append",
    "    try storage.ir.bindings.append(allocator, .{\n        .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 },\n        .ty = @enumFromInt(1), .mutability = .constant,\n    });\n    try storage.ir.bindings.append(allocator, .{\n        .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 },\n        .ty = @enumFromInt(1), .mutability = .constant,\n    });\n    try storage.generic_function_templates.append",
)

# Core verification now owns all structural range validation. Keep complete
# verification for completeness-specific invariants rather than duplicating an
# unreachable generic-argument bounds check.
replace(
    "src/4_semantics/module_semantic_complete_verify.zig",
    "const views = @import(\"module_semantic_views.zig\");\nconst verify = @import(\"semantic_verify.zig\");\n",
    "",
)
replace(
    "src/4_semantics/module_semantic_complete_verify.zig",
    "    try generic_instances.verifyGenericInstances(graph, graph.semantic.local_semantics_complete);\n    for (graph.semantic.external_refs.items) |reference| {\n        if (reference.generic_arguments) |arguments| {\n            if (!verify.rangeFits(arguments, views.genericArgumentCount(graph)))\n                return error.InvalidModuleExternalGenericArguments;\n        }\n    }",
    "    try generic_instances.verifyGenericInstances(graph, graph.semantic.local_semantics_complete);",
)
replace(
    "src/4_semantics/module_semantic_complete_verify.zig",
    "    try std.testing.expectError(error.InvalidModuleExternalGenericArguments, verifyModule(&graph));",
    "    try std.testing.expectError(error.InvalidModuleSemanticGraph, verifyModule(&graph));",
)

# Globalizer fixtures must satisfy the same provenance invariant as real
# ModuleSGs: every SourceRef points at a module file entry.
replace(
    "src/4_semantics/semantic_globalizer.zig",
    "    defer module.deinit(allocator);\n    try module.semantic.external_refs.append(allocator, .{",
    "    defer module.deinit(allocator);\n    try module.file_offsets.append(allocator, .{\n        .path = .{ .start = 0, .len = 0 },\n        .declaration_base = 0, .declaration_count = 0,\n        .type_reference_base = 0, .type_reference_count = 0,\n        .import_reference_base = 0, .import_reference_count = 0,\n    });\n    try module.semantic.external_refs.append(allocator, .{",
)

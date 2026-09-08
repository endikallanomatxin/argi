from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected pattern not found in {path}: {old!r}")
    file.write_text(text.replace(old, new))


# Safety no longer needs the enclosing function identity for auto-deinit.
replace(
    "src/4_semantics/global_safety_checker.zig",
    "    fn applyAutoDeinit(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, id: graph_mod.GlobalAutoDeinitId, state: *FunctionState) !void {\n        const cleanup",
    "    fn applyAutoDeinit(self: *SafetyChecker, function: graph_mod.GlobalFunctionId, id: graph_mod.GlobalAutoDeinitId, state: *FunctionState) !void {\n        _ = function;\n        const cleanup",
)

# Zig 0.16 does not implicitly lift !bool into !?bool. Every resolver arm
# participates in the same optional-dispatch protocol, so normalize them all.
for old, new in [
    (
        "            .resolve_type => |value| self.resolveTypeHole(module_index, module, o, value),",
        "            .resolve_type => |value| @as(?bool, try self.resolveTypeHole(module_index, module, o, value)),",
    ),
    (
        "            .resolve_call => |value| self.resolveCall(module_index, module, o, value),",
        "            .resolve_call => |value| @as(?bool, try self.resolveCall(module_index, module, o, value)),",
    ),
    (
        "            .resolve_field => |value| self.resolveField(module, o, value),",
        "            .resolve_field => |value| @as(?bool, try self.resolveField(module, o, value)),",
    ),
    (
        "            .resolve_binary => |value| self.resolveBinary(module_index, o, value),",
        "            .resolve_binary => |value| @as(?bool, try self.resolveBinary(module_index, o, value)),",
    ),
    (
        "            .resolve_comparison => |value| self.resolveComparison(module_index, o, value),",
        "            .resolve_comparison => |value| @as(?bool, try self.resolveComparison(module_index, o, value)),",
    ),
    (
        "            .resolve_index => |value| self.resolveIndex(module_index, o, value),",
        "            .resolve_index => |value| @as(?bool, try self.resolveIndex(module_index, o, value)),",
    ),
]:
    replace("src/4_semantics/global_semantic_core.zig", old, new)

# TemplateIR resolved shapes are the shared semantic type instantiated with Template IDs.
replace(
    "src/4_semantics/module_semantic_template_ir.zig",
    "pub const Field = primitives.Field(Ids);",
    "pub const ResolvedType = primitives.SemanticType(Ids);\npub const Field = primitives.Field(Ids);",
)

# LSP facade returns an optional owned slice; unwrap allocation failure first.
replace(
    "src/0_commands/lsp_service.zig",
    "    return output.toOwnedSlice();",
    "    return try output.toOwnedSlice();",
)

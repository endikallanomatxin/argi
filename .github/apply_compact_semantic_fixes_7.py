from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected pattern not found in {path}: {old!r}")
    file.write_text(text.replace(old, new))

replace(
    "src/5_codegen/global_codegen.zig",
    "        const pointer = try self.addressablePointer(target);\n        pointer.ty = self.graph.nodes.items[@intFromEnum(node_id)].ty;",
    "        var pointer = try self.addressablePointer(target);\n        pointer.ty = self.graph.nodes.items[@intFromEnum(node_id)].ty;",
)
replace(
    "src/5_codegen/global_codegen.zig",
    "    fn addressablePointer(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) CodegenError!TypedValue {",
    "    fn addressablePointer(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) anyerror!TypedValue {",
)

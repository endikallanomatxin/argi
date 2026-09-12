from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old in text:
        file.write_text(text.replace(old, new, 1))
        return
    assert new in text, f"missing old and new forms in {path}"


replace_once(
    "src/4_semantics/global/core.zig",
    "        self.graph.nodes.items[@intFromEnum(node)].content.struct_value_literal.ty = target;\n",
    "",
)

replace_once(
    "src/4_semantics/global/core.zig",
    "        .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 }, .ty = input_ty } },\n",
    "        .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } },\n",
)

replace_once(
    "src/4_semantics/global/constructors.zig",
    """            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = 0, .len = 0 },
                .ty = input_type,
            } },
""",
    """            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = 0, .len = 0 },
            } },
""",
)

print("struct literal fixtures updated")

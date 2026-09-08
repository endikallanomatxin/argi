from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected pattern not found in {path}: {old!r}")
    file.write_text(text.replace(old, new))


# Keep the existing hover formatting helpers while adapting their sink to
# Zig 0.16, where Managed ArrayList no longer exposes writer().
replace(
    "src/0_commands/indexed_lsp_service.zig",
    "fn formatHover(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, target: editor_index.Target) ![]u8 {",
    """const HoverWriter = struct {
    allocator: std.mem.Allocator,
    buffer: *std.array_list.Managed(u8),

    fn writeAll(self: HoverWriter, text: []const u8) !void {
        try self.buffer.appendSlice(text);
    }

    fn print(self: HoverWriter, comptime format: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(text);
        try self.buffer.appendSlice(text);
    }
};

fn formatHover(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, target: editor_index.Target) ![]u8 {""",
)
replace(
    "src/0_commands/indexed_lsp_service.zig",
    "    const writer = output.writer();",
    "    const writer = HoverWriter{ .allocator = allocator, .buffer = &output };",
)

# Auto-deinit field ranges are table ranges, not members of GlobalSemanticGraph.
replace(
    "src/5_codegen/global_codegen.zig",
    "        fields: graph_mod.GlobalSemanticGraph.AutoDeinitFieldRange,",
    "        fields: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),",
)

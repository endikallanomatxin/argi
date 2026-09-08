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

    fn writeAll(self: HoverWriter, text: []const u8) std.mem.Allocator.Error!void {
        try self.buffer.appendSlice(text);
    }

    fn print(self: HoverWriter, comptime format: []const u8, args: anytype) std.mem.Allocator.Error!void {
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
replace(
    "src/0_commands/indexed_lsp_service.zig",
    "fn writeFieldRange(writer: anytype, graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.FieldRange) !void {",
    "fn writeFieldRange(writer: HoverWriter, graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.FieldRange) std.mem.Allocator.Error!void {",
)
replace(
    "src/0_commands/indexed_lsp_service.zig",
    "fn writeType(writer: anytype, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !void {",
    "fn writeType(writer: HoverWriter, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) std.mem.Allocator.Error!void {",
)
replace(
    "src/0_commands/indexed_lsp_service.zig",
    "fn writeVariants(writer: anytype, graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.VariantRange) !void {",
    "fn writeVariants(writer: HoverWriter, graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.VariantRange) std.mem.Allocator.Error!void {",
)

# Auto-deinit field ranges are table ranges, not members of GlobalSemanticGraph.
replace(
    "src/5_codegen/global_codegen.zig",
    "        fields: graph_mod.GlobalSemanticGraph.AutoDeinitFieldRange,",
    "        fields: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),",
)

# addressablePointer is fallible, not optional. Only InvalidType means "this
# value is not addressable" and should fall back to extracting from a value;
# preserve real failures such as OOM or missing symbols.
replace(
    "src/5_codegen/global_codegen.zig",
    "    fn addressablePointer(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) !TypedValue {",
    "    fn addressablePointer(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) CodegenError!TypedValue {",
)
replace(
    "src/5_codegen/global_codegen.zig",
    "        if (self.addressablePointer(node_id)) |pointer_result| {\n            const pointer = pointer_result catch return CodegenError.InvalidType;",
    "        const maybe_pointer: ?TypedValue = self.addressablePointer(node_id) catch |err| switch (err) {\n            error.InvalidType => null,\n            else => return err,\n        };\n        if (maybe_pointer) |pointer| {",
)

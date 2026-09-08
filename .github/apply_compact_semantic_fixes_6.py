from pathlib import Path

path = Path("src/0_commands/indexed_lsp_service.zig")
text = path.read_text()

stale = '''const HoverWriter = struct {
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

'''

if stale in text:
    text = text.replace(stale, "", 1)

path.write_text(text)

const std = @import("std");
const lexical = @import("../1_base/lexical.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");

const reset = "\x1b[0m";
fn colored(output: *std.Io.Writer, source: []const u8, color: ?[]const u8) !void {
    if (color) |prefix| try output.writeAll(prefix);
    try output.writeAll(source);
    if (color != null) try output.writeAll(reset);
}

/// Presentation only: incomplete input is normal and diagnostics are discarded.
/// Color escapes never enter the editable source or its history.
pub fn render(allocator: std.mem.Allocator, output: *std.Io.Writer, line: []const u8, quote: ?u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diagnostics = try @import("../1_base/diagnostic.zig").Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var scanner = tokenizer.Tokenizer.init(a, &diagnostics, line, .unknown);
    defer scanner.deinit();
    if (quote) |delimiter| {
        const tail = lexical.quotedTail(line, 0, delimiter);
        try colored(output, line[0..tail.end], "\x1b[32m");
        scanner.location.offset = @intCast(tail.end);
    }
    while (scanner.location.offset < line.len) {
        const start: usize = scanner.location.offset;
        if (line[start] == '"' or line[start] == '\'') {
            const literal = lexical.quoted(line, start);
            try colored(output, line[start..literal.end], "\x1b[32m");
            scanner.location.offset = @intCast(literal.end);
            continue;
        }
        scanner.tokens.clearRetainingCapacity();
        scanner.lexNextToken() catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {},
        };
        if (scanner.location.offset <= start) scanner.location.offset = @intCast(start + 1);
        const end: usize = scanner.location.offset;
        const class = if (scanner.tokens.len == 0) null else token.lexicalClass(scanner.tokens.items(.content)[0]);
        const color: ?[]const u8 = if (class) |kind| switch (kind) {
            .keyword => "\x1b[35m",
            .number => "\x1b[33m",
            .string => "\x1b[32m",
            .comment => "\x1b[90m",
            .operator => "\x1b[34m",
            .identifier => if (std.ascii.isUpper(line[start])) "\x1b[36m" else if (start > 0 and line[start - 1] == '#') "\x1b[35m" else null,
        } else if (std.ascii.isDigit(line[start])) "\x1b[33m" else null;
        try colored(output, line[start..end], color);
    }
}

test "REPL highlighting uses token categories and tolerates unfinished literals" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try render(std.testing.allocator, &output.writer, "if true { value: Int32 = 0xff -- }", null);
    const text = output.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "\x1b[35mif\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\x1b[33m0xff\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\x1b[90m-- }\x1b[0m") != null);
    try render(std.testing.allocator, &output.writer, "\"unfinished € {", null);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "\x1b[32m\"unfinished € {\x1b[0m"));
    try render(std.testing.allocator, &output.writer, "continued }\" + 1e+", '"');
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\x1b[32mcontinued }\"\x1b[0m") != null);
}

test "REPL highlighting releases scratch on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn paint(a: std.mem.Allocator) !void {
            var buffer: [1024]u8 = undefined;
            var output = std.Io.Writer.fixed(&buffer);
            try render(a, &output, "if 1e+ @ \"unfinished", null);
        }
    }.paint, .{});
}

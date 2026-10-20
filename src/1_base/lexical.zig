const std = @import("std");

pub fn identifierContinue(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

pub fn commentEnd(source: []const u8, start: usize) usize {
    std.debug.assert(std.mem.startsWith(u8, source[start..], "--"));
    return std.mem.indexOfScalarPos(u8, source, start, '\n') orelse source.len;
}

pub fn escape(quote: u8, byte: u8) ?u21 {
    return switch (byte) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        '\\' => '\\',
        '0' => 0,
        '\'', '"' => if (byte == quote) byte else null,
        else => null,
    };
}

pub const Quoted = struct {
    /// End excludes the closing quote from the content, when present.
    content_end: usize,
    end: usize,
    closed: bool,
    invalid_escape: ?usize = null,
};

/// Boundaries are useful even when an inactive branch contains invalid tokens.
/// The tokenizer decides when to report escape, scalar and UTF-8 diagnostics.
pub fn quoted(source: []const u8, start: usize) Quoted {
    const quote = source[start];
    std.debug.assert(quote == '\'' or quote == '"');
    var offset = start + 1;
    var invalid: ?usize = null;
    while (offset < source.len) {
        const byte = source[offset];
        if (byte == quote) return .{ .content_end = offset, .end = offset + 1, .closed = true, .invalid_escape = invalid };
        offset += 1;
        if (byte == '\\' and offset < source.len) {
            if (invalid == null and escape(quote, source[offset]) == null) invalid = offset;
            offset += 1;
        }
    }
    return .{ .content_end = source.len, .end = source.len, .closed = false, .invalid_escape = invalid };
}

test "quoted boundaries retain invalid escapes without accepting them" {
    const source = "\"\\q #if hidden { \\\" }\" tail";
    const literal = quoted(source, 0);
    try std.testing.expect(literal.closed);
    try std.testing.expectEqual(@as(?usize, 2), literal.invalid_escape);
    try std.testing.expectEqualStrings(" tail", source[literal.end..]);
    try std.testing.expectEqual(@as(?u21, '\''), escape('\'', '\''));
    try std.testing.expectEqual(null, escape('"', '\''));
    try std.testing.expect(!quoted("\"trailing\\", 0).closed);
}

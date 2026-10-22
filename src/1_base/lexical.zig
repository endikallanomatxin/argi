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
    return quotedTail(source, start + 1, quote);
}

fn quotedTail(source: []const u8, start: usize, quote: u8) Quoted {
    var offset = start;
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

/// Incremental delimiter completion for line-oriented interactive input. This
/// recognizes boundaries only; tokenization remains responsible for diagnostics.
pub const Completion = struct {
    stack: [256]u8 = undefined,
    depth: usize = 0,
    quote: ?u8 = null,
    invalid: bool = false,

    pub fn feedLine(self: *Completion, line: []const u8) void {
        var offset: usize = 0;
        while (offset < line.len) : (offset += 1) {
            const byte = line[offset];
            if (self.quote) |quote| {
                const tail = quotedTail(line, offset, quote);
                if (!tail.closed) return;
                self.quote = null;
                offset = tail.end - 1;
                continue;
            }
            if (byte == '-' and offset + 1 < line.len and line[offset + 1] == '-') return;
            if (byte == '\'' or byte == '"') {
                self.quote = byte;
                continue;
            }
            switch (byte) {
                '(', '[', '{' => {
                    if (self.depth == self.stack.len) {
                        self.invalid = true;
                        return;
                    }
                    self.stack[self.depth] = byte;
                    self.depth += 1;
                },
                ')', ']', '}' => {
                    const expected: u8 = switch (byte) {
                        ')' => '(',
                        ']' => '[',
                        else => '{',
                    };
                    if (self.depth == 0 or self.stack[self.depth - 1] != expected) {
                        self.invalid = true;
                        return;
                    }
                    self.depth -= 1;
                },
                else => {},
            }
        }
    }

    pub fn complete(self: *const Completion) bool {
        return self.invalid or (self.depth == 0 and self.quote == null);
    }
};

test "interactive completion tracks delimiters without counting quoted or commented braces" {
    var state: Completion = .{};
    state.feedLine("answer := () -> () { -- } ignored");
    try std.testing.expect(!state.complete());
    state.feedLine("text ::= \"}\" -- { ignored");
    try std.testing.expect(!state.complete());
    state.feedLine("}");
    try std.testing.expect(state.complete());
    state = .{};
    state.feedLine("text ::= \"unfinished { ");
    try std.testing.expect(!state.complete());
    state.feedLine("continued }\"");
    try std.testing.expect(state.complete());
    state = .{};
    state.feedLine("([)");
    try std.testing.expect(state.complete());
    try std.testing.expect(state.invalid);
}

const std = @import("std");
const target_mod = @import("target.zig");

pub const Query = enum { target_os, target_arch, target_abi };

pub fn matches(target: target_mod.Config, query: Query, name: []const u8) !bool {
    return switch (query) {
        .target_os => target.os == (std.meta.stringToEnum(std.Target.Os.Tag, name) orelse return error.UnknownTargetValue),
        .target_arch => target.arch == (std.meta.stringToEnum(std.Target.Cpu.Arch, name) orelse return error.UnknownTargetValue),
        .target_abi => target.abi == (std.meta.stringToEnum(std.Target.Abi, name) orelse return error.UnknownTargetValue),
    };
}

pub fn errorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.UnknownTargetValue => "unknown OS, architecture, or ABI name in target predicate",
        error.InvalidTargetCondition => "expected target_os, target_arch, or target_abi with a literal string; combine predicates with not, and, or",
        error.UnterminatedTargetBranch => "expected closing '}' for target selection branch",
        error.UnmatchedTargetElse => "#else requires a preceding #if branch",
        else => @errorName(err),
    };
}

// Selection precedes import discovery and tokenizing. Blank discarded bytes,
// rather than deleting them, so every token and diagnostic keeps its original
// source offset. This deliberately handles target predicates, not general
// compile-time execution; the original source remains authoritative for tools.
pub fn select(allocator: std.mem.Allocator, source: []const u8, target: target_mod.Config, error_offset: *usize) ![]u8 {
    const output = try allocator.dupe(u8, source);
    errdefer allocator.free(output);
    var selector = Selector{ .source = source, .output = output, .target = target };
    selector.range(0, source.len, true) catch |err| {
        error_offset.* = selector.offset;
        return err;
    };
    return output;
}

const Selector = struct {
    source: []const u8,
    output: []u8,
    target: target_mod.Config,
    offset: usize = 0,

    fn blank(self: *Selector, start: usize, end: usize) void {
        for (self.output[start..end]) |*byte| {
            if (byte.* != '\n' and byte.* != '\r') byte.* = ' ';
        }
    }

    fn skipTrivia(self: *Selector) void {
        while (self.offset < self.source.len) {
            if (std.ascii.isWhitespace(self.source[self.offset])) {
                self.offset += 1;
            } else if (std.mem.startsWith(u8, self.source[self.offset..], "--")) {
                while (self.offset < self.source.len and self.source[self.offset] != '\n') self.offset += 1;
            } else break;
        }
    }

    fn word(self: *Selector, name: []const u8) bool {
        self.skipTrivia();
        if (!std.mem.startsWith(u8, self.source[self.offset..], name)) return false;
        const end = self.offset + name.len;
        if (end < self.source.len and (std.ascii.isAlphanumeric(self.source[end]) or self.source[end] == '_')) return false;
        self.offset = end;
        return true;
    }

    fn expect(self: *Selector, byte: u8) !void {
        self.skipTrivia();
        if (self.offset >= self.source.len or self.source[self.offset] != byte) return error.InvalidTargetCondition;
        self.offset += 1;
    }

    fn atom(self: *Selector) anyerror!bool {
        if (self.word("not")) return !(try self.atom());
        self.skipTrivia();
        if (self.offset < self.source.len and self.source[self.offset] == '(') {
            self.offset += 1;
            const value = try self.condition();
            try self.expect(')');
            return value;
        }
        var query: ?Query = null;
        inline for (std.meta.fields(Query)) |field| {
            if (query == null and self.word(field.name)) query = @enumFromInt(field.value);
        }
        const selected_query = query orelse return error.InvalidTargetCondition;
        try self.expect('(');
        try self.expect('"');
        const start = self.offset;
        while (self.offset < self.source.len and self.source[self.offset] != '"') : (self.offset += 1) {
            if (!std.ascii.isAlphanumeric(self.source[self.offset]) and self.source[self.offset] != '_') return error.InvalidTargetCondition;
        }
        const name = self.source[start..self.offset];
        try self.expect('"');
        try self.expect(')');
        return matches(self.target, selected_query, name);
    }

    fn conjunction(self: *Selector) !bool {
        var value = try self.atom();
        while (self.word("and")) {
            const rhs = try self.atom();
            value = value and rhs;
        }
        return value;
    }

    fn condition(self: *Selector) !bool {
        var value = try self.conjunction();
        while (self.word("or")) {
            const rhs = try self.conjunction();
            value = value or rhs;
        }
        return value;
    }

    fn skipQuoted(self: *Selector) void {
        const quote = self.source[self.offset];
        self.offset += 1;
        while (self.offset < self.source.len) {
            const byte = self.source[self.offset];
            self.offset += 1;
            if (byte == '\\' and self.offset < self.source.len) self.offset += 1 else if (byte == quote) return;
        }
    }

    fn closingBrace(self: *Selector) !usize {
        var depth: usize = 1;
        while (self.offset < self.source.len) {
            const byte = self.source[self.offset];
            if (byte == '"' or byte == '\'') {
                self.skipQuoted();
                continue;
            }
            if (std.mem.startsWith(u8, self.source[self.offset..], "--")) {
                while (self.offset < self.source.len and self.source[self.offset] != '\n') self.offset += 1;
                continue;
            }
            self.offset += 1;
            if (byte == '{') depth += 1;
            if (byte == '}') {
                depth -= 1;
                if (depth == 0) return self.offset - 1;
            }
        }
        return error.UnterminatedTargetBranch;
    }

    fn range(self: *Selector, start: usize, end: usize, enabled: bool) anyerror!void {
        self.offset = start;
        while (self.offset < end) {
            const byte = self.source[self.offset];
            if (byte == '"' or byte == '\'') {
                self.skipQuoted();
                continue;
            }
            if (std.mem.startsWith(u8, self.source[self.offset..], "--")) {
                while (self.offset < end and self.source[self.offset] != '\n') self.offset += 1;
                continue;
            }
            if (byte != '#') {
                self.offset += 1;
                continue;
            }
            const directive = self.offset;
            self.offset += 1;
            if (!self.word("if")) {
                if (self.word("else")) return error.UnmatchedTargetElse;
                self.offset = directive + 1;
                continue;
            }
            const chosen = try self.condition();
            try self.expect('{');
            const body_start = self.offset;
            const body_end = try self.closingBrace();
            if (body_end >= end) return error.UnterminatedTargetBranch;
            self.blank(directive, body_start);
            self.blank(body_end, body_end + 1);
            try self.range(body_start, body_end, enabled and chosen);
            self.offset = body_end + 1;
            self.skipTrivia();
            if (self.offset < end and self.source[self.offset] == '#') {
                const else_start = self.offset;
                self.offset += 1;
                if (self.word("else")) {
                    try self.expect('{');
                    const alternate_start = self.offset;
                    const alternate_end = try self.closingBrace();
                    if (alternate_end >= end) return error.UnterminatedTargetBranch;
                    self.blank(else_start, alternate_start);
                    self.blank(alternate_end, alternate_end + 1);
                    try self.range(alternate_start, alternate_end, enabled and !chosen);
                    self.offset = alternate_end + 1;
                } else self.offset = else_start;
            }
        }
        if (!enabled) self.blank(start, end);
    }
};

test "target selection keeps offsets and excludes imports before discovery" {
    const source = "#if target_os(\"windows\") {\nwrong := import(\"./missing\")\n} #else {\nanswer := 42\n}\n";
    var offset: usize = 0;
    const selected = try select(std.testing.allocator, source, .{ .os = .linux }, &offset);
    defer std.testing.allocator.free(selected);
    try std.testing.expectEqual(source.len, selected.len);
    try std.testing.expect(std.mem.indexOf(u8, selected, "missing") == null);
    try std.testing.expectEqual(std.mem.indexOf(u8, source, "answer"), std.mem.indexOf(u8, selected, "answer"));
}

test "target selection supports nested predicates and ignores quoted directives" {
    const source = "#if target_os(\"linux\") and (target_arch(\"aarch64\") or target_abi(\"msvc\")) {\n#if not target_abi(\"msvc\") { keep := \"#if {}\" } #else { discard := 0 }\n}\n-- #if invalid\n";
    var offset: usize = 0;
    const selected = try select(std.testing.allocator, source, .{ .os = .linux, .arch = .aarch64, .abi = .gnu }, &offset);
    defer std.testing.allocator.free(selected);
    try std.testing.expect(std.mem.indexOf(u8, selected, "keep") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected, "discard") == null);
}

test "target selection diagnoses invalid conditions and unmatched branches" {
    var offset: usize = 0;
    try std.testing.expectError(error.UnknownTargetValue, select(std.testing.allocator, "#if target_os(\"windos\") {}", .{}, &offset));
    try std.testing.expectError(error.InvalidTargetCondition, select(std.testing.allocator, "#if runtime_value {}", .{}, &offset));
    try std.testing.expectError(error.UnterminatedTargetBranch, select(std.testing.allocator, "#if target_os(\"linux\") {", .{}, &offset));
    try std.testing.expectError(error.UnmatchedTargetElse, select(std.testing.allocator, "#else {}", .{}, &offset));
}

test "target selection preserves CRLF and braces inside literals" {
    const source = "#if target_os(\"windows\") {\r\nkeep := \"}\\\"{\" -- }\r\n} #else {\r\ndiscard := 1\r\n}\r\n";
    var offset: usize = 0;
    const selected = try select(std.testing.allocator, source, .{ .os = .windows }, &offset);
    defer std.testing.allocator.free(selected);
    for (source, selected) |original, chosen| {
        if (original == '\r' or original == '\n') try std.testing.expectEqual(original, chosen);
    }
    try std.testing.expect(std.mem.indexOf(u8, selected, "keep") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected, "discard") == null);
}

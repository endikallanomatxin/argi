const std = @import("std");
const target_mod = @import("target.zig");

pub const Query = enum { target_os, target_arch, target_abi, target_pointer_bits };

pub fn matches(target: target_mod.Config, query: Query, name: []const u8) !bool {
    return switch (query) {
        .target_pointer_bits => target.stdTarget().ptrBitWidth() == (std.fmt.parseInt(u16, name, 10) catch return error.InvalidTargetCondition),
        .target_os => target.os == (std.meta.stringToEnum(std.Target.Os.Tag, name) orelse return error.UnknownTargetValue),
        .target_arch => target.arch == (std.meta.stringToEnum(std.Target.Cpu.Arch, name) orelse return error.UnknownTargetValue),
        .target_abi => target.abi == (std.meta.stringToEnum(std.Target.Abi, name) orelse return error.UnknownTargetValue),
    };
}

pub fn errorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.UnknownTargetValue => "unknown OS, architecture, or ABI name in target predicate",
        error.InvalidTargetCondition => "expected target_os, target_arch, or target_abi with a literal string, or target_pointer_bits with an integer literal; combine predicates with not, and, or",
        error.UnterminatedTargetBranch => "expected closing '}' for target selection branch",
        error.ConditionalDepthLimit => "conditional selection exceeds the nesting limit",
        error.ConditionalSourceTooLarge => "conditional source exceeds the supported source size",
        error.UnmatchedTargetElse => "#else requires a preceding #if branch",
        else => @errorName(err),
    };
}

// The source plan owns branch topology and stable offsets. This wrapper only
// supplies the established target predicates; staged execution can use the same
// plan with unresolved decisions without interpreting Argi in this scanner.
pub fn select(allocator: std.mem.Allocator, source: []const u8, target: target_mod.Config, error_offset: *usize) ![]u8 {
    return selectMode(allocator, source, target, error_offset, .target_only);
}

pub fn selectImports(allocator: std.mem.Allocator, source: []const u8, target: target_mod.Config, error_offset: *usize) ![]u8 {
    return selectMode(allocator, source, target, error_offset, .imports);
}

pub fn selectSyntax(allocator: std.mem.Allocator, source: []const u8, target: target_mod.Config, error_offset: *usize) ![]u8 {
    return selectMode(allocator, source, target, error_offset, .syntax);
}

const Mode = enum { target_only, imports, syntax };

fn selectMode(allocator: std.mem.Allocator, source: []const u8, target: target_mod.Config, error_offset: *usize, mode: Mode) ![]u8 {
    var plan = try @import("conditional_source.zig").Plan.parse(allocator, source, error_offset);
    defer plan.deinit(allocator);
    const decisions = try allocator.alloc(?bool, plan.branches.items.len);
    defer allocator.free(decisions);
    // Keep validating target conditions in discarded branches, as before.
    for (plan.branches.items, decisions) |branch, *decision| {
        var selector = Selector{ .source = source[0..branch.condition.end], .target = target, .offset = branch.condition.start };
        decision.* = selector.condition() catch |err| {
            if (mode != .target_only and err == error.InvalidTargetCondition) {
                decision.* = null;
                continue;
            }
            error_offset.* = selector.offset;
            return err;
        };
        selector.skipTrivia();
        if (selector.offset != branch.condition.end) {
            if (mode != .target_only) {
                decision.* = null;
                continue;
            }
            error_offset.* = selector.offset;
            return error.InvalidTargetCondition;
        }
    }
    const selection = if (mode == .syntax) try plan.selectSyntax(allocator, decisions) else try plan.select(allocator, decisions);
    allocator.free(selection.pending);
    return selection.source;
}

const Selector = struct {
    source: []const u8,
    target: target_mod.Config,
    offset: usize = 0,

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
        const name = if (selected_query == .target_pointer_bits) blk: {
            self.skipTrivia();
            const start = self.offset;
            while (self.offset < self.source.len and std.ascii.isDigit(self.source[self.offset])) self.offset += 1;
            if (self.offset == start) return error.InvalidTargetCondition;
            break :blk self.source[start..self.offset];
        } else blk: {
            try self.expect('"');
            const start = self.offset;
            while (self.offset < self.source.len and self.source[self.offset] != '"') : (self.offset += 1) {
                if (!std.ascii.isAlphanumeric(self.source[self.offset]) and self.source[self.offset] != '_') return error.InvalidTargetCondition;
            }
            const value = self.source[start..self.offset];
            try self.expect('"');
            break :blk value;
        };
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

test "pointer width selection follows target ABI and preserves offsets" {
    const source = "#if target_pointer_bits(32) { narrow := 1 } #else { wide := 2 }";
    var offset: usize = 0;
    const selected = try select(std.testing.allocator, source, .{ .arch = .x86_64, .abi = .gnux32 }, &offset);
    defer std.testing.allocator.free(selected);
    try std.testing.expectEqual(source.len, selected.len);
    try std.testing.expect(std.mem.indexOf(u8, selected, "narrow") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected, "wide") == null);
    try std.testing.expect(!try matches(.{ .arch = .x86_64, .abi = .gnu }, .target_pointer_bits, "32"));
    try std.testing.expectError(error.InvalidTargetCondition, select(std.testing.allocator, "#if target_pointer_bits(\"32\") {}", .{}, &offset));
}

test "target selection still validates predicates inside discarded branches" {
    const source = "#if target_os(\"windows\") { #if target_os(\"windos\") {} } #else { valid := 42 }";
    var offset: usize = 0;
    try std.testing.expectError(error.UnknownTargetValue, select(std.testing.allocator, source, .{ .os = .linux }, &offset));
    try std.testing.expect(offset > std.mem.indexOf(u8, source, "windos").?);
}

test "computed conditions retain syntax but withhold imports" {
    const a = std.testing.allocator;
    const source = "#if decide() { a := import(\"./pending\") } #else { b := import(\"./other\") }\n";
    var offset: usize = 0;
    const imports = try selectImports(a, source, .{}, &offset);
    defer a.free(imports);
    try std.testing.expect(std.mem.indexOf(u8, imports, "import") == null);
    const syntax = try selectSyntax(a, source, .{}, &offset);
    defer a.free(syntax);
    try std.testing.expectEqualStrings(source, syntax);
}

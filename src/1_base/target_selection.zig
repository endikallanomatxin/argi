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

pub const Prepared = struct {
    plan: @import("conditional_source.zig").Plan,
    decisions: []?bool,

    pub const Policy = enum { target_only, computed };
    pub const BranchId = @import("conditional_source.zig").BranchId;
    pub const Selection = @import("conditional_source.zig").Selection;

    /// Own target decisions while borrowing immutable source. A staged source
    /// loader can retain this owner and bind computed results without reparsing
    /// branch topology or changing source offsets. No Argi execution occurs here.
    /// Function-body conditions remain unresolved here and are specialized by
    /// ordinary semantic materialization, not bound globally by the loader.
    pub fn init(allocator: std.mem.Allocator, source: []const u8, target: target_mod.Config, error_offset: *usize, policy: Policy) !Prepared {
        var plan = try @import("conditional_source.zig").Plan.parse(allocator, source, error_offset);
        errdefer plan.deinit(allocator);
        const decisions = try allocator.alloc(?bool, plan.branches.items.len);
        errdefer allocator.free(decisions);
        // Keep validating target predicates in discarded branches, as before.
        for (plan.branches.items, decisions) |branch, *decision| {
            var selector = Selector{ .source = source[0..branch.condition.end], .target = target, .offset = branch.condition.start };
            decision.* = selector.condition() catch |err| {
                if (policy == .computed and err == error.InvalidTargetCondition) {
                    decision.* = null;
                    continue;
                }
                error_offset.* = selector.offset;
                return err;
            };
            selector.skipTrivia();
            if (selector.offset != branch.condition.end) {
                if (policy == .computed) {
                    decision.* = null;
                    continue;
                }
                error_offset.* = selector.offset;
                return error.InvalidTargetCondition;
            }
        }
        return .{ .plan = plan, .decisions = decisions };
    }

    pub fn deinit(self: *Prepared, allocator: std.mem.Allocator) void {
        allocator.free(self.decisions);
        self.plan.deinit(allocator);
        self.* = undefined;
    }

    pub fn imports(self: *const Prepared, allocator: std.mem.Allocator) !Selection {
        return self.plan.select(allocator, self.decisions);
    }

    pub fn syntax(self: *const Prepared, allocator: std.mem.Allocator) !Selection {
        return self.plan.selectSyntax(allocator, self.decisions);
    }

    /// Render only one selected arm for append-only module publication. Keep
    /// its original offsets and unresolved nested syntax, while excluding the
    /// containing module's already-published declarations.
    pub fn fragment(self: *const Prepared, allocator: std.mem.Allocator, branch: BranchId, comptime retain_syntax: bool) !Selection {
        const index = @intFromEnum(branch);
        if (index >= self.decisions.len) return error.InvalidConditionalBranch;
        try self.requireActive(branch);
        const chosen = self.decisions[index] orelse return error.UnresolvedConditionalBranch;
        const selected = self.plan.branches.items[index];
        const body = if (chosen) selected.then_body else selected.else_body;
        const rendered = if (retain_syntax) try self.syntax(allocator) else try self.imports(allocator);
        errdefer rendered.deinit(allocator);
        for (rendered.source, 0..) |*byte, offset| {
            if ((offset < body.start or offset >= body.end) and byte.* != '\n' and byte.* != '\r') byte.* = ' ';
        }
        var count: usize = 0;
        for (rendered.pending) |pending| {
            const extent = self.plan.branches.items[@intFromEnum(pending)].extent;
            if (extent.start >= body.start and extent.end <= body.end) count += 1;
        }
        const pending = try allocator.alloc(BranchId, count);
        var cursor: usize = 0;
        for (rendered.pending) |candidate| {
            const extent = self.plan.branches.items[@intFromEnum(candidate)].extent;
            if (extent.start >= body.start and extent.end <= body.end) {
                pending[cursor] = candidate;
                cursor += 1;
            }
        }
        allocator.free(rendered.pending);
        return .{ .source = rendered.source, .pending = pending };
    }

    fn requireActive(self: *const Prepared, branch: BranchId) !void {
        var current = self.plan.branches.items[@intFromEnum(branch)];
        while (current.parent != .none) {
            const parent = @intFromEnum(current.parent);
            if (self.decisions[parent] == null or self.decisions[parent].? != current.parent_arm)
                return error.InactiveConditionalBranch;
            current = self.plan.branches.items[parent];
        }
    }

    /// Publish one computed result only after all enclosing selections agree.
    /// Inactive dependencies must not be executed merely to decide another arm.
    pub fn resolve(self: *Prepared, branch: BranchId, value: bool) !void {
        const index = @intFromEnum(branch);
        if (index >= self.decisions.len) return error.InvalidConditionalBranch;
        if (self.decisions[index] != null) return error.ConditionalAlreadyResolved;
        try self.requireActive(branch);
        self.decisions[index] = value;
    }
};

fn selectMode(allocator: std.mem.Allocator, source: []const u8, target: target_mod.Config, error_offset: *usize, mode: Mode) ![]u8 {
    var prepared = try Prepared.init(allocator, source, target, error_offset, if (mode == .target_only) .target_only else .computed);
    defer prepared.deinit(allocator);
    const selection = if (mode == .syntax) try prepared.syntax(allocator) else try prepared.imports(allocator);
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

fn exerciseRetainedSelection(allocator: std.mem.Allocator) !void {
    const source =
        "#if choose() {\n" ++
        "    first := import(\"./first\")\n" ++
        "    #if nested() { second := import(\"./second\") }\n" ++
        "} #else { discarded := import(\"./missing\") }\n";
    var offset: usize = 0;
    var prepared = try Prepared.init(allocator, source, .{}, &offset, .computed);
    defer prepared.deinit(allocator);
    const before = try prepared.imports(allocator);
    defer before.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), before.pending.len);
    try std.testing.expect(std.mem.indexOf(u8, before.source, "import") == null);
    try std.testing.expectError(error.InactiveConditionalBranch, prepared.resolve(@enumFromInt(1), true));
    try std.testing.expect(prepared.decisions[1] == null);
    try prepared.resolve(before.pending[0], true);
    const outer = try prepared.imports(allocator);
    defer outer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), outer.pending.len);
    try std.testing.expect(std.mem.indexOf(u8, outer.source, "./first") != null);
    try std.testing.expect(std.mem.indexOf(u8, outer.source, "./second") == null);
    try std.testing.expect(std.mem.indexOf(u8, outer.source, "./missing") == null);
    try prepared.resolve(outer.pending[0], true);
    const complete = try prepared.syntax(allocator);
    defer complete.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), complete.pending.len);
    try std.testing.expectEqual(source.len, complete.source.len);
    try std.testing.expectEqual(std.mem.indexOf(u8, source, "./second"), std.mem.indexOf(u8, complete.source, "./second"));
    try std.testing.expect(std.mem.indexOf(u8, complete.source, "./missing") == null);
    try std.testing.expectError(error.ConditionalAlreadyResolved, prepared.resolve(@enumFromInt(0), false));
    try std.testing.expectError(error.InvalidConditionalBranch, prepared.resolve(.none, false));
}

test "retained target selection resumes active computed imports with stable offsets" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseRetainedSelection, .{});
}

test "retained selection cannot resolve children of discarded computed branches" {
    const allocator = std.testing.allocator;
    const source = "#if choose() { #if hidden() { missing := import(\"./missing\") } } #else { answer := 42 }";
    var offset: usize = 0;
    var prepared = try Prepared.init(allocator, source, .{}, &offset, .computed);
    defer prepared.deinit(allocator);
    try prepared.resolve(@enumFromInt(0), false);
    try std.testing.expectError(error.InactiveConditionalBranch, prepared.resolve(@enumFromInt(1), true));
    const selected = try prepared.imports(allocator);
    defer selected.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), selected.pending.len);
    try std.testing.expect(std.mem.indexOf(u8, selected.source, "./missing") == null);
    try std.testing.expect(std.mem.indexOf(u8, selected.source, "answer") != null);
}

fn renderSelectedFragments(allocator: std.mem.Allocator) !void {
    const source = "published := 1\n#if outer() {\nfirst := 2\n#if inner() { active := import(\"./active\") } #else { other := 3 }\n} #else { missing := import(\"./missing\") }\n#if unrelated() { later := 4 }";
    var offset: usize = 0;
    var selection = try Prepared.init(allocator, source, .{}, &offset, .computed);
    defer selection.deinit(allocator);
    try std.testing.expectError(error.UnresolvedConditionalBranch, selection.fragment(allocator, @enumFromInt(0), true));
    try selection.resolve(@enumFromInt(0), true);
    const syntax = try selection.fragment(allocator, @enumFromInt(0), true);
    defer syntax.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, syntax.source, "published") == null);
    try std.testing.expect(std.mem.indexOf(u8, syntax.source, "unrelated") == null);
    try std.testing.expect(std.mem.indexOf(u8, syntax.source, "missing") == null);
    try std.testing.expect(std.mem.indexOf(u8, syntax.source, "#if inner()") != null);
    try std.testing.expectEqual(@as(usize, 1), syntax.pending.len);
    const imports = try selection.fragment(allocator, @enumFromInt(0), false);
    defer imports.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, imports.source, "import") == null);
    try std.testing.expectEqual(@as(usize, 1), imports.pending.len);
    try selection.resolve(syntax.pending[0], true);
    const nested = try selection.fragment(allocator, syntax.pending[0], true);
    defer nested.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, nested.source, "first") == null);
    try std.testing.expectEqual(std.mem.indexOf(u8, source, "active :="), std.mem.indexOf(u8, nested.source, "active :="));
    try std.testing.expectEqual(source.len, nested.source.len);
    try std.testing.expectEqual(@as(usize, 0), nested.pending.len);
}

test "selected source fragments retain offsets without republishing surrounding declarations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, renderSelectedFragments, .{});
}

test "selected fragments handle false and absent else arms without reviving inactive children" {
    const allocator = std.testing.allocator;
    const source = "#if outer() { #if hidden() { missing := 1 } } #else { kept := 2 }\n#if empty() { discarded := 3 }";
    var offset: usize = 0;
    var selection = try Prepared.init(allocator, source, .{}, &offset, .computed);
    defer selection.deinit(allocator);
    try selection.resolve(@enumFromInt(0), false);
    const selected = try selection.fragment(allocator, @enumFromInt(0), true);
    defer selected.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, selected.source, "kept") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected.source, "missing") == null);
    try std.testing.expectEqual(@as(usize, 0), selected.pending.len);
    try std.testing.expectError(error.InactiveConditionalBranch, selection.fragment(allocator, @enumFromInt(1), true));
    try selection.resolve(@enumFromInt(2), false);
    const empty = try selection.fragment(allocator, @enumFromInt(2), false);
    defer empty.deinit(allocator);
    for (empty.source) |byte| try std.testing.expect(std.ascii.isWhitespace(byte));
    try std.testing.expectEqual(source.len, empty.source.len);
    try std.testing.expectError(error.InvalidConditionalBranch, selection.fragment(allocator, .none, false));
}

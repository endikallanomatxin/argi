const std = @import("std");
const lexical = @import("lexical.zig");

pub const BranchId = enum(u32) { none = std.math.maxInt(u32), _ };
pub const Span = struct {
    start: u32 = 0,
    end: u32 = 0,

    pub fn text(self: Span, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

// Source offsets are the identities of conditions until syntax/semantic work
// binds them. Records are preorder; parents always precede their children.
pub const Branch = struct {
    condition: Span,
    then_body: Span,
    else_body: Span = .{},
    else_header: Span = .{},
    extent: Span,
    parent: BranchId,
    parent_arm: bool,
};

pub const Selection = struct {
    source: []u8,
    pending: []BranchId,

    pub fn deinit(self: Selection, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.pending);
    }
};

pub const Plan = struct {
    // Borrowed immutable source; its owner must outlive this plan.
    source: []const u8 = &.{},
    branches: std.ArrayList(Branch) = .empty,

    pub fn deinit(self: *Plan, allocator: std.mem.Allocator) void {
        self.branches.deinit(allocator);
    }

    pub fn parse(allocator: std.mem.Allocator, source: []const u8, error_offset: *usize) !Plan {
        if (source.len > std.math.maxInt(u32)) return error.ConditionalSourceTooLarge;
        var parser = Parser{ .allocator = allocator, .source = source, .plan = .{ .source = source } };
        errdefer parser.plan.deinit(allocator);
        parser.range(0, source.len, .none, true, 0) catch |err| {
            error_offset.* = parser.offset;
            return err;
        };
        return parser.plan;
    }

    // Null is unresolved, not false. Both arms remain unavailable and only an
    // active unresolved condition becomes pending; its children cannot execute.
    pub fn select(self: *const Plan, allocator: std.mem.Allocator, decisions: []const ?bool) !Selection {
        return self.render(allocator, decisions, false);
    }

    // Parsing retains unresolved directives as syntax. Import discovery uses
    // select instead, withholding both arms until their condition is known.
    pub fn selectSyntax(self: *const Plan, allocator: std.mem.Allocator, decisions: []const ?bool) !Selection {
        return self.render(allocator, decisions, true);
    }

    fn render(self: *const Plan, allocator: std.mem.Allocator, decisions: []const ?bool, retain_pending: bool) !Selection {
        if (decisions.len != self.branches.items.len) return error.InvalidConditionalDecisions;
        const output = try allocator.dupe(u8, self.source);
        errdefer allocator.free(output);
        const active = try allocator.alloc(bool, decisions.len);
        defer allocator.free(active);
        var pending: std.ArrayList(BranchId) = .empty;
        errdefer pending.deinit(allocator);
        for (self.branches.items, 0..) |branch, index| {
            const enabled = if (branch.parent == .none) true else blk: {
                const parent = @intFromEnum(branch.parent);
                break :blk active[parent] and (if (decisions[parent]) |chosen| chosen == branch.parent_arm else retain_pending);
            };
            active[index] = enabled;
            const deferred = enabled and decisions[index] == null and retain_pending;
            if (!deferred) {
                blank(output, .{ .start = branch.extent.start, .end = branch.then_body.start });
                blank(output, .{ .start = branch.then_body.end, .end = branch.then_body.end + 1 });
                if (branch.else_header.start != branch.else_header.end) {
                    blank(output, branch.else_header);
                    blank(output, .{ .start = branch.else_body.end, .end = branch.else_body.end + 1 });
                }
            }
            const chosen = if (enabled) decisions[index] else null;
            if (!deferred) {
                if (chosen == null or !chosen.?) blank(output, branch.then_body);
                if (chosen == null or chosen.?) blank(output, branch.else_body);
            }
            if (enabled and chosen == null) try pending.append(allocator, @enumFromInt(index));
        }
        return .{ .source = output, .pending = try pending.toOwnedSlice(allocator) };
    }
};

fn blank(source: []u8, span: Span) void {
    for (source[span.start..span.end]) |*byte|
        if (byte.* != '\n' and byte.* != '\r') {
            byte.* = ' ';
        };
}

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    plan: Plan = .{},
    offset: usize = 0,

    fn span(start: usize, end: usize) Span {
        return .{ .start = @intCast(start), .end = @intCast(end) };
    }

    fn skipTrivia(self: *Parser) void {
        while (self.offset < self.source.len) {
            if (std.ascii.isWhitespace(self.source[self.offset])) {
                self.offset += 1;
            } else if (std.mem.startsWith(u8, self.source[self.offset..], "--")) {
                self.offset = lexical.commentEnd(self.source, self.offset);
            } else break;
        }
    }

    fn word(self: *Parser, name: []const u8) bool {
        self.skipTrivia();
        if (!std.mem.startsWith(u8, self.source[self.offset..], name)) return false;
        const end = self.offset + name.len;
        if (end < self.source.len and lexical.identifierContinue(self.source[end])) return false;
        self.offset = end;
        return true;
    }

    fn skipQuoted(self: *Parser) void {
        self.offset = lexical.quoted(self.source, self.offset).end;
    }

    fn closingBrace(self: *Parser) !usize {
        var depth: usize = 1;
        while (self.offset < self.source.len) {
            const byte = self.source[self.offset];
            if (byte == '"' or byte == '\'') {
                self.skipQuoted();
                continue;
            }
            if (std.mem.startsWith(u8, self.source[self.offset..], "--")) {
                self.offset = lexical.commentEnd(self.source, self.offset);
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

    fn conditionBody(self: *Parser) !usize {
        var parentheses: usize = 0;
        var brackets: usize = 0;
        while (self.offset < self.source.len) {
            const byte = self.source[self.offset];
            if (byte == '"' or byte == '\'') {
                self.skipQuoted();
                continue;
            }
            if (std.mem.startsWith(u8, self.source[self.offset..], "--")) {
                self.offset = lexical.commentEnd(self.source, self.offset);
                continue;
            }
            if (byte == '{' and parentheses == 0 and brackets == 0) return self.offset;
            switch (byte) {
                '(' => parentheses += 1,
                ')' => if (parentheses != 0) {
                    parentheses -= 1;
                } else return error.InvalidTargetCondition,
                '[' => brackets += 1,
                ']' => if (brackets != 0) {
                    brackets -= 1;
                } else return error.InvalidTargetCondition,
                else => {},
            }
            self.offset += 1;
        }
        return error.InvalidTargetCondition;
    }

    fn range(self: *Parser, start: usize, end: usize, parent: BranchId, parent_arm: bool, depth: usize) anyerror!void {
        if (depth > 128) return error.ConditionalDepthLimit;
        self.offset = start;
        while (self.offset < end) {
            const byte = self.source[self.offset];
            if (byte == '"' or byte == '\'') {
                self.skipQuoted();
                continue;
            }
            if (std.mem.startsWith(u8, self.source[self.offset..], "--")) {
                self.offset = @min(end, lexical.commentEnd(self.source, self.offset));
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
            self.skipTrivia();
            const condition_start = self.offset;
            const condition_end = try self.conditionBody();
            self.offset += 1;
            const body_start = self.offset;
            const body_end = try self.closingBrace();
            if (body_end >= end) return error.UnterminatedTargetBranch;
            self.skipTrivia();
            var alternate: Span = .{};
            var else_header: Span = .{};
            var extent_end = body_end + 1;
            if (self.offset < end and self.source[self.offset] == '#') {
                const else_start = self.offset;
                self.offset += 1;
                if (self.word("else")) {
                    self.skipTrivia();
                    if (self.offset >= end or self.source[self.offset] != '{') return error.InvalidTargetCondition;
                    self.offset += 1;
                    const alternate_start = self.offset;
                    const alternate_end = try self.closingBrace();
                    if (alternate_end >= end) return error.UnterminatedTargetBranch;
                    alternate = span(alternate_start, alternate_end);
                    else_header = span(else_start, alternate_start);
                    extent_end = alternate_end + 1;
                }
            }
            const id: BranchId = @enumFromInt(self.plan.branches.items.len);
            try self.plan.branches.append(self.allocator, .{
                .condition = span(condition_start, condition_end),
                .then_body = span(body_start, body_end),
                .else_body = alternate,
                .else_header = else_header,
                .extent = span(directive, extent_end),
                .parent = parent,
                .parent_arm = parent_arm,
            });
            try self.range(body_start, body_end, id, true, depth + 1);
            if (else_header.start != else_header.end) try self.range(alternate.start, alternate.end, id, false, depth + 1);
            self.offset = extent_end;
        }
    }
};

test "conditional source retains unknown conditions and hides both arms" {
    const a = std.testing.allocator;
    const source = "ready() -> (.ok: Bool = true) := {}\r\n#if ready() { missing := import(\"./missing\") } #else { other := 42 }";
    var offset: usize = 0;
    var plan = try Plan.parse(a, source, &offset);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), plan.branches.items.len);
    try std.testing.expectEqualStrings("ready() ", plan.branches.items[0].condition.text(source));
    const pending = try plan.select(a, &.{null});
    defer pending.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), pending.pending.len);
    try std.testing.expect(std.mem.indexOf(u8, pending.source, "missing") == null);
    try std.testing.expect(std.mem.indexOf(u8, pending.source, "other") == null);
    try std.testing.expect(std.mem.indexOf(u8, pending.source, "ready() ->") != null);
    const selected = try plan.select(a, &.{false});
    defer selected.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), selected.pending.len);
    try std.testing.expectEqual(std.mem.indexOf(u8, source, "other"), std.mem.indexOf(u8, selected.source, "other"));
    for (source, selected.source) |before, after| if (before == '\r' or before == '\n') try std.testing.expectEqual(before, after);
}

test "conditional source exposes only the active pending frontier" {
    const a = std.testing.allocator;
    const source = "#if first() { #if second() { yes := 1 } #else { no := 2 } } #else { #if third() { other := 3 } }";
    var offset: usize = 0;
    var plan = try Plan.parse(a, source, &offset);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), plan.branches.items.len);
    const waiting = try plan.select(a, &.{ null, true, true });
    defer waiting.deinit(a);
    try std.testing.expectEqualSlices(BranchId, &.{@enumFromInt(0)}, waiting.pending);
    const next = try plan.select(a, &.{ false, null, null });
    defer next.deinit(a);
    try std.testing.expectEqualSlices(BranchId, &.{@enumFromInt(2)}, next.pending);
    const ready = try plan.select(a, &.{ false, null, true });
    defer ready.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), ready.pending.len);
    try std.testing.expect(std.mem.indexOf(u8, ready.source, "other") != null);
    try std.testing.expect(std.mem.indexOf(u8, ready.source, "yes") == null);
    try std.testing.expect(std.mem.indexOf(u8, ready.source, "no :=") == null);
}

test "conditional source ignores quoted directives and validates branch structure" {
    const a = std.testing.allocator;
    const source = "text := \"#if nope {\" -- #else\n#if check(.text = \"}\", .f = () -> () { }) { valid := '}' }";
    var offset: usize = 0;
    var plan = try Plan.parse(a, source, &offset);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), plan.branches.items.len);
    try std.testing.expectError(error.InvalidConditionalDecisions, plan.select(a, &.{}));
    try std.testing.expectError(error.UnmatchedTargetElse, Plan.parse(a, "#else {}", &offset));
    try std.testing.expectError(error.UnterminatedTargetBranch, Plan.parse(a, "#if ready() {", &offset));
}

test "conditional source bounds nesting without evaluating conditions" {
    const a = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    for (0..130) |_| try source.appendSlice(a, "#if ready() {");
    try source.appendNTimes(a, '}', 130);
    var offset: usize = 0;
    try std.testing.expectError(error.ConditionalDepthLimit, Plan.parse(a, source.items, &offset));
}

test "conditional source preserves lexical boundaries in invalid inactive strings" {
    const source =
        \\#if enabled {
        \\    text := "\q #else { \" }" -- #if ignored { }
        \\    quote := '\''
        \\} #else {
        \\    selected := 42
        \\}
    ;
    const allocator = std.testing.allocator;
    var offset: usize = 0;
    var plan = try Plan.parse(allocator, source, &offset);
    defer plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), plan.branches.items.len);
    const selected = try plan.select(allocator, &.{false});
    defer selected.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, selected.source, "selected := 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected.source, "\\q") == null);
    try std.testing.expectEqual(source.len, selected.source.len);
}

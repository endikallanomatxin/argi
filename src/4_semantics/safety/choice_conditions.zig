const std = @import("std");
const place = @import("place.zig");

/// Entry selectors refer to values observed before the call's effects. They
/// never describe the current contents of a mutable input after the call.
pub const ChoiceCondition = struct {
    pub const Subject = enum { entry_input, output };

    subject: Subject,
    index: u32,
    projections: []const place.Projection = &.{},
    variant_index: u32,

    pub fn sameSelector(a: ChoiceCondition, b: ChoiceCondition) bool {
        if (a.subject != b.subject or a.index != b.index or a.projections.len != b.projections.len) return false;
        for (a.projections, b.projections) |left, right| if (!left.eql(right)) return false;
        return true;
    }

    pub fn eql(a: ChoiceCondition, b: ChoiceCondition) bool {
        return a.sameSelector(b) and a.variant_index == b.variant_index;
    }
};

/// A conjunction stores only requested selectors, never a product of all tags.
/// Alternatives are separate guarded effect records. An impossible conjunction
/// represents an unreachable partition, including conflicting ancestor tags.
pub const ChoiceConditions = struct {
    terms: []const ChoiceCondition = &.{},
    impossible: bool = false,

    pub fn eql(a: ChoiceConditions, b: ChoiceConditions) bool {
        if (a.impossible != b.impossible or a.terms.len != b.terms.len) return false;
        for (a.terms, b.terms) |left, right| if (!left.eql(right)) return false;
        return true;
    }

    pub fn implies(a: ChoiceConditions, b: ChoiceConditions) bool {
        if (a.impossible) return true;
        if (b.impossible) return false;
        for (b.terms) |wanted| {
            var found = false;
            for (a.terms) |known| if (known.eql(wanted)) {
                found = true;
                break;
            };
            if (!found) return false;
        }
        return true;
    }

    /// Match a compact nested output selector against normalized conditions
    /// without allocating another condition set. Every enclosing tag matters.
    pub fn impliesOutput(self: ChoiceConditions, output: u32, parents: []const u32, variant: u32) bool {
        if (self.impossible) return true;
        for (0..parents.len + 1) |depth| {
            const tag = if (depth == parents.len) variant else parents[depth];
            var found = false;
            for (self.terms) |term| {
                if (term.subject != .output or term.index != output or term.variant_index != tag or term.projections.len != depth) continue;
                var matches = true;
                for (term.projections, parents[0..depth]) |projection, parent| {
                    if (projection != .variant or projection.variant != parent) {
                        matches = false;
                        break;
                    }
                }
                if (matches) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
    }

    pub fn evaluate(condition: ChoiceConditions, known: ChoiceConditions) enum { satisfied, contradicted, unknown } {
        if (condition.impossible or known.impossible) return .contradicted;
        var missing = false;
        for (condition.terms) |wanted| {
            var found = false;
            for (known.terms) |actual| if (wanted.sameSelector(actual)) {
                if (wanted.variant_index != actual.variant_index) return .contradicted;
                found = true;
                break;
            };
            missing = missing or !found;
        }
        return if (missing) .unknown else .satisfied;
    }
};

/// Normalized projections and terms belong to the immutable summary arena.
pub fn normalize(allocator: std.mem.Allocator, terms: []const ChoiceCondition) !ChoiceConditions {
    var result: std.ArrayList(ChoiceCondition) = .empty;
    defer result.deinit(allocator);
    for (terms) |term| {
        for (term.projections, 0..) |projection, index| {
            if (projection == .dynamic_index) return error.DynamicChoiceCondition;
            if (projection == .variant) {
                var ancestor = term;
                ancestor.projections = term.projections[0..index];
                ancestor.variant_index = projection.variant;
                if (!try append(allocator, &result, ancestor)) return .{ .impossible = true };
            }
        }
        if (!try append(allocator, &result, term)) return .{ .impossible = true };
    }
    std.mem.sort(ChoiceCondition, result.items, {}, lessThan);
    return .{ .terms = try result.toOwnedSlice(allocator) };
}

pub fn conjoin(allocator: std.mem.Allocator, a: ChoiceConditions, b: ChoiceConditions) !ChoiceConditions {
    if (a.impossible or b.impossible) return .{ .impossible = true };
    const terms = try std.mem.concat(allocator, ChoiceCondition, &.{ a.terms, b.terms });
    defer allocator.free(terms);
    return normalize(allocator, terms);
}

/// Branch joins retain facts established on both paths. They do not invent a
/// conjunction from facts established separately on alternative paths.
pub fn commonFacts(allocator: std.mem.Allocator, a: ChoiceConditions, b: ChoiceConditions) !ChoiceConditions {
    if (a.impossible and b.impossible) return .{ .impossible = true };
    if (a.impossible) return normalize(allocator, b.terms);
    if (b.impossible) return normalize(allocator, a.terms);
    var terms: std.ArrayList(ChoiceCondition) = .empty;
    defer terms.deinit(allocator);
    for (a.terms) |left| for (b.terms) |right| {
        if (left.eql(right)) {
            try terms.append(allocator, left);
            break;
        }
    };
    return normalize(allocator, terms.items);
}

fn append(allocator: std.mem.Allocator, result: *std.ArrayList(ChoiceCondition), term: ChoiceCondition) !bool {
    for (result.items) |existing| if (existing.sameSelector(term)) return existing.variant_index == term.variant_index;
    var stored = term;
    stored.projections = try allocator.dupe(place.Projection, term.projections);
    try result.append(allocator, stored);
    return true;
}

fn lessThan(_: void, a: ChoiceCondition, b: ChoiceCondition) bool {
    if (a.subject != b.subject) return @intFromEnum(a.subject) < @intFromEnum(b.subject);
    if (a.index != b.index) return a.index < b.index;
    for (a.projections[0..@min(a.projections.len, b.projections.len)], b.projections[0..@min(a.projections.len, b.projections.len)]) |left, right| {
        const left_tag = std.meta.activeTag(left);
        const right_tag = std.meta.activeTag(right);
        if (left_tag != right_tag) return @intFromEnum(left_tag) < @intFromEnum(right_tag);
        if (left.eql(right)) continue;
        return switch (left) {
            .field => |index| index < right.field,
            .variant => |index| index < right.variant,
            .static_index => |index| index < right.static_index,
            .dynamic_index, .dereference => unreachable,
        };
    }
    if (a.projections.len != b.projections.len) return a.projections.len < b.projections.len;
    return a.variant_index < b.variant_index;
}

test "choice conjunctions distinguish entry input from output and require every selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const input: ChoiceCondition = .{ .subject = .entry_input, .index = 0, .variant_index = 1 };
    const output: ChoiceCondition = .{ .subject = .output, .index = 0, .variant_index = 2 };
    const condition = try normalize(allocator, &.{ input, output });
    try std.testing.expectEqual(.unknown, condition.evaluate(try normalize(allocator, &.{input})));
    try std.testing.expectEqual(.satisfied, condition.evaluate(try normalize(allocator, &.{ output, input })));
    try std.testing.expectEqual(.contradicted, condition.evaluate(try normalize(allocator, &.{.{ .subject = .output, .index = 0, .variant_index = 0 }})));
    try std.testing.expect(condition.implies(try normalize(allocator, &.{input})));
    try std.testing.expect(!(try normalize(allocator, &.{input})).implies(condition));
}

test "nested choice conditions require ancestor variants and preserve independent fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const nested: ChoiceCondition = .{ .subject = .output, .index = 1, .projections = &.{ .{ .variant = 2 }, .{ .field = 0 } }, .variant_index = 3 };
    const sibling: ChoiceCondition = .{ .subject = .output, .index = 1, .projections = &.{ .{ .variant = 2 }, .{ .field = 1 } }, .variant_index = 4 };
    const condition = try normalize(allocator, &.{ nested, sibling, nested });
    try std.testing.expectEqual(@as(usize, 3), condition.terms.len);
    const reversed = try normalize(allocator, &.{ sibling, nested });
    try std.testing.expect(condition.eql(reversed));
    const contradictory = try conjoin(allocator, condition, try normalize(allocator, &.{.{ .subject = .output, .index = 1, .variant_index = 0 }}));
    try std.testing.expect(contradictory.impossible);
}

test "choice branch joins never combine independent alternatives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const a = try normalize(allocator, &.{.{ .subject = .output, .index = 0, .variant_index = 1 }});
    const b = try normalize(allocator, &.{.{ .subject = .output, .index = 1, .variant_index = 1 }});
    try std.testing.expectEqual(@as(usize, 0), (try commonFacts(allocator, a, b)).terms.len);
    try std.testing.expectEqual(@as(usize, 2), (try conjoin(allocator, a, b)).terms.len);
    try std.testing.expect((try commonFacts(allocator, a, .{ .impossible = true })).eql(a));
    try std.testing.expect((try commonFacts(allocator, .{ .impossible = true }, .{ .impossible = true })).impossible);
}

test "choice conjunction storage follows explicit selectors without enumerating alternatives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var terms: [96]ChoiceCondition = undefined;
    for (&terms, 0..) |*term, index| term.* = .{ .subject = .output, .index = @intCast(index), .variant_index = 1 };
    const condition = try normalize(arena.allocator(), &terms);
    try std.testing.expectEqual(terms.len, condition.terms.len);
    try std.testing.expectEqual(.satisfied, condition.evaluate(condition));
    try std.testing.expectError(error.DynamicChoiceCondition, normalize(arena.allocator(), &.{.{ .subject = .output, .index = 0, .projections = &.{.dynamic_index}, .variant_index = 0 }}));
}

/// Remap a wrapper's published selectors without combining unrelated results.
/// Missing mappings lose the complete relation; dropping just that term would
/// incorrectly strengthen the guard. Entry inputs cannot become output facts.
pub const SelectorMapping = struct {
    subject: ChoiceCondition.Subject,
    index: u32,
    target_index: u32,
    target_prefix: []const place.Projection = &.{},
};

pub fn remap(allocator: std.mem.Allocator, conditions: ChoiceConditions, mappings: []const SelectorMapping) !?ChoiceConditions {
    if (conditions.impossible) return conditions;
    var terms: std.ArrayList(ChoiceCondition) = .empty;
    defer terms.deinit(allocator);
    for (conditions.terms) |term| {
        var selected: ?SelectorMapping = null;
        for (mappings) |mapping| if (mapping.subject == term.subject and mapping.index == term.index) {
            if (selected != null) return error.AmbiguousChoiceMapping;
            selected = mapping;
        };
        const mapping = selected orelse return null;
        try terms.append(allocator, .{
            .subject = term.subject,
            .index = mapping.target_index,
            .projections = try std.mem.concat(allocator, place.Projection, &.{ mapping.target_prefix, term.projections }),
            .variant_index = term.variant_index,
        });
    }
    return try normalize(allocator, terms.items);
}

test "choice forwarding preserves complete conjunctions and fails closed on missing relations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const condition = try normalize(allocator, &.{
        .{ .subject = .entry_input, .index = 0, .variant_index = 1 },
        .{ .subject = .output, .index = 0, .variant_index = 2 },
    });
    const mappings = [_]SelectorMapping{
        .{ .subject = .entry_input, .index = 0, .target_index = 3 },
        .{ .subject = .output, .index = 0, .target_index = 4, .target_prefix = &.{.{ .field = 1 }} },
    };
    const forwarded = (try remap(allocator, condition, &mappings)).?;
    try std.testing.expectEqual(@as(u32, 3), forwarded.terms[0].index);
    try std.testing.expectEqual(ChoiceCondition.Subject.entry_input, forwarded.terms[0].subject);
    try std.testing.expectEqual(@as(u32, 4), forwarded.terms[1].index);
    try std.testing.expectEqual(@as(usize, 1), forwarded.terms[1].projections.len);
    try std.testing.expect((try remap(allocator, condition, mappings[0..1])) == null);
    try std.testing.expectError(error.AmbiguousChoiceMapping, remap(allocator, condition, &.{ mappings[0], mappings[0], mappings[1] }));
}

test "compact output implication matches normalized nested selector implication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const wanted = try normalize(a, &.{.{ .subject = .output, .index = 1, .projections = &.{ .{ .variant = 2 }, .{ .variant = 3 } }, .variant_index = 4 }});
    const cases = [_]ChoiceConditions{
        wanted,
        .{},
        .{ .impossible = true },
        try normalize(a, &.{.{ .subject = .output, .index = 1, .variant_index = 2 }}),
        try normalize(a, &.{.{ .subject = .entry_input, .index = 1, .projections = &.{ .{ .variant = 2 }, .{ .variant = 3 } }, .variant_index = 4 }}),
        try normalize(a, &.{.{ .subject = .output, .index = 0, .projections = &.{ .{ .variant = 2 }, .{ .variant = 3 } }, .variant_index = 4 }}),
        try normalize(a, &.{.{ .subject = .output, .index = 1, .projections = &.{ .{ .variant = 2 }, .{ .variant = 3 } }, .variant_index = 5 }}),
        try normalize(a, &.{ .{ .subject = .entry_input, .index = 0, .variant_index = 7 }, .{ .subject = .output, .index = 1, .projections = &.{ .{ .variant = 2 }, .{ .variant = 3 } }, .variant_index = 4 } }),
    };
    for (cases) |known| try std.testing.expectEqual(known.implies(wanted), known.impliesOutput(1, &.{ 2, 3 }, 4));
    // Field projections cannot be mistaken for nested choice payloads.
    const field = try normalize(a, &.{.{ .subject = .output, .index = 1, .projections = &.{.{ .field = 2 }}, .variant_index = 4 }});
    try std.testing.expect(!field.impliesOutput(1, &.{2}, 4));
}

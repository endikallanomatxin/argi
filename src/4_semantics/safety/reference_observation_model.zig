//! Bounded design experiment, registered only by internal_tests.zig.
//! This is not a checker permission or a proof of the compiler. Physical
//! containment is an explicit hypothesis; pointer arithmetic cannot create it.
const std = @import("std");
const facts = @import("safety_facts.zig");

const Grade = enum { identity, contained };
const Relation = struct {
    source: facts.InputPath,
    grade: Grade,
};

// A snapshot identifies the certified extent, not an allocator's lifetime.
// There are two independent backings, two generations and two bytes each.
const Observation = struct {
    backing: u1,
    generation: facts.ValidityRootId,
    start: u8,
    end: u8,
};

fn holds(grade: Grade, source: Observation, output: Observation) bool {
    if (source.backing != output.backing or source.generation != output.generation) return false;
    return switch (grade) {
        .identity => source.start == output.start and source.end == output.end,
        .contained => source.start <= output.start and output.end <= source.end,
    };
}

fn weaker(a: Grade, b: Grade) Grade {
    return if (a == .identity and b == .identity) .identity else .contained;
}

// Alternatives retain a common universal guarantee, never one known branch.
fn join(a: ?Relation, b: ?Relation) ?Relation {
    const left = a orelse return null;
    const right = b orelse return null;
    if (!left.source.eql(right.source)) return null;
    return .{ .source = left.source, .grade = weaker(left.grade, right.grade) };
}

// Substitution has already resolved the middle observation to the selected
// argument value. This operation neither loads its referent nor changes source.
fn compose(source_to_middle: Relation, middle_to_output: Grade) Relation {
    return .{ .source = source_to_middle.source, .grade = weaker(source_to_middle.grade, middle_to_output) };
}

fn loadReference(slot: ?Relation, stored_reference: ?Relation) ?Relation {
    _ = slot;
    return stored_reference;
}

fn observations() [12]Observation {
    var all: [12]Observation = undefined;
    var index: usize = 0;
    for (0..2) |backing| for (0..2) |generation| {
        for ([_][2]u8{ .{ 0, 1 }, .{ 1, 2 }, .{ 0, 2 } }) |range| {
            all[index] = .{
                .backing = @intCast(backing),
                .generation = @enumFromInt(generation),
                .start = range[0],
                .end = range[1],
            };
            index += 1;
        }
    };
    return all;
}

test "observation model composition preserves containment for every bounded triple" {
    const all = observations();
    const source_path = facts.InputPath{ .input_index = 0 };
    for (std.enums.values(Grade)) |first| for (std.enums.values(Grade)) |second| {
        const composed = compose(.{ .source = source_path, .grade = first }, second);
        try std.testing.expect(composed.source.eql(source_path));
        for (all) |source| for (all) |middle| for (all) |output| {
            if (holds(first, source, middle) and holds(second, middle, output))
                try std.testing.expect(holds(composed.grade, source, output));
        };
    };
}

test "observation model joins cover both alternatives without inventing a source" {
    const all = observations();
    const path = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 1 }} };
    for (std.enums.values(Grade)) |first| for (std.enums.values(Grade)) |second| {
        const left = Relation{ .source = path, .grade = first };
        const right = Relation{ .source = path, .grade = second };
        const joined = join(left, right).?;
        for (all) |source| for (all) |output| {
            if (holds(first, source, output) or holds(second, source, output))
                try std.testing.expect(holds(joined.grade, source, output));
        };
        try std.testing.expect(join(left, null) == null);
        try std.testing.expect(join(null, right) == null);
        // Distinct paths can alias. Losing their common source is conservative;
        // their different names never establish physical disjointness.
        try std.testing.expect(join(left, .{ .source = .{ .input_index = 1 }, .grade = second }) == null);
    };
}

test "observation model slot containment does not describe loaded reference contents" {
    const path = facts.InputPath{ .input_index = 0 };
    const slot = Relation{ .source = path, .grade = .contained };
    try std.testing.expect(loadReference(slot, null) == null);
    const stored = Relation{ .source = .{ .input_index = 1 }, .grade = .identity };
    try std.testing.expect(loadReference(slot, stored).?.source.eql(stored.source));
    const backing = Observation{ .backing = 0, .generation = @enumFromInt(0), .start = 0, .end = 2 };
    const element = Observation{ .backing = 0, .generation = @enumFromInt(0), .start = 1, .end = 2 };
    const loaded = Observation{ .backing = 1, .generation = @enumFromInt(0), .start = 0, .end = 1 };
    try std.testing.expect(holds(.contained, backing, element));
    try std.testing.expect(!holds(.contained, backing, loaded));
}

test "observation model rejects widened extents and cannot reuse retargeted snapshots" {
    const scalar = Observation{ .backing = 0, .generation = @enumFromInt(0), .start = 0, .end = 1 };
    const whole = Observation{ .backing = 0, .generation = @enumFromInt(0), .start = 0, .end = 2 };
    try std.testing.expect(!holds(.contained, scalar, whole));
    var changed = scalar;
    changed.backing = 1;
    try std.testing.expect(!holds(.identity, changed, scalar));
    changed = scalar;
    changed.generation = @enumFromInt(1);
    try std.testing.expect(!holds(.contained, changed, scalar));
    // Relation truth alone does not establish liveness. An ended source/output
    // pair can still have equal snapshots; validity must be checked separately.
    try std.testing.expect(holds(.identity, scalar, scalar));
}

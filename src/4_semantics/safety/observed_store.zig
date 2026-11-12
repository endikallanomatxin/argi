//! Storage-content domain, separate from access authority. The checker uses it
//! for complete symbolic reference-cell writes. Keys name stable observations;
//! key equality is neither physical freshness nor an execution-loan certificate.
//! Clients must freeze retargetable paths and supply a sound alias relation.
//! Payloads describe the evaluated RHS, not a later load from a mutable source.
const std = @import("std");

pub const Relation = enum { same, disjoint, unknown };

/// Retain current write definitions and a finite proof of overwritten sources,
/// rather than a sequence of historical writes. Payloads and proof slices are
/// immutable in the fact allocator; the mutable table owns its own allocation.
/// Context provides relation(Key, Key), join(Value, Value) and equal(Value, Value).
/// Partial byte overlaps require typed projection/havoc before joining payloads.
pub fn Stores(comptime Key: type, comptime Value: type) type {
    return struct {
        const Self = @This();
        pub const Definition = struct {
            target: Key,
            value: Value,
            must_write: bool,
            /// This source groups forgotten observations, not one exact cell.
            summarized: bool = false,
            /// This definition definitely follows these sources' current writes.
            /// A new write to a source invalidates that proof in every other row.
            overwritten: []const Key = &.{},
        };
        fact_allocator: std.mem.Allocator,
        definitions: std.array_list.Managed(Definition),

        pub fn init(fact_allocator: std.mem.Allocator, state_allocator: std.mem.Allocator) Self {
            return .{ .fact_allocator = fact_allocator, .definitions = std.array_list.Managed(Definition).init(state_allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.definitions.deinit();
        }

        fn index(self: *const Self, target: Key) ?usize {
            for (self.definitions.items, 0..) |definition, i| if (definition.target.eql(target)) return i;
            return null;
        }

        fn contains(keys: []const Key, target: Key) bool {
            for (keys) |key| if (key.eql(target)) return true;
            return false;
        }

        fn sameKeys(left: []const Key, right: []const Key) bool {
            if (left.len != right.len) return false;
            for (left) |key| if (!contains(right, key)) return false;
            return true;
        }

        fn relation(left: Key, right: Key, context: anytype) Relation {
            return if (left.eql(right)) .same else context.relation(left, right);
        }

        /// A definite write needs one stable observed destination, not a
        /// singleton selected from an incomplete set of possible destinations.
        /// Merely possible writes retain their previous possible payload.
        pub fn store(self: *Self, target: Key, value: Value, definite: bool, context: anytype) !void {
            const selected = self.index(target);
            if (definite and selected != null and self.definitions.items[selected.?].summarized) return error.InvalidObservedStore;
            if (selected == null) try self.definitions.ensureUnusedCapacity(1);
            const previous: ?Definition = if (selected) |i| self.definitions.items[i] else null;
            const next_value = if (!definite and previous != null) try context.join(previous.?.value, value) else value;
            var overwritten: []const Key = if (previous) |old| old.overwritten else &.{};
            if (definite) {
                const count = self.definitions.items.len - @intFromBool(selected != null);
                var unchanged = overwritten.len == count;
                for (self.definitions.items) |definition| {
                    if (!definition.target.eql(target) and !contains(overwritten, definition.target)) unchanged = false;
                }
                if (!unchanged) {
                    const keys = try self.fact_allocator.alloc(Key, count);
                    var next: usize = 0;
                    for (self.definitions.items) |definition| if (!definition.target.eql(target)) {
                        keys[next] = definition.target;
                        next += 1;
                    };
                    overwritten = keys;
                }
            }
            const Update = struct { index: usize, overwritten: []const Key };
            var updates = std.array_list.Managed(Update).init(self.definitions.allocator);
            defer updates.deinit();
            for (self.definitions.items, 0..) |definition, i| {
                if (definition.target.eql(target) or !contains(definition.overwritten, target)) continue;
                const keys = try self.fact_allocator.alloc(Key, definition.overwritten.len - 1);
                var next: usize = 0;
                for (definition.overwritten) |key| if (!key.eql(target)) {
                    keys[next] = key;
                    next += 1;
                };
                try updates.append(.{ .index = i, .overwritten = keys });
            }
            // Publish only after every allocation and payload join succeeds.
            for (updates.items) |update| self.definitions.items[update.index].overwritten = update.overwritten;
            const definition: Definition = .{ .target = target, .value = next_value, .must_write = definite or (previous != null and previous.?.must_write), .summarized = previous != null and previous.?.summarized, .overwritten = overwritten };
            if (selected) |i| self.definitions.items[i] = definition else self.definitions.appendAssumeCapacity(definition);
        }

        /// Forget one exact observation while retaining its writes in a weak
        /// summary source. The driver must also rewrite every retained alias of
        /// `source` before reusing that key for another evaluated reference.
        /// Summary sources cannot be strongly written: they may denote many
        /// cells. This operation changes content precision, never authority.
        pub fn summarizeObservation(self: *Self, source: Key, summary: Key, context: anytype) !void {
            if (source.eql(summary)) return error.InvalidObservedStore;
            const source_index = self.index(source) orelse return;
            if (self.index(summary)) |i| if (self.definitions.items[i].must_write) return error.InvalidObservedStore;
            var candidate = Self.init(self.fact_allocator, self.definitions.allocator);
            errdefer candidate.deinit();
            try candidate.definitions.appendSlice(self.definitions.items);
            try candidate.store(summary, self.definitions.items[source_index].value, false, context);
            _ = candidate.definitions.orderedRemove(candidate.index(source).?);
            for (candidate.definitions.items) |*definition| {
                if (definition.target.eql(summary)) {
                    definition.must_write = false;
                    definition.summarized = true;
                    definition.overwritten = &.{};
                    continue;
                }
                // Neither an exact old source nor an old summary denotes the
                // newly widened source. Their kill proofs cannot survive.
                var count: usize = 0;
                for (definition.overwritten) |key|
                    if (!key.eql(source) and !key.eql(summary)) {
                        count += 1;
                    };
                if (count == definition.overwritten.len) continue;
                const keys = try self.fact_allocator.alloc(Key, count);
                var next: usize = 0;
                for (definition.overwritten) |key| if (!key.eql(source) and !key.eql(summary)) {
                    keys[next] = key;
                    next += 1;
                };
                definition.overwritten = keys;
            }
            self.definitions.deinit();
            self.definitions = candidate.definitions;
        }

        pub fn needsInitial(self: *const Self, target: Key, context: anytype) bool {
            for (self.definitions.items) |definition|
                if (definition.must_write and relation(target, definition.target, context) == .same) return false;
            return true;
        }

        pub fn reaches(self: *const Self, target: Key, source_index: usize, context: anytype) bool {
            const source = self.definitions.items[source_index];
            if (relation(target, source.target, context) == .disjoint) return false;
            for (self.definitions.items) |later| {
                if (!later.must_write or relation(target, later.target, context) != .same) continue;
                if (contains(later.overwritten, source.target)) return false;
            }
            return true;
        }

        pub fn read(self: *const Self, target: Key, initial: Value, context: anytype) !Value {
            var result: ?Value = if (self.needsInitial(target, context)) initial else null;
            for (self.definitions.items, 0..) |definition, i| if (self.reaches(target, i, context)) {
                result = if (result) |before| try context.join(before, definition.value) else definition.value;
            };
            // A mandatory same-cell definition cannot kill itself. Therefore
            // either the initial value or a reaching definition must survive.
            return result orelse error.InvalidObservedStore;
        }

        pub fn join(fact_allocator: std.mem.Allocator, state_allocator: std.mem.Allocator, left: *const Self, right: *const Self, context: anytype) !Self {
            var result = Self.init(fact_allocator, state_allocator);
            errdefer result.deinit();
            for (left.definitions.items) |a| {
                const b = if (right.index(a.target)) |i| right.definitions.items[i] else null;
                var merged = a;
                merged.summarized = a.summarized or (b != null and b.?.summarized);
                merged.must_write = !merged.summarized and b != null and a.must_write and b.?.must_write;
                merged.overwritten = &.{};
                if (b) |other| {
                    merged.value = try context.join(a.value, other.value);
                    if (merged.must_write) {
                        if (sameKeys(a.overwritten, other.overwritten)) {
                            merged.overwritten = a.overwritten;
                        } else {
                            var common = std.array_list.Managed(Key).init(state_allocator);
                            defer common.deinit();
                            for (a.overwritten) |key| if (contains(other.overwritten, key)) try common.append(key);
                            merged.overwritten = try fact_allocator.dupe(Key, common.items);
                        }
                    }
                }
                try result.definitions.append(merged);
            }
            for (right.definitions.items) |b| if (left.index(b.target) == null) {
                var merged = b;
                merged.must_write = false;
                merged.overwritten = &.{};
                try result.definitions.append(merged);
            };
            return result;
        }

        pub fn eql(self: *const Self, other: *const Self, context: anytype) bool {
            if (self.definitions.items.len != other.definitions.items.len) return false;
            for (self.definitions.items) |a| {
                const b = other.definitions.items[other.index(a.target) orelse return false];
                if (a.summarized != b.summarized or a.must_write != b.must_write or !sameKeys(a.overwritten, b.overwritten) or !context.equal(a.value, b.value)) return false;
            }
            return true;
        }

        /// Shallow payload/proof copies are sufficient within one proof arena.
        /// Cross-arena publication still requires the ordinary fact snapshotter.
        pub fn snapshot(self: *const Self, allocator: std.mem.Allocator) ![]const Definition {
            return allocator.dupe(Definition, self.definitions.items);
        }

        pub fn restore(fact_allocator: std.mem.Allocator, state_allocator: std.mem.Allocator, definitions: []const Definition) !Self {
            var result = Self.init(fact_allocator, state_allocator);
            errdefer result.deinit();
            for (definitions) |definition| {
                if (definition.summarized and (definition.must_write or definition.overwritten.len != 0)) return error.InvalidObservedStore;
                if (result.index(definition.target) != null or contains(definition.overwritten, definition.target)) return error.InvalidObservedStore;
                for (definition.overwritten, 0..) |key, proof_index| {
                    if (contains(definition.overwritten[0..proof_index], key)) return error.InvalidObservedStore;
                    var found = false;
                    for (definitions) |candidate| if (candidate.target.eql(key)) {
                        found = true;
                        break;
                    };
                    if (!found) return error.InvalidObservedStore;
                }
                try result.definitions.append(definition);
            }
            return result;
        }
    };
}

const facts = @import("facts.zig");
const TestKey = facts.StorageIdentity;
const Bits = Stores(TestKey, u8);
fn testKey(index: usize) TestKey {
    return .{ .symbolic = @enumFromInt(index) };
}
const BitContext = struct {
    aliases: ?[3]u8 = null,
    pub fn relation(self: @This(), a: TestKey, b: TestKey) Relation {
        const aliases = self.aliases orelse return .unknown;
        return if (aliases[@intFromEnum(a.symbolic)] == aliases[@intFromEnum(b.symbolic)]) .same else .disjoint;
    }
    pub fn join(_: @This(), a: u8, b: u8) !u8 {
        return a | b;
    }
    pub fn equal(_: @This(), a: u8, b: u8) bool {
        return a == b;
    }
};

test "observed stores preserve every three-cell alias valuation and optional write" {
    for (0..216) |sequence| for (0..8) |mandatory| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var stores = Bits.init(arena.allocator(), std.testing.allocator);
        defer stores.deinit();
        var operations: [3]usize = undefined;
        var rest = sequence;
        for (&operations, 0..) |*operation, step| {
            operation.* = rest % 6;
            rest /= 6;
            try stores.store(testKey(operation.* % 3), @as(u8, 2) << @intCast(operation.* / 3), mandatory & (@as(usize, 1) << @intCast(step)) != 0, BitContext{});
        }
        var possible: [3]u8 = undefined;
        for (&possible, 0..) |*value, i| value.* = try stores.read(testKey(i), 1, BitContext{});
        try std.testing.expect(stores.definitions.items.len <= 3);
        for (stores.definitions.items) |definition| try std.testing.expect(definition.overwritten.len <= 2);
        for (0..27) |valuation| {
            const aliases: [3]u8 = .{ @intCast(valuation % 3), @intCast((valuation / 3) % 3), @intCast(valuation / 9) };
            for (0..8) |executed| {
                if (executed & mandatory != mandatory) continue;
                var memory: [3]u8 = .{ 1, 1, 1 };
                for (operations, 0..) |operation, step| if (executed & (@as(usize, 1) << @intCast(step)) != 0) {
                    memory[aliases[operation % 3]] = @as(u8, 2) << @intCast(operation / 3);
                };
                for (0..3) |i| {
                    const actual = memory[aliases[i]];
                    try std.testing.expect(possible[i] & actual != 0);
                    const known = try stores.read(testKey(i), 1, BitContext{ .aliases = aliases });
                    try std.testing.expect(known & actual != 0);
                    if (mandatory == 7) try std.testing.expectEqual(actual, known);
                }
            }
        }
    };
}

test "observed stores join branch proofs conservatively and overwrite after joins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var left = Bits.init(arena.allocator(), std.testing.allocator);
    defer left.deinit();
    var right = Bits.init(arena.allocator(), std.testing.allocator);
    defer right.deinit();
    try left.store(testKey(0), 2, true, BitContext{});
    try left.store(testKey(1), 4, true, BitContext{});
    try right.store(testKey(1), 2, true, BitContext{});
    try right.store(testKey(0), 4, true, BitContext{});
    var joined = try Bits.join(arena.allocator(), std.testing.allocator, &left, &right, BitContext{});
    defer joined.deinit();
    for (0..27) |valuation| {
        const aliases: [3]u8 = .{ @intCast(valuation % 3), @intCast((valuation / 3) % 3), @intCast(valuation / 9) };
        const context = BitContext{ .aliases = aliases };
        for ([_][2]usize{ .{ 0, 1 }, .{ 1, 0 } }) |order| {
            var memory: [3]u8 = .{ 1, 1, 1 };
            memory[aliases[order[0]]] = 2;
            memory[aliases[order[1]]] = 4;
            for (0..3) |i| try std.testing.expect((try joined.read(testKey(i), 1, context)) & memory[aliases[i]] != 0);
        }
    }
    try joined.store(testKey(0), 1, true, BitContext{});
    try std.testing.expectEqual(@as(u8, 1), try joined.read(testKey(0), 4, BitContext{}));
    var same = try Bits.join(arena.allocator(), std.testing.allocator, &joined, &joined, BitContext{});
    defer same.deinit();
    try std.testing.expect(joined.eql(&same, BitContext{}));
}

test "observed stores keep repeated same-cell writes at a metadata fixed point" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var stores = Bits.init(arena.allocator(), std.testing.allocator);
    defer stores.deinit();
    try stores.store(testKey(0), 1, true, BitContext{});
    try stores.store(testKey(1), 2, true, BitContext{});
    try stores.store(testKey(0), 4, true, BitContext{});
    const before = try stores.snapshot(arena.allocator());
    var exhausted = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    stores.fact_allocator = exhausted.allocator();
    stores.definitions.allocator = exhausted.allocator();
    defer stores.definitions.allocator = std.testing.allocator;
    for (0..10000) |_| try stores.store(testKey(0), 4, true, BitContext{});
    try std.testing.expectEqualDeep(before, stores.definitions.items);
    try std.testing.expectEqual(@as(u8, 4), try stores.read(testKey(0), 1, BitContext{}));
}

test "observed stores publish no partial update after allocation failure" {
    var success = false;
    for (0..16) |failure| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var stores = Bits.init(arena.allocator(), std.testing.allocator);
        defer stores.deinit();
        try stores.store(testKey(0), 2, true, BitContext{});
        try stores.store(testKey(1), 4, true, BitContext{});
        const before = try stores.snapshot(arena.allocator());
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = failure });
        var mutation = std.heap.ArenaAllocator.init(failing.allocator());
        defer mutation.deinit();
        stores.fact_allocator = mutation.allocator();
        stores.definitions.allocator = failing.allocator();
        defer stores.definitions.allocator = std.testing.allocator;
        stores.store(testKey(0), 1, true, BitContext{}) catch |err| {
            if (err != error.OutOfMemory) return err;
            try std.testing.expectEqualDeep(before, stores.definitions.items);
            continue;
        };
        success = true;
        try std.testing.expectEqual(@as(u8, 1), try stores.read(testKey(0), 2, BitContext{}));
        break;
    }
    try std.testing.expect(success);
}

test "observed stores reject duplicate and dangling snapshot keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first: Bits.Definition = .{ .target = testKey(0), .value = 1, .must_write = true };
    try std.testing.expectError(error.InvalidObservedStore, Bits.restore(a, std.testing.allocator, &.{ first, first }));
    try std.testing.expectError(error.InvalidObservedStore, Bits.restore(a, std.testing.allocator, &.{.{ .target = testKey(0), .value = 1, .must_write = true, .overwritten = &.{testKey(0)} }}));
    try std.testing.expectError(error.InvalidObservedStore, Bits.restore(a, std.testing.allocator, &.{.{ .target = testKey(0), .value = 1, .must_write = true, .overwritten = &.{testKey(1)} }}));
    const other: Bits.Definition = .{ .target = testKey(1), .value = 2, .must_write = true };
    try std.testing.expectError(error.InvalidObservedStore, Bits.restore(a, std.testing.allocator, &.{ .{ .target = testKey(0), .value = 1, .must_write = true, .overwritten = &.{ testKey(1), testKey(1) } }, other }));
}

// The current observation changes its physical target at each simulated call.
// A summary source can denote any prior target, not a fresh allocation.
const ReobservedContext = struct {
    current: u8,
    pub fn relation(self: @This(), a: TestKey, b: TestKey) Relation {
        const left = @intFromEnum(a.symbolic);
        const right = @intFromEnum(b.symbolic);
        if (left == 1 or right == 1) return .unknown;
        const x = if (left == 0) self.current else left - 2;
        const y = if (right == 0) self.current else right - 2;
        return if (x == y) .same else .disjoint;
    }
    pub fn join(_: @This(), a: u8, b: u8) !u8 {
        return a | b;
    }
    pub fn equal(_: @This(), a: u8, b: u8) bool {
        return a == b;
    }
};

test "observed stores cannot reuse a call-site key without retaining prior targets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var naive = Bits.init(arena.allocator(), std.testing.allocator);
    defer naive.deinit();
    try naive.store(testKey(0), 2, true, ReobservedContext{ .current = 0 });
    // The same producer now returns a different cell. Pretending this is the
    // same observed value loses the first cell's still-retained payload.
    try naive.store(testKey(0), 4, true, ReobservedContext{ .current = 1 });
    try std.testing.expectEqual(@as(u8, 0), (try naive.read(testKey(2), 1, ReobservedContext{ .current = 1 })) & 2);

    var retained = Bits.init(arena.allocator(), std.testing.allocator);
    defer retained.deinit();
    try retained.store(testKey(0), 2, true, ReobservedContext{ .current = 0 });
    try retained.summarizeObservation(testKey(0), testKey(1), ReobservedContext{ .current = 0 });
    try retained.store(testKey(0), 4, true, ReobservedContext{ .current = 1 });
    try std.testing.expect((try retained.read(testKey(2), 1, ReobservedContext{ .current = 1 })) & 2 != 0);
    // Replacing through one unchanged current observation is still precise.
    try std.testing.expectEqual(@as(u8, 4), try retained.read(testKey(0), 1, ReobservedContext{ .current = 1 }));
}

test "observed stores summarize repeated observations with bounded source rows" {
    // Six calls, two physical cells and two possible RHS values: all 4096
    // concrete traces, including repeated and changing targets at one producer.
    for (0..4096) |trace| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var stores = Bits.init(arena.allocator(), std.testing.allocator);
        defer stores.deinit();
        var memory: [2]u8 = .{ 1, 1 };
        var rest = trace;
        for (0..6) |_| {
            const target: u8 = @intCast(rest % 2);
            const value: u8 = if (rest % 4 < 2) 2 else 4;
            rest /= 4;
            const context = ReobservedContext{ .current = target };
            try stores.summarizeObservation(testKey(0), testKey(1), context);
            try stores.store(testKey(0), value, true, context);
            memory[target] = value;
            for (memory, 0..) |actual, index|
                try std.testing.expect((try stores.read(testKey(index + 2), 1, context)) & actual != 0);
            try std.testing.expectEqual(value, try stores.read(testKey(0), 1, context));
            try std.testing.expect(stores.definitions.items.len <= 2);
        }
    }
}

test "observed store summarization is transactional on allocation failure" {
    var success = false;
    for (0..24) |failure| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var stores = Bits.init(arena.allocator(), std.testing.allocator);
        defer stores.deinit();
        try stores.store(testKey(0), 2, true, BitContext{});
        try stores.store(testKey(1), 4, false, BitContext{});
        try stores.store(testKey(2), 1, true, BitContext{});
        const before = try stores.snapshot(arena.allocator());
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = failure });
        var mutation = std.heap.ArenaAllocator.init(failing.allocator());
        defer mutation.deinit();
        stores.fact_allocator = mutation.allocator();
        stores.definitions.allocator = failing.allocator();
        defer stores.definitions.allocator = std.testing.allocator;
        stores.summarizeObservation(testKey(0), testKey(1), BitContext{}) catch |err| {
            if (err != error.OutOfMemory) return err;
            try std.testing.expectEqualDeep(before, stores.definitions.items);
            continue;
        };
        success = true;
        try std.testing.expectEqual(@as(usize, 2), stores.definitions.items.len);
        try std.testing.expectEqual(@as(u8, 7), try stores.read(testKey(1), 1, BitContext{}));
        break;
    }
    try std.testing.expect(success);
}

test "observed stores reject exact overwrites of summarized observations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var stores = Bits.init(arena.allocator(), std.testing.allocator);
    defer stores.deinit();
    try stores.store(testKey(0), 2, true, BitContext{});
    try std.testing.expectError(error.InvalidObservedStore, stores.summarizeObservation(testKey(0), testKey(0), BitContext{}));
    try stores.summarizeObservation(testKey(0), testKey(1), BitContext{});
    const before = try stores.snapshot(arena.allocator());
    try std.testing.expectError(error.InvalidObservedStore, stores.store(testKey(1), 4, true, BitContext{}));
    try std.testing.expectEqualDeep(before, stores.definitions.items);
    var restored = try Bits.restore(arena.allocator(), std.testing.allocator, before);
    defer restored.deinit();
    try std.testing.expect(restored.eql(&stores, BitContext{}));
    try std.testing.expectError(error.InvalidObservedStore, restored.store(testKey(1), 4, true, BitContext{}));
    var empty = Bits.init(arena.allocator(), std.testing.allocator);
    defer empty.deinit();
    var joined = try Bits.join(arena.allocator(), std.testing.allocator, &stores, &empty, BitContext{});
    defer joined.deinit();
    try std.testing.expectError(error.InvalidObservedStore, joined.store(testKey(1), 4, true, BitContext{}));
    var invalid = before[0];
    invalid.must_write = true;
    try std.testing.expectError(error.InvalidObservedStore, Bits.restore(arena.allocator(), std.testing.allocator, &.{invalid}));
    // Once the finite payload has stabilized, repeated observation recycling
    // reaches the same metadata state instead of adding historical rows.
    try stores.store(testKey(0), 4, true, BitContext{});
    try stores.summarizeObservation(testKey(0), testKey(1), BitContext{});
    try stores.store(testKey(0), 4, true, BitContext{});
    const fixed = try stores.snapshot(arena.allocator());
    try stores.summarizeObservation(testKey(0), testKey(1), BitContext{});
    try stores.store(testKey(0), 4, true, BitContext{});
    try std.testing.expectEqualDeep(fixed, stores.definitions.items);
}

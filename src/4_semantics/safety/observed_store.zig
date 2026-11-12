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
            const definition: Definition = .{ .target = target, .value = next_value, .must_write = definite or (previous != null and previous.?.must_write), .overwritten = overwritten };
            if (selected) |i| self.definitions.items[i] = definition else self.definitions.appendAssumeCapacity(definition);
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
                merged.must_write = b != null and a.must_write and b.?.must_write;
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
                if (a.must_write != b.must_write or !sameKeys(a.overwritten, b.overwritten) or !context.equal(a.value, b.value)) return false;
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

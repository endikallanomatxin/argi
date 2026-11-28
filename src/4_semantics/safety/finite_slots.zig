//! Mutable transfer scratch over a fixed layout. Published dataflow states
//! must own their snapshots. Rows name storage; columns name producers.
const std = @import("std");
const Observation = @import("loop_observation.zig").Observation;
const Initialization = @import("value_state.zig").Initialization;

/// Possible outstanding obligations. Positive bits cannot authorize a
/// move or destruction. That requires a separate unique selection proof.
pub const Custody = packed struct(u2) {
    current: bool = false,
    historical: bool = false,

    pub fn join(left: Custody, right: Custody) Custody {
        return .{ .current = left.current or right.current, .historical = left.historical or right.historical };
    }

    pub fn covers(self: Custody, other: Custody) bool {
        return (!other.current or self.current) and (!other.historical or self.historical);
    }

    pub fn age(self: Custody) Custody {
        return .{ .historical = self.current or self.historical };
    }
};

pub const Slots = struct {
    /// The concrete domain can change when its producing handle is renewed.
    /// Both rows are assigned once, before the first transfer.
    pub const OpaqueRows = struct {
        producer: usize,
        current: usize,
        historical: usize,
    };

    pub const Layout = struct {
        slots: usize,
        producers: usize,
        opaque_rows: []const OpaqueRows = &.{},
        /// Each opaque row belongs to exactly one domain. Sharing a row
        /// would let renewal of one domain clear another domain's contents.
        fn validate(self: Layout, allocator: std.mem.Allocator) !void {
            if (self.opaque_rows.len == 0) return;
            var used = try std.DynamicBitSetUnmanaged.initEmpty(allocator, self.slots);
            defer used.deinit(allocator);
            for (self.opaque_rows) |rows| {
                if (rows.producer >= self.producers or rows.current >= self.slots or rows.historical >= self.slots or
                    rows.current == rows.historical or used.isSet(rows.current) or used.isSet(rows.historical))
                    return error.InvalidOpaqueLayout;
                used.set(rows.current);
                used.set(rows.historical);
            }
        }
    };

    layout: Layout,
    initialization: []Initialization,
    observations: []Observation,
    custody: []Custody,

    pub fn init(allocator: std.mem.Allocator, layout: Layout) !Slots {
        const count = try std.math.mul(usize, layout.slots, layout.producers);
        try layout.validate(allocator);
        const initialization = try allocator.alloc(Initialization, layout.slots);
        errdefer allocator.free(initialization);
        const observations = try allocator.alloc(Observation, count);
        errdefer allocator.free(observations);
        const custody = try allocator.alloc(Custody, count);
        @memset(custody, .{});
        @memset(initialization, .{});
        @memset(observations, .{});
        return .{ .layout = layout, .initialization = initialization, .observations = observations, .custody = custody };
    }

    /// Copies a state in the same already validated layout.
    pub fn clone(self: Slots, allocator: std.mem.Allocator) !Slots {
        const initialization = try allocator.dupe(Initialization, self.initialization);
        errdefer allocator.free(initialization);
        const observations = try allocator.dupe(Observation, self.observations);
        errdefer allocator.free(observations);
        const custody = try allocator.dupe(Custody, self.custody);
        return .{ .layout = self.layout, .initialization = initialization, .observations = observations, .custody = custody };
    }

    pub fn deinit(self: Slots, allocator: std.mem.Allocator) void {
        allocator.free(self.custody);
        allocator.free(self.observations);
        allocator.free(self.initialization);
    }

    pub fn observation(self: Slots, slot: usize, producer: usize) Observation {
        return self.observationRow(slot)[producer];
    }

    fn observationRow(self: Slots, slot: usize) []Observation {
        std.debug.assert(slot < self.layout.slots);
        return self.observations[slot * self.layout.producers ..][0..self.layout.producers];
    }

    pub fn observeCurrent(self: Slots, destination: usize, producer: usize) void {
        const row = self.observationRow(destination);
        @memset(row, .{});
        row[producer] = .{ .current_live = true };
        self.initialization[destination] = .{ .initialized = true };
    }

    /// Write a copied reference into a preassigned storage row. A caller
    /// with multiple possible destinations applies a weak write to each.
    /// This does not copy or discharge owning obligations.
    pub fn writeReference(self: Slots, destination: usize, source: usize, definite: bool) void {
        if (destination == source) return;
        const incoming = self.observationRow(source);
        const stored = self.observationRow(destination);
        if (definite) {
            @memcpy(stored, incoming);
            self.initialization[destination] = self.initialization[source];
        } else {
            for (stored, incoming) |*old, new| old.* = old.join(new);
            self.initialization[destination] = self.initialization[destination].weakWrite(self.initialization[source]);
        }
    }

    /// On the success edge of a checked selection, the element inherits
    /// the observation dependencies of the receiver. Bounds, initialized
    /// contents, and access authority must be proved by the operation.
    /// A successful selection supplies no custody of the selected value.
    pub fn borrowSelected(self: Slots, destination: usize, receiver: usize) bool {
        if (!self.initialization[receiver].definitelyInitialized()) return false;
        const source = self.observationRow(receiver);
        var witnessed = false;
        for (source) |dependency| {
            if (dependency.current_ended or dependency.historical) return false;
            witnessed = witnessed or dependency.provesCurrent();
        }
        if (!witnessed) return false;
        self.writeReference(destination, receiver, true);
        return true;
    }

    pub fn owner(self: Slots, slot: usize, producer: usize) *Custody {
        std.debug.assert(slot < self.layout.slots and producer < self.layout.producers);
        return &self.custody[slot * self.layout.producers + producer];
    }

    /// The caller must already have identified the exact current owner.
    /// Destroying it cannot discharge older instances from the same producer.
    pub fn dischargeCurrent(self: Slots, slot: usize, producer: usize) void {
        self.owner(slot, producer).current = false;
        for (0..self.layout.slots) |index| {
            const row = self.observationRow(index);
            row[producer] = row[producer].retireCurrent();
        }
    }

    pub fn retainOpaqueObservation(self: Slots, domain: OpaqueRows, historical: bool, producer: usize, dependency: Observation) void {
        const row = self.observationRow(if (historical) domain.historical else domain.current);
        row[producer] = row[producer].join(dependency);
    }

    /// Clear dependency evidence for a certified exact emptying.
    /// The caller must account for the custody discharged by the operation.
    pub fn emptyCurrentOpaque(self: Slots, domain: OpaqueRows) void {
        @memset(self.observationRow(domain.current), .{});
    }

    fn moveOpaqueContents(self: Slots, from: usize, to: usize) void {
        const source = self.observationRow(from);
        const destination = self.observationRow(to);
        for (destination, source, 0..) |*retained, *moved, dependency_producer| {
            retained.* = retained.join(moved.*);
            moved.* = .{};
            const old_custody = self.owner(from, dependency_producer);
            const new_custody = self.owner(to, dependency_producer);
            new_custody.* = new_custody.join(old_custody.*);
            old_custody.* = .{};
        }
    }

    /// Apply a production event to every stored observation of this producer.
    /// Age observations and outstanding custody together.
    pub fn age(self: Slots, producer: usize) void {
        self.renewProducer(producer, null);
    }

    /// A verified full relocation moves initialized contents to the new
    /// current backing. Observations of the old backing still age. The
    /// caller proves a unique current source and preservation of contents.
    pub fn renewRelocatingOpaque(self: Slots, domain: OpaqueRows) void {
        self.renewProducer(domain.producer, domain.current);
    }

    fn renewProducer(self: Slots, producer: usize, relocated_row: ?usize) void {
        std.debug.assert(producer < self.layout.producers);
        for (0..self.layout.slots) |slot| {
            const row = self.observationRow(slot);
            row[producer] = row[producer].age();
            const custody = self.owner(slot, producer);
            custody.* = custody.age();
        }
        for (self.layout.opaque_rows) |domain| {
            if (domain.producer != producer or domain.current == relocated_row) continue;
            self.moveOpaqueContents(domain.current, domain.historical);
        }
    }

    fn sameLayout(self: Slots, incoming: Slots) bool {
        return self.layout.slots == incoming.layout.slots and
            self.layout.producers == incoming.layout.producers and
            self.layout.opaque_rows.ptr == incoming.layout.opaque_rows.ptr and
            self.layout.opaque_rows.len == incoming.layout.opaque_rows.len;
    }

    pub fn covers(self: Slots, incoming: Slots) bool {
        std.debug.assert(self.sameLayout(incoming));
        for (self.initialization, incoming.initialization) |a, b| if (!a.covers(b)) return false;
        for (self.observations, incoming.observations) |a, b| if (!a.covers(b)) return false;
        for (self.custody, incoming.custody) |a, b| if (!a.covers(b)) return false;
        return true;
    }

    pub fn include(self: Slots, incoming: Slots) void {
        std.debug.assert(self.sameLayout(incoming));
        for (self.initialization, incoming.initialization) |*a, b| a.* = a.join(b);
        for (self.observations, incoming.observations) |*a, b| a.* = a.join(b);
        for (self.custody, incoming.custody) |*a, b| a.* = a.join(b);
    }
};

test "safety finite slots age every alias without growing the layout" {
    const a = std.testing.allocator;
    const header = try Slots.init(a, .{ .slots = 3, .producers = 2 });
    defer header.deinit(a);
    const successor = try Slots.init(a, header.layout);
    defer successor.deinit(a);
    successor.observeCurrent(0, 0);
    successor.observeCurrent(1, 0);
    successor.observeCurrent(2, 1);
    successor.age(0);
    successor.observeCurrent(0, 0);
    header.include(successor);

    for (0..100) |_| {
        successor.age(0);
        successor.observeCurrent(0, 0);
        try std.testing.expect(header.covers(successor));
        try std.testing.expect(successor.observation(0, 0).provesCurrent());
        try std.testing.expect(!successor.observation(1, 0).provesCurrent());
        try std.testing.expect(successor.observation(1, 0).historical);
        try std.testing.expect(successor.observation(2, 1).provesCurrent());
    }
    try std.testing.expectEqual(@as(usize, 6), successor.observations.len);
}

test "safety finite slots preserve historical custody after exact current destruction" {
    const a = std.testing.allocator;
    const state = try Slots.init(a, .{ .slots = 2, .producers = 1 });
    defer state.deinit(a);
    const header = try Slots.init(a, state.layout);
    defer header.deinit(a);
    state.owner(0, 0).current = true;
    state.observeCurrent(1, 0);
    state.age(0);
    state.owner(0, 0).current = true;
    state.observeCurrent(1, 0);
    header.include(state);
    state.dischargeCurrent(0, 0);
    try std.testing.expectEqual(Custody{ .historical = true }, state.owner(0, 0).*);
    try std.testing.expect(!state.observation(1, 0).provesCurrent());
    try std.testing.expect(!header.covers(state));
    header.include(state);
    try std.testing.expect(header.covers(state));
    try std.testing.expectEqual(Custody{ .current = true, .historical = true }, header.owner(0, 0).*);
}

test "safety finite opaque rows age with their handle and preserve older hidden dependencies" {
    const a = std.testing.allocator;
    const domain: Slots.OpaqueRows = .{ .producer = 0, .current = 0, .historical = 1 };
    const state = try Slots.init(a, .{ .slots = 2, .producers = 2, .opaque_rows = &.{domain} });
    defer state.deinit(a);
    const header = try Slots.init(a, state.layout);
    defer header.deinit(a);
    state.retainOpaqueObservation(domain, false, 0, .{ .current_live = true });
    state.retainOpaqueObservation(domain, false, 1, .{ .current_live = true });
    state.owner(domain.current, 1).current = true;
    state.age(0);
    state.retainOpaqueObservation(domain, false, 1, .{ .current_live = true });
    state.emptyCurrentOpaque(domain);
    try std.testing.expectEqual(Observation{}, state.observation(domain.current, 1));
    try std.testing.expectEqual(Observation{ .historical = true }, state.observation(domain.historical, 0));
    try std.testing.expect(state.observation(domain.historical, 1).provesCurrent());
    try std.testing.expect(state.owner(domain.historical, 1).current);
    try std.testing.expect(!state.owner(domain.current, 1).current);
    try std.testing.expect(!header.covers(state));
    header.include(state);
    state.age(0);
    try std.testing.expect(header.covers(state));
}

test "safety checked selection borrows old owned elements from a current container" {
    const a = std.testing.allocator;
    const domain: Slots.OpaqueRows = .{ .producer = 0, .current = 3, .historical = 4 };
    const state = try Slots.init(a, .{ .slots = 5, .producers = 2, .opaque_rows = &.{domain} });
    defer state.deinit(a);
    for (0..100) |_| {
        state.age(1);
        state.owner(domain.current, 1).current = true;
    }
    try std.testing.expectEqual(Custody{ .current = true, .historical = true }, state.owner(domain.current, 1).*);
    try std.testing.expect(!state.borrowSelected(1, 0));
    state.observeCurrent(0, 0);
    try std.testing.expect(state.borrowSelected(1, 0));
    try std.testing.expect(state.observation(1, 0).provesCurrent());
    try std.testing.expectEqual(Observation{}, state.observation(1, 1));
    try std.testing.expectEqual(Custody{}, state.owner(1, 1).*);

    state.retainOpaqueObservation(domain, false, 0, .{ .current_live = true });
    state.renewRelocatingOpaque(domain);
    try std.testing.expect(!state.borrowSelected(2, 0));
    state.observeCurrent(0, 0);
    try std.testing.expect(state.borrowSelected(2, 0));
    try std.testing.expect(!state.observation(1, 0).provesCurrent());
    try std.testing.expect(state.observation(2, 0).provesCurrent());
    try std.testing.expectEqual(Custody{ .current = true, .historical = true }, state.owner(domain.current, 1).*);
    try std.testing.expectEqual(Custody{}, state.owner(domain.historical, 1).*);
    try std.testing.expect(state.observation(domain.current, 0).historical);
}

test "safety finite dataflow covers repeated owned element insertion and backing relocation" {
    const Domain = struct {
        pub const State = Slots;
        const backing = 0;
        const element = 1;
        const receiver = 0;
        const saved = 1;
        const fresh = 2;
        const contents: Slots.OpaqueRows = .{ .producer = backing, .current = 3, .historical = 4 };
        const layout: Slots.Layout = .{ .slots = 5, .producers = 2, .opaque_rows = &.{contents} };

        allocator: std.mem.Allocator,

        pub fn release(self: @This(), state: State) void {
            state.deinit(self.allocator);
        }

        pub fn successors(_: @This(), block: usize) []const usize {
            return switch (block) {
                0, 1 => &.{2},
                2 => &.{ 2, 1, 3 },
                else => &.{},
            };
        }

        pub fn transfer(self: @This(), block: usize, successor: usize, state: State) !?State {
            const next = try state.clone(self.allocator);
            errdefer next.deinit(self.allocator);
            if (block == 2 and successor == 3) {
                try std.testing.expect(next.borrowSelected(fresh, receiver));
                return next;
            }
            if (block == 2) {
                next.renewRelocatingOpaque(contents);
                next.observeCurrent(receiver, backing);
            } else {
                next.age(element);
                next.owner(contents.current, element).current = true;
                if (block == 0) try std.testing.expect(next.borrowSelected(saved, receiver));
            }
            return next;
        }

        pub fn join(self: @This(), left: State, right: State) !State {
            const next = try left.clone(self.allocator);
            next.include(right);
            return next;
        }

        pub fn covers(_: @This(), left: State, right: State) bool {
            return left.covers(right);
        }
    };
    const domain: Domain = .{ .allocator = std.testing.allocator };
    const initial = try Slots.init(domain.allocator, Domain.layout);
    initial.observeCurrent(Domain.receiver, Domain.backing);
    var headers: [4]?Slots = @splat(null);
    defer for (headers) |header| if (header) |state| domain.release(state);
    try @import("finite_dataflow.zig").solve(Domain, domain.allocator, &headers, 0, initial, domain);

    for (headers, 0..) |header, block| {
        for (domain.successors(block)) |successor| {
            const incoming = (try domain.transfer(block, successor, header.?)).?;
            defer domain.release(incoming);
            try std.testing.expect(headers[successor].?.covers(incoming));
        }
    }
    const after = headers[3].?;
    try std.testing.expectEqual(Custody{ .current = true, .historical = true }, after.owner(Domain.contents.current, Domain.element).*);
    try std.testing.expect(after.observation(Domain.fresh, Domain.backing).provesCurrent());
    try std.testing.expect(!after.observation(Domain.saved, Domain.backing).provesCurrent());
}

test "safety finite layouts reject overlapping opaque domain rows" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.InvalidOpaqueLayout, Slots.init(a, .{
        .slots = 3,
        .producers = 2,
        .opaque_rows = &.{
            .{ .producer = 0, .current = 0, .historical = 1 },
            .{ .producer = 1, .current = 2, .historical = 0 },
        },
    }));
}

test "safety finite symbolic writes preserve both targets of a possible update" {
    const a = std.testing.allocator;
    const state = try Slots.init(a, .{ .slots = 3, .producers = 2 });
    defer state.deinit(a);
    state.observeCurrent(0, 0);
    state.observeCurrent(1, 1);
    state.writeReference(2, 0, true);
    state.writeReference(2, 1, false);
    try std.testing.expect(state.observation(2, 0).provesCurrent());
    try std.testing.expect(state.observation(2, 1).provesCurrent());
    state.age(0);
    try std.testing.expect(!state.borrowSelected(0, 2));
    state.writeReference(2, 1, true);
    try std.testing.expectEqual(Observation{}, state.observation(2, 0));
    try std.testing.expect(state.borrowSelected(0, 2));
}

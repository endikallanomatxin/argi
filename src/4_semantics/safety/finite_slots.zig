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

/// Suspended authority from a statically named execution site. Historical
/// restrictions can represent several still-pending receipts.
const Restriction = packed struct(u4) {
    current_read: bool = false,
    current_write: bool = false,
    historical_read: bool = false,
    historical_write: bool = false,

    fn include(self: Restriction, incoming: Restriction) Restriction {
        return @bitCast(@as(u4, @bitCast(self)) | @as(u4, @bitCast(incoming)));
    }

    fn covers(self: Restriction, incoming: Restriction) bool {
        return @as(u4, @bitCast(self.include(incoming))) == @as(u4, @bitCast(self));
    }

    fn age(self: Restriction) Restriction {
        return .{
            .historical_read = self.current_read or self.historical_read,
            .historical_write = self.current_write or self.historical_write,
        };
    }
};

/// Construct the immutable overlap relation for authority checks. Unknown
/// referents may alias even when they have distinct symbolic identities.
pub const StorageOverlaps = struct {
    pairs: [][2]usize,
    unknown: []usize,

    pub fn deinit(self: StorageOverlaps, allocator: std.mem.Allocator) void {
        allocator.free(self.unknown);
        allocator.free(self.pairs);
    }
};

pub fn storageOverlaps(
    allocator: std.mem.Allocator,
    graph: *const @import("../global/graph.zig").GlobalSemanticGraph,
    storage: []const @import("facts.zig").StorageIdentity,
) !StorageOverlaps {
    var pairs: std.ArrayList([2]usize) = .empty;
    defer pairs.deinit(allocator);
    var unknown: std.ArrayList(usize) = .empty;
    defer unknown.deinit(allocator);
    var places: std.ArrayList(usize) = .empty;
    defer places.deinit(allocator);
    for (storage, 0..) |left, i| {
        if (left == .symbolic) {
            try unknown.append(allocator, i);
            continue;
        }
        for (places.items) |j| {
            if (@import("access_bounds.zig").storageMayOverlap(graph, left.place, storage[j].place))
                try pairs.append(allocator, .{ j, i });
        }
        try places.append(allocator, i);
    }
    const owned_pairs = try pairs.toOwnedSlice(allocator);
    errdefer allocator.free(owned_pairs);
    return .{ .pairs = owned_pairs, .unknown = try unknown.toOwnedSlice(allocator) };
}

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
        receipt_sites: usize = 0,
        opaque_rows: []const OpaqueRows = &.{},
        /// Symmetric pairs from the typed overlap analysis. Overlap is not
        /// transitive: disjoint siblings may both overlap a whole record.
        overlaps: []const [2]usize = &.{},
        /// Regions that may alias every slot, in ascending slot order.
        unknown_overlaps: []const usize = &.{},

        /// Each opaque row belongs to exactly one domain. Sharing a row
        /// would let renewal of one domain clear another domain's contents.
        fn validate(self: Layout, allocator: std.mem.Allocator) !void {
            for (self.unknown_overlaps, 0..) |slot, index| {
                if (slot >= self.slots or (index != 0 and self.unknown_overlaps[index - 1] >= slot))
                    return error.InvalidStorageOverlap;
            }
            for (self.overlaps) |pair| {
                if (pair[0] >= self.slots or pair[1] >= self.slots or pair[0] == pair[1])
                    return error.InvalidStorageOverlap;
            }
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

    pub const Selection = struct {
        destination: usize,
        receiver: usize,
        region: usize,
        mode: Access = .read,
    };

    pub const ReferenceWrite = struct {
        destination: usize,
        source: usize,
        definite: bool,
    };

    /// Transfer operands are resolved against the immutable layout before
    /// solving. The lowering must prove each exact destination and encode
    /// only the success edge of a checked selection.
    pub const Transfer = union(enum) {
        produce: usize,
        relocate_backing: OpaqueRows,
        destroy_opaque_contents: OpaqueRows,
        retain_owner: struct { slot: usize, producer: usize },
        observe: struct { slot: usize, producer: usize },
        copy_reference: ReferenceWrite,
        copy_reference_to_candidates: struct { source: usize, destinations: []const usize },
        reference_post_states: []const ReferenceWrite,
        select: Selection,
        extract_opaque_element: struct { selection: Selection, domain: OpaqueRows, result_producer: usize },
        suspend_access: struct { slot: usize, receipt_site: usize, exclusive: bool },
        start_execution: usize,
        complete_execution: usize,

        fn valid(self: Transfer, layout: Layout) bool {
            return switch (self) {
                .produce => |producer| producer < layout.producers,
                .relocate_backing, .destroy_opaque_contents => |domain| hasDomain(layout, domain),
                .retain_owner => |retained| retained.slot < layout.slots and retained.producer < layout.producers,
                .observe => |reference| reference.slot < layout.slots and reference.producer < layout.producers,
                .copy_reference => |write| validWrite(layout, write),
                .copy_reference_to_candidates => |write| blk: {
                    if (write.source >= layout.slots or write.destinations.len == 0) break :blk false;
                    for (write.destinations) |destination| if (destination >= layout.slots) break :blk false;
                    break :blk true;
                },
                .reference_post_states => |writes| for (writes) |write| {
                    if (!validWrite(layout, write)) break false;
                } else true,
                .select => |selection| validSelection(layout, selection),
                .extract_opaque_element => |op| hasDomain(layout, op.domain) and validSelection(layout, op.selection) and
                    op.selection.mode == .write and op.selection.region == op.domain.current and
                    op.selection.destination != op.domain.current and op.selection.destination != op.domain.historical and
                    op.result_producer < layout.producers and op.result_producer != op.domain.producer,
                .suspend_access => |loan| loan.slot < layout.slots and loan.receipt_site < layout.receipt_sites,
                .start_execution, .complete_execution => |site| site < layout.receipt_sites,
            };
        }

        fn validWrite(layout: Layout, write: ReferenceWrite) bool {
            return write.destination < layout.slots and write.source < layout.slots;
        }

        fn validSelection(layout: Layout, selection: Selection) bool {
            return selection.destination < layout.slots and selection.receiver < layout.slots and selection.region < layout.slots;
        }

        fn hasDomain(layout: Layout, domain: OpaqueRows) bool {
            for (layout.opaque_rows) |declared| if (std.meta.eql(declared, domain)) return true;
            return false;
        }

        fn requiredSelection(self: Transfer) ?Selection {
            return switch (self) {
                .select => |selected| selected,
                .extract_opaque_element => |extraction| extraction.selection,
                else => null,
            };
        }

        pub fn apply(self: Transfer, state: Slots, allocator: std.mem.Allocator) !void {
            if (self.requiredSelection()) |selected| {
                if (!state.canSelect(selected)) return error.UnprovedObservation;
            }
            try self.propagate(state, allocator);
        }

        // Compute the effect of a successful operation. The solver checks
        // its safety precondition against the fixed point before accepting.
        fn propagate(self: Transfer, state: Slots, allocator: std.mem.Allocator) !void {
            switch (self) {
                .produce => |producer| state.age(producer),
                .relocate_backing => |domain| state.renewRelocatingOpaque(domain),
                .destroy_opaque_contents => |domain| state.destroyOpaqueContents(domain),
                .retain_owner => |retained| state.owner(retained.slot, retained.producer).current = true,
                .observe => |reference| state.observeCurrent(reference.slot, reference.producer),
                .copy_reference => |write| state.writeReference(write.destination, write.source, write.definite),
                .copy_reference_to_candidates => |write| {
                    // A weak self-write is idempotent, so evaluating the
                    // source row once also works when it is a candidate.
                    const value = state.referenceValue(write.source);
                    for (write.destinations) |destination| state.writeReferenceValue(destination, value, false);
                },
                .reference_post_states => |writes| try state.applyReferencePostStates(allocator, writes),
                .suspend_access => |loan| state.suspendAccess(loan.slot, loan.receipt_site, loan.exclusive),
                .start_execution => |site| state.ageExecution(site),
                .complete_execution => |site| state.completeCurrent(site),
                .extract_opaque_element => |extraction| state.extractOpaqueElement(extraction.selection, extraction.domain, extraction.result_producer),
                .select => |selected| state.writeReference(selected.destination, selected.receiver, true),
            }
        }
    };

    layout: Layout,
    initialization: []Initialization,
    observations: []Observation,
    unobserved: []bool,
    custody: []Custody,
    restrictions: []Restriction,

    pub fn init(allocator: std.mem.Allocator, layout: Layout) !Slots {
        const count = try std.math.mul(usize, layout.slots, layout.producers);
        const restriction_count = try std.math.mul(usize, layout.slots, layout.receipt_sites);
        try layout.validate(allocator);
        const initialization = try allocator.alloc(Initialization, layout.slots);
        errdefer allocator.free(initialization);
        const observations = try allocator.alloc(Observation, count);
        errdefer allocator.free(observations);
        const custody = try allocator.alloc(Custody, count);
        errdefer allocator.free(custody);
        const restrictions = try allocator.alloc(Restriction, restriction_count);
        errdefer allocator.free(restrictions);
        const unobserved = try allocator.alloc(bool, layout.slots);
        @memset(unobserved, false);
        @memset(restrictions, .{});
        @memset(custody, .{});
        @memset(initialization, .{});
        @memset(observations, .{});
        return .{ .layout = layout, .initialization = initialization, .observations = observations, .custody = custody, .restrictions = restrictions, .unobserved = unobserved };
    }

    /// Entry slots exist even when the first trip around a loop never
    /// initializes them. Empty lattice state is reserved for accumulation.
    pub fn initEntry(allocator: std.mem.Allocator, layout: Layout) !Slots {
        const state = try init(allocator, layout);
        @memset(state.initialization, .{ .deinitialized = true });
        return state;
    }

    /// Copies a state in the same already validated layout.
    pub fn clone(self: Slots, allocator: std.mem.Allocator) !Slots {
        const initialization = try allocator.dupe(Initialization, self.initialization);
        errdefer allocator.free(initialization);
        const observations = try allocator.dupe(Observation, self.observations);
        errdefer allocator.free(observations);
        const custody = try allocator.dupe(Custody, self.custody);
        errdefer allocator.free(custody);
        const restrictions = try allocator.dupe(Restriction, self.restrictions);
        errdefer allocator.free(restrictions);
        const unobserved = try allocator.dupe(bool, self.unobserved);
        return .{ .layout = self.layout, .initialization = initialization, .observations = observations, .custody = custody, .restrictions = restrictions, .unobserved = unobserved };
    }

    pub fn deinit(self: Slots, allocator: std.mem.Allocator) void {
        allocator.free(self.unobserved);
        allocator.free(self.restrictions);
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
        self.unobserved[destination] = false;
    }

    /// An initialized pointer without a tracked observation cannot
    /// inherit evidence from a different incoming path.
    pub fn writeUnobservedReference(self: Slots, destination: usize) void {
        @memset(self.observationRow(destination), .{});
        self.initialization[destination] = .{ .initialized = true };
        self.unobserved[destination] = true;
    }

    /// Write a copied reference into a preassigned storage row. A caller
    /// with multiple possible destinations applies a weak write to each.
    /// This does not copy or discharge owning obligations.
    pub fn writeReference(self: Slots, destination: usize, source: usize, definite: bool) void {
        if (destination == source) return;
        self.writeReferenceValue(destination, self.referenceValue(source), definite);
    }

    const ReferenceValue = struct {
        observations: []const Observation,
        initialization: Initialization,
        unobserved: bool,
    };

    fn referenceValue(self: Slots, source: usize) ReferenceValue {
        return .{
            .observations = self.observationRow(source),
            .initialization = self.initialization[source],
            .unobserved = self.unobserved[source],
        };
    }

    /// Call post-values use the same entry snapshot. Their destinations
    /// have already been resolved, including possible aliases of writes.
    fn applyReferencePostStates(self: Slots, allocator: std.mem.Allocator, writes: []const ReferenceWrite) !void {
        if (writes.len == 0) return;
        if (writes.len == 1) {
            const write = writes[0];
            self.writeReference(write.destination, write.source, write.definite);
            return;
        }
        const width = self.layout.producers;
        const captures = try allocator.alloc(ReferenceValue, writes.len);
        defer allocator.free(captures);
        const observations = try allocator.alloc(Observation, try std.math.mul(usize, writes.len, width));
        defer allocator.free(observations);
        for (writes, captures, 0..) |write, *capture, index| {
            capture.* = self.referenceValue(write.source);
            const row = observations[index * width ..][0..width];
            @memcpy(row, capture.observations);
            capture.observations = row;
        }
        // A definite write kills entry contents, but gives no order
        // between aliased post-values. Keep every possible final value.
        var initialized_targets = try std.DynamicBitSetUnmanaged.initEmpty(allocator, self.layout.slots);
        defer initialized_targets.deinit(allocator);
        for (writes, captures) |write, value| {
            if (!write.definite or initialized_targets.isSet(write.destination)) continue;
            self.writeReferenceValue(write.destination, value, true);
            initialized_targets.set(write.destination);
        }
        for (writes, captures) |write, value|
            self.writeReferenceValue(write.destination, value, false);
    }

    fn writeReferenceValue(self: Slots, destination: usize, value: ReferenceValue, definite: bool) void {
        const stored = self.observationRow(destination);
        if (definite) {
            @memcpy(stored, value.observations);
            self.initialization[destination] = value.initialization;
            self.unobserved[destination] = value.unobserved;
        } else {
            for (stored, value.observations) |*old, new| old.* = old.join(new);
            self.initialization[destination] = self.initialization[destination].weakWrite(value.initialization);
            self.unobserved[destination] = self.unobserved[destination] or value.unobserved;
        }
    }

    /// On the success edge of a checked selection, the element inherits
    /// the observation dependencies of the receiver. The lowered operation
    /// supplies a region with checked bounds and initialized contents.
    /// A successful selection supplies no custody of the selected value.
    pub fn borrowSelected(self: Slots, selection: Selection) bool {
        if (!self.canSelect(selection)) return false;
        self.writeReference(selection.destination, selection.receiver, true);
        return true;
    }

    fn canSelect(self: Slots, selection: Selection) bool {
        if (self.accessSuspended(selection.receiver, .read) or self.accessSuspended(selection.region, selection.mode)) return false;
        if (self.unobserved[selection.receiver] or !self.initialization[selection.receiver].definitelyInitialized()) return false;
        const source = self.observationRow(selection.receiver);
        var witnessed = false;
        for (source) |dependency| {
            if (dependency.current_ended or dependency.historical) return false;
            witnessed = witnessed or dependency.provesCurrent();
        }
        for (self.layout.opaque_rows) |domain| {
            if (selection.region != domain.current) continue;
            for (self.observationRow(domain.current)) |dependency| {
                if (dependency.current_ended or dependency.historical) return false;
            }
            break;
        }
        return witnessed;
    }

    /// A verified extraction removes one occupied element and transfers
    /// its custody. Aggregate may-facts cannot identify the removed owner.
    fn extractOpaqueElement(self: Slots, selection: Selection, domain: OpaqueRows, result_producer: usize) void {
        std.debug.assert(selection.region == domain.current and selection.mode == .write);
        std.debug.assert(selection.destination != domain.current and selection.destination != domain.historical);
        std.debug.assert(result_producer != domain.producer);
        self.age(result_producer);
        self.retireObservations(domain.producer, true);
        for (0..self.layout.producers) |producer| {
            if (self.owner(domain.current, producer).current) self.retireObservations(producer, false);
        }
        self.observeCurrent(selection.destination, result_producer);
        const result = self.observationRow(selection.destination);
        for (result, self.observationRow(domain.current)) |*retained, dependency|
            retained.* = retained.join(dependency);
        self.owner(selection.destination, result_producer).current = true;
    }

    pub fn owner(self: Slots, slot: usize, producer: usize) *Custody {
        std.debug.assert(slot < self.layout.slots and producer < self.layout.producers);
        return &self.custody[slot * self.layout.producers + producer];
    }

    pub const Access = enum { read, write };

    /// The caller has checked compatibility and supplies every overlapping
    /// slot. Shared loans suspend writes; exclusive loans suspend both.
    pub fn suspendAccess(self: Slots, slot: usize, receipt_site: usize, exclusive: bool) void {
        const loan = self.restriction(slot, receipt_site);
        loan.current_read = loan.current_read or exclusive;
        loan.current_write = true;
    }

    fn restriction(self: Slots, slot: usize, receipt_site: usize) *Restriction {
        std.debug.assert(slot < self.layout.slots and receipt_site < self.layout.receipt_sites);
        return &self.restrictions[slot * self.layout.receipt_sites + receipt_site];
    }

    pub fn accessSuspended(self: Slots, slot: usize, mode: Access) bool {
        if (self.layout.receipt_sites == 0) return false;
        for (self.layout.unknown_overlaps) |unknown| {
            if (unknown == slot) {
                for (0..self.layout.slots) |candidate| if (self.hasRestriction(candidate, mode)) return true;
                return false;
            }
            if (self.hasRestriction(unknown, mode)) return true;
        }
        if (self.hasRestriction(slot, mode)) return true;
        for (self.layout.overlaps) |pair| {
            if (pair[0] == slot and self.hasRestriction(pair[1], mode)) return true;
            if (pair[1] == slot and self.hasRestriction(pair[0], mode)) return true;
        }
        return false;
    }

    fn hasRestriction(self: Slots, slot: usize, mode: Access) bool {
        for (0..self.layout.receipt_sites) |site| {
            const loan = self.restriction(slot, site).*;
            if (loan.current_read or loan.historical_read) return true;
            if (mode == .write and (loan.current_write or loan.historical_write)) return true;
        }
        return false;
    }

    fn ageExecution(self: Slots, receipt_site: usize) void {
        std.debug.assert(receipt_site < self.layout.receipt_sites);
        for (0..self.layout.slots) |slot| {
            const loan = self.restriction(slot, receipt_site);
            loan.* = loan.age();
        }
    }

    /// Completion is authorized by the exact current receipt, independent
    /// of validity or initialization. Historical loans stay suspended.
    pub fn completeCurrent(self: Slots, receipt_site: usize) void {
        for (0..self.layout.slots) |slot| {
            const loan = self.restriction(slot, receipt_site);
            loan.current_read = false;
            loan.current_write = false;
        }
    }

    /// The caller must already have identified the exact current owner.
    /// Destroying it cannot discharge older instances from the same producer.
    pub fn dischargeCurrent(self: Slots, slot: usize, producer: usize) void {
        self.owner(slot, producer).current = false;
        self.retireObservations(producer, true);
    }

    fn retireObservations(self: Slots, producer: usize, definite: bool) void {
        for (0..self.layout.slots) |index| {
            const row = self.observationRow(index);
            const retired = row[producer].retireCurrent();
            row[producer] = if (definite) retired else row[producer].join(retired);
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

    /// A verified whole-domain traversal can destroy every instance in
    /// the current backing, including older elements. Its effects on
    /// observations of possible element owners are weak.
    fn destroyOpaqueContents(self: Slots, domain: OpaqueRows) void {
        for (0..self.layout.producers) |producer| {
            const custody = self.owner(domain.current, producer);
            if (custody.current or producer == domain.producer)
                self.retireObservations(producer, producer == domain.producer);
            custody.* = .{};
        }
        self.emptyCurrentOpaque(domain);
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
            self.layout.receipt_sites == incoming.layout.receipt_sites and
            self.layout.unknown_overlaps.ptr == incoming.layout.unknown_overlaps.ptr and
            self.layout.unknown_overlaps.len == incoming.layout.unknown_overlaps.len and
            self.layout.overlaps.ptr == incoming.layout.overlaps.ptr and
            self.layout.overlaps.len == incoming.layout.overlaps.len and
            self.layout.opaque_rows.ptr == incoming.layout.opaque_rows.ptr and
            self.layout.opaque_rows.len == incoming.layout.opaque_rows.len;
    }

    pub fn covers(self: Slots, incoming: Slots) bool {
        std.debug.assert(self.sameLayout(incoming));
        for (self.initialization, incoming.initialization) |a, b| if (!a.covers(b)) return false;
        for (self.observations, incoming.observations) |a, b| if (!a.covers(b)) return false;
        for (self.unobserved, incoming.unobserved) |a, b| if (!a and b) return false;
        for (self.custody, incoming.custody) |a, b| if (!a.covers(b)) return false;
        for (self.restrictions, incoming.restrictions) |a, b| if (!a.covers(b)) return false;
        return true;
    }

    pub fn include(self: Slots, incoming: Slots) void {
        std.debug.assert(self.sameLayout(incoming));
        for (self.initialization, incoming.initialization) |*a, b| a.* = a.join(b);
        for (self.observations, incoming.observations) |*a, b| a.* = a.join(b);
        for (self.unobserved, incoming.unobserved) |*a, b| a.* = a.* or b;
        for (self.custody, incoming.custody) |*a, b| a.* = a.join(b);
        for (self.restrictions, incoming.restrictions) |*a, b| a.* = a.include(b);
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
    try std.testing.expectEqual(@as(usize, 0), successor.restrictions.len);
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
    try std.testing.expect(!state.borrowSelected(.{ .destination = 1, .receiver = 0, .region = domain.current }));
    state.observeCurrent(0, 0);
    try std.testing.expect(state.borrowSelected(.{ .destination = 1, .receiver = 0, .region = domain.current }));
    try std.testing.expect(state.observation(1, 0).provesCurrent());
    try std.testing.expectEqual(Observation{}, state.observation(1, 1));
    try std.testing.expectEqual(Custody{}, state.owner(1, 1).*);

    state.retainOpaqueObservation(domain, false, 1, .{ .current_live = true });
    state.renewRelocatingOpaque(domain);
    try std.testing.expect(!state.borrowSelected(.{ .destination = 2, .receiver = 0, .region = domain.current }));
    state.observeCurrent(0, 0);
    try std.testing.expect(state.borrowSelected(.{ .destination = 2, .receiver = 0, .region = domain.current }));
    try std.testing.expect(!state.observation(1, 0).provesCurrent());
    try std.testing.expect(state.observation(2, 0).provesCurrent());
    try std.testing.expectEqual(Custody{ .current = true, .historical = true }, state.owner(domain.current, 1).*);
    try std.testing.expectEqual(Custody{}, state.owner(domain.historical, 1).*);
    try std.testing.expect(state.observation(domain.current, 1).provesCurrent());
}

/// A lowered graph of transfers with statically named destinations.
pub const Program = struct {
    pub const State = Slots;
    pub const Edge = struct {
        destination: usize,
        operations: []const Slots.Transfer,
    };

    allocator: std.mem.Allocator,
    edges_by_block: []const []const Edge,

    /// Validate operands before publishing any header. The solver owns
    /// the initial allocation through publication or validation failure.
    pub fn solve(self: Program, headers: []?State, entry: usize, initial: State) !void {
        self.validate(headers, entry, initial.layout) catch |err| {
            self.release(initial);
            return err;
        };
        try @import("finite_dataflow.zig").solve(Program, self.allocator, headers, entry, initial, self);
        for (headers, self.edges_by_block) |header, edges| {
            const state = header orelse continue;
            for (edges) |edge| {
                var last_check: ?usize = null;
                for (edge.operations, 0..) |op, index| {
                    if (op.requiredSelection() != null) last_check = index;
                }
                const last = last_check orelse continue;
                const scratch = try state.clone(self.allocator);
                defer self.release(scratch);
                for (edge.operations[0 .. last + 1]) |op| try op.apply(scratch, self.allocator);
            }
        }
    }

    fn validate(self: Program, headers: []const ?State, entry: usize, layout: Slots.Layout) !void {
        if (headers.len != self.edges_by_block.len or entry >= headers.len) return error.InvalidFiniteGraph;
        for (headers) |header| if (header != null) return error.InvalidFiniteGraph;
        for (self.edges_by_block) |edges| for (edges) |edge| {
            if (edge.destination >= headers.len) return error.InvalidFiniteGraph;
            for (edge.operations) |operation|
                if (!operation.valid(layout)) return error.InvalidFiniteOperand;
        };
    }

    pub fn release(self: Program, state: State) void {
        state.deinit(self.allocator);
    }

    pub fn successors(self: Program, block: usize) []const Edge {
        return self.edges_by_block[block];
    }

    pub fn target(_: Program, edge: Edge) usize {
        return edge.destination;
    }

    pub fn transfer(self: Program, _: usize, edge: Edge, state: State) !?State {
        const next = try state.clone(self.allocator);
        errdefer next.deinit(self.allocator);
        for (edge.operations) |operation| try operation.propagate(next, self.allocator);
        return next;
    }

    pub fn include(_: Program, left: *State, right: State) error{}!void {
        left.include(right);
    }

    pub fn covers(_: Program, left: State, right: State) bool {
        return left.covers(right);
    }
};

test "safety finite dataflow covers repeated owned element insertion and backing relocation" {
    const backing = 0;
    const element = 1;
    const receiver = 0;
    const saved = 1;
    const fresh = 2;
    const contents: Slots.OpaqueRows = .{ .producer = backing, .current = 3, .historical = 4 };
    const layout: Slots.Layout = .{ .slots = 5, .producers = 2, .opaque_rows = &.{contents} };
    const insert = [_]Slots.Transfer{
        .{ .produce = element },
        .{ .retain_owner = .{ .slot = contents.current, .producer = element } },
    };
    const relocate: []const Slots.Transfer = &.{
        .{ .relocate_backing = contents },
        .{ .observe = .{ .slot = receiver, .producer = backing } },
    };
    const domain: Program = .{
        .allocator = std.testing.allocator,
        .edges_by_block = &.{
            &.{.{ .destination = 2, .operations = &(insert ++ [_]Slots.Transfer{.{ .select = .{ .destination = saved, .receiver = receiver, .region = contents.current } }}) }},
            &.{.{ .destination = 2, .operations = &insert }},
            &.{
                .{ .destination = 2, .operations = relocate },
                .{ .destination = 1, .operations = relocate },
                .{ .destination = 3, .operations = &.{.{ .select = .{ .destination = fresh, .receiver = receiver, .region = contents.current } }} },
            },
            &.{},
        },
    };
    const initial = try Slots.initEntry(domain.allocator, layout);
    initial.observeCurrent(receiver, backing);
    var headers: [4]?Slots = @splat(null);
    defer for (headers) |header| if (header) |state| domain.release(state);
    try domain.solve(&headers, 0, initial);

    for (headers, 0..) |header, block| {
        for (domain.successors(block)) |edge| {
            const incoming = (try domain.transfer(block, edge, header.?)).?;
            defer domain.release(incoming);
            try std.testing.expect(headers[edge.destination].?.covers(incoming));
        }
    }
    const after = headers[3].?;
    try std.testing.expectEqual(Custody{ .current = true, .historical = true }, after.owner(contents.current, element).*);
    try std.testing.expect(after.observation(fresh, backing).provesCurrent());
    try std.testing.expect(!after.observation(saved, backing).provesCurrent());
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
    try (Slots.Transfer{ .copy_reference = .{ .destination = 2, .source = 0, .definite = true } }).apply(state, a);
    try (Slots.Transfer{ .copy_reference = .{ .destination = 2, .source = 1, .definite = false } }).apply(state, a);
    try std.testing.expect(state.observation(2, 0).provesCurrent());
    try std.testing.expect(state.observation(2, 1).provesCurrent());
    state.age(0);
    try std.testing.expect(!state.borrowSelected(.{ .destination = 0, .receiver = 2, .region = 2 }));
    state.writeReference(2, 1, true);
    try std.testing.expectEqual(Observation{}, state.observation(2, 0));
    try std.testing.expect(state.borrowSelected(.{ .destination = 0, .receiver = 2, .region = 2 }));
}

test "safety finite authority retains historical loans independently of validity" {
    const a = std.testing.allocator;
    const before = try Slots.init(a, .{ .slots = 2, .producers = 1, .receipt_sites = 1 });
    defer before.deinit(a);
    before.observeCurrent(0, 0);
    const state = try before.clone(a);
    defer state.deinit(a);
    try (Slots.Transfer{ .suspend_access = .{ .slot = 0, .receipt_site = 0, .exclusive = false } }).apply(state, a);
    try (Slots.Transfer{ .start_execution = 0 }).apply(state, a);
    state.suspendAccess(1, 0, true);
    try std.testing.expect(state.accessSuspended(1, .read));
    const selection: Slots.Selection = .{ .destination = 1, .receiver = 0, .region = 1 };
    try std.testing.expectError(error.UnprovedObservation, (Slots.Transfer{ .select = selection }).apply(state, a));
    try (Slots.Transfer{ .complete_execution = 0 }).apply(state, a);
    try std.testing.expect(!state.accessSuspended(1, .read));
    try (Slots.Transfer{ .select = selection }).apply(state, a);
    try std.testing.expect(!state.borrowSelected(.{ .destination = 1, .receiver = 0, .region = 0, .mode = .write }));
    try std.testing.expect(!state.accessSuspended(0, .read));
    try std.testing.expect(state.accessSuspended(0, .write));
    try std.testing.expect(state.observation(0, 0).provesCurrent());
    state.suspendAccess(1, 0, true);
    state.age(0);
    state.completeCurrent(0);
    try std.testing.expect(!state.accessSuspended(1, .read));
    try std.testing.expect(state.accessSuspended(0, .write));
    try std.testing.expect(!before.covers(state));
    before.include(state);
    try std.testing.expect(before.covers(state));
}

test "safety finite joins keep initialized references without observations" {
    const a = std.testing.allocator;
    const tracked = try Slots.init(a, .{ .slots = 2, .producers = 1 });
    defer tracked.deinit(a);
    const unknown = try Slots.init(a, tracked.layout);
    defer unknown.deinit(a);
    tracked.observeCurrent(0, 0);
    unknown.writeUnobservedReference(0);
    try std.testing.expect(!tracked.covers(unknown));
    tracked.include(unknown);
    try std.testing.expect(tracked.covers(unknown));
    try std.testing.expect(tracked.initialization[0].definitelyInitialized());
    try std.testing.expect(!tracked.borrowSelected(.{ .destination = 1, .receiver = 0, .region = 0 }));
    tracked.observeCurrent(0, 0);
    try std.testing.expect(tracked.borrowSelected(.{ .destination = 1, .receiver = 0, .region = 0 }));
}

test "safety finite solver propagates through a long loop-carried reference chain" {
    const a = std.testing.allocator;
    const length = 32;
    const initial = try Slots.initEntry(a, .{ .slots = length, .producers = 1 });
    initial.observeCurrent(0, 0);
    var writes: [length - 1]Slots.Transfer = undefined;
    for (&writes, 0..) |*write, index| {
        const destination = length - 1 - index;
        write.* = .{ .copy_reference = .{ .destination = destination, .source = destination - 1, .definite = true } };
    }
    const edges = [_]Program.Edge{.{ .destination = 0, .operations = &writes }};
    const program: Program = .{ .allocator = a, .edges_by_block = &.{&edges} };
    var headers: [1]?Slots = @splat(null);
    defer if (headers[0]) |header| program.release(header);
    try program.solve(&headers, 0, initial);
    const header = headers[0].?;
    try std.testing.expect(header.observation(length - 1, 0).provesCurrent());
    try std.testing.expect(!header.initialization[length - 1].definitelyInitialized());
    const incoming = (try program.transfer(0, edges[0], header)).?;
    defer program.release(incoming);
    try std.testing.expect(header.covers(incoming));
}

test "safety finite summary reference outputs use the same entry snapshot" {
    const a = std.testing.allocator;
    const state = try Slots.initEntry(a, .{ .slots = 2, .producers = 2 });
    defer state.deinit(a);
    state.observeCurrent(0, 0);
    state.observeCurrent(1, 1);
    try (Slots.Transfer{ .reference_post_states = &.{
        .{ .destination = 0, .source = 1, .definite = true },
        .{ .destination = 1, .source = 0, .definite = true },
    } }).apply(state, a);
    try std.testing.expect(state.observation(0, 1).provesCurrent());
    try std.testing.expect(state.observation(1, 0).provesCurrent());
    try std.testing.expectEqual(Observation{}, state.observation(1, 1));
}

test "safety finite whole-container cleanup discharges only the current backing" {
    const a = std.testing.allocator;
    const domain: Slots.OpaqueRows = .{ .producer = 0, .current = 2, .historical = 3 };
    const state = try Slots.initEntry(a, .{ .slots = 4, .producers = 2, .opaque_rows = &.{domain} });
    defer state.deinit(a);
    state.owner(domain.historical, 1).historical = true;
    state.owner(domain.current, 1).* = .{ .current = true, .historical = true };
    state.retainOpaqueObservation(domain, false, 1, .{ .current_live = true });
    state.observeCurrent(0, 0);
    state.observeCurrent(1, 1);
    try (Slots.Transfer{ .destroy_opaque_contents = domain }).apply(state, a);
    try std.testing.expectEqual(Custody{}, state.owner(domain.current, 1).*);
    try std.testing.expect(state.owner(domain.historical, 1).historical);
    try std.testing.expectEqual(Observation{}, state.observation(domain.current, 1));
    try std.testing.expectEqual(Observation{ .current_ended = true }, state.observation(0, 0));
    try std.testing.expectEqual(Observation{ .current_live = true, .current_ended = true }, state.observation(1, 1));
}

test "safety finite extraction keeps other historical element owners" {
    const a = std.testing.allocator;
    const domain: Slots.OpaqueRows = .{ .producer = 0, .current = 2, .historical = 3 };
    const state = try Slots.initEntry(a, .{ .slots = 4, .producers = 4, .opaque_rows = &.{domain} });
    defer state.deinit(a);
    state.observeCurrent(0, 0);
    state.owner(domain.current, 1).historical = true;
    state.retainOpaqueObservation(domain, false, 3, .{ .current_live = true });
    try (Slots.Transfer{ .extract_opaque_element = .{
        .selection = .{ .destination = 1, .receiver = 0, .region = domain.current, .mode = .write },
        .domain = domain,
        .result_producer = 2,
    } }).apply(state, a);
    try std.testing.expect(state.owner(domain.current, 1).historical);
    try std.testing.expect(state.owner(1, 2).current);
    try std.testing.expect(state.observation(1, 2).provesCurrent());
    try std.testing.expect(state.observation(1, 3).provesCurrent());
    try std.testing.expect(!state.observation(0, 0).provesCurrent());
}

test "safety finite program rejects operands outside the frozen layout" {
    const a = std.testing.allocator;
    const state = try Slots.initEntry(a, .{ .slots = 1, .producers = 1 });
    const program: Program = .{
        .allocator = a,
        .edges_by_block = &.{&.{.{ .destination = 0, .operations = &.{.{ .produce = 1 }} }}},
    };
    var headers: [1]?Slots = @splat(null);
    try std.testing.expectError(error.InvalidFiniteOperand, program.solve(&headers, 0, state));
    try std.testing.expectEqual(null, headers[0]);
}

test "safety finite access restrictions follow symmetric nontransitive storage overlap" {
    const a = std.testing.allocator;
    const state = try Slots.init(a, .{
        .slots = 3,
        .producers = 0,
        .receipt_sites = 1,
        .overlaps = &.{ .{ 0, 1 }, .{ 0, 2 } },
    });
    defer state.deinit(a);
    state.suspendAccess(1, 0, true);
    try std.testing.expect(state.accessSuspended(0, .read));
    try std.testing.expect(!state.accessSuspended(2, .write));
    state.suspendAccess(0, 0, false);
    try std.testing.expect(state.accessSuspended(2, .write));
    try std.testing.expect(!state.accessSuspended(2, .read));
}

test "safety finite overlap does not infer disjointness from symbolic identity" {
    const a = std.testing.allocator;
    const graph: @import("../global/graph.zig").GlobalSemanticGraph = .{};
    const identities: []const @import("facts.zig").StorageIdentity = &.{
        .{ .place = .{ .root = @enumFromInt(0) } },
        .{ .place = .{ .root = @enumFromInt(1) } },
        .{ .symbolic = @enumFromInt(0) },
        .{ .symbolic = @enumFromInt(1) },
    };
    const overlaps = try storageOverlaps(a, &graph, identities);
    defer overlaps.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), overlaps.pairs.len);
    try std.testing.expectEqualSlices(usize, &.{ 2, 3 }, overlaps.unknown);
    const state = try Slots.init(a, .{
        .slots = identities.len,
        .producers = 0,
        .receipt_sites = 1,
        .overlaps = overlaps.pairs,
        .unknown_overlaps = overlaps.unknown,
    });
    defer state.deinit(a);
    state.suspendAccess(0, 0, true);
    try std.testing.expect(state.accessSuspended(2, .read));
    try std.testing.expect(!state.accessSuspended(1, .write));
    state.suspendAccess(3, 0, false);
    try std.testing.expect(state.accessSuspended(1, .write));
    try std.testing.expect(!state.accessSuspended(1, .read));
}

test "safety finite solver checks selection after a backedge invalidates its receiver" {
    const a = std.testing.allocator;
    const initial = try Slots.initEntry(a, .{ .slots = 2, .producers = 1 });
    initial.observeCurrent(0, 0);
    const program: Program = .{ .allocator = a, .edges_by_block = &.{
        &.{.{ .destination = 1, .operations = &.{.{ .select = .{ .destination = 1, .receiver = 0, .region = 0 } }} }},
        &.{.{ .destination = 0, .operations = &.{.{ .produce = 0 }} }},
    } };
    var headers: [2]?Slots = @splat(null);
    defer for (headers) |header| if (header) |state| program.release(state);
    try std.testing.expectError(error.UnprovedObservation, program.solve(&headers, 0, initial));
    try std.testing.expect(headers[1].?.observation(1, 0).historical);
}

test "safety finite post-values preserve alternatives for an aliased destination" {
    const a = std.testing.allocator;
    const state = try Slots.initEntry(a, .{ .slots = 3, .producers = 3 });
    defer state.deinit(a);
    for (0..3) |slot| state.observeCurrent(slot, slot);
    try state.applyReferencePostStates(a, &.{
        .{ .destination = 0, .source = 1, .definite = false },
        .{ .destination = 0, .source = 2, .definite = true },
    });
    try std.testing.expectEqual(Observation{}, state.observation(0, 0));
    try std.testing.expect(state.observation(0, 1).provesCurrent());
    try std.testing.expect(state.observation(0, 2).provesCurrent());
}

test "safety finite writes to possible destinations retain each entry alternative" {
    const a = std.testing.allocator;
    const state = try Slots.initEntry(a, .{ .slots = 3, .producers = 3 });
    defer state.deinit(a);
    for (0..3) |slot| state.observeCurrent(slot, slot);
    const op: Slots.Transfer = .{ .copy_reference_to_candidates = .{ .source = 0, .destinations = &.{ 1, 0, 2 } } };
    try std.testing.expect(op.valid(state.layout));
    try op.apply(state, a);
    for (0..3) |slot| {
        try std.testing.expect(state.observation(slot, slot).provesCurrent());
        try std.testing.expect(state.observation(slot, 0).provesCurrent());
    }
    try std.testing.expectEqual(Observation{}, state.observation(0, 1));
}

test "safety finite selection checks hidden obligations independently of the receiver" {
    const a = std.testing.allocator;
    const domain: Slots.OpaqueRows = .{ .producer = 0, .current = 2, .historical = 3 };
    const state = try Slots.initEntry(a, .{ .slots = 4, .producers = 2, .opaque_rows = &.{domain} });
    defer state.deinit(a);
    state.observeCurrent(0, 0);
    state.retainOpaqueObservation(domain, false, 1, .{ .current_live = true });
    const select: Slots.Selection = .{ .destination = 1, .receiver = 0, .region = domain.current };
    try std.testing.expect(state.borrowSelected(select));
    state.age(1);
    try std.testing.expect(state.observation(0, 0).provesCurrent());
    try std.testing.expect(!state.borrowSelected(select));
}

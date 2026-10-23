const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const v = @import("../5_codegen/bytecode/value.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const acquired = @import("acquisitions.zig");
const numeric = @import("../5_codegen/bytecode/numeric_layout.zig");
const partial = @import("partial_storage.zig");
const cleanup_layout = @import("../5_codegen/cleanup_layout.zig");

const Frame = struct {
    values: []?b.Value,
    partial_storage: std.AutoHashMapUnmanaged(b.Slot, partial.Storage) = .empty,
    cleanup: []const b.Cleanup = &.{},
    cleanup_flags: []bool = &.{},
    bytes: []const u8 = &.{},
    alive: bool = true,
    reusable_next: ?v.FrameId = null,
    duration: enum { call, session, static, acquired } = .call,
};

// Slots contain either a complete value (including Void) or no value. This is
// concrete occupancy, not the checker's abstract maybe-initialized state, and
// does not grant access to uninitialized fields or owner-controlled raw storage.
pub const Slots = struct {
    storage: *Storage,
    context: v.ContextId,
    frame: v.FrameId,

    pub fn get(self: Slots, index: b.Slot) !b.Value {
        const values = try self.cells();
        if (index >= values.len) return error.ExecutionInvalidReference;
        if (values[index]) |value| return value;
        if (self.storage.frames.items[@intFromEnum(self.frame)].partial_storage.getPtr(index)) |record| {
            return self.storage.readPartial(record, &.{});
        }
        return error.ExecutionUninitializedStorage;
    }

    // Verified instructions define complete slot values. Reference writes use
    // Storage.store instead, which preserves reserved partial storage and
    // checks projections before publishing a value.
    pub fn put(self: Slots, index: b.Slot, value: b.Value) !void {
        const values = try self.cells();
        if (index >= values.len) return error.ExecutionInvalidReference;
        values[index] = value;
        _ = self.storage.frames.items[@intFromEnum(self.frame)].partial_storage.remove(index);
    }

    fn cells(self: Slots) ![]?b.Value {
        if (self.context != self.storage.context) return error.ExecutionForeignReference;
        const values = try self.storage.frameValues(self.frame);
        // Acquired buffers retain occupancy, not authoritative numeric values.
        // Use Storage.read/store so accesses also observe physical bytes.
        if (self.storage.frames.items[@intFromEnum(self.frame)].duration == .acquired) return error.ExecutionInvalidReference;
        return values;
    }
};

var next_context = std.atomic.Value(u64).init(0);

// Captured executor access, never a language value or a safe-reference factory.
pub const WriteDestination = struct {
    reference: v.Reference,
    // Index in this target frame's immutable compiler-selected layout. This
    // belongs to the referent, never to the local slot holding a reference.
    cleanup_entry: ?CleanupSelection,
    require_cleanup: bool = true,
};

// Executor capability, never a language address or a proof of a legal borrow.
pub const AcquiredReservation = struct { context: v.ContextId, frame: v.FrameId };

const CleanupSelection = struct { offset: usize, layout: *const cleanup_layout.Layout };

// Context-local storage. Its allocator is an execution arena; references can neither
// name another execution nor expose a native address. Dead frame IDs stay dead.
pub const Storage = struct {
    context: v.ContextId,
    allocator: std.mem.Allocator,
    limit: usize,
    cells: usize = 0,
    frames: std.ArrayList(Frame) = .empty,
    // Exact-size bins hold dead call buffers, never reusable frame identities.
    // A bin is reserved on entry so leaving a frame cannot allocate or fail.
    reusable_frames: std.AutoHashMapUnmanaged(FrameSize, ?v.FrameId) = .empty,
    acquisitions: acquired.Regions = .{},
    acquired_views: std.AutoHashMapUnmanaged(v.FrameId, AcquiredView) = .empty,
    // One entry per reference-bearing batch, never per leaf or element. Byte
    // writes into ordinary numeric sessions do not scan unrelated view frames.
    reference_acquired_frames: std.ArrayList(v.FrameId) = .empty,
    // Reuse exact immutable numeric views, never infer typed owner identity
    // from a physical address. Permissions remain on each returned reference.
    acquired_frames: std.HashMapUnmanaged(AcquiredView, v.FrameId, AcquiredViewContext, std.hash_map.default_max_load_percentage) = .empty,

    const FrameSize = struct { values: usize, flags: usize };
    const FrameBuffers = struct { values: []?b.Value, flags: []bool };

    const AcquiredView = struct {
        handle: acquired.Handle,
        offset: usize,
        logical_index: ?u64 = null,
        receipt_origin: ?usize = null,
        layout: *const numeric.Layout,
        endian: std.builtin.Endian,
        count: usize = 1,
        // One immutable occupancy template for every slot in a reservation.
        // This is metadata, not part of a raw byte view's lookup identity.
        value_layout: ?*const partial.Layout = null,
    };

    const AcquiredViewContext = struct {
        pub fn hash(_: @This(), view: AcquiredView) u64 {
            // A cheap extent hash narrows candidates; equality checks the full
            // immutable shape without allocating or using descriptor addresses.
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHash(&hasher, view.handle);
            std.hash.autoHash(&hasher, view.offset);
            std.hash.autoHash(&hasher, view.logical_index);
            std.hash.autoHash(&hasher, view.receipt_origin);
            std.hash.autoHash(&hasher, view.endian);
            std.hash.autoHash(&hasher, view.layout.size);
            std.hash.autoHash(&hasher, view.layout.alignment);
            std.hash.autoHash(&hasher, view.count);
            return hasher.final();
        }

        pub fn eql(_: @This(), left: AcquiredView, right: AcquiredView) bool {
            return std.meta.eql(left.handle, right.handle) and left.offset == right.offset and left.count == right.count and
                left.logical_index == right.logical_index and left.receipt_origin == right.receipt_origin and left.endian == right.endian and
                numeric.equal(left.layout, right.layout);
        }
    };

    /// Execution-side establishment only. Checked bytecode must separately
    /// provide the language authorization; a handle or integer is not that proof.
    /// Layout metadata must outlive this storage, like other compiled layouts.
    pub fn acquiredReference(self: *Storage, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, endian: std.builtin.Endian, permission: p.PointerMutability, logical_index: ?u64) !v.Reference {
        return self.acquiredReferenceBatch(handle, offset, layout, endian, permission, logical_index, 1);
    }

    // A checked receipt may grant repeated numeric storage. This is a byte
    // view only: repeated occupancy and cleanup still require explicit reservation.
    pub fn acquiredReferenceBatch(self: *Storage, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, endian: std.builtin.Endian, permission: p.PointerMutability, logical_index: ?u64, count: usize) !v.Reference {
        if (layout.alignment == 0 or !std.math.isPowerOfTwo(layout.alignment)) return error.ExecutionInvalidReference;
        if (count == 0 or count > std.math.maxInt(b.Slot)) return error.ExecutionIndexOutOfBounds;
        if (logical_index) |index| _ = std.math.add(u64, index, count - 1) catch return error.ExecutionIndexOutOfBounds;
        const extent = std.math.mul(usize, count, layout.size) catch return error.ExecutionIndexOutOfBounds;
        _ = try self.acquisitions.range(self, handle, offset, extent, layout.alignment);
        const view: AcquiredView = .{ .handle = handle, .offset = offset, .layout = layout, .endian = endian, .logical_index = logical_index, .count = count };
        if (self.acquired_frames.get(view)) |frame| {
            if (self.frames.items[@intFromEnum(frame)].cleanup.len != 0) return error.ExecutionMissingCleanup;
            return .{ .context = self.context, .frame = frame, .root = 0, .path = &.{}, .mutability = permission };
        }
        const frame = try self.publishAcquiredFrame(view, &.{});
        return .{ .context = self.context, .frame = frame, .root = 0, .path = &.{}, .mutability = permission };
    }

    /// Reserve executor cleanup state before publishing any reference to this
    /// exact logical slot. This neither initializes bytes nor activates cleanup.
    /// The caller supplies a checked layout which must outlive the reservation.
    /// A previously published byte view cannot be upgraded into an owning slot.
    pub fn reserveAcquiredCleanup(self: *Storage, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, endian: std.builtin.Endian, logical_index: u64, value_layout: partial.Layout, cleanup: *const cleanup_layout.Layout) !AcquiredReservation {
        return self.reserveAcquiredCleanupBatch(handle, offset, layout, endian, logical_index, value_layout, cleanup, 1);
    }

    /// A batch shares its descriptors and owns contiguous value/flag buffers.
    /// Slots are independent owners, not children of an initialized array value.
    pub fn reserveAcquiredCleanupBatch(self: *Storage, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, endian: std.builtin.Endian, logical_index: u64, value_layout: partial.Layout, cleanup: *const cleanup_layout.Layout, count: usize) !AcquiredReservation {
        return self.reserveAcquiredBatch(handle, offset, layout, endian, logical_index, value_layout, cleanup, count, null);
    }

    // Region allocators can issue distinct receipts from one physical region.
    // Their private origins delimit logical index namespaces, not owner handles.
    pub fn reserveAcquiredReceipt(self: *Storage, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, endian: std.builtin.Endian, value_layout: partial.Layout, cleanup: ?*const cleanup_layout.Layout, count: usize, receipt_origin: usize) !AcquiredReservation {
        if (receipt_origin > offset) return error.ExecutionInvalidReference;
        _ = try self.acquisitions.range(self, handle, receipt_origin, offset - receipt_origin, 1);
        return self.reserveAcquiredBatch(handle, offset, layout, endian, 0, value_layout, cleanup, count, receipt_origin);
    }

    const empty_cleanup: cleanup_layout.Layout = .{};

    fn reserveAcquiredBatch(self: *Storage, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, endian: std.builtin.Endian, logical_index: u64, value_layout: partial.Layout, cleanup: ?*const cleanup_layout.Layout, count: usize, receipt_origin: ?usize) !AcquiredReservation {
        if (count > std.math.maxInt(b.Slot)) return error.ExecutionMemoryLimit;
        _ = std.math.add(u64, logical_index, count -| 1) catch return error.ExecutionMemoryLimit;
        const extent = std.math.mul(usize, count, layout.size) catch return error.ExecutionMemoryLimit;
        _ = try self.acquisitions.range(self, handle, offset, extent, layout.alignment);
        if (!@import("../5_codegen/bytecode/storage_layout.zig").matchesNumeric(value_layout, layout)) return error.ExecutionInvalidReference;
        _ = try partial.Storage.validateLayout(value_layout);
        var view: AcquiredView = .{ .handle = handle, .offset = offset, .layout = layout, .endian = endian, .logical_index = logical_index, .count = count, .receipt_origin = receipt_origin };
        if (self.acquired_frames.contains(view)) return error.ExecutionInitializedStorage;
        try self.requireUnreservedAcquiredSlots(view);
        try self.charge(1);
        errdefer self.cells -= 1;
        const Description = struct { owners: [1]b.Cleanup, values: partial.Layout };
        const description = try self.allocator.create(Description);
        errdefer self.allocator.destroy(description);
        description.* = .{ .owners = .{.{ .root = 0, .offset = 0, .layout = cleanup orelse &empty_cleanup }}, .values = value_layout };
        view.value_layout = &description.values;
        const frame = try self.publishAcquiredFrame(view, if (cleanup != null) &description.owners else &.{});
        return .{ .context = self.context, .frame = frame };
    }

    // Reservation is the publication boundary for ownership. Distinct batch
    // shapes must not issue independent cleanup state for intersecting slots.
    // This check rejects aliases; it never recovers a capability from an address.
    fn requireUnreservedAcquiredSlots(self: *const Storage, proposed: AcquiredView) !void {
        var entries = self.acquired_views.valueIterator();
        while (entries.next()) |existing| {
            if (!std.meta.eql(existing.handle, proposed.handle)) continue;
            if (existing.logical_index) |previous| {
                if (existing.receipt_origin == proposed.receipt_origin and overlappingRanges(previous, existing.count, proposed.logical_index.?, proposed.count)) return error.ExecutionInitializedStorage;
            }
            const previous_bytes = std.math.mul(usize, existing.count, existing.layout.size) catch return error.ExecutionInvalidReference;
            const proposed_bytes = std.math.mul(usize, proposed.count, proposed.layout.size) catch return error.ExecutionInvalidReference;
            if (overlappingRanges(existing.offset, previous_bytes, proposed.offset, proposed_bytes)) return error.ExecutionInitializedStorage;
        }
    }

    // Compare by subtraction so a valid last slot at maxInt needs no exclusive
    // end value beyond the representable range. Empty ranges never intersect.
    fn overlappingRanges(left: u64, left_count: u64, right: u64, right_count: u64) bool {
        if (left_count == 0 or right_count == 0) return false;
        return if (left <= right) right - left < left_count else left - right < right_count;
    }

    /// Project a previously reserved identity without allocating. The lowering
    /// must transport this capability; an address lookup cannot recover it.
    pub fn borrowAcquiredReservation(self: *Storage, reservation: AcquiredReservation, permission: p.PointerMutability) !v.Reference {
        return self.borrowAcquiredElement(reservation, 0, permission);
    }

    pub fn borrowAcquiredElement(self: *Storage, reservation: AcquiredReservation, index: usize, permission: p.PointerMutability) !v.Reference {
        const reference: v.Reference = .{ .context = reservation.context, .frame = reservation.frame, .root = std.math.cast(b.Slot, index) orelse return error.ExecutionIndexOutOfBounds, .path = &.{}, .mutability = permission };
        try self.validateContext(reference);
        const view = try self.acquiredView(reference) orelse return error.ExecutionMissingCleanup;
        if (view.value_layout == null) return error.ExecutionMissingCleanup;
        return reference;
    }

    pub fn borrowPreparedAcquired(self: *Storage, state: @import("../5_codegen/bytecode/acquired_receipt.zig").State, index: u64, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, permission: p.PointerMutability) !v.Reference {
        if (state.token == 0 or state.element_size != layout.size or index >= state.count) return error.ExecutionMissingCleanup;
        const frame = std.math.cast(u32, state.token - 1) orelse return error.ExecutionInvalidReference;
        const reference = try self.borrowAcquiredElement(.{ .context = self.context, .frame = @enumFromInt(frame) }, @intCast(index), permission);
        const original = self.acquired_views.get(reference.frame) orelse return error.ExecutionMissingCleanup;
        const selected = (try self.acquiredView(reference)).?;
        if (original.count != state.count or !std.meta.eql(selected.handle, handle) or selected.offset != offset or !numeric.equal(selected.layout, layout)) return error.ExecutionInvalidReference;
        return reference;
    }

    fn publishAcquiredFrame(self: *Storage, view: AcquiredView, cleanup: []const b.Cleanup) !v.FrameId {
        // Reserve both indexes before publishing the frame. Metadata remains
        // arena-owned, and every lookup checks acquisition liveness first.
        try self.acquired_views.ensureUnusedCapacity(self.allocator, 1);
        try self.acquired_frames.ensureUnusedCapacity(self.allocator, 1);
        if (view.layout.has_references) {
            if (view.value_layout == null) return error.ExecutionMissingCleanup;
            try self.reference_acquired_frames.ensureUnusedCapacity(self.allocator, 1);
        }
        const values = if (view.value_layout) |logical| std.math.mul(usize, view.count, logical.nodes[0].span) catch return error.ExecutionMemoryLimit else 1;
        const flags = std.math.mul(usize, view.count, b.cleanupFlagCount(cleanup) catch return error.ExecutionInvalidReference) catch return error.ExecutionMemoryLimit;
        const frame = try self.enterBuffers(values, cleanup, flags);
        self.acquired_views.putAssumeCapacityNoClobber(frame, view);
        self.acquired_frames.putAssumeCapacityNoClobber(view, frame);
        self.frames.items[@intFromEnum(frame)].duration = .acquired;
        if (view.layout.has_references) self.reference_acquired_frames.appendAssumeCapacity(frame);
        return frame;
    }

    fn acquiredView(self: *Storage, reference: v.Reference) !?AcquiredView {
        _ = try self.frameValues(reference.frame);
        if (self.frames.items[@intFromEnum(reference.frame)].duration != .acquired) return null;
        var view = self.acquired_views.get(reference.frame) orelse return error.ExecutionInvalidReference;
        if (reference.root >= view.count) return error.ExecutionIndexOutOfBounds;
        view.offset = try std.math.add(usize, view.offset, try std.math.mul(usize, reference.root, view.layout.size));
        if (view.logical_index) |index| view.logical_index = try std.math.add(u64, index, reference.root);
        for (reference.path) |projection| {
            switch (projection) {
                .field => |index| {
                    if (view.layout.shape != .fields or index >= view.layout.shape.fields.len) return error.ExecutionInvalidReference;
                    const field = view.layout.shape.fields[index];
                    view.offset = try std.math.add(usize, view.offset, field.offset);
                    view.layout = field.layout;
                },
                .element => |index| {
                    if (view.layout.shape != .array) return error.ExecutionInvalidReference;
                    const array = view.layout.shape.array;
                    if (index >= array.length) return error.ExecutionIndexOutOfBounds;
                    view.offset = try std.math.add(usize, view.offset, try std.math.mul(usize, index, array.stride));
                    view.layout = array.element;
                },
                .variant => return error.ExecutionInvalidReference,
            }
        }
        _ = try self.acquisitions.range(self, view.handle, view.offset, view.layout.size, view.layout.alignment);
        return view;
    }

    fn acquiredValues(self: *Storage, reference: v.Reference) !?partial.Storage {
        const view = self.acquired_views.get(reference.frame) orelse return null;
        const logical = view.value_layout orelse return null;
        if (reference.root >= view.count) return error.ExecutionIndexOutOfBounds;
        const values = try self.frameValues(reference.frame);
        const span = logical.nodes[0].span;
        const start = try std.math.mul(usize, reference.root, span);
        if (start > values.len or span > values.len - start) return error.ExecutionInvalidReference;
        return .{ .layout = logical.*, .values = values[start..][0..span] };
    }

    // Physical writes cannot manufacture or preserve reference evidence. One
    // compact reservation describes all repeated elements; inspect only the
    // intersecting elements and clear touched reference leaves without allocating.
    pub fn invalidateAcquiredReferences(self: *Storage, handle: acquired.Handle, offset: usize, length: usize) !void {
        if (length == 0) return;
        for (self.reference_acquired_frames.items) |frame| {
            const view = self.acquired_views.get(frame) orelse return error.ExecutionMissingCleanup;
            if (!std.meta.eql(view.handle, handle)) continue;
            const logical = view.value_layout orelse return error.ExecutionMissingCleanup;
            const extent = try std.math.mul(usize, view.count, view.layout.size);
            if (!overlappingRanges(offset, length, view.offset, extent)) continue;
            const first = (offset -| view.offset) / view.layout.size;
            const last = @min(view.count, (offset + length - 1 -| view.offset) / view.layout.size + 1);
            const values = try self.frameValues(frame);
            for (first..last) |index| {
                const start = try std.math.mul(usize, index, logical.nodes[0].span);
                var record: partial.Storage = .{ .layout = logical.*, .values = values[start..][0..logical.nodes[0].span] };
                var path: [64]v.Projection = undefined;
                try invalidateReferenceBytes(&record, view.layout, view.offset + index * view.layout.size, offset, length, &path, 0);
            }
        }
    }

    fn invalidateReferenceBytes(record: *partial.Storage, layout: *const numeric.Layout, base: usize, offset: usize, length: usize, path: *[64]v.Projection, depth: usize) anyerror!void {
        if (!layout.has_references or !overlappingRanges(base, layout.size, offset, length)) return;
        if (depth > path.len) return error.ExecutionValueDepthLimit;
        switch (layout.shape) {
            .reference, .virtual_reference => try record.clear(path[0..depth]),
            .fields => |fields| {
                if (depth == path.len) return error.ExecutionValueDepthLimit;
                for (fields, 0..) |field, index| {
                    path[depth] = .{ .field = @intCast(index) };
                    try invalidateReferenceBytes(record, field.layout, base + field.offset, offset, length, path, depth + 1);
                }
            },
            .array => |array| {
                if (depth == path.len or array.stride == 0) return error.ExecutionInvalidReference;
                const first = (offset -| base) / array.stride;
                const last = @min(array.length, (offset + length - 1 -| base) / array.stride + 1);
                for (first..last) |index| {
                    path[depth] = .{ .element = index };
                    try invalidateReferenceBytes(record, array.element, base + index * array.stride, offset, length, path, depth + 1);
                }
            },
            else => {},
        }
    }

    pub fn acquiredStoredValue(self: *Storage, reference: v.Reference) !b.Value {
        _ = try self.acquiredView(reference);
        const logical = try self.acquiredValues(reference) orelse return error.ExecutionMissingCleanup;
        return logical.storedValue(reference.path);
    }

    pub fn init(allocator: std.mem.Allocator, limit: usize) !Storage {
        var next = next_context.load(.monotonic);
        while (true) {
            // Exhaustion must fail rather than let an old handle name new storage.
            if (next == std.math.maxInt(u64)) return error.ExecutionContextLimit;
            next = next_context.cmpxchgWeak(next, next + 1, .monotonic, .monotonic) orelse
                return .{ .context = @enumFromInt(next), .allocator = allocator, .limit = limit };
        }
    }

    pub fn charge(self: *Storage, count: usize) !void {
        if (count > self.limit -| self.cells) return error.ExecutionMemoryLimit;
        self.cells += count;
    }
    /// Reserve concrete storage without initializing its values. This
    /// does not grant a loan or activate any cleanup obligation.
    pub fn prepareStorage(self: *Storage, frame: v.FrameId, root: b.Slot, layout: partial.Layout) !void {
        const slots_ = try self.slots(frame);
        const values = try slots_.cells();
        if (root >= values.len) return error.ExecutionInvalidReference;
        if (values[root] != null or self.frames.items[@intFromEnum(frame)].partial_storage.contains(root)) return error.ExecutionInitializedStorage;
        const charge_count = if (layout.nodes.len == 0) 0 else layout.nodes[0].span;
        try self.charge(charge_count);
        errdefer self.cells -= charge_count;
        const record = try partial.Storage.init(self.allocator, layout);
        errdefer self.allocator.free(record.values);
        try self.frames.items[@intFromEnum(frame)].partial_storage.put(self.allocator, root, record);
    }
    /// Re-enter lexical storage after its previous cleanup has finished.
    /// Existing leaf cells are reused; no old initialized value survives entry.
    pub fn resetStorage(self: *Storage, frame: v.FrameId, root: b.Slot, layout: partial.Layout) !usize {
        const slots_ = try self.slots(frame);
        const values = try slots_.cells();
        if (root >= values.len) return error.ExecutionInvalidReference;
        if (try self.cleanupRootActive(frame, root)) return error.ExecutionPendingCleanup;
        if (self.frames.items[@intFromEnum(frame)].partial_storage.getPtr(root)) |record| {
            if (record.layout.nodes.len != layout.nodes.len) return error.ExecutionInvalidReference;
            for (record.layout.nodes, layout.nodes) |old, new| if (!std.meta.eql(old, new)) return error.ExecutionInvalidReference;
            @memset(record.values, null);
            values[root] = null;
        } else {
            values[root] = null;
            try self.prepareStorage(frame, root, layout);
        }
        return layout.nodes[0].span;
    }
    pub fn allocate(self: *Storage, count: usize) ![]b.Value {
        try self.charge(count);
        errdefer self.cells -= count;
        return self.allocator.alloc(b.Value, count);
    }
    pub fn virtualize(self: *Storage, receiver: v.Reference, program: *const b.Program, table: *const b.VirtualTable) !b.Value {
        _ = try self.read(receiver);
        const descriptor_cells = comptime std.math.divCeil(usize, @sizeOf(v.Virtual), @sizeOf(b.Value)) catch unreachable;
        const charge_count = std.math.add(usize, descriptor_cells, receiver.path.len) catch return error.ExecutionMemoryLimit;
        try self.charge(charge_count);
        errdefer self.cells -= charge_count;
        const descriptor = try self.allocator.create(v.Virtual);
        errdefer self.allocator.destroy(descriptor);
        var retained = receiver;
        retained.path = try self.allocator.dupe(v.Projection, receiver.path);
        descriptor.* = .{ .receiver = retained, .program = program.*, .table = table };
        return .{ .virtual_ = descriptor };
    }
    /// Copy complete value data into this context's arena. Copying data never
    /// copies cleanup obligations or grants permission to duplicate an owner.
    /// Callers supply the frontend's checked copy/move and publication plans.
    pub fn cloneValues(self: *Storage, values: []const b.Value) ![]const b.Value {
        var count: CloneSize = .{};
        try self.countClone(values, 0, &count);
        const charge_count = std.math.add(usize, count.values, count.projections) catch return error.ExecutionMemoryLimit;
        try self.charge(charge_count);
        errdefer self.cells -= charge_count;
        const backing = try self.allocator.alloc(b.Value, count.values);
        errdefer self.allocator.free(backing);
        const paths = try self.allocator.alloc(v.Projection, count.projections);
        errdefer self.allocator.free(paths);
        var remaining_values = backing;
        var remaining_paths = paths;
        const result = fillClone(values, &remaining_values, &remaining_paths);
        std.debug.assert(remaining_values.len == 0 and remaining_paths.len == 0);
        return result;
    }

    const CloneSize = struct { values: usize = 0, projections: usize = 0 };

    // Preflight the complete tree before reserving either backing buffer. A
    // rejected context, depth or quota cannot leave a partially retained copy.
    fn countClone(self: *Storage, values: []const b.Value, depth: usize, count: *CloneSize) anyerror!void {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        count.values = std.math.add(usize, count.values, values.len) catch return error.ExecutionMemoryLimit;
        for (values) |value| switch (value) {
            .array => |elements| try self.countClone(elements, depth + 1, count),
            .record => |fields| try self.countClone(fields, depth + 1, count),
            .choice => |choice| if (choice.payload) |payload| try self.countClone(payload[0..1], depth + 1, count),
            .virtual_ => |handle| try self.validateContext(handle.receiver),
            .reference => |reference| {
                try self.validateContext(reference);
                count.projections = std.math.add(usize, count.projections, reference.path.len) catch return error.ExecutionMemoryLimit;
            },
            else => {},
        };
    }

    fn fillClone(values: []const b.Value, remaining: *[]b.Value, paths: *[]v.Projection) []const b.Value {
        const result = remaining.*[0..values.len];
        remaining.* = remaining.*[values.len..];
        for (result, values) |*out, value| out.* = switch (value) {
            .array => |elements| .{ .array = fillClone(elements, remaining, paths) },
            .record => |fields| .{ .record = fillClone(fields, remaining, paths) },
            .choice => |choice| .{ .choice = .{
                .variant = choice.variant,
                .payload = if (choice.payload) |payload| &fillClone(payload[0..1], remaining, paths)[0] else null,
            } },
            .reference => |reference| result: {
                const path = paths.*[0..reference.path.len];
                @memcpy(path, reference.path);
                paths.* = paths.*[path.len..];
                var retained = reference;
                retained.path = path;
                break :result .{ .reference = retained };
            },
            else => value,
        };
        return result;
    }

    /// Session slots have their own lifetime from creation. They are never
    /// promoted call-frame slots. Layouts are copied because their original
    /// bytecode unit may be released before this storage is retired.
    pub fn enterSession(self: *Storage, count: usize, cleanup: []const b.Cleanup) !Slots {
        const flag_count = b.cleanupFlagCount(cleanup) catch return error.ExecutionInvalidReference;
        for (cleanup) |entry| if (entry.root >= count) return error.ExecutionInvalidReference;
        const frame_cells = std.math.add(usize, std.math.add(usize, count, flag_count) catch return error.ExecutionMemoryLimit, 1) catch return error.ExecutionMemoryLimit;
        if (frame_cells > self.limit -| self.cells) return error.ExecutionMemoryLimit;
        var staging = std.heap.ArenaAllocator.init(self.allocator);
        errdefer staging.deinit();
        const a = staging.allocator();
        var copy: cleanup_layout.Layout.Copy = .{ .allocator = a };
        defer copy.deinit();
        for (cleanup) |entry| try copy.measure(entry.layout, 0);
        const metadata_cells = std.math.add(usize, cleanup.len, copy.cells) catch return error.ExecutionMemoryLimit;
        const total_cells = std.math.add(usize, metadata_cells, frame_cells) catch return error.ExecutionMemoryLimit;
        if (total_cells > self.limit -| self.cells) return error.ExecutionMemoryLimit;
        const retained = try a.alloc(b.Cleanup, cleanup.len);
        for (retained, cleanup) |*out, entry| {
            out.* = entry;
            out.layout = try copy.retain(entry.layout, 0);
        }
        try self.charge(metadata_cells);
        errdefer self.cells -= metadata_cells;
        const frame = try self.enterCleanup(count, retained);
        // The execution arena owns the staged immutable metadata's backing.
        self.frames.items[@intFromEnum(frame)].duration = .session;
        return .{ .storage = self, .context = self.context, .frame = frame };
    }

    /// Initialize vacant session storage with checked publication data. Reject
    /// references into command/call frames, including inside aggregates. The
    /// frontend still proves loans, moves and cleanup transfer; this checks the
    /// concrete lifetime boundary rather than reconstructing those proofs.
    pub fn initializeSession(self: *Storage, target: Slots, index: b.Slot, value: b.Value) !void {
        return self.publishSession(target, index, value, false);
    }

    /// Re-evaluated deferred storage may replace a value only after its checked
    /// cleanup has discharged every obligation. Caller-relative safety remains
    /// the frontend's responsibility, just as for ordinary checked writes.
    pub fn reinitializeSession(self: *Storage, target: Slots, index: b.Slot, value: b.Value) !void {
        return self.publishSession(target, index, value, true);
    }

    fn publishSession(self: *Storage, target: Slots, index: b.Slot, value: b.Value, reinitialize: bool) !void {
        if (target.storage != self or target.context != self.context) return error.ExecutionForeignReference;
        const values = try target.cells();
        if (self.frames.items[@intFromEnum(target.frame)].duration != .session) return error.ExecutionInvalidReference;
        if (index >= values.len) return error.ExecutionInvalidReference;
        if (values[index] != null and !reinitialize) return error.ExecutionInitializedStorage;
        if (try self.cleanupRootActive(target.frame, index)) return error.ExecutionPendingCleanup;
        try self.validateSessionValues((&value)[0..1], 0);
        const retained = try self.cloneValues((&value)[0..1]);
        values[index] = retained[0];
    }

    fn validateSessionValues(self: *Storage, values: []const b.Value, depth: usize) anyerror!void {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        for (values) |value| switch (value) {
            .reference => |reference| {
                try self.validateStorageAddress(reference);
                if (self.frames.items[@intFromEnum(reference.frame)].duration == .call) return error.ExecutionTemporaryReference;
            },
            .virtual_ => |handle| try self.validateSessionValues(&.{.{ .reference = handle.receiver }}, depth + 1),
            .choice => |choice| if (choice.payload) |payload| try self.validateSessionValues(payload[0..1], depth + 1),
            .record => |fields| try self.validateSessionValues(fields, depth + 1),
            .array => |elements| try self.validateSessionValues(elements, depth + 1),
            else => {},
        };
    }

    /// Checked cleanup must deactivate every represented obligation before
    /// retiring session storage. Releasing a region never runs user code.
    /// Literal backing has context lifetime and immutable storage, independently
    /// of the frame evaluating it. Include the native trailing zero without
    /// exposing it as part of a StringView's logical length.
    pub fn staticBytes(self: *Storage, bytes: []const u8) !v.Reference {
        const length = std.math.add(usize, bytes.len, 1) catch return error.ExecutionMemoryLimit;
        const backing_cells = std.math.add(usize, length, 1) catch return error.ExecutionMemoryLimit;
        const total_cells = std.math.add(usize, backing_cells, 1) catch return error.ExecutionMemoryLimit;
        if (total_cells > self.limit -| self.cells) return error.ExecutionMemoryLimit;
        try self.charge(backing_cells);
        errdefer self.cells -= backing_cells;
        const data = try self.allocator.alloc(u8, length);
        errdefer self.allocator.free(data);
        @memcpy(data[0..bytes.len], bytes);
        data[bytes.len] = 0;
        const path = try self.allocator.alloc(v.Projection, 1);
        errdefer self.allocator.free(path);
        path[0] = .{ .element = 0 };
        // The frame is the publication point. Nothing fallible may follow it.
        const frame = try self.enter(0);
        self.frames.items[@intFromEnum(frame)].bytes = data;
        self.frames.items[@intFromEnum(frame)].duration = .static;
        return .{ .context = self.context, .frame = frame, .root = 0, .path = path, .mutability = .read_only };
    }

    fn offsetInto(self: *Storage, reference: v.Reference, elements: i128, path: *[64]v.Projection) !v.Reference {
        try self.validateStorageAddress(reference);
        if (reference.byte_view) |view| {
            const amount = std.math.cast(usize, elements) orelse return error.ExecutionIndexOutOfBounds;
            var result = reference;
            result.byte_view.?.offset = std.math.add(usize, view.offset, amount) catch return error.ExecutionIndexOutOfBounds;
            try self.validateStorageAddress(result);
            return result;
        }
        if (elements < 0) return error.ExecutionIndexOutOfBounds;
        if (elements == 0) return reference;
        if (reference.path.len == 0) {
            if (self.acquired_views.contains(reference.frame)) {
                const offset = std.math.cast(b.Slot, elements) orelse return error.ExecutionIndexOutOfBounds;
                var result = reference;
                result.root = std.math.add(b.Slot, reference.root, offset) catch return error.ExecutionIndexOutOfBounds;
                try self.validateStorageAddress(result);
                return result;
            }
        }
        if (reference.path.len == 0 or reference.path[reference.path.len - 1] != .element) return error.ExecutionIndexOutOfBounds;
        const offset = std.math.cast(usize, elements) orelse return error.ExecutionIndexOutOfBounds;
        const index = std.math.add(usize, reference.path[reference.path.len - 1].element, offset) catch return error.ExecutionIndexOutOfBounds;
        if (reference.path.len > path.len) return error.ExecutionInvalidReference;
        @memcpy(path[0..reference.path.len], reference.path);
        path[reference.path.len - 1] = .{ .element = index };
        var result = reference;
        result.path = path[0..reference.path.len];
        try self.validateStorageAddress(result);
        return result;
    }

    // Projection copies publish their quota only with the owned buffer. Keep
    // this rule shared by borrow, address, offset and captured destinations.
    fn retainPath(self: *Storage, path: []const v.Projection) ![]const v.Projection {
        try self.charge(path.len);
        errdefer self.cells -= path.len;
        return self.allocator.dupe(v.Projection, path);
    }

    pub fn offsetReference(self: *Storage, reference: v.Reference, elements: i128) !v.Reference {
        var path: [64]v.Projection = undefined;
        var result = try self.offsetInto(reference, elements, &path);
        if (elements == 0 or result.byte_view != null or result.path.len == 0) return result;
        result.path = try self.retainPath(result.path);
        return result;
    }

    /// Host inspection uses bounded stack projections, without allocating
    /// executor cells or changing the program's execution resource budget.
    pub fn readOffset(self: *Storage, reference: v.Reference, elements: i128) !b.Value {
        var path: [64]v.Projection = undefined;
        return self.read(try self.offsetInto(reference, elements, &path));
    }

    pub fn literalBytes(self: *Storage, reference: v.Reference) ![]const u8 {
        _ = try self.read(reference);
        const frame = self.frames.items[@intFromEnum(reference.frame)];
        if (frame.duration != .static) return error.ExecutionInvalidReference;
        return frame.bytes[0 .. frame.bytes.len - 1];
    }

    pub fn releaseSession(self: *Storage, target: Slots) !void {
        if (target.storage != self or target.context != self.context) return error.ExecutionForeignReference;
        _ = try target.cells();
        const frame = &self.frames.items[@intFromEnum(target.frame)];
        if (frame.duration != .session) return error.ExecutionInvalidReference;
        if (std.mem.indexOfScalar(bool, frame.cleanup_flags, true) != null) return error.ExecutionActiveCleanup;
        frame.alive = false;
    }

    pub fn enter(self: *Storage, count: usize) !v.FrameId {
        return self.enterCleanup(count, &.{});
    }
    pub fn enterCleanup(self: *Storage, count: usize, cleanup: []const b.Cleanup) !v.FrameId {
        for (cleanup) |entry| if (entry.root >= count) return error.ExecutionInvalidReference;
        const flag_count = b.cleanupFlagCount(cleanup) catch return error.ExecutionInvalidReference;
        return self.enterBuffers(count, cleanup, flag_count);
    }

    fn enterBuffers(self: *Storage, count: usize, cleanup: []const b.Cleanup, flag_count: usize) !v.FrameId {
        if (self.frames.items.len >= std.math.maxInt(u32)) return error.ExecutionMemoryLimit;
        // Reserve both buffers before publishing an identity or removing a
        // reusable frame. Failed allocations leave the pool and quota intact.
        const charge_count = std.math.add(usize, std.math.add(usize, count, flag_count) catch return error.ExecutionMemoryLimit, 1) catch return error.ExecutionMemoryLimit;
        try self.charge(charge_count);
        errdefer self.cells -= charge_count;
        try self.frames.ensureUnusedCapacity(self.allocator, 1);
        const bin = try self.reusable_frames.getOrPut(self.allocator, .{ .values = count, .flags = flag_count });
        if (!bin.found_existing) bin.value_ptr.* = null;
        const buffers: FrameBuffers = if (bin.value_ptr.*) |previous| reused: {
            const retired = &self.frames.items[@intFromEnum(previous)];
            std.debug.assert(!retired.alive and retired.duration == .call);
            const buffers: FrameBuffers = .{ .values = retired.values, .flags = retired.cleanup_flags };
            bin.value_ptr.* = retired.reusable_next;
            retired.values = &.{};
            retired.cleanup_flags = &.{};
            retired.reusable_next = null;
            break :reused buffers;
        } else allocated: {
            const values = try self.allocator.alloc(?b.Value, count);
            errdefer self.allocator.free(values);
            const flags = try self.allocator.alloc(bool, flag_count);
            break :allocated .{ .values = values, .flags = flags };
        };
        @memset(buffers.values, null);
        @memset(buffers.flags, false);
        const id: v.FrameId = @enumFromInt(self.frames.items.len);
        self.frames.appendAssumeCapacity(.{ .values = buffers.values, .cleanup = cleanup, .cleanup_flags = buffers.flags });
        return id;
    }
    pub fn leave(self: *Storage, id: v.FrameId) void {
        const frame = &self.frames.items[@intFromEnum(id)];
        std.debug.assert(frame.duration == .call);
        if (!frame.alive) return;
        frame.alive = false;
        const bin = self.reusable_frames.getPtr(.{ .values = frame.values.len, .flags = frame.cleanup_flags.len }).?;
        frame.reusable_next = bin.*;
        bin.* = id;
    }
    pub fn slots(self: *Storage, id: v.FrameId) !Slots {
        _ = try self.frameValues(id);
        return .{ .storage = self, .context = self.context, .frame = id };
    }
    fn frameValues(self: *Storage, id: v.FrameId) ![]?b.Value {
        const index = @intFromEnum(id);
        if (index >= self.frames.items.len or !self.frames.items[index].alive) return error.ExecutionDeadReference;
        return self.frames.items[index].values;
    }
    pub fn elementIndex(index: i128, length: usize) !usize {
        if (index < 0 or index >= length) return error.ExecutionIndexOutOfBounds;
        return @intCast(index);
    }
    pub fn numericBytes(self: *Storage, reference: v.Reference, layout: *const @import("../5_codegen/bytecode/numeric_layout.zig").Layout, endian: std.builtin.Endian) !v.Reference {
        if (layout.has_references) return error.ExecutionInvalidReference;
        if (reference.byte_view != null) return error.ExecutionInvalidReference;
        _ = try self.read(reference);
        if (layout.size == 0) return error.ExecutionIndexOutOfBounds;
        var result = reference;
        result.byte_view = .{ .layout = layout, .offset = 0, .endian = endian };
        _ = try self.read(result);
        result.path = try self.retainPath(reference.path);
        return result;
    }

    // Read only the discriminant's existing representation. No payload snapshot
    // or initialized sibling is needed to select structural cleanup.
    pub fn choiceTag(self: *Storage, reference: v.Reference) !u32 {
        try self.validateContext(reference);
        _ = try self.frameValues(reference.frame);
        const frame = &self.frames.items[@intFromEnum(reference.frame)];
        if (reference.byte_view != null or frame.duration == .static or frame.duration == .acquired) return error.ExecutionInvalidReference;
        const value = if (frame.partial_storage.getPtr(reference.root)) |record|
            try record.storedValue(reference.path)
        else value: {
            if (reference.root >= frame.values.len) return error.ExecutionInvalidReference;
            var current = frame.values[reference.root] orelse return error.ExecutionUninitializedStorage;
            for (reference.path) |projection| current = try child(current, projection);
            break :value current;
        };
        return if (value == .choice) value.choice.variant else error.ExecutionInvalidReference;
    }

    pub fn read(self: *Storage, reference: v.Reference) !b.Value {
        try self.validateContext(reference);
        if (reference.byte_view) |view| {
            var base = reference;
            base.byte_view = null;
            return .{ .integer = try @import("../5_codegen/bytecode/numeric_layout.zig").readByte(view.layout, try self.read(base), view.offset, view.endian) };
        }
        if (try self.acquiredView(reference)) |view| {
            if (try self.acquiredValues(reference)) |record|
                _ = try record.materializationCells(reference.path);
            return if (view.layout.has_references) @import("acquired_values.zig").readPrepared(self, view.handle, view.offset, view.layout, view.endian, reference) else @import("acquired_values.zig").read(self, view.handle, view.offset, view.layout, view.endian);
        }
        _ = try self.frameValues(reference.frame);
        const frame = self.frames.items[@intFromEnum(reference.frame)];
        if (frame.duration == .static) {
            if (reference.root != 0 or reference.path.len != 1 or reference.path[0] != .element) return error.ExecutionInvalidReference;
            const index = reference.path[0].element;
            if (index >= frame.bytes.len) return error.ExecutionIndexOutOfBounds;
            return .{ .integer = frame.bytes[index] };
        }
        const values = try self.slots(reference.frame);
        if (self.frames.items[@intFromEnum(reference.frame)].partial_storage.getPtr(reference.root)) |record| {
            return self.readPartial(record, reference.path);
        }
        var value = try values.get(reference.root);
        for (reference.path) |projection| value = try child(value, projection);
        return value;
    }
    fn readPartial(self: *Storage, record: *partial.Storage, path: []const v.Projection) !b.Value {
        const cells = try record.materializationCells(path);
        try self.charge(cells);
        errdefer self.cells -= cells;
        return record.read(self.allocator, path);
    }
    fn child(value: b.Value, projection: v.Projection) !b.Value {
        return switch (projection) {
            .variant => |variant| if (value == .choice and value.choice.variant == variant and value.choice.payload != null) value.choice.payload.?.* else error.ExecutionInactiveVariant,
            .field => |index| if (value == .record and index < value.record.len) value.record[index] else error.ExecutionInvalidReference,
            .element => |index| if (value == .array and index < value.array.len) value.array[index] else error.ExecutionIndexOutOfBounds,
        };
    }
    pub fn resolve(self: *Storage, frame: v.FrameId, place: b.Place, path: *[64]v.Projection) !v.Reference {
        return self.resolveTarget(frame, place, path, true, null);
    }
    // Lifecycle access locates storage without reading its current value. Only
    // following a reference or checking an array index needs an operand read.
    pub fn resolveCleanup(self: *Storage, frame: v.FrameId, place: b.Place, path: *[64]v.Projection) !v.Reference {
        return self.resolveTarget(frame, place, path, false, null);
    }
    pub fn resolveSession(self: *Storage, frame: v.FrameId, target: v.FrameId, place: b.Place, path: *[64]v.Projection, comptime read_value: bool) !v.Reference {
        return self.resolveTarget(frame, place, path, read_value, target);
    }
    fn resolveTarget(self: *Storage, frame: v.FrameId, place: b.Place, path: *[64]v.Projection, comptime read_value: bool, session_frame: ?v.FrameId) !v.Reference {
        const locals = try self.slots(frame);
        if ((place.region == .session) != (session_frame != null)) return error.ExecutionInvalidReference;
        const target = try self.slots(session_frame orelse frame);
        const root = if (session_frame != null) 0 else place.root;
        if (root >= (try target.cells()).len) return error.ExecutionInvalidReference;
        var reference = v.Reference{ .context = self.context, .frame = target.frame, .root = root, .path = &.{}, .mutability = .read_write };
        var length: usize = 0;
        for (place.path) |projection| {
            reference.path = path[0..length];
            if (projection == .dereference) {
                const pointer = try self.read(reference);
                if (pointer != .reference) return error.ExecutionInvalidReference;
                reference = pointer.reference;
                try self.validateContext(reference);
                _ = try self.slots(reference.frame);
                if (reference.path.len > path.len) return error.ExecutionInvalidReference;
                length = reference.path.len;
                @memcpy(path[0..length], reference.path);
                continue;
            }
            if (reference.byte_view != null or length == path.len) return error.ExecutionInvalidReference;
            const concrete: v.Projection = switch (projection) {
                .field => |index| .{ .field = index },
                .variant => |variant| .{ .variant = variant.ordinal },
                .element => |index| blk: {
                    const array_length = blk_length: {
                        if (try self.acquiredView(reference)) |view| {
                            if (view.layout.shape != .array) return error.ExecutionInvalidReference;
                            break :blk_length view.layout.shape.array.length;
                        }
                        if (self.frames.items[@intFromEnum(reference.frame)].partial_storage.getPtr(reference.root)) |partial_| {
                            if (try partial_.arrayLength(reference.path)) |count| break :blk_length count;
                        }
                        const array = try self.read(reference);
                        if (array != .array) return error.ExecutionInvalidReference;
                        break :blk_length array.array.len;
                    };
                    const bounds = index.kind.bounds() orelse return error.ExecutionInvalidReference;
                    const ordinal = @import("../5_codegen/integer_arithmetic.zig").decode((try locals.get(index.slot)).integer, bounds);
                    break :blk .{ .element = try elementIndex(ordinal, array_length) };
                },
                .dereference => unreachable,
            };
            path[length] = concrete;
            length += 1;
        }
        reference.path = path[0..length];
        if (read_value) _ = try self.read(reference);
        return reference;
    }
    fn validateStorageAddress(self: *Storage, reference: v.Reference) !void {
        try self.validateContext(reference);
        _ = try self.frameValues(reference.frame);
        if (reference.byte_view) |view| {
            if (view.offset >= view.layout.size) return error.ExecutionIndexOutOfBounds;
            var base = reference;
            base.byte_view = null;
            try self.validateStorageAddress(base);
            return;
        }
        const frame = self.frames.items[@intFromEnum(reference.frame)];
        if (frame.duration == .static) {
            if (reference.root != 0 or reference.path.len != 1 or reference.path[0] != .element) return error.ExecutionInvalidReference;
            if (reference.path[0].element >= frame.bytes.len) return error.ExecutionIndexOutOfBounds;
            return;
        }
        if (try self.acquiredView(reference) != null) return;
        const slots_ = try self.slots(reference.frame);
        if (reference.root >= (try slots_.cells()).len) return error.ExecutionInvalidReference;
        if (reference.path.len != 0) {
            if (self.frames.items[@intFromEnum(reference.frame)].partial_storage.getPtr(reference.root)) |record| {
                // Resolve the layout without requiring a value at its leaf.
                if (try record.aggregatePrefix(reference.path) < reference.path.len)
                    _ = try self.readPartial(record, reference.path);
            } else _ = try self.read(reference);
        }
    }
    pub fn address(self: *Storage, reference: v.Reference, mutability: p.PointerMutability) !b.Value {
        try self.validateStorageAddress(reference);
        if (mutability == .read_write and (reference.mutability != .read_write or self.frames.items[@intFromEnum(reference.frame)].duration == .static)) return error.ExecutionReadonlyReference;
        var result = reference;
        result.path = try self.retainPath(reference.path);
        result.mutability = mutability;
        return .{ .reference = result };
    }
    pub fn borrow(self: *Storage, reference: v.Reference, mutability: p.PointerMutability) !b.Value {
        _ = try self.read(reference);
        if (mutability == .read_write and (reference.mutability != .read_write or self.frames.items[@intFromEnum(reference.frame)].duration == .static)) return error.ExecutionReadonlyReference;
        var result = reference;
        result.path = try self.retainPath(reference.path);
        result.mutability = mutability;
        return .{ .reference = result };
    }

    fn cleanupRootActive(self: *Storage, frame: v.FrameId, root: b.Slot) !bool {
        const selected = (try self.cleanupOwner(frame, root)) orelse return false;
        const record = self.frames.items[@intFromEnum(frame)];
        const end = std.math.add(usize, selected.offset, selected.layout.count) catch return error.ExecutionInvalidReference;
        if (end > record.cleanup_flags.len) return error.ExecutionInvalidReference;
        return std.mem.indexOfScalar(bool, record.cleanup_flags[selected.offset..end], true) != null;
    }

    fn cleanupOwner(self: *Storage, frame: v.FrameId, root: b.Slot) !?CleanupSelection {
        _ = try self.frameValues(frame);
        const record = self.frames.items[@intFromEnum(frame)];
        if (record.duration == .acquired) {
            const view = self.acquired_views.get(frame) orelse return error.ExecutionInvalidReference;
            if (root >= view.count) return error.ExecutionIndexOutOfBounds;
            if (record.cleanup.len == 0) return null;
            const layout = record.cleanup[0].layout;
            return .{ .offset = try std.math.mul(usize, root, layout.count), .layout = layout };
        }
        var start: usize = 0;
        var end = record.cleanup.len;
        while (start < end) {
            const middle = start + (end - start) / 2;
            switch (std.math.order(record.cleanup[middle].root, root)) {
                .lt => start = middle + 1,
                .gt => end = middle,
                .eq => {
                    const owner = record.cleanup[middle];
                    return .{ .offset = owner.offset, .layout = owner.layout };
                },
            }
        }
        return null;
    }

    fn cleanupEntry(self: *Storage, reference: v.Reference) !CleanupSelection {
        if (reference.byte_view != null) return error.ExecutionInvalidReference;
        try self.validateContext(reference);
        _ = try self.acquiredView(reference);
        var selected = (try self.cleanupOwner(reference.frame, reference.root)) orelse return error.ExecutionMissingCleanup;
        const record = self.frames.items[@intFromEnum(reference.frame)];
        for (reference.path) |projection| {
            const span = selected.layout.project(projection) orelse return error.ExecutionMissingCleanup;
            selected.offset = std.math.add(usize, selected.offset, span.offset) catch return error.ExecutionInvalidReference;
            selected.layout = span.layout;
        }
        if (selected.offset >= record.cleanup_flags.len or selected.layout.count > record.cleanup_flags.len - selected.offset) return error.ExecutionInvalidReference;
        return selected;
    }
    pub fn cleanupPresent(self: *Storage, reference: v.Reference) !bool {
        const selected = try self.cleanupEntry(reference);
        return self.frames.items[@intFromEnum(reference.frame)].cleanup_flags[selected.offset + @intFromBool(selected.layout.is_choice)];
    }
    pub fn cleanupTest(self: *Storage, reference: v.Reference) !bool {
        const selected = try self.cleanupEntry(reference);
        return self.frames.items[@intFromEnum(reference.frame)].cleanup_flags[selected.offset];
    }
    pub fn cleanupSet(self: *Storage, reference: v.Reference, enabled: bool) !usize {
        try self.validateWritable(reference);
        return self.cleanupSetAt(reference, try self.cleanupEntry(reference), enabled);
    }
    fn cleanupSetAt(self: *Storage, reference: v.Reference, selected: CleanupSelection, enabled: bool) !usize {
        _ = try self.acquiredView(reference);
        _ = try self.slots(reference.frame);
        const record = self.frames.items[@intFromEnum(reference.frame)];
        const flags = record.cleanup_flags;
        var updated = selected.layout.count;
        const Ancestor = struct { offset: usize, layout: *const cleanup_layout.Layout };
        var parents: [64]Ancestor = undefined;
        const owner = (try self.cleanupOwner(reference.frame, reference.root)) orelse return error.ExecutionMissingCleanup;
        var parent: Ancestor = .{ .offset = owner.offset, .layout = owner.layout };
        if (reference.path.len > parents.len) return error.ExecutionInvalidReference;
        for (reference.path, 0..) |projection, index| {
            parents[index] = parent;
            const span = parent.layout.project(projection) orelse return error.ExecutionMissingCleanup;
            parent = .{ .offset = parent.offset + span.offset, .layout = span.layout };
        }
        @memset(flags[selected.offset..][0..selected.layout.count], enabled);
        var depth = reference.path.len;
        while (depth != 0) {
            depth -= 1;
            const ancestor = parents[depth];
            updated += 1;
            // Ending an actual descendant always makes its ancestors
            // incomplete. No sibling scan is needed to prove this direction.
            if (!enabled) {
                flags[ancestor.offset] = false;
                updated += 1;
                continue;
            }
            if (ancestor.layout.repetition) |array| {
                if (array.length == 0) continue;
                var complete = true;
                for (0..array.length) |index| {
                    complete = complete and flags[ancestor.offset + 1 + index * array.element.count];
                    updated += 1;
                }
                flags[ancestor.offset] = complete;
                updated += 1;
                continue;
            }
            if (!ancestor.layout.is_record and !ancestor.layout.is_choice) continue;
            if (ancestor.layout.is_record and ancestor.layout.children.len == 0) continue;
            var complete = if (ancestor.layout.is_choice) flags[ancestor.offset + 1] else true;
            for (ancestor.layout.children) |maybe_child| if (maybe_child) |span| {
                complete = complete and flags[ancestor.offset + span.offset];
                updated += 1;
            };
            flags[ancestor.offset] = complete;
            updated += 1;
        }
        return updated;
    }
    pub fn captureWrite(self: *Storage, frame: v.FrameId, place: b.Place, activate_cleanup: bool) !WriteDestination {
        var path: [64]v.Projection = undefined;
        const reference = try self.resolve(frame, place, &path);
        return self.captureResolvedWrite(reference, activate_cleanup);
    }
    // The caller has already evaluated and resolved the complete destination.
    pub fn captureResolvedWrite(self: *Storage, reference: v.Reference, activate_cleanup: bool) !WriteDestination {
        return self.captureWriteEvidence(reference, activate_cleanup, activate_cleanup);
    }

    // Non-owning field writes still contribute to an enclosing owner's
    // completeness. Missing evidence is permitted only when the write itself
    // has no selected cleanup obligation; byte views carry no such flags.
    pub fn captureWriteEvidence(self: *Storage, reference: v.Reference, activate_cleanup: bool, require_cleanup: bool) !WriteDestination {
        try self.validateWritable(reference);
        try self.validateStorageAddress(reference);
        const cleanup_entry = if (!activate_cleanup or (!require_cleanup and reference.byte_view != null)) null else self.cleanupEntry(reference) catch |err| switch (err) {
            error.ExecutionMissingCleanup => if (require_cleanup) return err else null,
            else => return err,
        };
        var captured = reference;
        captured.path = try self.retainPath(reference.path);
        return .{ .reference = captured, .cleanup_entry = cleanup_entry, .require_cleanup = require_cleanup };
    }

    // Checked relocation transfers an existing value into vacant storage.
    // A by-value input or an output need not have automatic local cleanup;
    // absence of those flags creates no new obligation. Capture both references
    // and read the complete source before the first write.
    pub fn relocate(self: *Storage, source: v.Reference, destination: v.Reference) !usize {
        const from = try self.captureWriteEvidence(source, true, false);
        var to = try self.captureWriteEvidence(destination, true, false);
        to.require_cleanup = true;
        var work = try self.checkWriteCleanup(to);
        const value = try self.read(from.reference);
        try self.write(to, value);
        work = try std.math.add(usize, work, try self.activateWriteCleanup(to));
        if (from.cleanup_entry) |selected|
            work = try std.math.add(usize, work, try self.cleanupSetAt(from.reference, selected, false));
        return work;
    }

    // Validate compiler-selected cleanup state independently of value storage.
    // The executor orders this check, the write and subsequent activation.
    pub fn checkWriteCleanup(self: *Storage, destination: WriteDestination) !usize {
        if (!destination.require_cleanup) return 0;
        if (destination.cleanup_entry) |selected| {
            try self.validateContext(destination.reference);
            _ = try self.acquiredView(destination.reference);
            _ = try self.slots(destination.reference.frame);
            const flags = self.frames.items[@intFromEnum(destination.reference.frame)].cleanup_flags;
            if (std.mem.indexOfScalar(bool, flags[selected.offset..][0..selected.layout.count], true) != null) return error.ExecutionPendingCleanup;
            return selected.layout.count;
        }
        return 0;
    }

    // A write changes only the value. It never manufactures or reactivates a
    // cleanup obligation, and capture does not authorize vacant storage.
    pub fn write(self: *Storage, destination: WriteDestination, value: b.Value) !void {
        try self.store(destination.reference, value);
    }

    // Like cleanupSet, this reports traversal work rather than changed flags.
    pub fn activateWriteCleanup(self: *Storage, destination: WriteDestination) !usize {
        if (destination.cleanup_entry) |index| {
            try self.validateContext(destination.reference);
            if (destination.reference.mutability != .read_write) return error.ExecutionReadonlyReference;
            return self.cleanupSetAt(destination.reference, index, true);
        }
        return 0;
    }

    pub fn store(self: *Storage, reference: v.Reference, value: b.Value) !void {
        try self.validateWritable(reference);
        if (reference.byte_view) |view| {
            if (value != .integer or value.integer > 255) return error.ExecutionInvalidReference;
            var base = reference;
            base.byte_view = null;
            try self.charge(view.layout.size);
            const updated = try @import("../5_codegen/bytecode/numeric_layout.zig").writeByte(self.allocator, view.layout, try self.read(base), view.offset, @intCast(value.integer), view.endian);
            return self.store(base, updated);
        }
        if (try self.acquiredView(reference)) |view| {
            var record = try self.acquiredValues(reference);
            if (view.layout.has_references and record == null) return error.ExecutionMissingCleanup;
            if (record) |*logical| try logical.validateWritePath(reference.path);
            try @import("acquired_values.zig").write(self, view.handle, view.offset, view.layout, value, view.endian);
            if (record) |*logical| try logical.write(reference.path, value);
            return;
        }
        const values = try self.slots(reference.frame);
        if (self.frames.items[@intFromEnum(reference.frame)].partial_storage.getPtr(reference.root)) |record| {
            const prefix = try record.aggregatePrefix(reference.path);
            if (prefix == reference.path.len) {
                try record.write(reference.path, value);
            } else {
                const fields = reference.path[0..prefix];
                const previous = try self.readPartial(record, fields);
                try record.write(fields, try self.update(previous, reference.path[prefix..], value));
            }
            return;
        }
        const previous = try values.get(reference.root);
        try values.put(reference.root, try self.update(previous, reference.path, value));
    }

    fn validateWritable(self: *Storage, reference: v.Reference) !void {
        try self.validateContext(reference);
        if (reference.mutability != .read_write) return error.ExecutionReadonlyReference;
        _ = try self.frameValues(reference.frame);
        if (self.frames.items[@intFromEnum(reference.frame)].duration == .static) return error.ExecutionReadonlyReference;
    }

    fn validateContext(self: *const Storage, reference: v.Reference) !void {
        if (reference.context != self.context) return error.ExecutionForeignReference;
    }
    // Rebuild only the modified aggregate path; all untouched subtrees remain
    // immutable shared values. References retain storage identity across updates.
    fn update(self: *Storage, base: b.Value, path: []const v.Projection, value: b.Value) anyerror!b.Value {
        if (path.len == 0) return value;
        const old = try child(base, path[0]);
        const changed = try self.update(old, path[1..], value);
        if (path[0] == .variant) {
            const payload = try self.allocate(1);
            payload[0] = changed;
            return .{ .choice = .{ .variant = base.choice.variant, .payload = &payload[0] } };
        }
        const elements, const index = switch (path[0]) {
            .field => |index| .{ base.record, @as(usize, index) },
            .element => |index| .{ base.array, index },
            .variant => unreachable,
        };
        const result = try self.allocate(elements.len);
        @memcpy(result, elements);
        result[index] = changed;
        return switch (path[0]) {
            .field => .{ .record = result },
            .element => .{ .array = result },
            .variant => unreachable,
        };
    }
    // Returning a borrow of a caller's storage is valid; returning one into the
    // completed frame is not. This is a runtime backstop, not a second safety checker.
    pub fn validateLive(self: *Storage, values: []const b.Value) anyerror!void {
        for (values) |value| switch (value) {
            .reference => |reference| try self.validateStorageAddress(reference),
            .virtual_ => |handle| try self.validateStorageAddress(handle.receiver),
            .choice => |choice| if (choice.payload) |payload| try self.validateLive(payload[0..1]),
            .record => |fields| try self.validateLive(fields),
            .array => |elements| try self.validateLive(elements),
            else => {},
        };
    }
};

test "numeric byte storage views retain identity permissions and frame lifetime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const frame = try storage.enter(1);
    const slots_ = try storage.slots(frame);
    try slots_.put(0, .{ .integer = 0x12345678 });
    const root: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = false } } };
    const bytes = try storage.numericBytes(root, &layout, .little);
    try std.testing.expectEqual(@as(i128, 0x78), (try storage.read(bytes)).integer);
    const second = try storage.offsetReference(bytes, 1);
    try storage.store(second, .{ .integer = 0xab });
    try std.testing.expectEqual(@as(i128, 0x1234ab78), (try storage.read(root)).integer);
    try slots_.put(0, .{ .integer = 42 });
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(bytes)).integer);
    const readonly = (try storage.borrow(bytes, .read_only)).reference;
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(readonly, .{ .integer = 0 }));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.offsetReference(bytes, 4));
    try std.testing.expectError(error.ExecutionInvalidReference, storage.store(bytes, .{ .integer = 256 }));
    try std.testing.expectError(error.ExecutionInvalidReference, storage.captureResolvedWrite(bytes, true));
    storage.leave(frame);
    try std.testing.expectError(error.ExecutionDeadReference, storage.read(bytes));
}

test "deferred session initialization requires discharged cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const slots_ = try storage.enterSession(2, &.{.{ .root = 0, .offset = 0 }});
    try std.testing.expectError(error.ExecutionUninitializedStorage, slots_.get(0));
    try storage.initializeSession(slots_, 0, .{ .integer = 41 });
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.initializeSession(slots_, 0, .{ .integer = 42 }));
    storage.frames.items[@intFromEnum(slots_.frame)].cleanup_flags[0] = true;
    try std.testing.expectError(error.ExecutionPendingCleanup, storage.reinitializeSession(slots_, 0, .{ .integer = 42 }));
    try std.testing.expectEqual(@as(i128, 41), (try slots_.get(0)).integer);
    storage.frames.items[@intFromEnum(slots_.frame)].cleanup_flags[0] = false;
    try storage.reinitializeSession(slots_, 0, .{ .integer = 42 });
    try std.testing.expectEqual(@as(i128, 42), (try slots_.get(0)).integer);
    try std.testing.expect(!storage.frames.items[@intFromEnum(slots_.frame)].cleanup_flags[0]);
}

test "partial record storage reads initialized projected fields only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const frame = try storage.enter(1);
    const root: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    try storage.prepareStorage(frame, 0, .{ .nodes = &.{ .{ .kind = .record, .first = 1, .count = 2, .span = 3 }, .{ .offset = 1 }, .{ .offset = 2 } } });
    const reserved_cells = storage.cells;
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    try std.testing.expectEqual(reserved_cells, storage.cells);
    var field = root;
    field.path = &.{.{ .field = 0 }};
    try storage.store(field, .{ .integer = 41 });
    try std.testing.expectEqual(@as(i128, 41), (try storage.read(field)).integer);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    const readonly = (try storage.borrow(field, .read_only)).reference;
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(readonly, .{ .integer = 0 }));
    field.path = &.{.{ .field = 1 }};
    try storage.store(field, .{ .integer = 42 });
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(root)).record[1].integer);
    const complete_cells = storage.cells;
    _ = try storage.read(root);
    try std.testing.expectEqual(complete_cells, storage.cells);
    storage.leave(frame);
    try std.testing.expectError(error.ExecutionDeadReference, storage.read(field));
}

test "lexical record reset clears values only after cleanup is discharged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const frame = try storage.enterCleanup(2, &.{.{ .root = 0, .offset = 0 }});
    const layout: partial.Layout = .{ .nodes = &.{ .{ .kind = .record, .first = 1, .count = 1, .span = 2 }, .{ .offset = 1 } } };
    _ = try storage.resetStorage(frame, 0, layout);
    const root: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var field = root;
    field.path = &.{.{ .field = 0 }};
    try storage.store(field, .{ .integer = 42 });
    const snapshot = try storage.read(root);
    const slots_ = try storage.slots(frame);
    storage.frames.items[@intFromEnum(slots_.frame)].cleanup_flags[0] = true;
    try std.testing.expectError(error.ExecutionPendingCleanup, storage.resetStorage(frame, 0, layout));
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(field)).integer);
    storage.frames.items[@intFromEnum(slots_.frame)].cleanup_flags[0] = false;
    const cells = storage.cells;
    _ = try storage.resetStorage(frame, 0, layout);
    try std.testing.expectEqual(cells, storage.cells);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(field));
    try std.testing.expectEqual(@as(i128, 42), snapshot.record[0].integer);
}

test "field cleanup activation completes record ancestors but not choices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const frame = try storage.enterCleanup(8, &.{
        .{ .root = 0, .layout = &@import("../test_support.zig").cleanup_layouts.pair },
        .{ .root = 4, .offset = 3, .layout = &@import("../test_support.zig").cleanup_layouts.choice },
    });
    const root: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var field = root;
    field.path = &.{.{ .field = 0 }};
    _ = try storage.cleanupSet(field, true);
    try std.testing.expect(!try storage.cleanupTest(root));
    field.path = &.{.{ .field = 1 }};
    _ = try storage.cleanupSet(field, true);
    try std.testing.expect(try storage.cleanupTest(root));
    // Ending a descendant must revoke whole-record cleanup immediately.
    _ = try storage.cleanupSet(field, false);
    try std.testing.expect(!try storage.cleanupTest(root));
    var sibling = root;
    sibling.path = &.{.{ .field = 0 }};
    try std.testing.expect(try storage.cleanupTest(sibling));
    _ = try storage.cleanupSet(field, true);
    try std.testing.expect(try storage.cleanupTest(root));
    var choice = root;
    choice.root = 4;
    var payload = choice;
    payload.path = &.{.{ .variant = 0 }};
    _ = try storage.cleanupSet(payload, true);
    try std.testing.expect(!try storage.cleanupTest(choice));
    try std.testing.expect(!try storage.cleanupPresent(choice));
    _ = try storage.cleanupSet(choice, true);
    _ = try storage.cleanupSet(payload, false);
    try std.testing.expect(!try storage.cleanupTest(choice));
    try std.testing.expect(try storage.cleanupPresent(choice));
    _ = try storage.cleanupSet(payload, true);
    try std.testing.expect(try storage.cleanupTest(choice));
    _ = try storage.cleanupSet(choice, false);
    try std.testing.expect(!try storage.cleanupPresent(choice));
}

test "consuming nested storage revokes ancestor cleanup and reinitialization restores it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const frame = try storage.enterCleanup(5, &.{
        .{ .root = 0, .layout = &@import("../test_support.zig").cleanup_layouts.nested },
    });
    const root: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var parent = root;
    parent.path = &.{.{ .field = 0 }};
    var nested = root;
    nested.path = &.{ .{ .field = 0 }, .{ .field = 0 } };
    var sibling = root;
    sibling.path = &.{.{ .field = 1 }};
    _ = try storage.cleanupSet(root, true);
    _ = try storage.cleanupSet(nested, false);
    try std.testing.expect(!try storage.cleanupTest(root));
    try std.testing.expect(!try storage.cleanupTest(parent));
    try std.testing.expect(try storage.cleanupTest(sibling));
    _ = try storage.cleanupSet(nested, true);
    try std.testing.expect(try storage.cleanupTest(parent));
    try std.testing.expect(try storage.cleanupTest(root));
}

test "compact partial array layouts charge concrete cells before allocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 16);
    const frame = try storage.enter(1);
    const before = storage.cells;
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.prepareStorage(frame, 0, .{ .nodes = &.{
        .{ .kind = .array, .first = 1, .count = 1000000, .span = 1000001 },
        .{ .offset = 1 },
    } }));
    try std.testing.expectEqual(before, storage.cells);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items[@intFromEnum(frame)].partial_storage.count());
}

fn failedVirtualStorage(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 10000);
    const frame = try storage.enter(1);
    try (try storage.slots(frame)).put(0, .{ .record = &.{.{ .integer = 42 }} });
    const receiver: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{.{ .field = 0 }}, .mutability = .read_only };
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    const program: b.Program = .{ .graph = &graph, .functions = &.{} };
    const table: b.VirtualTable = .{ .virtual_type = @enumFromInt(0), .concrete_type = @enumFromInt(0), .methods = &.{} };
    const before = storage.cells;
    storage.allocator = a;
    const result = storage.virtualize(receiver, &program, &table) catch |err| {
        try std.testing.expectEqual(before, storage.cells);
        try std.testing.expectEqual(@as(u64, 42), (try storage.read(receiver)).integer);
        return err;
    };
    defer a.destroy(result.virtual_);
    defer a.free(result.virtual_.receiver.path);
}

test "virtual descriptor allocation failures preserve receiver and storage quota" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedVirtualStorage, .{});
}

test "literal creation checks its complete storage quota before publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 5);
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.staticBytes("abc"));
    try std.testing.expectEqual(@as(usize, 0), storage.cells);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
    storage.limit = 6;
    const reference = try storage.staticBytes("abc");
    try std.testing.expectEqual(@as(usize, 6), storage.cells);
    try std.testing.expectEqualStrings("abc", try storage.literalBytes(reference));
    try std.testing.expectEqual(@as(u64, 0), (try storage.readOffset(reference, 3)).integer);
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(reference, .{ .integer = 0 }));
}

fn failedLiteralStorage(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 10000);
    const text: [4096]u8 = @splat('a');
    _ = storage.staticBytes(&text) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), storage.cells);
        try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
        return err;
    };
}

test "literal allocation failures publish neither frames nor quota charges" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedLiteralStorage, .{});
}

test "session creation validates complete quota before retaining cleanup layouts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4);
    const cleanup = &.{b.Cleanup{ .root = 0, .layout = &@import("../test_support.zig").cleanup_layouts.single }};
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.enterSession(2, cleanup));
    try std.testing.expectEqual(@as(usize, 0), storage.cells);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
    storage.limit = 9;
    const session = try storage.enterSession(2, cleanup);
    try std.testing.expectEqual(@as(usize, 9), storage.cells);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(session.frame));
}

fn failedSessionStorage(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100000);
    const cleanup = &.{b.Cleanup{ .root = 0, .layout = &@import("../test_support.zig").cleanup_layouts.single }};
    _ = storage.enterSession(4096, cleanup) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), storage.cells);
        try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
        return err;
    };
}

test "session allocation failures publish neither cleanup layouts nor frames" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedSessionStorage, .{});
}

test "rejected frames preserve quota and frame identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 2);
    try std.testing.expectError(error.ExecutionInvalidReference, storage.enterCleanup(2, &.{.{ .root = 0, .offset = 1 }}));
    try std.testing.expectEqual(@as(usize, 0), storage.cells);
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.enter(2));
    try std.testing.expectEqual(@as(usize, 0), storage.cells);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(try storage.enter(1)));
}

fn failedFrameStorage(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100000);
    _ = storage.enterCleanup(4096, &.{.{ .root = 0, .offset = 0 }}) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), storage.cells);
        try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
        return err;
    };
}

test "frame allocation failures publish neither identities nor quota charges" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedFrameStorage, .{});
}

test "rejected partial layouts publish neither storage nor quota charges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const frame = try storage.enter(1);
    const before = storage.cells;
    try std.testing.expectError(error.ExecutionInvalidReference, storage.prepareStorage(frame, 0, .{ .nodes = &.{
        .{ .kind = .record, .count = 1, .first = 0, .span = 2 },
    } }));
    try std.testing.expectEqual(before, storage.cells);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items[@intFromEnum(frame)].partial_storage.count());
    try storage.prepareStorage(frame, 0, .{ .nodes = &.{.{}} });
    try std.testing.expectEqual(before + 1, storage.cells);
}

fn failedPartialStorage(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100000);
    const frame = try storage.enter(1);
    const before = storage.cells;
    storage.prepareStorage(frame, 0, .{ .nodes = &.{
        .{ .kind = .array, .first = 1, .count = 4096, .span = 4097 },
        .{ .offset = 1 },
    } }) catch |err| {
        try std.testing.expectEqual(before, storage.cells);
        try std.testing.expectEqual(@as(usize, 0), storage.frames.items[@intFromEnum(frame)].partial_storage.count());
        return err;
    };
}

test "partial storage allocation failures preserve quota and publication" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedPartialStorage, .{});
}

test "acquired scalar frames use ordinary references and reject release or permission violations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const region = try storage.acquisitions.acquire(&storage, 8, 8);
    const reference = try storage.acquiredReference(region, 4, &layout, .little, .read_write, null);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(reference));
    // Addressing vacant storage is valid; borrowing a readable value is not.
    _ = try storage.address(reference, .read_write);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.borrow(reference, .read_only));
    const destination = try storage.captureResolvedWrite(reference, false);
    _ = try storage.checkWriteCleanup(destination);
    try storage.write(destination, .{ .integer = 42 });
    _ = try storage.activateWriteCleanup(destination);
    const readonly = (try storage.borrow(reference, .read_only)).reference;
    const copy = try storage.cloneValues(&.{.{ .reference = readonly }});
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(copy[0].reference)).integer);
    const byte_reference = try storage.numericBytes(readonly, &layout, .little);
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(byte_reference)).integer);
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(byte_reference, .{ .integer = 7 }));
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(readonly, .{ .integer = 7 }));
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.address(readonly, .read_write));
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupTest(reference));
    try storage.acquisitions.release(&storage, region);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(copy[0].reference));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(byte_reference));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.store(reference, .{ .integer = 7 }));
    const replacement = try storage.acquisitions.acquire(&storage, 8, 8);
    _ = try storage.acquiredReference(replacement, 4, &layout, .little, .read_write, null);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(reference));
}

test "acquired aggregates preserve partial initialization and validate writes before commit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 1000);
    const byte: numeric.Layout = .{ .size = 1, .alignment = 1, .shape = .{ .integer = .{ .signed = false } } };
    const word: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const layout: numeric.Layout = .{ .size = 8, .alignment = 4, .shape = .{ .fields = &.{ .{ .offset = 0, .layout = &byte }, .{ .offset = 4, .layout = &word } } } };
    const region = try storage.acquisitions.acquire(&storage, 8, 4);
    const root = try storage.acquiredReference(region, 0, &layout, .little, .read_write, null);
    var first = root;
    first.path = &.{.{ .field = 0 }};
    var second = root;
    second.path = &.{.{ .field = 1 }};
    try storage.store(first, .{ .integer = 7 });
    const before_read = storage.cells;
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    try std.testing.expectEqual(before_read, storage.cells);
    try std.testing.expectError(error.ExecutionIntegerOutOfRange, storage.store(root, .{ .record = &.{ .{ .integer = 9 }, .{ .integer = std.math.maxInt(u32) + @as(u64, 1) } } }));
    try std.testing.expectEqual(@as(i128, 7), (try storage.read(first)).integer);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(second));
    try storage.store(second, .{ .integer = 42 });
    const normal_limit = storage.limit;
    storage.limit = storage.cells + 1;
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.read(root));
    try std.testing.expectEqual(before_read, storage.cells);
    storage.limit = normal_limit;
    const complete = try storage.read(root);
    try std.testing.expectEqual(@as(i128, 42), complete.record[1].integer);
    // Padding remains vacant and is never exposed by a typed aggregate read.
    var padding: [1]u8 = undefined;
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.acquisitions.read(&storage, region, 1, &padding));
    try storage.acquisitions.release(&storage, region);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(first));
}

test "acquired array indices resolve from layout before elements are initialized" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const element: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const layout: numeric.Layout = .{ .size = 8, .alignment = 4, .shape = .{ .array = .{ .element = &element, .length = 2, .stride = 4 } } };
    const region = try storage.acquisitions.acquire(&storage, 8, 4);
    const reference = try storage.acquiredReference(region, 0, &layout, .little, .read_write, null);
    const frame = try storage.enter(2);
    const slots_ = try storage.slots(frame);
    try slots_.put(0, .{ .reference = reference });
    try slots_.put(1, .{ .integer = 1 });
    var path: [64]v.Projection = undefined;
    const place: b.Place = .{ .root = 0, .path = &.{ .dereference, .{ .element = .{ .slot = 1, .kind = .u64 } } } };
    const target = try storage.resolveCleanup(frame, place, &path);
    try storage.store(target, .{ .integer = 42 });
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(target)).integer);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(reference));
    try slots_.put(1, .{ .integer = 2 });
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.resolveCleanup(frame, place, &path));
}

test "acquired floating records preserve precision and validate writes before mutation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const single: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .floating = .float32 } };
    const double: numeric.Layout = .{ .size = 8, .alignment = 8, .shape = .{ .floating = .float64 } };
    const layout: numeric.Layout = .{ .size = 16, .alignment = 8, .shape = .{ .fields = &.{ .{ .offset = 0, .layout = &single }, .{ .offset = 8, .layout = &double } } } };
    for ([_]std.builtin.Endian{ .little, .big }) |endian| {
        const region = try storage.acquisitions.acquire(&storage, 16, 8);
        const root = try storage.acquiredReference(region, 0, &layout, endian, .read_write, null);
        var first = root;
        first.path = &.{.{ .field = 0 }};
        var second = root;
        second.path = &.{.{ .field = 1 }};
        try storage.store(first, .{ .float32 = @bitCast(@as(u32, 0x80000000)) });
        try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
        try std.testing.expectError(error.ExecutionInvalidReference, storage.store(root, .{ .record = &.{ .{ .float32 = 42 }, .{ .float32 = 0 } } }));
        try std.testing.expectEqual(@as(u32, 0x80000000), @as(u32, @bitCast((try storage.read(first)).float32)));
        try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(second));
        try storage.store(second, .{ .float64 = @bitCast(@as(u64, 0x7ff8000012345678)) });
        const complete = try storage.read(root);
        try std.testing.expectEqual(@as(u64, 0x7ff8000012345678), @as(u64, @bitCast(complete.record[1].float64)));
        var padding: [1]u8 = undefined;
        try std.testing.expectError(error.ExecutionUninitializedStorage, storage.acquisitions.read(&storage, region, 4, &padding));
        try storage.acquisitions.release(&storage, region);
        try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(first));
    }
}

test "choice tag observation neither materializes vacant siblings nor allocates payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const frame = try storage.enter(1);
    try storage.prepareStorage(frame, 0, .{ .nodes = &.{
        .{ .kind = .record, .first = 1, .count = 2, .span = 3 },
        .{ .offset = 1 },
        .{ .offset = 2 },
    } });
    const reference: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{.{ .field = 0 }}, .mutability = .read_write };
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.choiceTag(reference));
    const payload: b.Value = .erased;
    try storage.store(reference, .{ .choice = .{ .variant = 1, .payload = &payload } });
    const before = storage.cells;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    storage.allocator = failing.allocator();
    try std.testing.expectEqual(@as(u32, 1), try storage.choiceTag(reference));
    try std.testing.expectEqual(before, storage.cells);
    const record = storage.frames.items[@intFromEnum(frame)].partial_storage.getPtr(0).?;
    try std.testing.expect(record.values[0] == null);
    try std.testing.expect(record.values[2] == null);
    var sibling = reference;
    sibling.path = &.{.{ .field = 1 }};
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.choiceTag(sibling));
    storage.leave(frame);
    try std.testing.expectError(error.ExecutionDeadReference, storage.choiceTag(reference));
}

fn failedPartialSnapshot(allocator: std.mem.Allocator, through_slots: bool) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const frame = try storage.enter(1);
    try storage.prepareStorage(frame, 0, .{ .nodes = &.{
        .{ .kind = .array, .first = 1, .count = 2, .span = 5 },
        .{ .kind = .record, .first = 2, .count = 1, .span = 2, .offset = 1 },
        .{ .offset = 1 },
    } });
    const record = storage.frames.items[@intFromEnum(frame)].partial_storage.getPtr(0).?;
    try record.write(&.{ .{ .element = 0 }, .{ .field = 0 } }, .{ .integer = 40 });
    try record.write(&.{ .{ .element = 1 }, .{ .field = 0 } }, .{ .integer = 2 });
    const before = storage.cells;
    const reference: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    storage.allocator = allocator;
    const value = (if (through_slots) (try storage.slots(frame)).get(0) else storage.read(reference)) catch |err| {
        try std.testing.expectEqual(before, storage.cells);
        try std.testing.expect(record.values[0] == null and record.values[1] == null and record.values[3] == null);
        try std.testing.expectEqual(@as(u64, 40), record.values[2].?.integer);
        try std.testing.expectEqual(@as(u64, 2), record.values[4].?.integer);
        return err;
    };
    const backing: []const b.Value = value.array.ptr[0..4];
    defer allocator.free(backing);
    try std.testing.expectEqual(before + 4, storage.cells);
    try std.testing.expectEqual(@as(u64, 40), value.array[0].record[0].integer);
    try std.testing.expectEqual(@as(u64, 2), value.array[1].record[0].integer);
    // Repeated reads reuse the published root snapshot without charging again.
    try std.testing.expect((try storage.read(reference)).array.ptr == value.array.ptr);
    try std.testing.expectEqual(before + 4, storage.cells);
}

test "partial snapshots publish one backing or preserve cells through slots and references" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedPartialSnapshot, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedPartialSnapshot, .{true});
}

test "call buffers reuse cells without reviving retired frame identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 10000);
    const first = try storage.enterCleanup(3, &.{.{ .root = 0, .offset = 0 }});
    const old_slots = try storage.slots(first);
    try old_slots.put(0, .{ .integer = 42 });
    storage.frames.items[@intFromEnum(first)].cleanup_flags[0] = true;
    const reference: v.Reference = .{ .context = storage.context, .frame = first, .root = 0, .path = &.{}, .mutability = .read_write };
    const backing = storage.frames.items[@intFromEnum(first)].values.ptr;
    storage.leave(first);
    const differently_sized = try storage.enter(4);
    const without_cleanup = try storage.enter(3);
    try std.testing.expect(storage.frames.items[@intFromEnum(without_cleanup)].values.ptr != backing);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items[@intFromEnum(without_cleanup)].cleanup_flags.len);
    storage.leave(without_cleanup);
    const second = try storage.enterCleanup(3, &.{.{ .root = 0, .offset = 0 }});
    try std.testing.expect(first != second);
    try std.testing.expect(storage.frames.items[@intFromEnum(second)].values.ptr == backing);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items[@intFromEnum(first)].values.len);
    const new_slots = try storage.slots(second);
    try std.testing.expectError(error.ExecutionUninitializedStorage, new_slots.get(0));
    try std.testing.expectError(error.ExecutionUninitializedStorage, new_slots.get(1));
    try std.testing.expect(!storage.frames.items[@intFromEnum(second)].cleanup_flags[0]);
    try std.testing.expectError(error.ExecutionUninitializedStorage, new_slots.get(2));
    try new_slots.put(0, .{ .integer = 7 });
    try std.testing.expectError(error.ExecutionDeadReference, old_slots.get(0));
    try std.testing.expectError(error.ExecutionDeadReference, storage.read(reference));
    storage.leave(second);
    storage.leave(differently_sized);
    for (0..100) |_| {
        const next = try storage.enterCleanup(3, &.{.{ .root = 0, .offset = 0 }});
        try std.testing.expect(storage.frames.items[@intFromEnum(next)].values.ptr == backing);
        storage.leave(next);
    }
}

test "acquired view publication preserves frames quota and earlier views on allocation failure" {
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = false } } };
    var fail_index: usize = 0;
    while (fail_index < 20) : (fail_index += 1) {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var storage = try Storage.init(arena.allocator(), 10000);
        const handle = try storage.acquisitions.acquire(&storage, 8, 4);
        const first = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, null);
        try storage.store(first, .{ .integer = 42 });
        // Fill the table so the next publication must reserve metadata. Wrap
        // its allocator calls, rather than arena growth, to exercise every step.
        while (storage.acquired_views.count() < storage.acquired_views.capacity() * 80 / 100)
            _ = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, @intCast(storage.acquired_views.count()));
        const frames = storage.frames.items.len;
        const views = storage.acquired_views.count();
        const cells = storage.cells;
        const indexed = storage.acquired_frames.count();
        var failure = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = fail_index });
        storage.allocator = failure.allocator();
        if (storage.acquiredReference(handle, 0, &layout, .little, .read_only, @intCast(views + 1))) |reference| {
            try std.testing.expect(!failure.has_induced_failure);
            try std.testing.expectEqual(@as(u64, 42), (try storage.read(reference)).integer);
            try std.testing.expectEqual(@as(u64, 42), (try storage.read(first)).integer);
            return;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(frames, storage.frames.items.len);
            try std.testing.expectEqual(views, storage.acquired_views.count());
            try std.testing.expectEqual(indexed, storage.acquired_frames.count());
            try std.testing.expectEqual(cells, storage.cells);
            try std.testing.expectEqual(@as(u64, 42), (try storage.read(first)).integer);
        }
    }
    return error.MissingSuccessfulAcquiredViewPublication;
}

test "reference factories roll back unpublished projection quota on allocation failure" {
    const Factory = struct {
        const Kind = enum { address, borrow, offset, bytes, write };
        fn run(storage: *Storage, reference: v.Reference, kind: Kind) !void {
            const word: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = false } } };
            switch (kind) {
                .address => _ = try storage.address(reference, .read_only),
                .borrow => _ = try storage.borrow(reference, .read_only),
                .offset => _ = try storage.offsetReference(reference, 1),
                .bytes => _ = try storage.numericBytes(reference, &word, .little),
                .write => _ = try storage.captureResolvedWrite(reference, false),
            }
        }
    };
    for (std.meta.tags(Factory.Kind)) |kind| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var storage = try Storage.init(arena.allocator(), 1000);
        const frame = try storage.enter(2);
        const slots_ = try storage.slots(frame);
        try slots_.put(0, .{ .record = &.{.{ .integer = 42 }} });
        try slots_.put(1, .{ .array = &.{ .{ .integer = 42 }, .{ .integer = 7 } } });
        const reference: v.Reference = .{ .context = storage.context, .frame = frame, .root = if (kind == .offset) 1 else 0, .path = if (kind == .offset) &.{.{ .element = 0 }} else &.{.{ .field = 0 }}, .mutability = .read_write };
        const cells = storage.cells;
        var failure = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = 0 });
        storage.allocator = failure.allocator();
        try std.testing.expectError(error.OutOfMemory, Factory.run(&storage, reference, kind));
        try std.testing.expectEqual(cells, storage.cells);
        try std.testing.expectEqual(@as(u64, 42), (try storage.read(reference)).integer);
        try std.testing.expectEqual(@as(usize, 1), storage.frames.items.len);
    }
}

test "nested session copies publish complete buffers or preserve destination and quota" {
    for (0..3) |fail_index| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var storage = try Storage.init(arena.allocator(), 10000);
        const target = try storage.enterSession(1, &.{});
        try storage.initializeSession(target, 0, .{ .integer = 7 });
        const origin = try storage.enterSession(1, &.{});
        try storage.initializeSession(origin, 0, .{ .record = &.{.{ .integer = 42 }} });
        const reference: v.Reference = .{ .context = storage.context, .frame = origin.frame, .root = 0, .path = &.{.{ .field = 0 }}, .mutability = .read_only };
        const source: b.Value = .{ .record = &.{.{ .array = &.{.{ .choice = .{ .variant = 0, .payload = &.{ .reference = reference } } }} }} };
        const cells = storage.cells;
        var failure = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = fail_index });
        storage.allocator = failure.allocator();
        if (storage.reinitializeSession(target, 0, source)) |_| {
            try std.testing.expect(!failure.has_induced_failure);
            const retained = (try target.get(0)).record[0].array[0].choice.payload.?.reference;
            try std.testing.expect(retained.path.ptr != reference.path.ptr);
            try std.testing.expectEqual(@as(u64, 42), (try storage.read(retained)).integer);
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(cells, storage.cells);
            try std.testing.expectEqual(@as(u64, 7), (try target.get(0)).integer);
        }
    }
}

test "value copies reject foreign nested references and quota before publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 1000);
    var other = try Storage.init(arena.allocator(), 1000);
    const frame = try other.enter(1);
    const reference: v.Reference = .{ .context = other.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_only };
    const source = &.{b.Value{ .record = &.{.{ .reference = reference }} }};
    const before = storage.cells;
    try std.testing.expectError(error.ExecutionForeignReference, storage.cloneValues(source));
    try std.testing.expectEqual(before, storage.cells);
    storage.limit = 1;
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.cloneValues(&.{.{ .record = &.{.{ .integer = 42 }} }}));
    try std.testing.expectEqual(before, storage.cells);
}

test "cleanup flags cannot be read or overwritten as language values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const frame = try storage.enterCleanup(1, &.{.{ .root = 0, .offset = 0 }});
    const slots_ = try storage.slots(frame);
    const reference: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    try std.testing.expectEqual(@as(usize, 1), storage.frames.items[@intFromEnum(frame)].values.len);
    try std.testing.expectEqual(@as(usize, 1), storage.frames.items[@intFromEnum(frame)].cleanup_flags.len);
    try slots_.put(0, .{ .boolean = true });
    try std.testing.expect(!try storage.cleanupTest(reference));
    _ = try storage.cleanupSet(reference, true);
    try slots_.put(0, .{ .boolean = false });
    try std.testing.expect(try storage.cleanupTest(reference));
    try std.testing.expectError(error.ExecutionInvalidReference, slots_.get(1));
    _ = try storage.cleanupSet(reference, false);
    try std.testing.expect(!(try slots_.get(0)).boolean);
}

test "repeated cleanup uses indexed identities and refreshes nested array ancestors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 1000);
    const leaf: cleanup_layout.Layout = .{};
    const inner = try cleanup_layout.Layout.repeated(@enumFromInt(0), &leaf, 3);
    const outer = try cleanup_layout.Layout.repeated(@enumFromInt(1), &inner, 2);
    const frame = try storage.enterCleanup(1, &.{.{ .root = 0, .layout = &outer }});
    const root: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var first = root;
    first.path = &.{ .{ .element = 0 }, .{ .element = 1 } };
    var sibling = root;
    sibling.path = &.{ .{ .element = 1 }, .{ .element = 1 } };
    _ = try storage.cleanupSet(root, true);
    _ = try storage.cleanupSet(first, false);
    try std.testing.expect(!try storage.cleanupTest(first));
    try std.testing.expect(try storage.cleanupTest(sibling));
    try std.testing.expect(!try storage.cleanupTest(root));
    _ = try storage.cleanupSet(first, true);
    try std.testing.expect(try storage.cleanupTest(root));
    // No initialized value or physical address is needed to identify flags.
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    var outside = root;
    outside.path = &.{.{ .element = 2 }};
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupSet(outside, false));
    try std.testing.expect(try storage.cleanupTest(root));
    _ = try storage.cleanupSet(root, false);
}

test "optional write evidence activates represented cleanup without inventing owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const slots_ = try storage.enterSession(2, &.{.{ .root = 0 }});
    const owner: v.Reference = .{ .context = storage.context, .frame = slots_.frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var ordinary = owner;
    ordinary.root = 1;
    const absent = try storage.captureWriteEvidence(ordinary, true, false);
    try std.testing.expectEqual(@as(usize, 0), try storage.activateWriteCleanup(absent));
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.captureWriteEvidence(ordinary, true, true));
    const present = try storage.captureWriteEvidence(owner, true, false);
    try std.testing.expectEqual(@as(usize, 1), try storage.activateWriteCleanup(present));
    try std.testing.expect(try storage.cleanupTest(owner));
    ordinary.mutability = .read_only;
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.captureWriteEvidence(ordinary, true, false));
}

test "zero-sized acquired slots retain logical indices without granting cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 0, 1);
    const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const first = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, 0);
    const second = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, 1);
    try std.testing.expectEqual(@as(?u64, 0), storage.acquired_views.get(first.frame).?.logical_index);
    try std.testing.expectEqual(@as(?u64, 1), storage.acquired_views.get(second.frame).?.logical_index);
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupTest(first));
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupTest(second));
}

test "reserved acquired cleanup keeps zero-sized owners distinct and borrowing allocation free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 0, 1);
    const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const cleanup: cleanup_layout.Layout = .{ .is_record = true };
    const value_layout: partial.Layout = .{ .nodes = &.{.{}} };
    const first = try storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 0, value_layout, &cleanup);
    const second = try storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 1, value_layout, &cleanup);
    try std.testing.expect(first.frame != second.frame);
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 0, value_layout, &cleanup));
    // Knowing the same address, shape and index does not recover a reservation.
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.acquiredReference(handle, 0, &layout, .little, .read_write, 0));
    const cells = storage.cells;
    const frames = storage.frames.items.len;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    storage.allocator = failing.allocator();
    const a = try storage.borrowAcquiredReservation(first, .read_write);
    const b_ = try storage.borrowAcquiredReservation(second, .read_write);
    try std.testing.expect(!try storage.cleanupTest(a));
    try std.testing.expect(!try storage.cleanupTest(b_));
    _ = try storage.cleanupSet(a, true);
    try std.testing.expect(try storage.cleanupTest(a));
    try std.testing.expect(!try storage.cleanupTest(b_));
    const readonly = try storage.borrowAcquiredReservation(first, .read_only);
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.cleanupSet(readonly, false));
    try std.testing.expectEqual(cells, storage.cells);
    try std.testing.expectEqual(frames, storage.frames.items.len);
    try std.testing.expectEqual(@as(usize, 0), failing.allocations);
    storage.allocator = arena.allocator();
    const captured = try storage.captureResolvedWrite(b_, true);
    try storage.acquisitions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.borrowAcquiredReservation(first, .read_write));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.cleanupTest(a));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.checkWriteCleanup(captured));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.activateWriteCleanup(captured));
}

test "acquired cleanup reservation failures publish neither owners nor charges" {
    var fail_index: usize = 0;
    while (fail_index < 20) : (fail_index += 1) {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var storage = try Storage.init(arena.allocator(), 4096);
        const handle = try storage.acquisitions.acquire(&storage, 0, 1);
        const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
        const cleanup: cleanup_layout.Layout = .{ .is_record = true };
        const value_layout: partial.Layout = .{ .nodes = &.{.{}} };
        const cells = storage.cells;
        var failure = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = fail_index });
        storage.allocator = failure.allocator();
        if (storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 0, value_layout, &cleanup)) |reservation| {
            try std.testing.expect(!failure.has_induced_failure);
            const reference = try storage.borrowAcquiredReservation(reservation, .read_write);
            try std.testing.expect(!try storage.cleanupTest(reference));
            return;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(cells, storage.cells);
            try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
            try std.testing.expectEqual(@as(u32, 0), storage.acquired_views.count());
            try std.testing.expectEqual(@as(u32, 0), storage.acquired_frames.count());
        }
    }
    return error.MissingSuccessfulAcquiredReservationReservation;
}

test "reserved acquired cleanup projects partial owners independently of byte offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 0, 1);
    const leaf: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{
        .{ .offset = 0, .layout = &leaf },
        .{ .offset = 0, .layout = &leaf },
    } } };
    const leaf_cleanup: cleanup_layout.Layout = .{ .is_record = true };
    const cleanup: cleanup_layout.Layout = .{ .count = 3, .is_record = true, .children = &.{
        .{ .offset = 1, .ty = @enumFromInt(0), .layout = &leaf_cleanup },
        .{ .offset = 2, .ty = @enumFromInt(0), .layout = &leaf_cleanup },
    } };
    const value_layout: partial.Layout = .{ .nodes = &.{
        .{ .kind = .record, .first = 1, .count = 2, .span = 3 },
        .{ .offset = 1 },
        .{ .offset = 2 },
    } };
    const reservation = try storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 0, value_layout, &cleanup);
    const root = try storage.borrowAcquiredReservation(reservation, .read_write);
    var first = root;
    first.path = &.{.{ .field = 0 }};
    var second = root;
    second.path = &.{.{ .field = 1 }};
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    // Cleanup flags never establish the value's independent occupancy proof.
    _ = try storage.cleanupSet(root, true);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    _ = try storage.cleanupSet(root, false);
    const destination = try storage.captureResolvedWrite(first, true);
    _ = try storage.checkWriteCleanup(destination);
    try storage.write(destination, .{ .record = &.{} });
    _ = try storage.activateWriteCleanup(destination);
    try std.testing.expect(!try storage.cleanupTest(root));
    try std.testing.expect(try storage.cleanupTest(first));
    try std.testing.expect(!try storage.cleanupTest(second));
    try std.testing.expectEqual(@as(usize, 0), (try storage.read(first)).record.len);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(second));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    try storage.store(second, .{ .record = &.{} });
    _ = try storage.cleanupSet(second, true);
    try std.testing.expectEqual(@as(usize, 2), (try storage.read(root)).record.len);
    try std.testing.expect(try storage.cleanupTest(root));
    _ = try storage.cleanupSet(first, false);
    try std.testing.expect(!try storage.cleanupTest(root));
    try std.testing.expect(try storage.cleanupTest(second));
}

test "reserved acquired values separate occupancy from live numeric bytes and cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 8, 4);
    const integer: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const layout: numeric.Layout = .{ .size = 8, .alignment = 4, .shape = .{ .fields = &.{
        .{ .offset = 0, .layout = &integer },
        .{ .offset = 4, .layout = &integer },
    } } };
    const leaf_cleanup: cleanup_layout.Layout = .{};
    const cleanup: cleanup_layout.Layout = .{ .count = 3, .is_record = true, .children = &.{
        .{ .offset = 1, .ty = @enumFromInt(0), .layout = &leaf_cleanup },
        .{ .offset = 2, .ty = @enumFromInt(0), .layout = &leaf_cleanup },
    } };
    const value_layout: partial.Layout = .{ .nodes = &.{
        .{ .kind = .record, .first = 1, .count = 2, .span = 3 },
        .{ .offset = 1 },
        .{ .offset = 2 },
    } };
    const reservation = try storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 0, value_layout, &cleanup);
    const root = try storage.borrowAcquiredReservation(reservation, .read_write);
    var first = root;
    first.path = &.{.{ .field = 0 }};
    var second = root;
    second.path = &.{.{ .field = 1 }};
    try storage.store(first, .{ .integer = 20 });
    try std.testing.expectError(error.ExecutionInvalidReference, storage.store(root, .{ .record = &.{ .{ .integer = 99 }, .{ .boolean = true } } }));
    try std.testing.expectEqual(@as(u64, 20), (try storage.read(first)).integer);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(second));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    try storage.store(second, .{ .integer = 22 });
    try std.testing.expect(!try storage.cleanupTest(root));
    // Raw byte edits change live numeric data, never the retained occupancy
    // proof. Reads must not return stale numbers cached in that proof's tree.
    const byte: numeric.Layout = .{ .size = 1, .alignment = 1, .shape = .{ .integer = .{ .signed = false } } };
    const alias = try storage.acquiredReference(handle, 0, &byte, .little, .read_write, null);
    try storage.store(alias, .{ .integer = 21 });
    const value = try storage.read(root);
    try std.testing.expectEqual(@as(u64, 21), value.record[0].integer);
    try std.testing.expectEqual(@as(u64, 22), value.record[1].integer);
    const cells = storage.cells;
    const frames = storage.frames.items.len;
    try std.testing.expectError(error.ExecutionInvalidReference, storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 1, .{ .nodes = &.{.{}} }, &cleanup));
    try std.testing.expectEqual(cells, storage.cells);
    try std.testing.expectEqual(frames, storage.frames.items.len);
}

test "reserved acquired arrays share templates and retain zero-sized element occupancy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 0, 1);
    const leaf: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .array = .{ .element = &leaf, .length = 1000, .stride = 0 } } };
    const leaf_cleanup: cleanup_layout.Layout = .{ .is_record = true };
    const cleanup = try cleanup_layout.Layout.repeated(@enumFromInt(0), &leaf_cleanup, 1000);
    const value_layout: partial.Layout = .{ .nodes = &.{
        .{ .kind = .array, .first = 1, .count = 1000, .span = 1001 },
        .{ .offset = 1 },
    } };
    const reservation = try storage.reserveAcquiredCleanup(handle, 0, &layout, .little, 0, value_layout, &cleanup);
    const root = try storage.borrowAcquiredReservation(reservation, .read_write);
    var first = root;
    first.path = &.{.{ .element = 0 }};
    var last = root;
    last.path = &.{.{ .element = 999 }};
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(first));
    try storage.store(first, .{ .record = &.{} });
    try storage.store(last, .{ .record = &.{} });
    try std.testing.expectEqual(@as(usize, 0), (try storage.read(last)).record.len);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(root));
    _ = try storage.cleanupSet(first, true);
    try std.testing.expect(!try storage.cleanupTest(last));
    try std.testing.expect(!try storage.cleanupTest(root));
    const retained = (try storage.acquiredValues(root)).?;
    try std.testing.expectEqual(@as(usize, 2), retained.layout.nodes.len);
    try std.testing.expectEqual(@as(usize, 1001), retained.values.len);
}

test "acquired reservation batches borrow indexed owners without allocating or reading values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 0, 1);
    const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const cleanup: cleanup_layout.Layout = .{ .is_record = true };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const reservation = try storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 0, logical, &cleanup, 1000);
    try std.testing.expectEqual(@as(usize, 1), storage.frames.items.len);
    try std.testing.expectEqual(@as(u32, 1), storage.acquired_views.count());
    try std.testing.expectEqual(@as(usize, 1), storage.frames.items[0].cleanup.len);
    try std.testing.expectEqual(@as(usize, 1000), storage.frames.items[0].cleanup_flags.len);
    try std.testing.expectEqual(@as(usize, 1000), storage.frames.items[0].values.len);
    try std.testing.expectEqual(@as(u32, 0), storage.frames.items[0].partial_storage.count());
    const cells = storage.cells;
    var failure = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = 0 });
    storage.allocator = failure.allocator();
    const first = try storage.borrowAcquiredElement(reservation, 0, .read_write);
    const last = try storage.borrowAcquiredElement(reservation, 999, .read_write);
    const offset = try storage.offsetReference(first, 999);
    try std.testing.expectEqual(last.frame, offset.frame);
    try std.testing.expectEqual(last.root, offset.root);
    try std.testing.expectEqual(@as(usize, 0), offset.path.len);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.borrowAcquiredElement(reservation, 1000, .read_write));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.offsetReference(first, 1000));
    try std.testing.expectEqual(@as(usize, 0), failure.allocations);
    try std.testing.expectEqual(cells, storage.cells);
    storage.allocator = arena.allocator();
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(last));
    try storage.store(first, .{ .record = &.{} });
    _ = try storage.cleanupSet(first, true);
    try std.testing.expect(!try storage.cleanupTest(last));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(last));
    try storage.store(last, .{ .record = &.{} });
    const copied = try storage.cloneValues(&.{.{ .reference = last }});
    try std.testing.expectEqual(last.root, copied[0].reference.root);
    _ = try storage.cleanupSet(copied[0].reference, true);
    _ = try storage.cleanupSet(first, false);
    try std.testing.expect(try storage.cleanupTest(last));
    const slots_ = try storage.slots(last.frame);
    try std.testing.expectError(error.ExecutionInvalidReference, slots_.get(last.root));
    try std.testing.expectError(error.ExecutionInvalidReference, slots_.put(last.root, .unit));
    try storage.acquisitions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.borrowAcquiredElement(reservation, 999, .read_write));
}

test "empty acquired batches and oversized reservations publish no usable owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 20);
    const handle = try storage.acquisitions.acquire(&storage, 0, 1);
    const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const cleanup: cleanup_layout.Layout = .{ .is_record = true };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const empty = try storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 0, logical, &cleanup, 0);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.borrowAcquiredReservation(empty, .read_write));
    const cells = storage.cells;
    const frames = storage.frames.items.len;
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 0, logical, &cleanup, 1000));
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, std.math.maxInt(u64), logical, &cleanup, 2));
    try std.testing.expectEqual(cells, storage.cells);
    try std.testing.expectEqual(frames, storage.frames.items.len);
    try std.testing.expectEqual(@as(u32, 1), storage.acquired_views.count());
}

test "acquired batch projections use independent value and cleanup strides" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 16, 4);
    const integer: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .fields = &.{.{ .offset = 0, .layout = &integer }} } };
    const leaf_cleanup: cleanup_layout.Layout = .{};
    const cleanup: cleanup_layout.Layout = .{ .count = 2, .is_record = true, .children = &.{.{ .offset = 1, .ty = @enumFromInt(0), .layout = &leaf_cleanup }} };
    const logical: partial.Layout = .{ .nodes = &.{
        .{ .kind = .record, .first = 1, .count = 1, .span = 2 },
        .{ .offset = 1 },
    } };
    const reservation = try storage.reserveAcquiredCleanupBatch(handle, 4, &layout, .little, 0, logical, &cleanup, 3);
    const first = try storage.borrowAcquiredElement(reservation, 0, .read_write);
    const last = try storage.borrowAcquiredElement(reservation, 2, .read_write);
    var field = last;
    field.path = &.{.{ .field = 0 }};
    const destination = try storage.captureResolvedWrite(field, true);
    _ = try storage.checkWriteCleanup(destination);
    try storage.write(destination, .{ .integer = 42 });
    _ = try storage.activateWriteCleanup(destination);
    try std.testing.expectEqual(@as(i128, 42), try storage.acquisitions.loadInteger(&storage, handle, 12, &integer, .little));
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(last)).record[0].integer);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(first));
    try std.testing.expect(!try storage.cleanupTest(first));
    try std.testing.expect(try storage.cleanupTest(last));
    try std.testing.expectEqualSlices(bool, &.{ false, false, false, false, true, true }, storage.frames.items[@intFromEnum(first.frame)].cleanup_flags);
}

test "acquired numeric byte offsets do not materialize snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 8, 4);
    const integer: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const layout: numeric.Layout = .{ .size = 8, .alignment = 4, .shape = .{ .fields = &.{
        .{ .offset = 0, .layout = &integer },
        .{ .offset = 4, .layout = &integer },
    } } };
    const reference = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, null);
    try storage.store(reference, .{ .record = &.{ .{ .integer = 20 }, .{ .integer = 22 } } });
    const bytes = try storage.numericBytes(reference, &layout, .little);
    const cells = storage.cells;
    var failure = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = 0 });
    storage.allocator = failure.allocator();
    const last = try storage.offsetReference(bytes, 7);
    try std.testing.expectEqual(@as(usize, 7), last.byte_view.?.offset);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.offsetReference(bytes, 8));
    try std.testing.expectEqual(@as(usize, 0), failure.allocations);
    try std.testing.expectEqual(cells, storage.cells);
}

test "acquired views reuse equivalent descriptors across compilation units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 4, 4);
    const first_layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const second_layout = first_layout;
    const first = try storage.acquiredReference(handle, 0, &first_layout, .little, .read_write, 0);
    const second = try storage.acquiredReference(handle, 0, &second_layout, .little, .read_only, 0);
    try std.testing.expectEqual(first.frame, second.frame);
    try std.testing.expectEqual(p.PointerMutability.read_only, second.mutability);
    try storage.store(first, .{ .integer = 42 });
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(second)).integer);
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupTest(second));
    // Matching size/alignment alone cannot equate different interpretations.
    const unsigned_layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = false } } };
    const unsigned = try storage.acquiredReference(handle, 0, &unsigned_layout, .little, .read_only, 0);
    try std.testing.expect(unsigned.frame != first.frame);
    const first_record: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .fields = &.{.{ .offset = 0, .layout = &first_layout }} } };
    const second_record: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .fields = &.{.{ .offset = 0, .layout = &second_layout }} } };
    const record = try storage.acquiredReference(handle, 0, &first_record, .little, .read_write, 0);
    const record_alias = try storage.acquiredReference(handle, 0, &second_record, .little, .read_only, 0);
    try std.testing.expectEqual(record.frame, record_alias.frame);
    try std.testing.expect(record.frame != first.frame);
    try storage.acquisitions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(second));
}

test "relocation transfers represented cleanup and accepts slots without automatic obligations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const slots_ = try storage.enterSession(3, &.{ .{ .root = 0, .offset = 0 }, .{ .root = 1, .offset = 1 } });
    try storage.prepareStorage(slots_.frame, 1, .{ .nodes = &.{.{}} });
    try slots_.put(0, .{ .integer = 42 });
    try slots_.put(2, .{ .integer = 7 });
    const source: v.Reference = .{ .context = storage.context, .frame = slots_.frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var destination = source;
    destination.root = 1;
    var plain = source;
    plain.root = 2;
    _ = try storage.cleanupSet(source, true);
    _ = try storage.relocate(source, destination);
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(destination)).integer);
    try std.testing.expect(!try storage.cleanupTest(source));
    try std.testing.expect(try storage.cleanupTest(destination));
    _ = try storage.relocate(plain, source);
    try std.testing.expectEqual(@as(u64, 7), (try storage.read(source)).integer);
    try std.testing.expect(try storage.cleanupTest(source));
    try std.testing.expectError(error.ExecutionPendingCleanup, storage.relocate(source, destination));
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(destination)).integer);
    var readonly = source;
    readonly.mutability = .read_only;
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.relocate(readonly, plain));
}

test "relocation keeps zero-sized sibling cleanup identities distinct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const element: cleanup_layout.Layout = .{};
    const shape = try cleanup_layout.Layout.repeated(@enumFromInt(0), &element, 2);
    const slots_ = try storage.enterSession(1, &.{.{ .root = 0, .layout = &shape }});
    try slots_.put(0, .{ .array = &.{ .unit, .unit } });
    const source: v.Reference = .{ .context = storage.context, .frame = slots_.frame, .root = 0, .path = &.{.{ .element = 0 }}, .mutability = .read_write };
    var destination = source;
    destination.path = &.{.{ .element = 1 }};
    _ = try storage.cleanupSet(source, true);
    _ = try storage.relocate(source, destination);
    try std.testing.expectEqualSlices(bool, &.{ false, false, true }, storage.frames.items[@intFromEnum(slots_.frame)].cleanup_flags);
}

test "repeated acquired references retain one exact view without widening permissions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100000);
    const handle = try storage.acquisitions.acquire(&storage, 8, 4);
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const first = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, 0);
    try storage.store(first, .{ .integer = 42 });
    const frames = storage.frames.items.len;
    const cells = storage.cells;
    for (0..1000) |_| {
        const alias = try storage.acquiredReference(handle, 0, &layout, .little, .read_only, 0);
        try std.testing.expectEqual(@as(u64, 42), (try storage.read(alias)).integer);
        try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(alias, .{ .integer = 7 }));
    }
    try std.testing.expectEqual(frames, storage.frames.items.len);
    try std.testing.expectEqual(cells, storage.cells);
    const raw = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, null);
    try std.testing.expect(raw.frame != first.frame);
    const sibling = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, 1);
    try std.testing.expect(sibling.frame != first.frame);
    const swapped = try storage.acquiredReference(handle, 0, &layout, .big, .read_write, 0);
    try std.testing.expect(swapped.frame != first.frame);
    const other = try storage.acquiredReference(handle, 4, &layout, .little, .read_write, 1);
    try std.testing.expect(other.frame != first.frame);
    try storage.acquisitions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.acquiredReference(handle, 0, &layout, .little, .read_only, 0));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(first));
}

test "acquired cleanup reservations reject intersecting logical and physical owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 24, 4);
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const cleanup: cleanup_layout.Layout = .{};
    _ = try storage.reserveAcquiredCleanupBatch(handle, 4, &layout, .little, 10, logical, &cleanup, 3);
    const cells = storage.cells;
    const frames = storage.frames.items.len;
    var failing = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = 0 });
    storage.allocator = failing.allocator();
    // Partial containment, encompassing batches and aliases with a different
    // logical index must not create another set of obligations for live bytes.
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanupBatch(handle, 8, &layout, .little, 11, logical, &cleanup, 2));
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 9, logical, &cleanup, 5));
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanupBatch(handle, 8, &layout, .little, 100, logical, &cleanup, 1));
    // Even disjoint physical bytes cannot redefine an existing logical slot.
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanupBatch(handle, 20, &layout, .little, 11, logical, &cleanup, 1));
    try std.testing.expectEqual(cells, storage.cells);
    try std.testing.expectEqual(frames, storage.frames.items.len);
    try std.testing.expectEqual(@as(usize, 0), failing.allocations);
    storage.allocator = arena.allocator();
    _ = try storage.reserveAcquiredCleanupBatch(handle, 16, &layout, .little, 13, logical, &cleanup, 2);
}

test "zero-sized cleanup batches intersect by logical index rather than address" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 0, 1);
    const layout: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const cleanup: cleanup_layout.Layout = .{ .is_record = true };
    _ = try storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 10, logical, &cleanup, 3);
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 11, logical, &cleanup, 1));
    const next = try storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 13, logical, &cleanup, 1);
    _ = try storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, std.math.maxInt(u64), logical, &cleanup, 1);
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, std.math.maxInt(u64) - 1, logical, &cleanup, 2));
    const last = try storage.borrowAcquiredReservation(next, .read_write);
    try storage.store(last, .{ .record = &.{} });
    _ = try storage.cleanupSet(last, true);
    try std.testing.expect(try storage.cleanupTest(last));
}

test "acquired cleanup reservation cannot upgrade a previously published numeric alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 4, 4);
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const cleanup: cleanup_layout.Layout = .{};
    const previous = try storage.acquiredReference(handle, 0, &layout, .little, .read_write, null);
    const frames = storage.frames.items.len;
    const cells = storage.cells;
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredCleanupBatch(handle, 0, &layout, .little, 0, logical, &cleanup, 1));
    try std.testing.expectEqual(cells, storage.cells);
    try std.testing.expectEqual(frames, storage.frames.items.len);
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupTest(previous));
}

test "counted acquired numeric views advance through vacant elements without snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 16, 4);
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const first = try storage.acquiredReferenceBatch(handle, 4, &layout, .little, .read_write, 1, 3);
    const cells = storage.cells;
    var failing = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = 0 });
    storage.allocator = failing.allocator();
    const last = try storage.offsetReference(first, 2);
    try std.testing.expectEqual(@as(b.Slot, 2), last.root);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(last));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.offsetReference(first, 3));
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupTest(last));
    try std.testing.expectEqual(cells, storage.cells);
    try std.testing.expectEqual(@as(usize, 0), failing.allocations);
    storage.allocator = arena.allocator();
    try storage.store(last, .{ .integer = 42 });
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(last)).integer);
    try std.testing.expectEqual(@as(i128, 42), try storage.acquisitions.loadInteger(&storage, handle, 12, &layout, .little));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(first));
    try storage.acquisitions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(last));
}

test "distinct acquired receipts retain independent zero-sized slot namespaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 16, 8);
    const physical: numeric.Layout = .{ .size = 0, .alignment = 1, .shape = .{ .fields = &.{} } };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const cleanup: cleanup_layout.Layout = .{ .is_record = true };
    const first = try storage.reserveAcquiredReceipt(handle, 8, &physical, .little, logical, &cleanup, 2, 0);
    const second = try storage.reserveAcquiredReceipt(handle, 16, &physical, .little, logical, &cleanup, 2, 8);
    try std.testing.expect(first.frame != second.frame);
    const left = try storage.borrowAcquiredElement(first, 0, .read_write);
    const right = try storage.borrowAcquiredElement(second, 0, .read_write);
    try storage.store(left, .{ .record = &.{} });
    _ = try storage.cleanupSet(left, true);
    try std.testing.expect(!try storage.cleanupTest(right));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(right));
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.reserveAcquiredReceipt(handle, 8, &physical, .little, logical, &cleanup, 1, 0));
    try std.testing.expectError(error.ExecutionInvalidReference, storage.reserveAcquiredReceipt(handle, 8, &physical, .little, logical, &cleanup, 1, 9));
}

test "prepared acquired references retain siblings and revoke only physically overwritten evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const caller = try storage.enter(2);
    const slots_ = try storage.slots(caller);
    try slots_.put(0, .{ .integer = 11 });
    try slots_.put(1, .{ .integer = 31 });
    const left: v.Reference = .{ .context = storage.context, .frame = caller, .root = 0, .path = &.{}, .mutability = .read_write };
    const right: v.Reference = .{ .context = storage.context, .frame = caller, .root = 1, .path = &.{}, .mutability = .read_only };
    const pointer: numeric.Layout = .{ .size = 8, .alignment = 8, .has_references = true, .shape = .{ .reference = .read_only } };
    const number: numeric.Layout = .{ .size = 8, .alignment = 8, .shape = .{ .integer = .{ .signed = false } } };
    const physical: numeric.Layout = .{ .size = 24, .alignment = 8, .has_references = true, .shape = .{ .fields = &.{ .{ .offset = 0, .layout = &pointer }, .{ .offset = 8, .layout = &pointer }, .{ .offset = 16, .layout = &number } } } };
    const logical: partial.Layout = .{ .nodes = &.{ .{ .kind = .record, .first = 1, .count = 3, .span = 4 }, .{ .offset = 1 }, .{ .offset = 2 }, .{ .offset = 3 } } };
    const handle = try storage.acquisitions.acquire(&storage, 80, 8);
    const prepared = try storage.reserveAcquiredReceipt(handle, 32, &physical, .little, logical, null, 2, 0);
    const first = try storage.borrowAcquiredElement(prepared, 0, .read_write);
    const second = try storage.borrowAcquiredElement(prepared, 1, .read_write);
    const value: b.Value = .{ .record = &.{ .{ .reference = left }, .{ .reference = right }, .{ .integer = 5 } } };
    try storage.store(first, value);
    try storage.store(second, value);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items[@intFromEnum(prepared.frame)].cleanup_flags.len);
    try std.testing.expectError(error.ExecutionInvalidReference, storage.store(first, .{ .record = &.{ .{ .reference = right }, .{ .integer = 0 }, .{ .integer = 99 } } }));
    const snapshot = try storage.read(first);
    try std.testing.expectEqual(@as(u64, 11), (try storage.read(snapshot.record[0].reference)).integer);
    try std.testing.expectEqual(p.PointerMutability.read_only, snapshot.record[0].reference.mutability);
    var field = first;
    field.path = &.{.{ .field = 0 }};
    try storage.acquisitions.write(&storage, handle, 32, &.{0});
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(field));
    field.path = &.{.{ .field = 1 }};
    try std.testing.expectEqual(@as(u64, 31), (try storage.read((try storage.read(field)).reference)).integer);
    try storage.acquisitions.write(&storage, handle, 48, &.{9});
    try std.testing.expectEqual(@as(u64, 31), (try storage.read((try storage.read(field)).reference)).integer);
    field.path = &.{.{ .field = 2 }};
    try std.testing.expectEqual(@as(u64, 9), (try storage.read(field)).integer);
    try std.testing.expectEqual(@as(u64, 5), (try storage.read(second)).record[2].integer);
    field.path = &.{.{ .field = 0 }};
    try storage.store(field, .{ .reference = left });
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.acquisitions.requireInitialized(&storage, handle, 32, 1));
    try std.testing.expectEqual(@as(u64, 11), (try storage.read((try storage.read(field)).reference)).integer);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.write(&storage, handle, 79, &.{ 0, 0 }));
    try std.testing.expectEqual(@as(u64, 11), (try storage.read((try storage.read(field)).reference)).integer);
    try storage.acquisitions.write(&storage, handle, 33, &.{0});
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(field));
    // An earlier value copy keeps its original reference; revocation belongs
    // to the overwritten storage slot, not to the pointee or immutable copies.
    try std.testing.expectEqual(@as(u64, 11), (try storage.read(snapshot.record[0].reference)).integer);
    try storage.acquisitions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.read(second));
}

test "prepared acquired virtual values retain one selected witness and invalidate both physical words" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4096);
    const frame = try storage.enter(1);
    try (try storage.slots(frame)).put(0, .{ .integer = 42 });
    const receiver: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_only };
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    const program: b.Program = .{ .graph = &graph, .functions = &.{} };
    const table: b.VirtualTable = .{ .virtual_type = @enumFromInt(0), .concrete_type = @enumFromInt(0), .methods = &.{} };
    const value = try storage.virtualize(receiver, &program, &table);
    const physical: numeric.Layout = .{ .size = 16, .alignment = 8, .has_references = true, .shape = .virtual_reference };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const handle = try storage.acquisitions.acquire(&storage, 80, 8);
    const prepared = try storage.reserveAcquiredReceipt(handle, 64, &physical, .little, logical, null, 1, 0);
    const slot = try storage.borrowAcquiredElement(prepared, 0, .read_write);
    try storage.store(slot, value);
    const before = storage.cells;
    const retained = try storage.read(slot);
    try std.testing.expectEqual(before, storage.cells);
    try std.testing.expect(retained.virtual_ == value.virtual_);
    try std.testing.expect(retained.virtual_.table == &table);
    try std.testing.expect(retained.virtual_.program.graph == &graph);
    try std.testing.expectError(error.ExecutionInvalidReference, storage.store(slot, .{ .reference = receiver }));
    try std.testing.expect((try storage.read(slot)).virtual_ == value.virtual_);
    try storage.acquisitions.write(&storage, handle, 64, &.{0});
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(slot));
    try storage.store(slot, value);
    try storage.acquisitions.write(&storage, handle, 72, &.{0});
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(slot));
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(retained.virtual_.receiver)).integer);
    storage.leave(frame);
    try std.testing.expectError(error.ExecutionDeadReference, storage.store(slot, retained));
}

test "prepared acquired mutable references preserve permission without upgrading readonly values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 1024);
    const frame = try storage.enter(1);
    try (try storage.slots(frame)).put(0, .{ .integer = 7 });
    const mutable: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var readonly = mutable;
    readonly.mutability = .read_only;
    const physical: numeric.Layout = .{ .size = 8, .alignment = 8, .has_references = true, .shape = .{ .reference = .read_write } };
    const logical: partial.Layout = .{ .nodes = &.{.{}} };
    const handle = try storage.acquisitions.acquire(&storage, 72, 8);
    const prepared = try storage.reserveAcquiredReceipt(handle, 64, &physical, .little, logical, null, 1, 0);
    const slot = try storage.borrowAcquiredElement(prepared, 0, .read_write);
    try std.testing.expectError(error.ExecutionInvalidReference, storage.store(slot, .{ .reference = readonly }));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(slot));
    try storage.store(slot, .{ .reference = mutable });
    const retained = (try storage.read(slot)).reference;
    try storage.store(retained, .{ .integer = 42 });
    try std.testing.expectEqual(@as(u64, 42), (try storage.read(mutable)).integer);
    try std.testing.expectError(error.ExecutionInvalidReference, storage.numericBytes(slot, &physical, .little));
}

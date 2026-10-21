const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const v = @import("../5_codegen/bytecode/value.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const acquired = @import("acquisitions.zig");
const numeric = @import("../5_codegen/bytecode/numeric_layout.zig");
const partial = @import("partial_storage.zig");

const Frame = struct {
    values: []?b.Value,
    partial_storage: std.AutoHashMapUnmanaged(b.Slot, partial.Storage) = .empty,
    cleanup: []const b.Cleanup = &.{},
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
        return self.storage.frameValues(self.frame);
    }
};

var next_context = std.atomic.Value(u64).init(0);

// Captured executor access, never a language value or a safe-reference factory.
pub const WriteDestination = struct {
    reference: v.Reference,
    // Index in this target frame's immutable compiler-selected layout. This
    // belongs to the referent, never to the local slot holding a reference.
    cleanup_entry: ?usize,
    require_cleanup: bool = true,
};

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
    reusable_frames: std.AutoHashMapUnmanaged(usize, ?v.FrameId) = .empty,
    acquisitions: acquired.Regions = .{},
    acquired_views: std.AutoHashMapUnmanaged(v.FrameId, AcquiredView) = .empty,

    const AcquiredView = struct {
        handle: acquired.Handle,
        offset: usize,
        layout: *const numeric.Layout,
        endian: std.builtin.Endian,
    };

    /// Execution-side establishment only. Checked bytecode must separately
    /// provide the language authorization; a handle or integer is not that proof.
    /// Layout metadata must outlive this storage, like other compiled layouts.
    pub fn acquiredReference(self: *Storage, handle: acquired.Handle, offset: usize, layout: *const numeric.Layout, endian: std.builtin.Endian, permission: p.PointerMutability) !v.Reference {
        if (layout.alignment == 0 or !std.math.isPowerOfTwo(layout.alignment)) return error.ExecutionInvalidReference;
        _ = try self.acquisitions.range(self, handle, offset, layout.size, layout.alignment);
        // Reserve the descriptor before publishing its storage identity. Once
        // enter succeeds, publication cannot fail or leave an orphaned frame.
        try self.acquired_views.ensureUnusedCapacity(self.allocator, 1);
        const frame = try self.enter(1);
        self.acquired_views.putAssumeCapacityNoClobber(frame, .{ .handle = handle, .offset = offset, .layout = layout, .endian = endian });
        self.frames.items[@intFromEnum(frame)].duration = .acquired;
        return .{ .context = self.context, .frame = frame, .root = 0, .path = &.{}, .mutability = permission };
    }

    fn acquiredView(self: *Storage, reference: v.Reference) !?AcquiredView {
        _ = try self.frameValues(reference.frame);
        if (self.frames.items[@intFromEnum(reference.frame)].duration != .acquired) return null;
        var view = self.acquired_views.get(reference.frame) orelse return error.ExecutionInvalidReference;
        if (reference.root != 0) return error.ExecutionInvalidReference;
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
        for (self.frames.items[@intFromEnum(frame)].cleanup) |entry|
            if (entry.root == root and ((try slots_.get(entry.flag)).boolean or (if (entry.presence) |flag| (try slots_.get(flag)).boolean else false))) return error.ExecutionPendingCleanup;
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
        var metadata_cells = cleanup.len;
        for (cleanup) |entry| {
            if (entry.root >= count or entry.flag >= count or entry.root == entry.flag) return error.ExecutionInvalidReference;
            if (entry.presence) |flag| if (flag >= count or flag == entry.root or flag == entry.flag) return error.ExecutionInvalidReference;
            metadata_cells = std.math.add(usize, metadata_cells, entry.path.len) catch return error.ExecutionMemoryLimit;
        }
        const frame_cells = std.math.add(usize, count, 1) catch return error.ExecutionMemoryLimit;
        const total_cells = std.math.add(usize, metadata_cells, frame_cells) catch return error.ExecutionMemoryLimit;
        if (total_cells > self.limit -| self.cells) return error.ExecutionMemoryLimit;
        try self.charge(metadata_cells);
        errdefer self.cells -= metadata_cells;
        const retained = try self.allocator.alloc(b.Cleanup, cleanup.len);
        var copied: usize = 0;
        errdefer {
            for (retained[0..copied]) |entry| self.allocator.free(entry.path);
            self.allocator.free(retained);
        }
        for (retained, cleanup) |*out, entry| {
            out.* = entry;
            out.path = try self.allocator.dupe(v.Projection, entry.path);
            copied += 1;
        }
        const frame = try self.enterCleanup(count, retained);
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
        for (self.frames.items[@intFromEnum(target.frame)].cleanup) |entry|
            if (entry.flag == index or entry.presence == index) return error.ExecutionInvalidReference;
        if (values[index] != null and !reinitialize) return error.ExecutionInitializedStorage;
        for (self.frames.items[@intFromEnum(target.frame)].cleanup) |entry| {
            if (entry.root == index and ((try target.get(entry.flag)).boolean or (if (entry.presence) |flag| (try target.get(flag)).boolean else false))) return error.ExecutionPendingCleanup;
        }
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
        _ = try self.read(reference);
        if (reference.byte_view) |view| {
            const amount = std.math.cast(usize, elements) orelse return error.ExecutionIndexOutOfBounds;
            var result = reference;
            result.byte_view.?.offset = std.math.add(usize, view.offset, amount) catch return error.ExecutionIndexOutOfBounds;
            _ = try self.read(result);
            return result;
        }
        if (elements < 0) return error.ExecutionIndexOutOfBounds;
        if (elements == 0) return reference;
        if (reference.path.len == 0 or reference.path[reference.path.len - 1] != .element) return error.ExecutionIndexOutOfBounds;
        const offset = std.math.cast(usize, elements) orelse return error.ExecutionIndexOutOfBounds;
        const index = std.math.add(usize, reference.path[reference.path.len - 1].element, offset) catch return error.ExecutionIndexOutOfBounds;
        if (reference.path.len > path.len) return error.ExecutionInvalidReference;
        @memcpy(path[0..reference.path.len], reference.path);
        path[reference.path.len - 1] = .{ .element = index };
        var result = reference;
        result.path = path[0..reference.path.len];
        _ = try self.read(result);
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
        if (elements == 0 or result.byte_view != null) return result;
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
        const values = try target.cells();
        const frame = &self.frames.items[@intFromEnum(target.frame)];
        if (frame.duration != .session) return error.ExecutionInvalidReference;
        for (frame.cleanup) |entry|
            if (values[entry.flag].?.boolean or (if (entry.presence) |flag| values[flag].?.boolean else false)) return error.ExecutionActiveCleanup;
        frame.alive = false;
    }

    pub fn enter(self: *Storage, count: usize) !v.FrameId {
        return self.enterCleanup(count, &.{});
    }
    pub fn enterCleanup(self: *Storage, count: usize, cleanup: []const b.Cleanup) !v.FrameId {
        if (self.frames.items.len >= std.math.maxInt(u32)) return error.ExecutionMemoryLimit;
        for (cleanup) |entry|
            if (entry.root >= count or entry.flag >= count or entry.root == entry.flag) return error.ExecutionInvalidReference;
        for (cleanup) |entry| if (entry.presence) |flag| if (flag >= count or flag == entry.root or flag == entry.flag) return error.ExecutionInvalidReference;
        // Bound zero-slot frames too, but publish neither quota nor identity
        // until all frame storage and metadata allocations have succeeded.
        const charge_count = std.math.add(usize, count, 1) catch return error.ExecutionMemoryLimit;
        try self.charge(charge_count);
        errdefer self.cells -= charge_count;
        try self.frames.ensureUnusedCapacity(self.allocator, 1);
        const bin = try self.reusable_frames.getOrPut(self.allocator, count);
        if (!bin.found_existing) bin.value_ptr.* = null;
        const values = if (bin.value_ptr.*) |previous| reused: {
            const retired = &self.frames.items[@intFromEnum(previous)];
            std.debug.assert(!retired.alive and retired.duration == .call);
            const buffer = retired.values;
            bin.value_ptr.* = retired.reusable_next;
            retired.values = &.{};
            retired.reusable_next = null;
            break :reused buffer;
        } else try self.allocator.alloc(?b.Value, count);
        @memset(values, null);
        for (cleanup) |entry| {
            values[entry.flag] = .{ .boolean = false };
            if (entry.presence) |flag| values[flag] = .{ .boolean = false };
        }
        const id: v.FrameId = @enumFromInt(self.frames.items.len);
        self.frames.appendAssumeCapacity(.{ .values = values, .cleanup = cleanup });
        return id;
    }
    pub fn leave(self: *Storage, id: v.FrameId) void {
        const frame = &self.frames.items[@intFromEnum(id)];
        std.debug.assert(frame.duration == .call);
        if (!frame.alive) return;
        frame.alive = false;
        const bin = self.reusable_frames.getPtr(frame.values.len).?;
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
        if (try self.acquiredView(reference)) |view|
            return @import("acquired_values.zig").read(self, view.handle, view.offset, view.layout, view.endian);
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
        if (reference.byte_view != null or self.frames.items[@intFromEnum(reference.frame)].duration == .static) {
            _ = try self.read(reference);
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

    fn cleanupEntry(self: *Storage, reference: v.Reference) !usize {
        if (reference.byte_view != null) return error.ExecutionInvalidReference;
        try self.validateContext(reference);
        if (try self.acquiredView(reference) != null) return error.ExecutionMissingCleanup;
        _ = try self.slots(reference.frame);
        const layout = self.frames.items[@intFromEnum(reference.frame)].cleanup;
        const key = b.Cleanup{ .root = reference.root, .path = reference.path, .flag = 0 };
        var start: usize = 0;
        var end = layout.len;
        while (start < end) {
            const middle = start + (end - start) / 2;
            switch (b.cleanupOrder(layout[middle], key)) {
                .lt => start = middle + 1,
                .gt => end = middle,
                .eq => return middle,
            }
        }
        return error.ExecutionMissingCleanup;
    }
    pub fn cleanupPresent(self: *Storage, reference: v.Reference) !bool {
        const index = try self.cleanupEntry(reference);
        const entry = self.frames.items[@intFromEnum(reference.frame)].cleanup[index];
        return (try (try self.slots(reference.frame)).get(entry.presence orelse entry.flag)).boolean;
    }
    pub fn cleanupTest(self: *Storage, reference: v.Reference) !bool {
        const index = try self.cleanupEntry(reference);
        const flag = self.frames.items[@intFromEnum(reference.frame)].cleanup[index].flag;
        return (try (try self.slots(reference.frame)).get(flag)).boolean;
    }
    // Returns work units for execution metering, including ancestor inspection.
    pub fn cleanupSet(self: *Storage, reference: v.Reference, enabled: bool) !usize {
        try self.validateWritable(reference);
        return self.cleanupSetAt(reference, try self.cleanupEntry(reference), enabled);
    }
    fn cleanupSetAt(self: *Storage, reference: v.Reference, index: usize, enabled: bool) !usize {
        const values = try self.slots(reference.frame);
        const layout = self.frames.items[@intFromEnum(reference.frame)].cleanup;
        var updated: usize = 0;
        for (layout[index..]) |entry| {
            if (!b.cleanupContains(layout[index], entry)) break;
            try values.put(entry.flag, .{ .boolean = enabled });
            if (entry.presence) |flag| try values.put(flag, .{ .boolean = enabled });
            updated += 1;
        }
        var ancestor = index;
        while (ancestor != 0) {
            ancestor -= 1;
            updated += 1;
            const parent = layout[ancestor];
            if (parent.root != layout[index].root) break;
            if (!b.cleanupContains(parent, layout[index]) or parent.path.len >= layout[index].path.len) continue;
            var has_fields = parent.presence != null;
            var complete = if (parent.presence) |flag| (try values.get(flag)).boolean else true;
            for (layout[ancestor + 1 ..]) |entry| {
                updated += 1;
                if (!b.cleanupContains(parent, entry)) break;
                if (entry.path.len != parent.path.len + 1) continue;
                if (entry.path[entry.path.len - 1] != .field and parent.presence == null) {
                    complete = false;
                    break;
                }
                has_fields = true;
                if (!(try values.get(entry.flag)).boolean) complete = false;
            }
            if (has_fields) {
                try values.put(parent.flag, .{ .boolean = complete });
                updated += 1;
            }
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
        try self.validateWritable(reference);
        try self.validateStorageAddress(reference);
        const cleanup_entry = if (activate_cleanup) try self.cleanupEntry(reference) else null;
        var captured = reference;
        captured.path = try self.retainPath(reference.path);
        return .{ .reference = captured, .cleanup_entry = cleanup_entry };
    }

    // Validate compiler-selected cleanup state independently of value storage.
    // The executor orders this check, the write and subsequent activation.
    pub fn checkWriteCleanup(self: *Storage, destination: WriteDestination) !usize {
        if (!destination.require_cleanup) return 0;
        var checked: usize = 0;
        if (destination.cleanup_entry) |index| {
            try self.validateContext(destination.reference);
            const slots_ = try self.slots(destination.reference.frame);
            const layout = self.frames.items[@intFromEnum(destination.reference.frame)].cleanup;
            // A replacement may start with an active or partially moved value,
            // but its selected cleanup must finish before committing the new one.
            // Root occupancy alone cannot prove that every child was discharged.
            for (layout[index..]) |entry| {
                if (!b.cleanupContains(layout[index], entry)) break;
                if ((try slots_.get(entry.flag)).boolean or (if (entry.presence) |flag| (try slots_.get(flag)).boolean else false)) return error.ExecutionPendingCleanup;
                checked += 1;
            }
        }
        return checked;
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
            return @import("acquired_values.zig").write(self, view.handle, view.offset, view.layout, value, view.endian);
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
    const slots_ = try storage.enterSession(2, &.{.{ .root = 0, .path = &.{}, .flag = 1 }});
    try std.testing.expectError(error.ExecutionUninitializedStorage, slots_.get(0));
    try storage.initializeSession(slots_, 0, .{ .integer = 41 });
    try std.testing.expectError(error.ExecutionInitializedStorage, storage.initializeSession(slots_, 0, .{ .integer = 42 }));
    try slots_.put(1, .{ .boolean = true });
    try std.testing.expectError(error.ExecutionPendingCleanup, storage.reinitializeSession(slots_, 0, .{ .integer = 42 }));
    try std.testing.expectEqual(@as(i128, 41), (try slots_.get(0)).integer);
    try slots_.put(1, .{ .boolean = false });
    try storage.reinitializeSession(slots_, 0, .{ .integer = 42 });
    try std.testing.expectEqual(@as(i128, 42), (try slots_.get(0)).integer);
    try std.testing.expect(!(try slots_.get(1)).boolean);
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
    const frame = try storage.enterCleanup(2, &.{.{ .root = 0, .path = &.{}, .flag = 1 }});
    const layout: partial.Layout = .{ .nodes = &.{ .{ .kind = .record, .first = 1, .count = 1, .span = 2 }, .{ .offset = 1 } } };
    _ = try storage.resetStorage(frame, 0, layout);
    const root: v.Reference = .{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    var field = root;
    field.path = &.{.{ .field = 0 }};
    try storage.store(field, .{ .integer = 42 });
    const snapshot = try storage.read(root);
    const slots_ = try storage.slots(frame);
    try slots_.put(1, .{ .boolean = true });
    try std.testing.expectError(error.ExecutionPendingCleanup, storage.resetStorage(frame, 0, layout));
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(field)).integer);
    try slots_.put(1, .{ .boolean = false });
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
        .{ .root = 0, .path = &.{}, .flag = 1 },
        .{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 2 },
        .{ .root = 0, .path = &.{.{ .field = 1 }}, .flag = 3 },
        .{ .root = 4, .path = &.{}, .flag = 5, .presence = 7 },
        .{ .root = 4, .path = &.{.{ .variant = 0 }}, .flag = 6 },
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
        .{ .root = 0, .path = &.{}, .flag = 1 },
        .{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 2 },
        .{ .root = 0, .path = &.{ .{ .field = 0 }, .{ .field = 0 } }, .flag = 3 },
        .{ .root = 0, .path = &.{.{ .field = 1 }}, .flag = 4 },
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

test "session creation validates complete quota before retaining cleanup paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 4);
    const cleanup = &.{b.Cleanup{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 1 }};
    try std.testing.expectError(error.ExecutionMemoryLimit, storage.enterSession(2, cleanup));
    try std.testing.expectEqual(@as(usize, 0), storage.cells);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items.len);
    storage.limit = 5;
    const session = try storage.enterSession(2, cleanup);
    try std.testing.expectEqual(@as(usize, 5), storage.cells);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(session.frame));
}

fn failedSessionStorage(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100000);
    const cleanup = &.{b.Cleanup{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 1 }};
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
    try std.testing.expectError(error.ExecutionInvalidReference, storage.enterCleanup(2, &.{.{ .root = 0, .path = &.{}, .flag = 0 }}));
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
    _ = storage.enterCleanup(4096, &.{.{ .root = 0, .path = &.{}, .flag = 1 }}) catch |err| {
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
    const reference = try storage.acquiredReference(region, 4, &layout, .little, .read_write);
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
    _ = try storage.acquiredReference(replacement, 4, &layout, .little, .read_write);
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
    const root = try storage.acquiredReference(region, 0, &layout, .little, .read_write);
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
    const reference = try storage.acquiredReference(region, 0, &layout, .little, .read_write);
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
        const root = try storage.acquiredReference(region, 0, &layout, endian, .read_write);
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
    const first = try storage.enterCleanup(3, &.{.{ .root = 0, .path = &.{}, .flag = 1 }});
    const old_slots = try storage.slots(first);
    try old_slots.put(0, .{ .integer = 42 });
    try old_slots.put(1, .{ .boolean = true });
    const reference: v.Reference = .{ .context = storage.context, .frame = first, .root = 0, .path = &.{}, .mutability = .read_write };
    const backing = storage.frames.items[@intFromEnum(first)].values.ptr;
    storage.leave(first);
    const differently_sized = try storage.enter(4);
    const second = try storage.enterCleanup(3, &.{.{ .root = 0, .path = &.{}, .flag = 2 }});
    try std.testing.expect(first != second);
    try std.testing.expect(storage.frames.items[@intFromEnum(second)].values.ptr == backing);
    try std.testing.expectEqual(@as(usize, 0), storage.frames.items[@intFromEnum(first)].values.len);
    const new_slots = try storage.slots(second);
    try std.testing.expectError(error.ExecutionUninitializedStorage, new_slots.get(0));
    try std.testing.expectError(error.ExecutionUninitializedStorage, new_slots.get(1));
    try std.testing.expect(!(try new_slots.get(2)).boolean);
    try new_slots.put(0, .{ .integer = 7 });
    try std.testing.expectError(error.ExecutionDeadReference, old_slots.get(0));
    try std.testing.expectError(error.ExecutionDeadReference, storage.read(reference));
    storage.leave(second);
    storage.leave(differently_sized);
    for (0..100) |_| {
        const next = try storage.enter(3);
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
        const first = try storage.acquiredReference(handle, 0, &layout, .little, .read_write);
        try storage.store(first, .{ .integer = 42 });
        // Fill the table so the next publication must reserve metadata. Wrap
        // its allocator calls, rather than arena growth, to exercise every step.
        while (storage.acquired_views.count() < storage.acquired_views.capacity() * 80 / 100)
            _ = try storage.acquiredReference(handle, 0, &layout, .little, .read_write);
        const frames = storage.frames.items.len;
        const views = storage.acquired_views.count();
        const cells = storage.cells;
        var failure = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = fail_index });
        storage.allocator = failure.allocator();
        if (storage.acquiredReference(handle, 0, &layout, .little, .read_only)) |reference| {
            try std.testing.expect(!failure.has_induced_failure);
            try std.testing.expectEqual(@as(u64, 42), (try storage.read(reference)).integer);
            try std.testing.expectEqual(@as(u64, 42), (try storage.read(first)).integer);
            return;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(frames, storage.frames.items.len);
            try std.testing.expectEqual(views, storage.acquired_views.count());
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

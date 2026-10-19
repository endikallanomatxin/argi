const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const v = @import("../5_codegen/bytecode/value.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const partial = @import("partial_storage.zig");

const Frame = struct {
    values: []?b.Value,
    partial_storage: std.AutoHashMapUnmanaged(b.Slot, partial.Storage) = .empty,
    cleanup: []const b.Cleanup = &.{},
    bytes: []const u8 = &.{},
    alive: bool = true,
    duration: enum { call, session, static } = .call,
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
            try self.storage.charge(try record.materializationCells(&.{}));
            return record.read(self.storage.allocator, &.{});
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
};

// Context-local storage. Its allocator is an execution arena; references can neither
// name another execution nor expose a native address. Dead frame IDs stay dead.
pub const Storage = struct {
    context: v.ContextId,
    allocator: std.mem.Allocator,
    limit: usize,
    cells: usize = 0,
    frames: std.ArrayList(Frame) = .empty,

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
        try self.charge(if (layout.nodes.len == 0) 0 else layout.nodes[0].span);
        const record = try partial.Storage.init(self.allocator, layout);
        try self.frames.items[@intFromEnum(frame)].partial_storage.put(self.allocator, root, record);
    }
    /// Re-enter lexical storage after its previous cleanup has finished.
    /// Existing leaf cells are reused; no old initialized value survives entry.
    pub fn resetStorage(self: *Storage, frame: v.FrameId, root: b.Slot, layout: partial.Layout) !usize {
        const slots_ = try self.slots(frame);
        const values = try slots_.cells();
        if (root >= values.len) return error.ExecutionInvalidReference;
        for (self.frames.items[@intFromEnum(frame)].cleanup) |entry|
            if (entry.root == root and (try slots_.get(entry.flag)).boolean) return error.ExecutionPendingCleanup;
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
        return self.allocator.alloc(b.Value, count);
    }
    pub fn virtualize(self: *Storage, receiver: v.Reference, program: *const b.Program, table: *const b.VirtualTable) !b.Value {
        _ = try self.read(receiver);
        const descriptor_cells = comptime std.math.divCeil(usize, @sizeOf(v.Virtual), @sizeOf(b.Value)) catch unreachable;
        try self.charge(descriptor_cells + receiver.path.len);
        const descriptor = try self.allocator.create(v.Virtual);
        var retained = receiver;
        retained.path = try self.allocator.dupe(v.Projection, receiver.path);
        descriptor.* = .{ .receiver = retained, .program = program.*, .table = table };
        return .{ .virtual_ = descriptor };
    }
    /// Copy complete value data into this context's arena. Copying data never
    /// copies cleanup obligations or grants permission to duplicate an owner.
    /// Callers supply the frontend's checked copy/move and publication plans.
    pub fn cloneValues(self: *Storage, values: []const b.Value) ![]const b.Value {
        return self.cloneValuesDepth(values, 0);
    }
    fn cloneValuesDepth(self: *Storage, values: []const b.Value, depth: usize) anyerror![]const b.Value {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        const result = try self.allocate(values.len);
        for (result, values) |*out, value| out.* = switch (value) {
            .array => |elements| .{ .array = try self.cloneValuesDepth(elements, depth + 1) },
            .record => |fields| .{ .record = try self.cloneValuesDepth(fields, depth + 1) },
            .choice => |choice| .{ .choice = .{
                .variant = choice.variant,
                .payload = if (choice.payload) |payload| &(try self.cloneValuesDepth(payload[0..1], depth + 1))[0] else null,
            } },
            .virtual_ => |handle| blk: {
                try self.validateContext(handle.receiver);
                break :blk value;
            },
            .reference => |reference| blk: {
                try self.validateContext(reference);
                try self.charge(reference.path.len);
                var retained = reference;
                retained.path = try self.allocator.dupe(v.Projection, reference.path);
                break :blk .{ .reference = retained };
            },
            else => value,
        };
        return result;
    }

    /// Session slots have their own lifetime from creation. They are never
    /// promoted call-frame slots. Layouts are copied because their original
    /// bytecode unit may be released before this storage is retired.
    pub fn enterSession(self: *Storage, count: usize, cleanup: []const b.Cleanup) !Slots {
        try self.charge(cleanup.len);
        const retained = try self.allocator.alloc(b.Cleanup, cleanup.len);
        for (retained, cleanup) |*out, entry| {
            try self.charge(entry.path.len);
            out.* = entry;
            out.path = try self.allocator.dupe(v.Projection, entry.path);
        }
        const frame = try self.enterCleanup(count, retained);
        self.frames.items[@intFromEnum(frame)].duration = .session;
        return self.slots(frame);
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
            if (entry.flag == index) return error.ExecutionInvalidReference;
        if (values[index] != null and !reinitialize) return error.ExecutionInitializedStorage;
        for (self.frames.items[@intFromEnum(target.frame)].cleanup) |entry| {
            if (entry.root == index and (try target.get(entry.flag)).boolean) return error.ExecutionPendingCleanup;
        }
        try self.validateSessionValues((&value)[0..1], 0);
        const retained = try self.cloneValues((&value)[0..1]);
        values[index] = retained[0];
    }

    fn validateSessionValues(self: *Storage, values: []const b.Value, depth: usize) anyerror!void {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        for (values) |value| switch (value) {
            .reference => |reference| {
                _ = try self.read(reference);
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
        const length = try std.math.add(usize, bytes.len, 1);
        try self.charge(length);
        const data = try self.allocator.alloc(u8, length);
        @memcpy(data[0..bytes.len], bytes);
        data[bytes.len] = 0;
        const frame = try self.enter(0);
        self.frames.items[@intFromEnum(frame)].bytes = data;
        self.frames.items[@intFromEnum(frame)].duration = .static;
        try self.charge(1);
        const path = try self.allocator.alloc(v.Projection, 1);
        path[0] = .{ .element = 0 };
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

    pub fn offsetReference(self: *Storage, reference: v.Reference, elements: i128) !v.Reference {
        var path: [64]v.Projection = undefined;
        var result = try self.offsetInto(reference, elements, &path);
        if (elements == 0 or result.byte_view != null) return result;
        try self.charge(result.path.len);
        result.path = try self.allocator.dupe(v.Projection, result.path);
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
            if (values[entry.flag].?.boolean) return error.ExecutionActiveCleanup;
        frame.alive = false;
    }

    pub fn enter(self: *Storage, count: usize) !v.FrameId {
        return self.enterCleanup(count, &.{});
    }
    pub fn enterCleanup(self: *Storage, count: usize, cleanup: []const b.Cleanup) !v.FrameId {
        // Also bound zero-slot frames and the frame identity table.
        try self.charge(1);
        if (self.frames.items.len >= std.math.maxInt(u32)) return error.ExecutionMemoryLimit;
        try self.charge(count);
        const values = try self.allocator.alloc(?b.Value, count);
        @memset(values, null);
        for (cleanup) |entry| {
            if (entry.root >= count or entry.flag >= count or entry.root == entry.flag) return error.ExecutionInvalidReference;
            values[entry.flag] = .{ .boolean = false };
        }
        const id: v.FrameId = @enumFromInt(self.frames.items.len);
        try self.frames.append(self.allocator, .{ .values = values, .cleanup = cleanup });
        return id;
    }
    pub fn leave(self: *Storage, id: v.FrameId) void {
        std.debug.assert(self.frames.items[@intFromEnum(id)].duration == .call);
        self.frames.items[@intFromEnum(id)].alive = false;
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
        try self.charge(reference.path.len);
        result.path = try self.allocator.dupe(v.Projection, reference.path);
        result.byte_view = .{ .layout = layout, .offset = 0, .endian = endian };
        _ = try self.read(result);
        return result;
    }

    pub fn read(self: *Storage, reference: v.Reference) !b.Value {
        try self.validateContext(reference);
        if (reference.byte_view) |view| {
            var base = reference;
            base.byte_view = null;
            return .{ .integer = try @import("../5_codegen/bytecode/numeric_layout.zig").readByte(view.layout, try self.read(base), view.offset, view.endian) };
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
            try self.charge(try record.materializationCells(reference.path));
            return record.read(self.allocator, reference.path);
        }
        var value = try values.get(reference.root);
        for (reference.path) |projection| value = try child(value, projection);
        return value;
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
                .variant => |variant| .{ .variant = @intFromEnum(variant) },
                .element => |index| blk: {
                    const array_length = blk_length: {
                        if (self.frames.items[@intFromEnum(reference.frame)].partial_storage.getPtr(reference.root)) |partial_| {
                            if (try partial_.arrayLength(reference.path)) |count| break :blk_length count;
                        }
                        const array = try self.read(reference);
                        if (array != .array) return error.ExecutionInvalidReference;
                        break :blk_length array.array.len;
                    };
                    break :blk .{ .element = try elementIndex((try locals.get(index)).integer, array_length) };
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
        const slots_ = try self.slots(reference.frame);
        if (reference.root >= (try slots_.cells()).len) return error.ExecutionInvalidReference;
        if (reference.path.len != 0) {
            if (self.frames.items[@intFromEnum(reference.frame)].partial_storage.getPtr(reference.root)) |record| {
                // Resolve the layout without requiring a value at its leaf.
                if (try record.aggregatePrefix(reference.path) < reference.path.len)
                    try self.charge(try record.materializationCells(reference.path));
                try record.validatePath(self.allocator, reference.path);
            } else _ = try self.read(reference);
        }
    }
    pub fn address(self: *Storage, reference: v.Reference, mutability: p.PointerMutability) !b.Value {
        try self.validateStorageAddress(reference);
        if (mutability == .read_write and (reference.mutability != .read_write or self.frames.items[@intFromEnum(reference.frame)].duration == .static)) return error.ExecutionReadonlyReference;
        try self.charge(reference.path.len);
        var result = reference;
        result.path = try self.allocator.dupe(v.Projection, reference.path);
        result.mutability = mutability;
        return .{ .reference = result };
    }
    pub fn borrow(self: *Storage, reference: v.Reference, mutability: p.PointerMutability) !b.Value {
        _ = try self.read(reference);
        if (mutability == .read_write and (reference.mutability != .read_write or self.frames.items[@intFromEnum(reference.frame)].duration == .static)) return error.ExecutionReadonlyReference;
        try self.charge(reference.path.len);
        var result = reference;
        result.path = try self.allocator.dupe(v.Projection, reference.path);
        result.mutability = mutability;
        return .{ .reference = result };
    }

    fn cleanupEntry(self: *Storage, reference: v.Reference) !usize {
        if (reference.byte_view != null) return error.ExecutionInvalidReference;
        try self.validateContext(reference);
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
            updated += 1;
        }
        if (enabled) {
            var ancestor = index;
            while (ancestor != 0) {
                ancestor -= 1;
                updated += 1;
                const parent = layout[ancestor];
                if (parent.root != layout[index].root) break;
                if (!b.cleanupContains(parent, layout[index]) or parent.path.len >= layout[index].path.len) continue;
                var has_fields = false;
                var complete = true;
                for (layout[ancestor + 1 ..]) |entry| {
                    updated += 1;
                    if (!b.cleanupContains(parent, entry)) break;
                    if (entry.path.len != parent.path.len + 1) continue;
                    if (entry.path[entry.path.len - 1] != .field) {
                        complete = false;
                        break;
                    }
                    has_fields = true;
                    if (!(try values.get(entry.flag)).boolean) complete = false;
                }
                if (has_fields and complete) {
                    try values.put(parent.flag, .{ .boolean = true });
                    updated += 1;
                }
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
        try self.charge(reference.path.len);
        var captured = reference;
        captured.path = try self.allocator.dupe(v.Projection, reference.path);
        return .{ .reference = captured, .cleanup_entry = cleanup_entry };
    }

    // Validate compiler-selected cleanup state independently of value storage.
    // The executor orders this check, the write and subsequent activation.
    pub fn checkWriteCleanup(self: *Storage, destination: WriteDestination) !usize {
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
                if ((try slots_.get(entry.flag)).boolean) return error.ExecutionPendingCleanup;
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
            if (value != .integer or value.integer < 0 or value.integer > 255) return error.ExecutionInvalidReference;
            var base = reference;
            base.byte_view = null;
            try self.charge(view.layout.size);
            const updated = try @import("../5_codegen/bytecode/numeric_layout.zig").writeByte(self.allocator, view.layout, try self.read(base), view.offset, @intCast(value.integer), view.endian);
            return self.store(base, updated);
        }
        const values = try self.slots(reference.frame);
        if (self.frames.items[@intFromEnum(reference.frame)].partial_storage.getPtr(reference.root)) |record| {
            const prefix = try record.aggregatePrefix(reference.path);
            if (prefix == reference.path.len) {
                try record.write(reference.path, value);
            } else {
                const fields = reference.path[0..prefix];
                try self.charge(try record.materializationCells(fields));
                const previous = try record.read(self.allocator, fields);
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
            .reference => |reference| _ = try self.read(reference),
            .virtual_ => |handle| _ = try self.read(handle.receiver),
            .choice => |choice| if (choice.payload) |payload| try self.validateLive(payload[0..1]),
            .record => |fields| try self.validateLive(fields),
            .array => |elements| try self.validateLive(elements),
            else => {},
        };
    }
};

test "numeric byte storage views retain identity permissions and frame lifetime" {
    const numeric = @import("../5_codegen/bytecode/numeric_layout.zig");
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
    const frame = try storage.enterCleanup(7, &.{
        .{ .root = 0, .path = &.{}, .flag = 1 },
        .{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 2 },
        .{ .root = 0, .path = &.{.{ .field = 1 }}, .flag = 3 },
        .{ .root = 4, .path = &.{}, .flag = 5 },
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
    var choice = root;
    choice.root = 4;
    var payload = choice;
    payload.path = &.{.{ .variant = 0 }};
    _ = try storage.cleanupSet(payload, true);
    try std.testing.expect(!try storage.cleanupTest(choice));
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

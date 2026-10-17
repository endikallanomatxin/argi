const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const v = @import("../5_codegen/bytecode/value.zig");
const p = @import("../4_semantics/primitives/schema.zig");

const Frame = struct { values: []?b.Value, cleanup: []const b.Cleanup = &.{}, alive: bool = true };

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
        return values[index] orelse error.ExecutionUninitializedStorage;
    }

    // Verified instructions define complete slot values. Reference writes use
    // Storage.store instead, which requires an already initialized destination.
    pub fn put(self: Slots, index: b.Slot, value: b.Value) !void {
        const values = try self.cells();
        if (index >= values.len) return error.ExecutionInvalidReference;
        values[index] = value;
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

// Run-local storage. Its allocator is an execution arena; references can neither
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
    pub fn allocate(self: *Storage, count: usize) ![]b.Value {
        try self.charge(count);
        return self.allocator.alloc(b.Value, count);
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
    pub fn read(self: *Storage, reference: v.Reference) !b.Value {
        try self.validateContext(reference);
        const values = try self.slots(reference.frame);
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
        return self.resolveTarget(frame, place, path, true);
    }
    // Lifecycle access locates storage without reading its current value. Only
    // following a reference or checking an array index needs an operand read.
    pub fn resolveCleanup(self: *Storage, frame: v.FrameId, place: b.Place, path: *[64]v.Projection) !v.Reference {
        return self.resolveTarget(frame, place, path, false);
    }
    fn resolveTarget(self: *Storage, frame: v.FrameId, place: b.Place, path: *[64]v.Projection, comptime read_value: bool) !v.Reference {
        const locals = try self.slots(frame);
        if (place.root >= (try locals.cells()).len) return error.ExecutionInvalidReference;
        var reference = v.Reference{ .context = self.context, .frame = frame, .root = place.root, .path = &.{}, .mutability = .read_write };
        var value: ?b.Value = if (read_value) try self.read(reference) else null;
        var length: usize = 0;
        for (place.path) |projection| {
            reference.path = path[0..length];
            if (projection == .dereference) {
                const pointer = value orelse try self.read(reference);
                if (pointer != .reference) return error.ExecutionInvalidReference;
                reference = pointer.reference;
                try self.validateContext(reference);
                _ = try self.slots(reference.frame);
                if (reference.path.len > path.len) return error.ExecutionInvalidReference;
                value = if (read_value) try self.read(reference) else null;
                length = reference.path.len;
                @memcpy(path[0..length], reference.path);
                continue;
            }
            if (length == path.len) return error.ExecutionInvalidReference;
            const concrete: v.Projection = switch (projection) {
                .field => |index| .{ .field = index },
                .variant => |variant| .{ .variant = @intFromEnum(variant) },
                .element => |index| blk: {
                    const array = value orelse try self.read(reference);
                    if (array != .array) return error.ExecutionInvalidReference;
                    break :blk .{ .element = try elementIndex((try locals.get(index)).integer, array.array.len) };
                },
                .dereference => unreachable,
            };
            if (read_value) value = try child(value.?, concrete);
            path[length] = concrete;
            length += 1;
        }
        reference.path = path[0..length];
        return reference;
    }
    pub fn borrow(self: *Storage, reference: v.Reference, mutability: p.PointerMutability) !b.Value {
        _ = try self.read(reference);
        if (mutability == .read_write and reference.mutability != .read_write) return error.ExecutionReadonlyReference;
        try self.charge(reference.path.len);
        var result = reference;
        result.path = try self.allocator.dupe(v.Projection, reference.path);
        result.mutability = mutability;
        return .{ .reference = result };
    }

    fn cleanupEntry(self: *Storage, reference: v.Reference) !usize {
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
    pub fn cleanupSet(self: *Storage, reference: v.Reference, enabled: bool) !usize {
        try self.validateContext(reference);
        if (reference.mutability != .read_write) return error.ExecutionReadonlyReference;
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
        return updated;
    }
    pub fn captureWrite(self: *Storage, frame: v.FrameId, place: b.Place, activate_cleanup: bool) !WriteDestination {
        var path: [64]v.Projection = undefined;
        const reference = try self.resolve(frame, place, &path);
        if (reference.mutability != .read_write) return error.ExecutionReadonlyReference;
        const cleanup_entry = if (activate_cleanup) try self.cleanupEntry(reference) else null;
        try self.charge(reference.path.len);
        var captured = reference;
        captured.path = try self.allocator.dupe(v.Projection, reference.path);
        return .{ .reference = captured, .cleanup_entry = cleanup_entry };
    }

    pub fn write(self: *Storage, destination: WriteDestination, value: b.Value) !usize {
        // Recheck storage liveness, permissions and aggregate shape. Capturing
        // access never grants initialization of vacant or released storage.
        try self.store(destination.reference, value);
        // Commit value and its checked cleanup obligation to the same captured
        // storage. No cleanup state is copied from the replacement value.
        return if (destination.cleanup_entry) |index|
            self.cleanupSetAt(destination.reference, index, true)
        else
            0;
    }

    pub fn store(self: *Storage, reference: v.Reference, value: b.Value) !void {
        try self.validateContext(reference);
        if (reference.mutability != .read_write) return error.ExecutionReadonlyReference;
        const values = try self.slots(reference.frame);
        const previous = try values.get(reference.root);
        try values.put(reference.root, try self.update(previous, reference.path, value));
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
            .choice => |choice| if (choice.payload) |payload| try self.validateLive(payload[0..1]),
            .record => |fields| try self.validateLive(fields),
            .array => |elements| try self.validateLive(elements),
            else => {},
        };
    }
};

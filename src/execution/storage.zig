const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const v = @import("../5_codegen/bytecode/value.zig");
const p = @import("../4_semantics/primitives/schema.zig");

const Frame = struct { values: []b.Value, alive: bool = true };

// Run-local storage. Its allocator is an execution arena; references can neither
// name another execution nor expose a native address. Dead frame IDs stay dead.
pub const Storage = struct {
    allocator: std.mem.Allocator,
    limit: usize,
    cells: usize = 0,
    frames: std.ArrayList(Frame) = .empty,

    pub fn charge(self: *Storage, count: usize) !void {
        if (count > self.limit -| self.cells) return error.ExecutionMemoryLimit;
        self.cells += count;
    }
    pub fn allocate(self: *Storage, count: usize) ![]b.Value {
        try self.charge(count);
        return self.allocator.alloc(b.Value, count);
    }
    pub fn enter(self: *Storage, count: usize) !v.FrameId {
        // Also bound zero-slot frames and the frame identity table.
        try self.charge(1);
        if (self.frames.items.len >= std.math.maxInt(u32)) return error.ExecutionMemoryLimit;
        const values = try self.allocate(count);
        @memset(values, .unit);
        const id: v.FrameId = @enumFromInt(self.frames.items.len);
        try self.frames.append(self.allocator, .{ .values = values });
        return id;
    }
    pub fn leave(self: *Storage, id: v.FrameId) void {
        self.frames.items[@intFromEnum(id)].alive = false;
    }
    pub fn slots(self: *Storage, id: v.FrameId) ![]b.Value {
        const index = @intFromEnum(id);
        if (index >= self.frames.items.len or !self.frames.items[index].alive) return error.ExecutionDeadReference;
        return self.frames.items[index].values;
    }
    pub fn elementIndex(index: i128, length: usize) !usize {
        if (index < 0 or index >= length) return error.ExecutionIndexOutOfBounds;
        return @intCast(index);
    }
    pub fn read(self: *Storage, reference: v.Reference) !b.Value {
        const values = try self.slots(reference.frame);
        if (reference.root >= values.len) return error.ExecutionInvalidReference;
        var value = values[reference.root];
        for (reference.path) |projection| value = try child(value, projection);
        return value;
    }
    fn child(value: b.Value, projection: v.Projection) !b.Value {
        return switch (projection) {
            .field => |index| if (value == .record and index < value.record.len) value.record[index] else error.ExecutionInvalidReference,
            .element => |index| if (value == .array and index < value.array.len) value.array[index] else error.ExecutionIndexOutOfBounds,
        };
    }
    pub fn resolve(self: *Storage, frame: v.FrameId, place: b.Place, path: *[64]v.Projection) !v.Reference {
        const locals = try self.slots(frame);
        var reference = v.Reference{ .frame = frame, .root = place.root, .path = &.{}, .mutability = .read_write };
        var value = try self.read(reference);
        var length: usize = 0;
        for (place.path) |projection| switch (projection) {
            .dereference => {
                if (value != .reference) return error.ExecutionInvalidReference;
                reference = value.reference;
                if (reference.path.len > path.len) return error.ExecutionInvalidReference;
                value = try self.read(reference);
                length = reference.path.len;
                @memcpy(path[0..length], reference.path);
            },
            else => {
                if (length == path.len) return error.ExecutionInvalidReference;
                const concrete: v.Projection = switch (projection) {
                    .field => |index| .{ .field = index },
                    .element => |index| .{ .element = try elementIndex(locals[index].integer, if (value == .array) value.array.len else return error.ExecutionInvalidReference) },
                    .dereference => unreachable,
                };
                value = try child(value, concrete);
                path[length] = concrete;
                length += 1;
            },
        };
        reference.path = path[0..length];
        return reference;
    }
    pub fn borrow(self: *Storage, reference: v.Reference, mutability: p.PointerMutability) !b.Value {
        if (mutability == .read_write and reference.mutability != .read_write) return error.ExecutionReadonlyReference;
        try self.charge(reference.path.len);
        var result = reference;
        result.path = try self.allocator.dupe(v.Projection, reference.path);
        result.mutability = mutability;
        return .{ .reference = result };
    }
    pub fn store(self: *Storage, reference: v.Reference, value: b.Value) !void {
        if (reference.mutability != .read_write) return error.ExecutionReadonlyReference;
        const values = try self.slots(reference.frame);
        if (reference.root >= values.len) return error.ExecutionInvalidReference;
        values[reference.root] = try self.update(values[reference.root], reference.path, value);
    }
    // Rebuild only the modified aggregate path; all untouched subtrees remain
    // immutable shared values. References retain storage identity across updates.
    fn update(self: *Storage, base: b.Value, path: []const v.Projection, value: b.Value) anyerror!b.Value {
        if (path.len == 0) return value;
        const old = try child(base, path[0]);
        const changed = try self.update(old, path[1..], value);
        const elements, const index = switch (path[0]) {
            .field => |index| .{ base.record, @as(usize, index) },
            .element => |index| .{ base.array, index },
        };
        const result = try self.allocate(elements.len);
        @memcpy(result, elements);
        result[index] = changed;
        return switch (path[0]) {
            .field => .{ .record = result },
            .element => .{ .array = result },
        };
    }
    // Returning a borrow of a caller's storage is valid; returning one into the
    // completed frame is not. This is a runtime backstop, not a second safety checker.
    pub fn validateLive(self: *Storage, values: []const b.Value) anyerror!void {
        for (values) |value| switch (value) {
            .reference => |reference| _ = try self.read(reference),
            .record => |fields| try self.validateLive(fields),
            .array => |elements| try self.validateLive(elements),
            else => {},
        };
    }
};

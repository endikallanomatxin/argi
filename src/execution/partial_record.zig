const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const Projection = @import("../5_codegen/bytecode/value.zig").Projection;

const layout_mod = @import("../5_codegen/bytecode/storage_layout.zig");
pub const Layout = layout_mod.Layout;

pub const Storage = struct {
    layout: Layout,
    values: []?b.Value,

    pub fn init(allocator: std.mem.Allocator, layout: Layout) !Storage {
        if (layout.nodes.len == 0) return error.ExecutionInvalidReference;
        for (layout.nodes, 0..) |node, index| {
            if (!node.record and node.count != 0) return error.ExecutionInvalidReference;
            if (node.record and node.count == 0) return error.ExecutionInvalidReference;
            if (node.count != 0 and (node.first <= index or node.first > layout.nodes.len or node.count > layout.nodes.len - node.first)) return error.ExecutionInvalidReference;
        }
        const values = try allocator.alloc(?b.Value, layout.nodes.len);
        @memset(values, null);
        return .{ .layout = layout, .values = values };
    }

    // The caller owns allocation/fuel accounting. Materialization never fills
    // missing leaves or manufactures a default value.
    pub fn read(self: *Storage, allocator: std.mem.Allocator, path: []const Projection) anyerror!b.Value {
        return self.readAt(allocator, 0, path, 0);
    }
    fn readAt(self: *Storage, allocator: std.mem.Allocator, index: u32, path: []const Projection, depth: usize) anyerror!b.Value {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (self.values[index]) |value| {
            var result = value;
            for (path) |projection| result = try project(result, projection);
            return result;
        }
        const node = self.layout.nodes[index];
        if (path.len != 0) return self.readAt(allocator, try self.field(index, path[0]), path[1..], depth + 1);
        if (!node.record) return error.ExecutionUninitializedStorage;
        const fields = try allocator.alloc(b.Value, node.count);
        for (fields, 0..) |*value, offset| value.* = try self.readAt(allocator, node.first + @as(u32, @intCast(offset)), &.{}, depth + 1);
        const result: b.Value = .{ .record = fields };
        self.values[index] = result;
        return result;
    }
    // Check completeness and account for snapshot cells before allocating.
    pub fn materializationCells(self: *const Storage, path: []const Projection) !usize {
        return self.requiredCells(0, path, 0);
    }
    fn requiredCells(self: *const Storage, index: u32, path: []const Projection, depth: usize) anyerror!usize {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (self.values[index] != null) return 0;
        if (path.len != 0) return self.requiredCells(try self.field(index, path[0]), path[1..], depth + 1);
        const node = self.layout.nodes[index];
        if (!node.record) return error.ExecutionUninitializedStorage;
        var result: usize = node.count;
        for (0..node.count) |offset| result = std.math.add(usize, result, try self.requiredCells(node.first + @as(u32, @intCast(offset)), &.{}, depth + 1)) catch return error.ExecutionMemoryLimit;
        return result;
    }
    pub fn recordPrefix(self: *const Storage, path: []const Projection) !usize {
        var index: u32 = 0;
        var count: usize = 0;
        while (count < path.len and self.layout.nodes[index].record) : (count += 1)
            index = try self.field(index, path[count]);
        return count;
    }
    pub fn validatePath(self: *Storage, allocator: std.mem.Allocator, path: []const Projection) !void {
        const prefix = try self.recordPrefix(path);
        if (prefix < path.len) _ = try self.read(allocator, path);
    }
    fn project(value: b.Value, projection: Projection) !b.Value {
        return switch (projection) {
            .field => |index| if (value == .record and index < value.record.len) value.record[index] else error.ExecutionInvalidReference,
            .element => |index| if (value == .array and index < value.array.len) value.array[index] else error.ExecutionIndexOutOfBounds,
            .variant => |index| if (value == .choice and value.choice.variant == index and value.choice.payload != null) value.choice.payload.?.* else error.ExecutionInactiveVariant,
        };
    }
    pub fn write(self: *Storage, path: []const Projection, value: b.Value) !void {
        return self.writeAt(0, path, value, 0);
    }
    fn writeAt(self: *Storage, index: u32, path: []const Projection, value: b.Value, depth: usize) !void {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (path.len == 0) {
            self.values[index] = value;
            return;
        }
        const child = try self.field(index, path[0]);
        const node = self.layout.nodes[index];
        if (self.values[index]) |previous| {
            if (previous != .record or previous.record.len != node.count) return error.ExecutionInvalidReference;
            for (previous.record, 0..) |entry, offset| self.values[node.first + @as(u32, @intCast(offset))] = entry;
            self.values[index] = null;
        }
        try self.writeAt(child, path[1..], value, depth + 1);
    }
    fn field(self: *const Storage, index: u32, projection: Projection) !u32 {
        const node = self.layout.nodes[index];
        if (projection != .field or !node.record or projection.field >= node.count) return error.ExecutionInvalidReference;
        const selected = std.math.add(u32, node.first, projection.field) catch return error.ExecutionInvalidReference;
        if (selected >= self.values.len) return error.ExecutionInvalidReference;
        return selected;
    }
};

test "partial records preserve initialized siblings and immutable snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var storage = try Storage.init(allocator, .{ .nodes = &.{
        .{ .record = true, .first = 1, .count = 2 },
        .{},
        .{ .record = true, .first = 3, .count = 1 },
        .{},
    } });
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(allocator, &.{}));
    try storage.write(&.{.{ .field = 0 }}, .{ .integer = 41 });
    try std.testing.expectEqual(@as(i128, 41), (try storage.read(allocator, &.{.{ .field = 0 }})).integer);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(allocator, &.{}));
    try storage.write(&.{ .{ .field = 1 }, .{ .field = 0 } }, .{ .integer = 42 });
    const snapshot = try storage.read(allocator, &.{});
    try storage.write(&.{ .{ .field = 1 }, .{ .field = 0 } }, .{ .integer = 7 });
    try std.testing.expectEqual(@as(i128, 42), snapshot.record[1].record[0].integer);
    try std.testing.expectEqual(@as(i128, 7), (try storage.read(allocator, &.{})).record[1].record[0].integer);
    try std.testing.expectEqual(@as(i128, 41), (try storage.read(allocator, &.{})).record[0].integer);
}

test "vacant empty record storage requires an explicit value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
    });
    try graph.fields.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(0),
    });
    var nested = try Storage.init(allocator, try layout_mod.compile(allocator, &graph, @enumFromInt(1)));
    const field = &.{Projection{ .field = 0 }};
    try std.testing.expectError(error.ExecutionUninitializedStorage, nested.read(allocator, field));
    try std.testing.expectError(error.ExecutionUninitializedStorage, nested.materializationCells(&.{}));
    try nested.write(field, .{ .record = &.{} });
    try std.testing.expectEqual(@as(usize, 0), (try nested.read(allocator, &.{})).record[0].record.len);

    var empty = try Storage.init(allocator, try layout_mod.compile(allocator, &graph, @enumFromInt(0)));
    try std.testing.expectError(error.ExecutionUninitializedStorage, empty.read(allocator, &.{}));
    try std.testing.expectError(error.ExecutionUninitializedStorage, empty.materializationCells(&.{}));
    try empty.write(&.{}, .{ .record = &.{} });
    try std.testing.expectEqual(@as(usize, 0), (try empty.read(allocator, &.{})).record.len);
    try std.testing.expectError(error.ExecutionInvalidReference, Storage.init(allocator, .{
        .nodes = &.{.{ .record = true }},
    }));
}

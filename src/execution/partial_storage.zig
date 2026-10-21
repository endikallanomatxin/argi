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
            if (node.kind == .leaf) {
                if (node.count != 0 or node.span != 1) return error.ExecutionInvalidReference;
                continue;
            }
            if (node.kind == .array and node.count == 0) {
                if (node.first != 0 or node.span != 1) return error.ExecutionInvalidReference;
                continue;
            }
            const children = if (node.kind == .array) 1 else node.count;
            if (node.count == 0 or node.first <= index or node.first > layout.nodes.len or children > layout.nodes.len - node.first) return error.ExecutionInvalidReference;
            var span: u32 = 1;
            for (layout.nodes[node.first..][0..children]) |child| {
                if (child.offset != span) return error.ExecutionInvalidReference;
                span = std.math.add(u32, span, std.math.mul(u32, child.span, if (node.kind == .array) node.count else 1) catch return error.ExecutionInvalidReference) catch return error.ExecutionInvalidReference;
            }
            if (node.span != span) return error.ExecutionInvalidReference;
        }
        const values = try allocator.alloc(?b.Value, layout.nodes[0].span);
        @memset(values, null);
        return .{ .layout = layout, .values = values };
    }

    const Position = struct { node: u32 = 0, cell: u32 = 0 };

    // Materialization never fills missing leaves or manufactures defaults.
    pub fn read(self: *Storage, allocator: std.mem.Allocator, path: []const Projection) anyerror!b.Value {
        return self.readAt(allocator, .{}, path, 0);
    }
    fn readAt(self: *Storage, allocator: std.mem.Allocator, position: Position, path: []const Projection, depth: usize) anyerror!b.Value {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (self.values[position.cell]) |value| {
            var result = value;
            for (path) |projection| result = try project(result, projection);
            return result;
        }
        const node = self.layout.nodes[position.node];
        if (path.len != 0) return self.readAt(allocator, try self.selectChild(position, path[0]), path[1..], depth + 1);
        if (node.kind == .leaf or node.count == 0) return error.ExecutionUninitializedStorage;
        const fields = try allocator.alloc(b.Value, node.count);
        for (fields, 0..) |*value, offset| value.* = try self.readAt(allocator, try self.selectChild(position, projectionFor(node, @intCast(offset))), &.{}, depth + 1);
        const result: b.Value = if (node.kind == .array) .{ .array = fields } else .{ .record = fields };
        self.values[position.cell] = result;
        return result;
    }
    // Observe an existing value without constructing aggregate snapshots. Tag
    // queries use this path so unrelated vacant fields are never materialized.
    pub fn storedValue(self: *const Storage, path: []const Projection) !b.Value {
        var position: Position = .{};
        var consumed: usize = 0;
        while (true) {
            if (self.values[position.cell]) |value| {
                var result = value;
                for (path[consumed..]) |projection| result = try project(result, projection);
                return result;
            }
            if (consumed == path.len) return error.ExecutionUninitializedStorage;
            position = try self.selectChild(position, path[consumed]);
            consumed += 1;
        }
    }

    pub fn materializationCells(self: *const Storage, path: []const Projection) !usize {
        return self.requiredCells(.{}, path, 0);
    }
    fn requiredCells(self: *const Storage, position: Position, path: []const Projection, depth: usize) anyerror!usize {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (self.values[position.cell] != null) return 0;
        if (path.len != 0) return self.requiredCells(try self.selectChild(position, path[0]), path[1..], depth + 1);
        const node = self.layout.nodes[position.node];
        if (node.kind == .leaf or node.count == 0) return error.ExecutionUninitializedStorage;
        var result: usize = node.count;
        for (0..node.count) |offset| result = std.math.add(usize, result, try self.requiredCells(try self.selectChild(position, projectionFor(node, @intCast(offset))), &.{}, depth + 1)) catch return error.ExecutionMemoryLimit;
        return result;
    }
    pub fn arrayLength(self: *const Storage, path: []const Projection) !?usize {
        var position: Position = .{};
        for (path) |selected| {
            if (self.layout.nodes[position.node].kind == .leaf) return null;
            position = try self.selectChild(position, selected);
        }
        const node = self.layout.nodes[position.node];
        return if (node.kind == .array) node.count else null;
    }
    pub fn aggregatePrefix(self: *const Storage, path: []const Projection) !usize {
        var position: Position = .{};
        var count: usize = 0;
        while (count < path.len and self.layout.nodes[position.node].kind != .leaf) : (count += 1)
            position = try self.selectChild(position, path[count]);
        return count;
    }
    pub fn validatePath(self: *Storage, allocator: std.mem.Allocator, path: []const Projection) !void {
        const prefix = try self.aggregatePrefix(path);
        if (prefix < path.len) _ = try self.read(allocator, path);
    }
    fn project(value: b.Value, selected: Projection) !b.Value {
        return switch (selected) {
            .field => |index| if (value == .record and index < value.record.len) value.record[index] else error.ExecutionInvalidReference,
            .element => |index| if (value == .array and index < value.array.len) value.array[index] else error.ExecutionIndexOutOfBounds,
            .variant => |index| if (value == .choice and value.choice.variant == index and value.choice.payload != null) value.choice.payload.?.* else error.ExecutionInactiveVariant,
        };
    }
    pub fn write(self: *Storage, path: []const Projection, value: b.Value) !void {
        return self.writeAt(.{}, path, value, 0);
    }
    fn writeAt(self: *Storage, position: Position, path: []const Projection, value: b.Value, depth: usize) !void {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (path.len == 0) {
            self.values[position.cell] = value;
            return;
        }
        const target = try self.selectChild(position, path[0]);
        const node = self.layout.nodes[position.node];
        if (self.values[position.cell]) |previous| {
            const fields = switch (node.kind) {
                .record => if (previous == .record) previous.record else return error.ExecutionInvalidReference,
                .array => if (previous == .array) previous.array else return error.ExecutionInvalidReference,
                .leaf => return error.ExecutionInvalidReference,
            };
            if (fields.len != node.count) return error.ExecutionInvalidReference;
            for (fields, 0..) |entry, offset| self.values[(try self.selectChild(position, projectionFor(node, @intCast(offset)))).cell] = entry;
            self.values[position.cell] = null;
        }
        try self.writeAt(target, path[1..], value, depth + 1);
    }
    fn projectionFor(node: layout_mod.Node, index: u32) Projection {
        return if (node.kind == .array) .{ .element = index } else .{ .field = index };
    }
    fn selectChild(self: *const Storage, position: Position, selected: Projection) !Position {
        const node = self.layout.nodes[position.node];
        const index: u32 = switch (node.kind) {
            .leaf => return error.ExecutionInvalidReference,
            .record => if (selected == .field) selected.field else return error.ExecutionInvalidReference,
            .array => if (selected == .element) std.math.cast(u32, selected.element) orelse return error.ExecutionIndexOutOfBounds else return error.ExecutionInvalidReference,
        };
        if (index >= node.count) return if (node.kind == .array) error.ExecutionIndexOutOfBounds else error.ExecutionInvalidReference;
        const template = node.first + if (node.kind == .array) @as(u32, 0) else index;
        const offset = if (node.kind == .array) 1 + index * self.layout.nodes[template].span else self.layout.nodes[template].offset;
        return .{ .node = template, .cell = position.cell + offset };
    }
};

test "partial records preserve initialized siblings and immutable snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var storage = try Storage.init(allocator, .{ .nodes = &.{
        .{ .kind = .record, .first = 1, .count = 2, .span = 4 },
        .{ .offset = 1 },
        .{ .kind = .record, .first = 3, .count = 1, .span = 2, .offset = 2 },
        .{ .offset = 1 },
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
        .nodes = &.{.{ .kind = .record }},
    }));
}

test "partial arrays keep repeated element storage and snapshots independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var storage = try Storage.init(allocator, .{ .nodes = &.{
        .{ .kind = .array, .first = 1, .count = 2, .span = 5 },
        .{ .kind = .record, .first = 2, .count = 1, .span = 2, .offset = 1 },
        .{ .offset = 1 },
    } });
    const first = &.{ Projection{ .element = 0 }, Projection{ .field = 0 } };
    const second = &.{ Projection{ .element = 1 }, Projection{ .field = 0 } };
    try storage.write(first, .{ .integer = 40 });
    try std.testing.expectEqual(@as(i128, 40), (try storage.read(allocator, first)).integer);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.materializationCells(&.{}));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(allocator, second));
    try storage.write(second, .{ .integer = 2 });
    try std.testing.expectEqual(@as(usize, 4), try storage.materializationCells(&.{}));
    const snapshot = try storage.read(allocator, &.{});
    try storage.write(first, .{ .integer = 7 });
    try std.testing.expectEqual(@as(i128, 40), snapshot.array[0].record[0].integer);
    try std.testing.expectEqual(@as(i128, 7), (try storage.read(allocator, first)).integer);
    try std.testing.expectEqual(@as(i128, 2), (try storage.read(allocator, second)).integer);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.write(&.{.{ .element = 2 }}, .unit));
}

test "array layout templates do not grow with element count" {
    const allocator = std.testing.allocator;
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 1000000 } },
    });
    const layout = try layout_mod.compile(allocator, &graph, @enumFromInt(1));
    defer allocator.free(layout.nodes);
    try std.testing.expectEqual(@as(usize, 2), layout.nodes.len);
    try std.testing.expectEqual(@as(u32, 1000001), layout.nodes[0].span);
}

test "vacant empty arrays retain bounds without manufacturing a value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var storage = try Storage.init(allocator, .{ .nodes = &.{.{ .kind = .array }} });
    try std.testing.expectEqual(@as(?usize, 0), try storage.arrayLength(&.{}));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(allocator, &.{}));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.write(&.{.{ .element = 0 }}, .unit));
    try storage.write(&.{}, .{ .array = &.{} });
    try std.testing.expectEqual(@as(usize, 0), (try storage.read(allocator, &.{})).array.len);
}

const std = @import("std");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const Projection = @import("../5_codegen/bytecode/value.zig").Projection;

const layout_mod = @import("../5_codegen/bytecode/storage_layout.zig");
pub const Layout = layout_mod.Layout;

pub const Storage = struct {
    layout: Layout,
    values: []?b.Value,

    pub fn init(allocator: std.mem.Allocator, layout: Layout) !Storage {
        const count = try validateLayout(layout);
        const values = try allocator.alloc(?b.Value, count);
        @memset(values, null);
        return .{ .layout = layout, .values = values };
    }

    pub fn validateLayout(layout: Layout) !usize {
        if (layout.nodes.len == 0 or layout.nodes[0].kind == .payloadless) return error.ExecutionInvalidReference;
        for (layout.nodes, 0..) |node, index| {
            if (node.kind == .leaf or node.kind == .payloadless) {
                if (node.count != 0 or node.first != 0 or node.span != @as(u32, if (node.kind == .leaf) 1 else 0)) return error.ExecutionInvalidReference;
                continue;
            }
            if ((node.kind == .array or node.kind == .choice) and node.count == 0) {
                if (node.first != 0 or node.span != 1) return error.ExecutionInvalidReference;
                continue;
            }
            const children = if (node.kind == .array) 1 else node.count;
            if (node.count == 0 or node.first <= index or node.first > layout.nodes.len or children > layout.nodes.len - node.first) return error.ExecutionInvalidReference;
            var span: u32 = 1;
            for (layout.nodes[node.first..][0..children]) |child| {
                if (child.offset != span or (node.kind != .choice and child.kind == .payloadless)) return error.ExecutionInvalidReference;
                span = std.math.add(u32, span, std.math.mul(u32, child.span, if (node.kind == .array) node.count else 1) catch return error.ExecutionInvalidReference) catch return error.ExecutionInvalidReference;
            }
            if (node.span != span) return error.ExecutionInvalidReference;
        }
        return layout.nodes[0].span;
    }

    const Position = struct { node: u32 = 0, cell: u32 = 0 };
    const Walk = struct { position: Position, consumed: usize, inherited: ?b.Value };

    // A choice cell retains its tag even while its active payload is partial.
    // A null payload is complete only for a declared payloadless alternative.
    // These internal markers never escape through read/materialize.
    fn complete(self: *const Storage, position: Position, value: ?b.Value) !bool {
        const present = value orelse return false;
        const node = self.layout.nodes[position.node];
        if (node.kind != .choice) return true;
        if (present != .choice or present.choice.variant >= node.count) return error.ExecutionInvalidReference;
        const payloadless = self.layout.nodes[node.first + present.choice.variant].kind == .payloadless;
        if (payloadless and present.choice.payload != null) return error.ExecutionInvalidReference;
        return payloadless or present.choice.payload != null;
    }

    // Every projection uses the same nonmutating walk, including reads, bounds,
    // address validation and writes. Cached ancestors do not require unpacking.
    fn walk(self: *const Storage, start: Position, path: []const Projection) !Walk {
        if (path.len > 64) return error.ExecutionValueDepthLimit;
        var position = start;
        var inherited: ?b.Value = null;
        var consumed: usize = 0;
        while (consumed < path.len) : (consumed += 1) {
            const node = self.layout.nodes[position.node];
            if (node.kind == .leaf or node.kind == .payloadless) break;
            const selected = try self.selectChild(position, path[consumed]);
            inherited = try self.observedChild(position, path[consumed], inherited orelse self.values[position.cell]);
            position = selected;
        }
        return .{ .position = position, .consumed = consumed, .inherited = inherited };
    }

    pub fn read(self: *Storage, allocator: std.mem.Allocator, path: []const Projection) anyerror!b.Value {
        const selected = try self.walk(.{}, path);
        const value = selected.inherited orelse self.values[selected.position.cell];
        if (selected.consumed != path.len) {
            var result = value orelse return error.ExecutionUninitializedStorage;
            for (path[selected.consumed..]) |projection| result = try project(result, projection);
            return result;
        }
        if (try self.complete(selected.position, value)) return value.?;
        const cells = try self.requiredCells(selected.position, 0);
        const backing = try allocator.alloc(b.Value, cells);
        errdefer allocator.free(backing);
        var remaining = backing;
        const result = try self.materialize(selected.position, &remaining, 0);
        std.debug.assert(remaining.len == 0);
        self.values[selected.position.cell] = result;
        return result;
    }

    fn materialize(self: *const Storage, position: Position, remaining: *[]b.Value, depth: usize) anyerror!b.Value {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (try self.complete(position, self.values[position.cell])) return self.values[position.cell].?;
        const node = self.layout.nodes[position.node];
        if (node.kind == .leaf or node.kind == .payloadless or node.count == 0) return error.ExecutionUninitializedStorage;
        if (node.kind == .choice) {
            const tag = (self.values[position.cell] orelse return error.ExecutionUninitializedStorage).choice.variant;
            const payload = &remaining.*[0];
            remaining.* = remaining.*[1..];
            payload.* = try self.materialize(try self.selectChild(position, .{ .variant = tag }), remaining, depth + 1);
            return .{ .choice = .{ .variant = tag, .payload = payload } };
        }
        const fields = remaining.*[0..node.count];
        remaining.* = remaining.*[node.count..];
        for (fields, 0..) |*value, offset| value.* = try self.materialize(try self.selectChild(position, projectionFor(node, @intCast(offset))), remaining, depth + 1);
        return if (node.kind == .array) .{ .array = fields } else .{ .record = fields };
    }

    // Tag queries may observe an internal partial-choice marker. Value reads
    // use complete/materialize and therefore still require the active payload.
    pub fn storedValue(self: *const Storage, path: []const Projection) !b.Value {
        const selected = try self.walk(.{}, path);
        var result = selected.inherited orelse self.values[selected.position.cell] orelse return error.ExecutionUninitializedStorage;
        for (path[selected.consumed..]) |projection| result = try project(result, projection);
        return result;
    }

    pub fn materializationCells(self: *const Storage, path: []const Projection) !usize {
        const selected = try self.walk(.{}, path);
        const value = selected.inherited orelse self.values[selected.position.cell];
        if (try self.complete(selected.position, value)) return 0;
        if (selected.consumed != path.len) return error.ExecutionUninitializedStorage;
        return self.requiredCells(selected.position, 0);
    }

    fn requiredCells(self: *const Storage, position: Position, depth: usize) anyerror!usize {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        if (try self.complete(position, self.values[position.cell])) return 0;
        const node = self.layout.nodes[position.node];
        if (node.kind == .leaf or node.kind == .payloadless or node.count == 0) return error.ExecutionUninitializedStorage;
        if (node.kind == .choice) {
            const tag = (self.values[position.cell] orelse return error.ExecutionUninitializedStorage).choice.variant;
            return std.math.add(usize, 1, try self.requiredCells(try self.selectChild(position, .{ .variant = tag }), depth + 1)) catch error.ExecutionMemoryLimit;
        }
        var result: usize = node.count;
        for (0..node.count) |offset| result = std.math.add(usize, result, try self.requiredCells(try self.selectChild(position, projectionFor(node, @intCast(offset))), depth + 1)) catch return error.ExecutionMemoryLimit;
        return result;
    }

    pub fn arrayLength(self: *const Storage, path: []const Projection) !?usize {
        const selected = try self.walk(.{}, path);
        const node = self.layout.nodes[selected.position.node];
        return if (selected.consumed == path.len and node.kind == .array) node.count else null;
    }

    pub fn aggregatePrefix(self: *const Storage, path: []const Projection) !usize {
        return (try self.walk(.{}, path)).consumed;
    }

    fn project(value: b.Value, selected: Projection) !b.Value {
        return switch (selected) {
            .field => |index| if (value == .record and index < value.record.len) value.record[index] else error.ExecutionInvalidReference,
            .element => |index| if (value == .array and index < value.array.len) value.array[index] else error.ExecutionIndexOutOfBounds,
            .variant => |index| if (value == .choice and value.choice.variant == index and value.choice.payload != null) value.choice.payload.?.* else error.ExecutionInactiveVariant,
        };
    }

    pub fn write(self: *Storage, path: []const Projection, value: b.Value) !void {
        try self.validateWritePath(path);
        try self.writeAt(.{}, path, value, 0);
    }

    pub fn clear(self: *Storage, path: []const Projection) !void {
        try self.validateWritePath(path);
        try self.writeAt(.{}, path, null, 0);
    }

    pub fn validateWritePath(self: *const Storage, path: []const Projection) !void {
        if ((try self.walk(.{}, path)).consumed != path.len) return error.ExecutionInvalidReference;
    }

    fn writeAt(self: *Storage, position: Position, path: []const Projection, value: ?b.Value, depth: usize) !void {
        if (depth > 64) return error.ExecutionValueDepthLimit;
        const node = self.layout.nodes[position.node];
        if (path.len == 0) {
            if (value == null or node.kind == .choice) @memset(self.values[position.cell..][0..node.span], null);
            self.values[position.cell] = value;
            return;
        }
        const target = try self.selectChild(position, path[0]);
        if (self.values[position.cell]) |previous| {
            _ = try self.observedChild(position, path[0], previous);
            if (node.kind == .choice) {
                if (previous.choice.payload) |payload| {
                    @memset(self.values[position.cell + 1 ..][0 .. node.span - 1], null);
                    self.values[target.cell] = payload.*;
                    self.values[position.cell] = .{ .choice = .{ .variant = previous.choice.variant, .payload = null } };
                }
            } else {
                const fields = if (node.kind == .record) previous.record else previous.array;
                for (fields, 0..) |entry, offset| self.values[(try self.selectChild(position, projectionFor(node, @intCast(offset)))).cell] = entry;
                self.values[position.cell] = null;
            }
        }
        try self.writeAt(target, path[1..], value, depth + 1);
    }

    fn projectionFor(node: layout_mod.Node, index: u32) Projection {
        return switch (node.kind) {
            .array => .{ .element = index },
            .choice => .{ .variant = index },
            else => .{ .field = index },
        };
    }

    fn observedChild(self: *const Storage, position: Position, projection: Projection, previous: ?b.Value) !?b.Value {
        const node = self.layout.nodes[position.node];
        const value = previous orelse return if (node.kind == .choice) error.ExecutionUninitializedStorage else null;
        if (node.kind == .choice) {
            if (value != .choice or value.choice.variant != projection.variant) return error.ExecutionInactiveVariant;
            return if (value.choice.payload) |payload| payload.* else null;
        }
        const fields = switch (node.kind) {
            .record => if (value == .record) value.record else return error.ExecutionInvalidReference,
            .array => if (value == .array) value.array else return error.ExecutionInvalidReference,
            else => return error.ExecutionInvalidReference,
        };
        if (fields.len != node.count) return error.ExecutionInvalidReference;
        return fields[if (projection == .field) projection.field else projection.element];
    }

    fn selectChild(self: *const Storage, position: Position, selected: Projection) !Position {
        const node = self.layout.nodes[position.node];
        const index: u32 = switch (node.kind) {
            .leaf, .payloadless => return error.ExecutionInvalidReference,
            .record => if (selected == .field) selected.field else return error.ExecutionInvalidReference,
            .array => if (selected == .element) std.math.cast(u32, selected.element) orelse return error.ExecutionIndexOutOfBounds else return error.ExecutionInvalidReference,
            .choice => if (selected == .variant) selected.variant else return error.ExecutionInvalidReference,
        };
        if (index >= node.count) return if (node.kind == .array) error.ExecutionIndexOutOfBounds else error.ExecutionInvalidReference;
        const template = node.first + if (node.kind == .array) @as(u32, 0) else index;
        if (self.layout.nodes[template].kind == .payloadless) return error.ExecutionInactiveVariant;
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

test "rejected nested writes preserve cached ancestors and vacant child cells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var storage = try Storage.init(allocator, .{ .nodes = &.{
        .{ .kind = .record, .first = 1, .count = 1, .span = 4 },
        .{ .kind = .array, .first = 2, .count = 2, .span = 3, .offset = 1 },
        .{ .offset = 1 },
    } });
    const value: b.Value = .{ .record = &.{.{ .array = &.{ .{ .integer = 20 }, .{ .integer = 22 } } }} };
    try storage.write(&.{}, value);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.write(&.{ .{ .field = 0 }, .{ .element = 2 } }, .{ .integer = 99 }));
    try std.testing.expect(storage.values[0] != null);
    for (storage.values[1..]) |cell| try std.testing.expectEqual(@as(?b.Value, null), cell);
    const retained = try storage.read(allocator, &.{});
    try std.testing.expect(retained.record.ptr == value.record.ptr);
    try std.testing.expectEqual(@as(u64, 22), retained.record[0].array[1].integer);
}

test "clearing a partial subtree preserves siblings without reviving cached descendants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var storage = try Storage.init(a, .{ .nodes = &.{
        .{ .kind = .record, .first = 1, .count = 2, .span = 5 },
        .{ .kind = .record, .first = 3, .count = 2, .span = 3, .offset = 1 },
        .{ .offset = 4 },
        .{ .offset = 1 },
        .{ .offset = 2 },
    } });
    try storage.write(&.{}, .{ .record = &.{ .{ .record = &.{ .{ .integer = 11 }, .{ .integer = 12 } } }, .{ .integer = 31 } } });
    const old = try storage.read(a, &.{});
    try storage.clear(&.{.{ .field = 0 }});
    try storage.write(&.{ .{ .field = 0 }, .{ .field = 0 } }, .{ .integer = 21 });
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(a, &.{ .{ .field = 0 }, .{ .field = 1 } }));
    try std.testing.expectEqual(@as(u64, 31), (try storage.read(a, &.{.{ .field = 1 }})).integer);
    try std.testing.expectEqual(@as(u64, 12), old.record[0].record[1].integer);
}

fn partialChoiceFailures(allocator: std.mem.Allocator) !void {
    const layout: Layout = .{ .nodes = &.{
        .{ .kind = .choice, .first = 1, .count = 2, .span = 4 },
        .{ .kind = .record, .first = 3, .count = 2, .span = 3, .offset = 1 },
        .{ .kind = .payloadless, .span = 0, .offset = 4 },
        .{ .offset = 1 },
        .{ .offset = 2 },
    } };
    const a = std.testing.allocator;
    var storage = try Storage.init(a, layout);
    defer a.free(storage.values);
    const fields = [_]b.Value{ .{ .integer = 20 }, .{ .integer = 22 } };
    const payload: b.Value = .{ .record = &fields };
    const initial: b.Value = .{ .choice = .{ .variant = 0, .payload = &payload } };
    try storage.write(&.{}, initial);
    const snapshot = try storage.read(a, &.{});
    try storage.clear(&.{ .{ .variant = 0 }, .{ .field = 0 } });
    try std.testing.expectEqual(@as(u32, 0), (try storage.storedValue(&.{})).choice.variant);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(a, &.{}));
    try std.testing.expectEqual(@as(u64, 22), (try storage.read(a, &.{ .{ .variant = 0 }, .{ .field = 1 } })).integer);
    try std.testing.expectEqual(@as(u64, 20), snapshot.choice.payload.?.record[0].integer);
    try storage.write(&.{ .{ .variant = 0 }, .{ .field = 0 } }, .{ .integer = 40 });
    const before = try a.dupe(?b.Value, storage.values);
    defer a.free(before);
    var snapshots = std.heap.ArenaAllocator.init(allocator);
    defer snapshots.deinit();
    const result = storage.read(snapshots.allocator(), &.{}) catch |err| {
        try std.testing.expectEqualDeep(before, storage.values);
        return err;
    };
    // Materialization allocates one payload cell and two record fields together.
    try std.testing.expectEqual(@as(u64, 40), result.choice.payload.?.record[0].integer);
    try std.testing.expectEqual(@as(u64, 22), result.choice.payload.?.record[1].integer);
    try storage.write(&.{}, .{ .choice = .{ .variant = 1, .payload = null } });
    try std.testing.expect((try storage.read(a, &.{})).choice.payload == null);
    try std.testing.expectError(error.ExecutionInactiveVariant, storage.clear(&.{.{ .variant = 0 }}));
    // Re-selecting an empty payload cannot revive the previous alternative.
    try storage.write(&.{}, .{ .choice = .{ .variant = 0, .payload = null } });
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(a, &.{ .{ .variant = 0 }, .{ .field = 1 } }));
}

test "partial choices retain tags and live siblings without reviving old payloads" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, partialChoiceFailures, .{});
}

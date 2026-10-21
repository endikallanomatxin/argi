const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const types = @import("../4_semantics/global/types.zig");

pub const Projection = union(enum) { field: u32, variant: g.GlobalVariantId };
pub const Child = struct { projection: Projection, ty: g.GlobalTypeId };

pub fn requiredBindings(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) ![]bool {
    const required = try allocator.alloc(bool, graph.bindings.items.len);
    @memset(required, false);
    for (graph.auto_deinits.items) |plan| if (plan.ownerBinding()) |binding| {
        required[@intFromEnum(binding)] = true;
    };
    return required;
}

// Preorder storage gives every present subtree a contiguous flag range. A
// companion can point at that range without depending on value addresses.
// Choices reserve one additional flag for discriminant presence: ending a
// payload descendant revokes completeness without erasing the active variant.
pub const Layout = struct {
    pub const Span = struct { offset: usize, ty: g.GlobalTypeId, layout: *const Layout };
    count: usize = 1,
    children: []const ?Span = &.{},
    is_record: bool = false,
    is_choice: bool = false,

    pub fn project(self: *const Layout, projection: @import("bytecode/value.zig").Projection) ?Span {
        const index: usize = switch (projection) {
            .field => |index| if (self.is_record) index else return null,
            .variant => |index| if (self.is_choice) index else return null,
            .element => return null,
        };
        if (index >= self.children.len) return null;
        return self.children[index];
    }

    pub const Equal = struct {
        const Pair = struct { left: *const Layout, right: *const Layout };
        allocator: std.mem.Allocator,
        seen: std.AutoHashMapUnmanaged(Pair, void) = .empty,

        pub fn deinit(self: *Equal) void {
            self.seen.deinit(self.allocator);
        }

        pub fn compare(self: *Equal, left: *const Layout, right: *const Layout, depth: usize) error{OutOfMemory}!bool {
            if (depth > 64) return false;
            if (left.count != right.count or left.is_record != right.is_record or left.is_choice != right.is_choice or left.children.len != right.children.len) return false;
            const key: Pair = .{ .left = left, .right = right };
            if (self.seen.contains(key)) return true;
            for (left.children, right.children) |a, b| {
                if ((a == null) != (b == null)) return false;
                if (a) |span| if (span.offset != b.?.offset or span.ty != b.?.ty or !try self.compare(span.layout, b.?.layout, depth + 1)) return false;
            }
            try self.seen.put(self.allocator, key, {});
            return true;
        }
    };

    // Copy immutable shape DAGs once per source identity. Array repetition will
    // share its element shape rather than create one descriptor per element.
    pub const Copy = struct {
        allocator: std.mem.Allocator,
        memo: std.AutoHashMapUnmanaged(*const Layout, struct { retained: ?*const Layout = null }) = .empty,
        cells: usize = 0,

        pub fn deinit(self: *Copy) void {
            self.memo.deinit(self.allocator);
        }

        pub fn measure(self: *Copy, source: *const Layout, depth: usize) error{ OutOfMemory, InvalidCleanupLayout, Overflow }!void {
            if (depth > 64) return error.InvalidCleanupLayout;
            const entry = try self.memo.getOrPut(self.allocator, source);
            if (entry.found_existing) return;
            entry.value_ptr.* = .{};
            self.cells = try std.math.add(usize, self.cells, try std.math.add(usize, 1, source.children.len));
            for (source.children) |child| if (child) |span| try self.measure(span.layout, depth + 1);
        }

        pub fn retain(self: *Copy, source: *const Layout, depth: usize) error{ OutOfMemory, InvalidCleanupLayout, Overflow }!*const Layout {
            if (depth > 64) return error.InvalidCleanupLayout;
            if (!self.memo.contains(source)) try self.measure(source, depth);
            if (self.memo.get(source).?.retained) |retained| return retained;
            const result = try self.allocator.create(Layout);
            const children = try self.allocator.alloc(?Span, source.children.len);
            for (children, source.children) |*out, child| {
                out.* = if (child) |span| .{ .offset = span.offset, .ty = span.ty, .layout = try self.retain(span.layout, depth + 1) } else null;
            }
            result.* = source.*;
            result.children = children;
            self.memo.getPtr(source).?.retained = result;
            return result;
        }
    };
};

pub const Counts = struct {
    pub const Span = Layout.Span;
    pub const Description = Layout;
    values: std.AutoHashMapUnmanaged(g.GlobalTypeId, *const Layout) = .empty,

    pub fn deinit(self: *Counts, allocator: std.mem.Allocator) void {
        var entries = self.values.valueIterator();
        while (entries.next()) |entry| {
            allocator.free(entry.*.children);
            allocator.destroy(entry.*);
        }
        self.values.deinit(allocator);
    }

    // Cache structure once per type, rather than once per owner or projected
    // view. Descriptions contain ranges, never copies of runtime flag state.
    pub fn count(self: *Counts, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) error{ OutOfMemory, Overflow }!usize {
        if (self.values.get(ty)) |value| return value.count;
        const shape = Shape.of(graph, ty);
        const children = try allocator.alloc(?Span, shape.len());
        errdefer allocator.free(children);
        @memset(children, null);
        var result: usize = if (shape == .variants) 2 else 1;
        for (children, 0..) |*span, index| if (shape.child(graph, index)) |child| {
            const child_count = try self.count(allocator, graph, child.ty);
            span.* = .{ .offset = result, .ty = child.ty, .layout = self.values.get(child.ty).? };
            result = try std.math.add(usize, result, child_count);
        };
        const retained_layout = try allocator.create(Layout);
        errdefer allocator.destroy(retained_layout);
        retained_layout.* = .{ .count = result, .children = children, .is_record = shape == .fields, .is_choice = shape == .variants };
        try self.values.put(allocator, ty, retained_layout);
        return result;
    }

    // Nodes are individually allocated: growing the construction index cannot
    // invalidate a published owner's shape or its child pointers.
    pub fn retained(self: *const Counts, ty: g.GlobalTypeId) *const Layout {
        return self.values.get(ty).?;
    }

    pub fn description(self: *const Counts, ty: g.GlobalTypeId) Description {
        return self.values.get(ty).?.*;
    }
};

// This is a view of checked storage structure, not destructor selection. Both
// backends attach their concrete flags to the same field/variant identities.
// Physical addresses are insufficient: zero-sized siblings can share one.
// Reference leaves never include the state of their referents, and variants
// without payloads have no child storage. Arrays retain the current whole-value
// state until indexed ownership transitions are represented by the frontend.
pub const Shape = union(enum) {
    leaf,
    fields: p.Range(g.GlobalFieldId),
    variants: p.Range(g.GlobalVariantId),

    pub fn of(graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) Shape {
        if (types.variants(graph, ty)) |range| return .{ .variants = range };
        if (types.fields(graph, ty)) |range| return .{ .fields = range };
        return .leaf;
    }

    pub fn len(self: Shape) usize {
        return switch (self) {
            .leaf => 0,
            .fields => |range| range.len,
            .variants => |range| range.len,
        };
    }

    pub fn child(self: Shape, graph: *const g.GlobalSemanticGraph, index: usize) ?Child {
        if (index >= self.len()) return null;
        return switch (self) {
            .leaf => null,
            .fields => |range| .{
                .projection = .{ .field = @intCast(index) },
                .ty = graph.fields.items[range.start + index].ty,
            },
            .variants => |range| .{
                .projection = .{ .variant = @enumFromInt(range.start + index) },
                .ty = graph.variants.items[range.start + index].payload_type orelse return null,
            },
        };
    }
};

test "cleanup counts exclude payloadless variants and stop at reference leaves" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    const name = p.StringRange{ .start = 0, .len = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } },
        .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 2 } } },
    });
    try graph.fields.appendSlice(a, &.{
        .{ .name = name, .ty = @enumFromInt(0), .source = source },
        .{ .name = name, .ty = @enumFromInt(0), .source = source },
    });
    try graph.variants.appendSlice(a, &.{
        .{ .name = name, .value = 0, .source = source },
        .{ .name = name, .value = 1, .source = source, .payload_type = @enumFromInt(1) },
    });
    var counts: Counts = .{};
    defer counts.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), try counts.count(a, &graph, @enumFromInt(0)));
    try std.testing.expectEqual(@as(usize, 3), try counts.count(a, &graph, @enumFromInt(1)));
    try std.testing.expectEqual(@as(usize, 1), try counts.count(a, &graph, @enumFromInt(2)));
    try std.testing.expectEqual(@as(usize, 5), try counts.count(a, &graph, @enumFromInt(3)));
}

test "cleanup counts reject overflowing repeated aggregate layouts" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    for (0..@bitSizeOf(usize)) |index| {
        const start: u32 = @intCast(graph.fields.items.len);
        for (0..2) |_| try graph.fields.append(a, .{
            .name = .{ .start = 0, .len = 0 },
            .ty = @enumFromInt(index),
            .source = source,
        });
        try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = start, .len = 2 } } });
    }
    var counts: Counts = .{};
    defer counts.deinit(a);
    try std.testing.expectError(error.Overflow, counts.count(a, &graph, @enumFromInt(@bitSizeOf(usize))));
}

// Conservative ownership classification from already-selected frontend evidence.
// Used at executor/freeze boundaries, never to resolve conformance again.
pub fn owningTypes(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) ![]bool {
    const standard_contracts = @import("../4_semantics/global/standard_contracts.zig");
    const cleanup_types = try allocator.alloc(bool, graph.types.items.len);
    @memset(cleanup_types, false);
    if (standard_contracts.standardDeclaration(graph, "Deinit")) |deinit| {
        for (graph.contract_conformances.items) |conformance| {
            if (conformance.declaration != deinit or conformance.participants.len == 0) continue;
            const participant = graph.generic_arguments.items[conformance.participants.start].value;
            if (participant == .type and graph.semanticType(participant.type) != .pointer)
                cleanup_types[@intFromEnum(participant.type)] = true;
        }
    }
    // Read selected frontend evidence and structural ownership. This is
    // only a lowering boundary check, never another conformance resolver.
    var changed = true;
    while (changed) {
        changed = false;
        for (graph.types.items, 0..) |_, index| {
            if (cleanup_types[index]) continue;
            const ty: g.GlobalTypeId = @enumFromInt(index);
            if (graph.semanticType(ty) == .pointer) continue;
            var owns_cleanup = false;
            if (types.arrayElement(graph, ty)) |element| {
                owns_cleanup = cleanup_types[@intFromEnum(element)];
            } else if (types.fields(graph, ty)) |fields| {
                for (graph.fields.items[fields.start..][0..fields.len]) |field| {
                    if (cleanup_types[@intFromEnum(field.ty)]) {
                        owns_cleanup = true;
                        break;
                    }
                }
            } else if (types.variants(graph, ty)) |variants| {
                for (graph.variants.items[variants.start..][0..variants.len]) |variant| {
                    if (variant.payload_type) |payload| if (cleanup_types[@intFromEnum(payload)]) {
                        owns_cleanup = true;
                        break;
                    };
                }
            }
            if (owns_cleanup) {
                cleanup_types[index] = true;
                changed = true;
            }
        }
    }
    return cleanup_types;
}

test "indirect cleanup storage never manufactures flags on its reference slot" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: p.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } } });
    try graph.bindings.appendSlice(a, &.{
        .{ .name = .{ .start = 0, .len = 0 }, .source = source, .ty = @enumFromInt(0), .mutability = .variable },
        .{ .name = .{ .start = 0, .len = 0 }, .source = source, .ty = @enumFromInt(1), .mutability = .variable },
    });
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = @enumFromInt(1), .content = .{ .binding_use = @enumFromInt(1) } },
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .dereference = .{ .pointer = @enumFromInt(0), .ty = @enumFromInt(0), .pointer_type = @enumFromInt(1) } } },
    });
    try graph.auto_deinits.append(a, .{ .storage = .{ .indirect = @enumFromInt(1) }, .deinit_fn = null });
    const indirect = try requiredBindings(a, &graph);
    defer a.free(indirect);
    try std.testing.expect(!indirect[0] and !indirect[1]);
    try std.testing.expect(graph.auto_deinits.items[0].ownerBinding() == null);
    try std.testing.expectEqual(@as(g.GlobalNodeId, @enumFromInt(1)), graph.auto_deinits.items[0].targetNode().?);
    graph.auto_deinits.items[0].storage = .{ .projected = .{ .binding = @enumFromInt(0), .target = @enumFromInt(1) } };
    const projected = try requiredBindings(a, &graph);
    defer a.free(projected);
    try std.testing.expect(projected[0] and !projected[1]);
}

test "cleanup layout retention preserves shared children independently of source storage" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var source_leaf: Layout = .{};
    var source_children = [_]?Layout.Span{
        .{ .offset = 1, .ty = @enumFromInt(0), .layout = &source_leaf },
        .{ .offset = 2, .ty = @enumFromInt(0), .layout = &source_leaf },
    };
    var source: Layout = .{ .count = 3, .is_record = true, .children = &source_children };
    var copy: Layout.Copy = .{ .allocator = arena.allocator() };
    defer copy.deinit();
    try copy.measure(&source, 0);
    try std.testing.expectEqual(@as(usize, 4), copy.cells);
    const retained = try copy.retain(&source, 0);
    try std.testing.expect(retained != &source);
    try std.testing.expect(retained.children[0].?.layout != &source_leaf);
    try std.testing.expect(retained.children[0].?.layout == retained.children[1].?.layout);
    source_leaf.count = 99;
    source_children[0] = null;
    source.count = 1;
    try std.testing.expectEqual(@as(usize, 3), retained.count);
    try std.testing.expectEqual(@as(usize, 1), retained.project(.{ .field = 0 }).?.layout.count);
    try std.testing.expect(retained.project(.{ .variant = 0 }) == null);
}

test "cleanup layout comparisons do not cache rejected shapes as valid" {
    const a = std.testing.allocator;
    var equal: Layout.Equal = .{ .allocator = a };
    defer equal.deinit();
    const leaf: Layout = .{};
    const expected: Layout = .{ .count = 2, .is_record = true, .children = &.{.{ .offset = 1, .ty = @enumFromInt(0), .layout = &leaf }} };
    const forged: Layout = .{ .count = 2, .is_record = true, .children = &.{.{ .offset = 0, .ty = @enumFromInt(0), .layout = &leaf }} };
    try std.testing.expect(!try equal.compare(&expected, &forged, 0));
    try std.testing.expect(!try equal.compare(&expected, &forged, 0));
    try std.testing.expect(try equal.compare(&expected, &expected, 0));
}

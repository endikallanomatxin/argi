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
    pub const Repetition = struct { ty: g.GlobalTypeId, element: *const Layout, length: usize };
    count: usize = 1,
    repetition: ?Repetition = null,
    children: []const ?Span = &.{},
    is_record: bool = false,
    is_choice: bool = false,

    pub fn repeated(ty: g.GlobalTypeId, element: *const Layout, length: usize) error{Overflow}!Layout {
        return .{ .count = try std.math.add(usize, 1, try std.math.mul(usize, element.count, length)), .repetition = .{ .ty = ty, .element = element, .length = length } };
    }

    pub fn project(self: *const Layout, projection: @import("bytecode/value.zig").Projection) ?Span {
        const index: usize = switch (projection) {
            .field => |index| if (self.is_record) index else return null,
            .variant => |index| if (self.is_choice) index else return null,
            .element => |index| {
                const array = self.repetition orelse return null;
                if (index >= array.length) return null;
                return .{ .offset = 1 + index * array.element.count, .ty = array.ty, .layout = array.element };
            },
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
            if ((left.repetition == null) != (right.repetition == null)) return false;
            const key: Pair = .{ .left = left, .right = right };
            if (self.seen.contains(key)) return true;
            if (left.repetition) |array| {
                const other = right.repetition.?;
                if (array.ty != other.ty or array.length != other.length or !try self.compare(array.element, other.element, depth + 1)) return false;
            }
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
            if (source.repetition) |array| try self.measure(array.element, depth + 1);
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
            if (source.repetition) |array| result.repetition = .{ .ty = array.ty, .length = array.length, .element = try self.retain(array.element, depth + 1) };
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
        if (types.arrayElement(graph, ty)) |element| {
            _ = try self.count(allocator, graph, element);
            const length = std.math.cast(usize, types.arrayLength(graph, ty).?) orelse return error.Overflow;
            const result = try allocator.create(Layout);
            errdefer allocator.destroy(result);
            result.* = try Layout.repeated(element, self.retained(element), length);
            try self.values.put(allocator, ty, result);
            return result.count;
        }
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
// without payloads have no child storage. Array flag geometry is represented
// by Layout.repetition; Shape only enumerates declared fields and variants.
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

// Graph slots are storage positions, not type identities. Keep selected claims
// in the language's existing equality domain; coarse nominal/shape hashes avoid
// recursively hashing reference cycles or inventing a second type identity.
const SelectedCleanupContext = struct {
    graph: *const g.GlobalSemanticGraph,

    pub fn hash(self: @This(), id: g.GlobalTypeId) u64 {
        const ty = self.graph.semanticType(id);
        var result = std.hash.Wyhash.init(0);
        std.hash.autoHash(&result, std.meta.activeTag(ty));
        switch (ty) {
            .declared => |declaration| std.hash.autoHash(&result, declaration),
            .builtin => |builtin| std.hash.autoHash(&result, builtin),
            .generic => |generic| std.hash.autoHash(&result, generic.base),
            .array => |array| std.hash.autoHash(&result, array.length),
            .structural => |shape| std.hash.autoHash(&result, shape.fields.len),
            .structural_choice => |shape| std.hash.autoHash(&result, shape.variants.len),
            else => {},
        }
        return result.final();
    }

    pub fn eql(self: @This(), left: g.GlobalTypeId, right: g.GlobalTypeId) bool {
        return types.equal(self.graph, left, right);
    }
};

// Conservative ownership classification from already-selected frontend evidence.
// Used at executor/freeze boundaries, never to resolve conformance again.
pub fn owningTypes(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) ![]bool {
    const standard_contracts = @import("../4_semantics/global/standard_contracts.zig");
    const cleanup_types = try allocator.alloc(bool, graph.types.items.len);
    errdefer allocator.free(cleanup_types);
    @memset(cleanup_types, false);
    var selected: std.HashMapUnmanaged(g.GlobalTypeId, void, SelectedCleanupContext, 80) = .empty;
    defer selected.deinit(allocator);
    const context: SelectedCleanupContext = .{ .graph = graph };
    if (standard_contracts.standardDeclaration(graph, "Deinit")) |deinit| {
        for (graph.contract_conformances.items) |conformance| {
            if (conformance.declaration != deinit or conformance.participants.len == 0) continue;
            const participant = graph.generic_arguments.items[conformance.participants.start].value;
            if (participant == .type and graph.semanticType(participant.type) != .pointer) {
                cleanup_types[@intFromEnum(participant.type)] = true;
                try selected.putContext(allocator, participant.type, {}, context);
            }
        }
    }
    if (selected.count() == 0) return cleanup_types;

    // Globalization and generic materialization can retain equivalent types
    // in distinct slots. Propagate existing evidence without resolving again.
    for (cleanup_types, 0..) |*owns, index| {
        if (!owns.*) owns.* = selected.containsContext(@enumFromInt(index), context);
    }
    // Decode storage children once per classification, not once per fixed-point
    // round. The graph is read-only here; only the local ownership bits grow.
    // Keep discovery order so late children propagate exactly as in a full sweep.
    const Children = union(enum) {
        element: g.GlobalTypeId,
        fields: g.FieldRange,
        variants: g.VariantRange,

        fn owns(self: @This(), source: *const g.GlobalSemanticGraph, owning: []const bool) bool {
            return switch (self) {
                .element => |element| owning[@intFromEnum(element)],
                .fields => |fields| for (source.fields.items[fields.start..][0..fields.len]) |field| {
                    if (owning[@intFromEnum(field.ty)]) break true;
                } else false,
                .variants => |variants| for (source.variants.items[variants.start..][0..variants.len]) |variant| {
                    if (variant.payload_type) |payload| if (owning[@intFromEnum(payload)]) break true;
                } else false,
            };
        }
    };
    var pending: std.ArrayList(struct { ty: g.GlobalTypeId, children: Children }) = .empty;
    defer pending.deinit(allocator);
    for (cleanup_types, 0..) |owns, index| {
        if (owns) continue;
        const ty: g.GlobalTypeId = @enumFromInt(index);
        if (graph.semanticType(ty) == .pointer) continue;
        const children: Children = if (types.arrayElement(graph, ty)) |element|
            .{ .element = element }
        else if (types.fields(graph, ty)) |fields|
            .{ .fields = fields }
        else if (types.variants(graph, ty)) |variants|
            .{ .variants = variants }
        else
            continue;
        try pending.append(allocator, .{ .ty = ty, .children = children });
    }
    // No conformance is resolved here. Selected nominal evidence and structural
    // children still determine the same conservative ownership fixed point.
    var changed = true;
    while (changed) {
        changed = false;
        var write: usize = 0;
        for (pending.items) |candidate| {
            if (candidate.children.owns(graph, cleanup_types)) {
                cleanup_types[@intFromEnum(candidate.ty)] = true;
                changed = true;
            } else {
                pending.items[write] = candidate;
                write += 1;
            }
        }
        pending.shrinkRetainingCapacity(write);
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

test "repeated cleanup layouts project logical elements without expanding metadata" {
    const leaf: Layout = .{};
    const element: Layout = .{ .count = 2, .is_record = true, .children = &.{.{ .offset = 1, .ty = @enumFromInt(0), .layout = &leaf }} };
    const array = try Layout.repeated(@enumFromInt(1), &element, 1_000_000);
    try std.testing.expectEqual(@as(usize, 2_000_001), array.count);
    try std.testing.expectEqual(@as(usize, 0), array.children.len);
    const last = array.project(.{ .element = 999_999 }).?;
    try std.testing.expectEqual(@as(usize, 1_999_999), last.offset);
    try std.testing.expect(last.layout == &element);
    try std.testing.expect(array.project(.{ .element = 1_000_000 }) == null);
    try std.testing.expect(array.project(.{ .field = 0 }) == null);
    const empty = try Layout.repeated(@enumFromInt(1), &element, 0);
    try std.testing.expectEqual(@as(usize, 1), empty.count);
    try std.testing.expect(empty.project(.{ .element = 0 }) == null);
    try std.testing.expectError(error.Overflow, Layout.repeated(@enumFromInt(1), &element, std.math.maxInt(usize)));
}

test "repeated cleanup retention shares nested elements and validates dimensions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const leaf: Layout = .{};
    const inner = try Layout.repeated(@enumFromInt(0), &leaf, 1_000_000);
    const outer = try Layout.repeated(@enumFromInt(1), &inner, 2);
    var copy: Layout.Copy = .{ .allocator = arena.allocator() };
    defer copy.deinit();
    try copy.measure(&outer, 0);
    try std.testing.expectEqual(@as(usize, 3), copy.cells);
    const retained = try copy.retain(&outer, 0);
    try std.testing.expect(retained.repetition.?.element != &inner);
    var equal: Layout.Equal = .{ .allocator = arena.allocator() };
    defer equal.deinit();
    try std.testing.expect(try equal.compare(&outer, retained, 0));
    const wrong_length = try Layout.repeated(@enumFromInt(1), &inner, 3);
    try std.testing.expect(!try equal.compare(&outer, &wrong_length, 0));
    try std.testing.expectEqual(@as(usize, 1_000_002), retained.project(.{ .element = 1 }).?.offset);
}

test "cleanup counts cache repeated array elements without per-element descriptors" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 1_000_000 } },
        .{ .array = .{ .element = @enumFromInt(1), .length = 2 } },
        .{ .array = .{ .element = @enumFromInt(0), .length = std.math.maxInt(u64) } },
    });
    var counts: Counts = .{};
    defer counts.deinit(a);
    try std.testing.expectEqual(@as(usize, 2_000_003), try counts.count(a, &graph, @enumFromInt(2)));
    try std.testing.expectEqual(@as(usize, 3), counts.values.count());
    const array = counts.retained(@enumFromInt(2));
    try std.testing.expectEqual(@as(usize, 0), array.children.len);
    try std.testing.expect(array.repetition.?.element == counts.retained(@enumFromInt(1)));
    try std.testing.expectError(error.Overflow, counts.count(a, &graph, @enumFromInt(3)));
    try std.testing.expectEqual(@as(usize, 3), counts.values.count());
}

test "selected cleanup evidence covers every slot of one nominal declaration" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: p.SourceRef = .{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(a, "Deinit");
    try graph.declarations.append(a, .{ .kind = .contract_type, .name = name, .source = source });
    try graph.declarations.append(a, .{ .kind = .type, .name = try graph.addString(a, "Resource"), .source = source });
    try graph.declarations.append(a, .{ .kind = .type, .name = try graph.addString(a, "Other"), .source = source });
    try graph.modules.append(a, .{ .dir = name, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 3 }, .is_bundled_core = true });
    try graph.types.appendSlice(a, &.{
        .{ .declared = @enumFromInt(1) },
        .{ .declared = @enumFromInt(1) },
        .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } },
        .{ .array = .{ .element = @enumFromInt(1), .length = 2 } },
        .{ .declared = @enumFromInt(2) },
    });
    try graph.generic_arguments.append(a, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = @enumFromInt(0) } });
    try graph.contract_conformances.append(a, .{ .declaration = @enumFromInt(0), .participants = .{ .start = 0, .len = 1 }, .associated_arguments = .{ .start = 0, .len = 0 }, .source = source });
    const owning = try owningTypes(a, &graph);
    defer a.free(owning);
    try std.testing.expect(types.equal(&graph, @enumFromInt(0), @enumFromInt(1)));
    try std.testing.expect(owning[0] and owning[1] and owning[3]);
    try std.testing.expect(!owning[2] and !owning[4]);
}

test "selected cleanup evidence covers equivalent generic argument slots" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: p.SourceRef = .{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(a, "Deinit");
    try graph.declarations.append(a, .{ .kind = .contract_type, .name = name, .source = source });
    try graph.declarations.append(a, .{ .kind = .type, .name = try graph.addString(a, "Box"), .source = source });
    try graph.modules.append(a, .{ .dir = name, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 2 }, .is_bundled_core = true });
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .builtin = .Int32 },
        .{ .builtin = .UInt32 },
        .{ .generic = .{ .base = @enumFromInt(1), .arguments = .{ .start = 0, .len = 1 } } },
        .{ .generic = .{ .base = @enumFromInt(1), .arguments = .{ .start = 1, .len = 1 } } },
        .{ .generic = .{ .base = @enumFromInt(1), .arguments = .{ .start = 2, .len = 1 } } },
    });
    for (0..3) |index|
        try graph.generic_arguments.append(a, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = @enumFromInt(index) } });
    try graph.generic_arguments.append(a, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = @enumFromInt(3) } });
    try graph.contract_conformances.append(a, .{ .declaration = @enumFromInt(0), .participants = .{ .start = 3, .len = 1 }, .associated_arguments = .{ .start = 0, .len = 0 }, .source = source });
    const owning = try owningTypes(a, &graph);
    defer a.free(owning);
    try std.testing.expect(types.equal(&graph, @enumFromInt(3), @enumFromInt(4)));
    try std.testing.expect(owning[3] and owning[4]);
    try std.testing.expect(!owning[0] and !owning[1] and !owning[2] and !owning[5]);
}

test "cleanup ownership follows late aggregate children and generic aliases without following pointers" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: p.SourceRef = .{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(a, "Deinit");
    try graph.declarations.append(a, .{ .kind = .contract_type, .name = name, .source = source });
    try graph.declarations.append(a, .{ .kind = .type, .name = try graph.addString(a, "Resource"), .source = source });
    try graph.declarations.append(a, .{ .kind = .type, .name = try graph.addString(a, "Alias"), .source = source });
    try graph.modules.append(a, .{ .dir = name, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 3 }, .is_bundled_core = true });
    try graph.fields.appendSlice(a, &.{
        .{ .name = name, .source = source, .ty = @enumFromInt(1) },
        .{ .name = name, .source = source, .ty = @enumFromInt(5) },
    });
    try graph.variants.appendSlice(a, &.{
        .{ .name = name, .source = source, .value = 0, .payload_type = @enumFromInt(3) },
        .{ .name = name, .source = source, .value = 1, .payload_type = null },
    });
    try graph.types.appendSlice(a, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
        .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 2 } } },
        .{ .array = .{ .element = @enumFromInt(4), .length = 2 } },
        .{ .generic = .{ .base = @enumFromInt(2), .arguments = .{ .start = 0, .len = 0 } } },
        .{ .declared = @enumFromInt(1) },
        .{ .pointer = .{ .child = @enumFromInt(4), .mutability = .read_write } },
        .{ .structural = .{ .fields = .{ .start = 1, .len = 1 } } },
        .{ .builtin = .Int32 },
        .{ .array = .{ .element = @enumFromInt(4), .length = 0 } },
        .{ .structural_choice = .{ .variants = .{ .start = 1, .len = 1 } } },
    });
    try graph.generic_instances.append(a, .{ .type_id = @enumFromInt(3), .shape = .{ .alias = @enumFromInt(2) } });
    try graph.generic_arguments.append(a, .{ .name = name, .value = .{ .type = @enumFromInt(4) } });
    try graph.contract_conformances.append(a, .{ .declaration = @enumFromInt(0), .participants = .{ .start = 0, .len = 1 }, .associated_arguments = .{ .start = 0, .len = 0 }, .source = source });
    try std.testing.checkAllAllocationFailures(a, struct {
        fn classify(allocator: std.mem.Allocator, g_: *const g.GlobalSemanticGraph) !void {
            const owning = try owningTypes(allocator, g_);
            defer allocator.free(owning);
            try std.testing.expectEqualSlices(bool, &.{ true, true, true, true, true, false, false, false, true, false }, owning);
        }
    }.classify, .{&graph});
    // No seed evidence means no structural type can acquire cleanup merely
    // from a layout. Recompute from the current graph, never a previous result.
    graph.contract_conformances.clearRetainingCapacity();
    const empty = try owningTypes(a, &graph);
    defer a.free(empty);
    for (empty) |owns| try std.testing.expect(!owns);
}

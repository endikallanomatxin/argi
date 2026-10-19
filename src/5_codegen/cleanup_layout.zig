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
pub const Counts = struct {
    pub const Span = struct { offset: usize, ty: g.GlobalTypeId };
    pub const Description = struct { count: usize, children: []const ?Span, is_record: bool };
    values: std.AutoHashMapUnmanaged(g.GlobalTypeId, Description) = .empty,

    pub fn deinit(self: *Counts, allocator: std.mem.Allocator) void {
        var entries = self.values.valueIterator();
        while (entries.next()) |entry| allocator.free(entry.children);
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
        var result: usize = 1;
        for (children, 0..) |*span, index| if (shape.child(graph, index)) |child| {
            span.* = .{ .offset = result, .ty = child.ty };
            result = try std.math.add(usize, result, try self.count(allocator, graph, child.ty));
        };
        try self.values.put(allocator, ty, .{ .count = result, .children = children, .is_record = shape == .fields });
        return result;
    }

    // A retained view only refers to a type already materialized by count().
    // Return by value: map growth must never invalidate an owner's view.
    pub fn description(self: *const Counts, ty: g.GlobalTypeId) Description {
        return self.values.get(ty).?;
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
    try std.testing.expectEqual(@as(usize, 4), try counts.count(a, &graph, @enumFromInt(3)));
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

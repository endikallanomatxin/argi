const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const p = @import("../4_semantics/primitives/schema.zig");

// Reference evidence belongs to value leaves, independently of that value's
// own cleanup flags. A copied reference retains its referent's storage view;
// copying the enclosing record never clones the referent's obligations.
pub const Shape = union(enum) {
    leaf,
    reference,
    virtual_reference,
    fields: g.FieldRange,
    variants: g.VariantRange,
    array: struct { element: g.GlobalTypeId, length: u64 },
    alias: g.GlobalTypeId,
};

pub const Projection = union(enum) { field: u32, variant: g.GlobalVariantId, element: u64 };
pub const Slice = struct { offset: usize, count: usize, ty: g.GlobalTypeId };
pub const Error = error{ OutOfMemory, Overflow, InvalidReferenceLayout, InvalidReferenceProjection };

// Cache against one retained, finalized graph. Counting arrays uses arithmetic,
// never one entry per element; pointer recursion stops at the reference leaf.
pub const Layout = struct {
    counts: std.AutoHashMapUnmanaged(g.GlobalTypeId, ?usize) = .empty,

    pub fn deinit(self: *Layout, allocator: std.mem.Allocator) void {
        self.counts.deinit(allocator);
    }

    pub fn shape(graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) Error!Shape {
        const semantic = graph.resolvedSemanticType(ty) orelse return error.InvalidReferenceLayout;
        return switch (semantic) {
            .pointer => .reference,
            .builtin, .definition => .leaf,
            .array => |a| .{ .array = .{ .element = a.element, .length = a.length } },
            .structural => |s| .{ .fields = s.fields },
            inline .structural_choice, .inferred_choice => |s| .{ .variants = s.variants },
            .nominal => |id| blk: {
                const declaration = graph.typeDefinition(id);
                if (declaration.underlying_type) |target| break :blk .{ .alias = target };
                if (declaration.struct_layout == .c_function_pointer) break :blk .leaf;
                if (declaration.struct_fields) |fields| break :blk .{ .fields = fields };
                if (declaration.choice_variants) |variants| break :blk .{ .variants = variants };
                return error.InvalidReferenceLayout;
            },
            .generic => blk: {
                const instance = @import("../4_semantics/global/types.zig").genericInstance(graph, ty) orelse return error.InvalidReferenceLayout;
                break :blk switch (instance.shape) {
                    .structure => |s| .{ .fields = s.fields },
                    .choice => |s| .{ .variants = s.variants },
                    .array => |a| .{ .array = .{ .element = a.element, .length = a.length } },
                    .alias => |target| .{ .alias = target },
                };
            },
            // The value already carries its selected method table. Its one
            // erased receiver retains a storage view independently of that table.
            .virtual => .virtual_reference,
            .nullable, .inferred_errable => error.InvalidReferenceLayout,
        };
    }

    pub fn count(self: *Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) Error!usize {
        if (self.counts.get(ty)) |cached| return cached orelse error.InvalidReferenceLayout;
        try self.counts.put(allocator, ty, null);
        errdefer _ = self.counts.remove(ty);
        const result: usize = switch (try shape(graph, ty)) {
            .leaf => 0,
            .reference, .virtual_reference => 1,
            .alias => |target| try self.count(allocator, graph, target),
            .array => |a| blk: {
                if (a.length == 0) break :blk 0;
                const per_element = try self.count(allocator, graph, a.element);
                if (per_element == 0) break :blk 0;
                const length = std.math.cast(usize, a.length) orelse return error.Overflow;
                break :blk try std.math.mul(usize, length, per_element);
            },
            .fields => |fields| blk: {
                var total: usize = 0;
                for (graph.fields.items[fields.start..][0..fields.len]) |field|
                    total = try std.math.add(usize, total, try self.count(allocator, graph, field.ty));
                break :blk total;
            },
            // Variants occupy distinct evidence ranges. Only the selected
            // payload's range is valid; projection does not read inactive data.
            .variants => |variants| blk: {
                var total: usize = 0;
                for (graph.variants.items[variants.start..][0..variants.len]) |variant| if (variant.payload_type) |payload| {
                    total = try std.math.add(usize, total, try self.count(allocator, graph, payload));
                };
                break :blk total;
            },
        };
        // Recursive counting may rehash the cache; never retain entry pointers.
        try self.counts.put(allocator, ty, result);
        return result;
    }

    pub fn project(self: *Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, projection: Projection) Error!Slice {
        _ = try self.count(allocator, graph, ty);
        switch (try shape(graph, ty)) {
            .alias => |target| return self.project(allocator, graph, target, projection),
            .array => |a| {
                if (projection != .element or projection.element >= a.length) return error.InvalidReferenceProjection;
                const size = try self.count(allocator, graph, a.element);
                const offset = if (size == 0) 0 else try std.math.mul(usize, std.math.cast(usize, projection.element) orelse return error.Overflow, size);
                return .{ .offset = offset, .count = size, .ty = a.element };
            },
            .fields => |fields| {
                if (projection != .field or projection.field >= fields.len) return error.InvalidReferenceProjection;
                var offset: usize = 0;
                for (graph.fields.items[fields.start..][0..projection.field]) |field|
                    offset = try std.math.add(usize, offset, try self.count(allocator, graph, field.ty));
                const child = graph.fields.items[fields.start + projection.field].ty;
                return .{ .offset = offset, .count = try self.count(allocator, graph, child), .ty = child };
            },
            .variants => |variants| {
                if (projection != .variant) return error.InvalidReferenceProjection;
                const raw = @intFromEnum(projection.variant);
                if (raw < variants.start or raw - variants.start >= variants.len) return error.InvalidReferenceProjection;
                var offset: usize = 0;
                for (graph.variants.items[variants.start..raw]) |variant| if (variant.payload_type) |payload| {
                    offset = try std.math.add(usize, offset, try self.count(allocator, graph, payload));
                };
                const child = graph.variants.items[raw].payload_type orelse return error.InvalidReferenceProjection;
                return .{ .offset = offset, .count = try self.count(allocator, graph, child), .ty = child };
            },
            else => return error.InvalidReferenceProjection,
        }
    }
};

test "reference evidence separates recursive referents fields arrays and choice payloads" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    const name = p.StringRange{ .start = 0, .len = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(2), .mutability = .read_write } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 3 } } },
        .{ .array = .{ .element = @enumFromInt(2), .length = 4 } },
        .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 3 } } },
        .{ .array = .{ .element = @enumFromInt(1), .length = 0 } },
    });
    for ([_]u32{ 1, 0, 1 }) |ty| try graph.fields.append(a, .{ .name = name, .ty = @enumFromInt(ty), .source = source });
    for ([_]?g.GlobalTypeId{ null, @enumFromInt(1), @enumFromInt(2) }, 0..) |payload, index|
        try graph.variants.append(a, .{ .name = name, .value = @intCast(index), .source = source, .payload_type = payload });
    var layout: Layout = .{};
    defer layout.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), try layout.count(a, &graph, @enumFromInt(2)));
    try std.testing.expectEqual(@as(usize, 8), try layout.count(a, &graph, @enumFromInt(3)));
    try std.testing.expectEqual(@as(usize, 3), try layout.count(a, &graph, @enumFromInt(4)));
    try std.testing.expectEqual(@as(usize, 0), try layout.count(a, &graph, @enumFromInt(5)));
    const first = try layout.project(a, &graph, @enumFromInt(2), .{ .field = 0 });
    const second = try layout.project(a, &graph, @enumFromInt(2), .{ .field = 2 });
    try std.testing.expectEqual(@as(usize, 0), first.offset);
    try std.testing.expectEqual(@as(usize, 1), second.offset);
    const element = try layout.project(a, &graph, @enumFromInt(3), .{ .element = 3 });
    try std.testing.expectEqual(@as(usize, 6), element.offset);
    const payload = try layout.project(a, &graph, @enumFromInt(4), .{ .variant = @enumFromInt(2) });
    try std.testing.expectEqual(@as(usize, 1), payload.offset);
    try std.testing.expectEqual(@as(usize, 2), payload.count);
    try std.testing.expectError(error.InvalidReferenceProjection, layout.project(a, &graph, @enumFromInt(4), .{ .variant = @enumFromInt(0) }));
    try std.testing.expectError(error.InvalidReferenceProjection, layout.project(a, &graph, @enumFromInt(2), .{ .element = 0 }));
    try std.testing.expectError(error.InvalidReferenceProjection, layout.project(a, &graph, @enumFromInt(3), .{ .element = 4 }));
}

test "reference evidence bounds repeated layouts and rejects cycles without poisoning cache" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .array = .{ .element = @enumFromInt(0), .length = std.math.maxInt(u64) } },
        .{ .array = .{ .element = @enumFromInt(1), .length = 2 } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
    });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(3), .source = source });
    var layout: Layout = .{};
    defer layout.deinit(a);
    try std.testing.expectError(error.Overflow, layout.count(a, &graph, @enumFromInt(2)));
    try std.testing.expectError(error.InvalidReferenceLayout, layout.count(a, &graph, @enumFromInt(3)));
    try std.testing.expect(!layout.counts.contains(@enumFromInt(3)));
    try std.testing.expectEqual(@as(usize, 1), try layout.count(a, &graph, @enumFromInt(0)));
}

test "reference evidence follows materialized nominal and generic shapes" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    const name = p.StringRange{ .start = 0, .len = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .UInt8 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .nominal = @enumFromInt(0) },
        .{ .generic = .{ .base = @enumFromInt(0), .arguments = .{ .start = 0, .len = 0 } } },
        .{ .generic = .{ .base = @enumFromInt(0), .arguments = .{ .start = 0, .len = 0 } } },
        .{ .virtual = @enumFromInt(2) },
    });
    try graph.fields.append(a, .{ .name = name, .ty = @enumFromInt(1), .source = source });
    try graph.declarations.append(a, .{ .name = name, .source = source, .kind = .type });
    try graph.type_definitions.append(a, .{ .source = source, .struct_fields = .{ .start = 0, .len = 1 } });
    try graph.generic_instances.appendSlice(a, &.{
        .{ .type_id = @enumFromInt(3), .shape = .{ .array = .{ .element = @enumFromInt(2), .length = 7 } } },
        .{ .type_id = @enumFromInt(4), .shape = .{ .alias = @enumFromInt(3) } },
    });
    var layout: Layout = .{};
    defer layout.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), try layout.count(a, &graph, @enumFromInt(2)));
    try std.testing.expectEqual(@as(usize, 7), try layout.count(a, &graph, @enumFromInt(4)));
    const element = try layout.project(a, &graph, @enumFromInt(4), .{ .element = 6 });
    try std.testing.expectEqual(@as(usize, 6), element.offset);
    try std.testing.expectEqual(@as(g.GlobalTypeId, @enumFromInt(2)), element.ty);
    try std.testing.expectEqual(@as(usize, 1), try layout.count(a, &graph, @enumFromInt(5)));
}

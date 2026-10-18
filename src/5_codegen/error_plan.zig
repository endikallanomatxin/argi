const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");

/// Representation facts of an already-checked propagation. Backends emit their
/// own control flow; neither chooses reasons nor reconstructs tracer evidence.
pub const Payload = struct {
    source_reason: types.FieldHit,
    target_reason: types.FieldHit,
    source_tracer: types.FieldHit,
    target_tracer: types.FieldHit,
};

pub fn payload(graph: *const g.GlobalSemanticGraph, source: g.GlobalTypeId, target: g.GlobalTypeId) !Payload {
    const result: Payload = .{
        .source_reason = types.findField(graph, source, "reason") orelse return error.InvalidErrorPlan,
        .target_reason = types.findField(graph, target, "reason") orelse return error.InvalidErrorPlan,
        .source_tracer = types.findField(graph, source, "tracer") orelse return error.InvalidErrorPlan,
        .target_tracer = types.findField(graph, target, "tracer") orelse return error.InvalidErrorPlan,
    };
    if (!types.equal(graph, result.source_tracer.field.ty, result.target_tracer.field.ty)) return error.InvalidErrorPlan;
    return result;
}

/// Reason sets carry nominal variants. Map those identities by their checked
/// names, independently of either backend's physical discriminant encoding.
pub fn reasonTarget(graph: *const g.GlobalSemanticGraph, source_type: g.GlobalTypeId, target_type: g.GlobalTypeId, source: g.GlobalVariantId) !g.GlobalVariantId {
    const variants = types.variants(graph, source_type) orelse return error.InvalidErrorPlan;
    const raw = @intFromEnum(source);
    if (raw < variants.start or raw - variants.start >= variants.len) return error.InvalidErrorPlan;
    const variant = graph.variants.items[raw];
    if (variant.payload_type != null) return error.InvalidErrorPlan;
    const target = types.findVariant(graph, target_type, graph.text(variant.name)) orelse return error.InvalidErrorPlan;
    if (target.variant.payload_type != null) return error.InvalidErrorPlan;
    return target.id;
}

test "error reason plans preserve identities across reordered reason sets" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const first = try graph.addString(a, "first");
    const second = try graph.addString(a, "second");
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 2 } } },
        .{ .structural_choice = .{ .variants = .{ .start = 2, .len = 2 } } },
        .{ .structural_choice = .{ .variants = .{ .start = 2, .len = 1 } } },
    });
    for ([_]@TypeOf(first){ first, second, second, first }, 0..) |name, index|
        try graph.variants.append(a, .{ .name = name, .source = source, .value = @intCast(index % 2) });
    try std.testing.expectEqual(@as(g.GlobalVariantId, @enumFromInt(3)), try reasonTarget(&graph, @enumFromInt(0), @enumFromInt(1), @enumFromInt(0)));
    try std.testing.expectEqual(@as(g.GlobalVariantId, @enumFromInt(2)), try reasonTarget(&graph, @enumFromInt(0), @enumFromInt(1), @enumFromInt(1)));
    try std.testing.expectError(error.InvalidErrorPlan, reasonTarget(&graph, @enumFromInt(0), @enumFromInt(2), @enumFromInt(0)));
    try std.testing.expectError(error.InvalidErrorPlan, reasonTarget(&graph, @enumFromInt(0), @enumFromInt(1), @enumFromInt(2)));
}

test "error payload plans preserve tracer types and resolve field positions" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const reason = try graph.addString(a, "reason");
    const tracer = try graph.addString(a, "tracer");
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .builtin = .Bool },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .structural = .{ .fields = .{ .start = 2, .len = 2 } } },
        .{ .structural = .{ .fields = .{ .start = 4, .len = 2 } } },
    });
    for ([_]@TypeOf(reason){ reason, tracer, tracer, reason, reason, tracer }, 0..) |name, index|
        try graph.fields.append(a, .{ .name = name, .source = source, .ty = @enumFromInt(@as(u32, if (index == 5) 1 else 0)) });
    const plan = try payload(&graph, @enumFromInt(2), @enumFromInt(3));
    try std.testing.expectEqual(@as(u32, 0), plan.source_reason.index);
    try std.testing.expectEqual(@as(u32, 1), plan.target_reason.index);
    try std.testing.expectEqual(@as(u32, 1), plan.source_tracer.index);
    try std.testing.expectEqual(@as(u32, 0), plan.target_tracer.index);
    try std.testing.expectError(error.InvalidErrorPlan, payload(&graph, @enumFromInt(2), @enumFromInt(4)));
}

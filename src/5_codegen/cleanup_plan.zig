const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");

// Views of finalized cleanup plans. They neither select destructors nor copy
// the plan into another IR; backends retain their own addresses and emission.
pub const Access = enum { complete, present };

pub const Child = struct {
    ty: g.GlobalTypeId,
    variant: ?g.GlobalVariantId = null,
};

pub fn child(graph: *const g.GlobalSemanticGraph, parent: g.GlobalTypeId, field: g.AutoDeinitField) !Child {
    if (field.is_variant) {
        const variants = types.variants(graph, parent) orelse return error.InvalidCleanupPlan;
        if (field.field_index >= variants.len) return error.InvalidCleanupPlan;
        const variant: g.GlobalVariantId = @enumFromInt(variants.start + field.field_index);
        return .{
            .ty = graph.variants.items[@intFromEnum(variant)].payload_type orelse return error.InvalidCleanupPlan,
            .variant = variant,
        };
    }
    const fields = types.fields(graph, parent) orelse return error.InvalidCleanupPlan;
    if (field.field_index >= fields.len) return error.InvalidCleanupPlan;
    return .{ .ty = graph.fields.items[fields.start + field.field_index].ty };
}

// Non-receiver arguments retain the selected lexical input, falling back to
// the function field's default. The backend only evaluates the chosen node.
pub fn argument(graph: *const g.GlobalSemanticGraph, input: ?g.GlobalNodeId, field: g.Field) !g.GlobalNodeId {
    if (input) |node| {
        const content = graph.node(node).content;
        if (content == .struct_value_literal) {
            const fields = content.struct_value_literal.fields;
            for (graph.value_fields.items[fields.start..][0..fields.len]) |supplied| {
                if (std.mem.eql(u8, graph.text(supplied.name), graph.text(field.name))) return supplied.value;
            }
        }
    }
    return field.default_value orelse error.InvalidCleanupPlan;
}

// Borrow the selected outcome path instead of materializing another tree.
// Each step must be guarded before projecting its payload; the final predicate
// can select a payloadless variant and never reads that payload.
pub const OutcomePath = struct {
    graph: *const g.GlobalSemanticGraph,
    ty: g.GlobalTypeId,
    parents: []const u32,
    final: u32,
    depth: usize = 0,

    pub const Step = struct {
        ty: g.GlobalTypeId,
        index: u32,
        variant: g.GlobalVariantId,
        payload: ?g.GlobalTypeId,
    };

    pub fn init(graph: *const g.GlobalSemanticGraph, outputs: g.FieldRange, cleanup: @import("../4_semantics/primitives/schema.zig").OutcomeCleanup(g.Ids)) !OutcomePath {
        if (cleanup.output_index >= outputs.len) return error.InvalidCleanupPlan;
        return .{ .graph = graph, .ty = graph.fields.items[outputs.start + cleanup.output_index].ty, .parents = cleanup.parent_variants, .final = cleanup.variant_index };
    }

    pub fn next(self: *OutcomePath) !?Step {
        if (self.depth > self.parents.len) return null;
        const parent = self.depth < self.parents.len;
        const index = if (parent) self.parents[self.depth] else self.final;
        const variants = types.variants(self.graph, self.ty) orelse return error.InvalidCleanupPlan;
        if (index >= variants.len) return error.InvalidCleanupPlan;
        const variant: g.GlobalVariantId = @enumFromInt(variants.start + index);
        const payload = if (parent)
            self.graph.variants.items[@intFromEnum(variant)].payload_type orelse return error.InvalidCleanupPlan
        else
            null;
        const step = Step{ .ty = self.ty, .index = index, .variant = variant, .payload = payload };
        if (payload) |ty| self.ty = ty;
        self.depth += 1;
        return step;
    }
};

test "cleanup outcome paths guard parents and preserve nominal variant identities" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const name = @import("../4_semantics/primitives/schema.zig").StringRange{ .start = 0, .len = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 2 } } },
        .{ .structural_choice = .{ .variants = .{ .start = 2, .len = 2 } } },
    });
    for (0..4) |index| try graph.variants.append(a, .{
        .name = name,
        .value = @intCast(index % 2),
        .source = source,
        .payload_type = if (index == 0) @enumFromInt(1) else null,
    });
    try graph.fields.append(a, .{ .name = name, .ty = @enumFromInt(0), .source = source });
    var cleanup = @import("../4_semantics/primitives/schema.zig").OutcomeCleanup(g.Ids){ .place = @enumFromInt(0), .output_index = 0, .parent_variants = &.{0}, .variant_index = 1 };
    var path = try OutcomePath.init(&graph, .{ .start = 0, .len = 1 }, cleanup);
    const outer = (try path.next()).?;
    try std.testing.expectEqual(@as(g.GlobalTypeId, @enumFromInt(1)), outer.payload.?);
    const inner = (try path.next()).?;
    try std.testing.expectEqual(@as(u32, 1), inner.index);
    try std.testing.expectEqual(@as(g.GlobalVariantId, @enumFromInt(3)), inner.variant);
    try std.testing.expect(inner.payload == null);
    try std.testing.expect(try path.next() == null);
    cleanup.parent_variants = &.{1};
    path = try OutcomePath.init(&graph, .{ .start = 0, .len = 1 }, cleanup);
    try std.testing.expectError(error.InvalidCleanupPlan, path.next());
    cleanup.parent_variants = &.{2};
    path = try OutcomePath.init(&graph, .{ .start = 0, .len = 1 }, cleanup);
    try std.testing.expectError(error.InvalidCleanupPlan, path.next());
    cleanup.output_index = 1;
    try std.testing.expectError(error.InvalidCleanupPlan, OutcomePath.init(&graph, .{ .start = 0, .len = 1 }, cleanup));
}

// One walk of the selected plan, specialized for each emitter at compile time.
// Emitters own only representation and instruction emission. No runtime visitor,
// extra IR or copied cleanup state is introduced.
pub const Operation = struct {
    deinit_fn: ?g.GlobalFunctionId,
    input: ?g.GlobalNodeId,
    self_field_index: u32,
    fields: @import("../4_semantics/primitives/schema.zig").Range(g.GlobalAutoDeinitFieldId),

    fn fromField(field: g.AutoDeinitField) Operation {
        return .{ .deinit_fn = field.deinit_fn, .input = field.input, .self_field_index = field.self_field_index, .fields = field.fields };
    }
};

pub fn emit(backend: anytype, graph: *const g.GlobalSemanticGraph, plan: Operation, target: anytype) anyerror!void {
    if (plan.deinit_fn) |callee| {
        const active = try backend.begin(target, .complete);
        try backend.call(target, callee, plan.input, plan.self_field_index);
        // Successful whole-value destruction clears its complete subtree.
        // The fallback walk therefore runs only for incomplete values.
        try backend.finish(target, active);
        if (types.variants(graph, target.ty) != null) {
            const present = try backend.begin(target, .present);
            try emitFields(backend, graph, plan, target);
            try backend.finish(target, present);
        } else {
            try emitFields(backend, graph, plan, target);
            try backend.clear(target);
        }
    } else if (types.fields(graph, target.ty) != null) {
        // An incomplete record can still contain live owning fields. Its root
        // flag must not suppress their individually guarded cleanup.
        try emitFields(backend, graph, plan, target);
        try backend.clear(target);
    } else {
        // Choices need a live discriminant before selecting a payload.
        const active = try backend.begin(target, .present);
        try emitFields(backend, graph, plan, target);
        try backend.finish(target, active);
    }
}

fn emitFields(backend: anytype, graph: *const g.GlobalSemanticGraph, plan: Operation, target: anytype) anyerror!void {
    for (graph.auto_deinit_fields.items[plan.fields.start..][0..plan.fields.len]) |field| {
        const selected = try child(graph, target.ty, field);
        if (selected.variant != null) {
            const variant = try backend.beginVariant(target, field, selected);
            try emit(backend, graph, Operation.fromField(field), try backend.project(target, field, selected));
            try backend.endVariant(variant);
        } else {
            try emit(backend, graph, Operation.fromField(field), try backend.project(target, field, selected));
        }
    }
}

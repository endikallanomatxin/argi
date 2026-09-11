const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const views = @import("views.zig");

/// Collapse the builder-era compatibility prefixes and canonical semantic tails
/// into one Module* ID space without changing any logical ID. This runs only
/// after ModuleSema has finished writing, so downstream GlobalSema never has to
/// reason about split type/field/variant/generic-argument storage.
pub fn run(allocator: std.mem.Allocator, graph: *graph_mod.ModuleSemanticGraph) !void {
    var types: std.ArrayList(entities.ModuleType) = .empty;
    errdefer types.deinit(allocator);
    try types.ensureTotalCapacity(allocator, views.typeCount(graph));
    for (0..views.typeCount(graph)) |raw|
        types.appendAssumeCapacity(try views.typeView(graph, @enumFromInt(@as(u32, @intCast(raw)))));

    var fields: std.ArrayList(entities.Field) = .empty;
    errdefer fields.deinit(allocator);
    try fields.ensureTotalCapacity(allocator, views.fieldCount(graph));
    for (0..views.fieldCount(graph)) |raw|
        fields.appendAssumeCapacity(try views.fieldView(graph, @enumFromInt(@as(u32, @intCast(raw)))));

    var variants: std.ArrayList(entities.ChoiceVariant) = .empty;
    errdefer variants.deinit(allocator);
    try variants.ensureTotalCapacity(allocator, views.variantCount(graph));
    for (0..views.variantCount(graph)) |raw|
        variants.appendAssumeCapacity(try views.variantView(graph, @enumFromInt(@as(u32, @intCast(raw)))));

    var generic_arguments: std.ArrayList(entities.GenericArgument) = .empty;
    errdefer generic_arguments.deinit(allocator);
    try generic_arguments.ensureTotalCapacity(allocator, views.genericArgumentCount(graph));
    for (0..views.genericArgumentCount(graph)) |raw|
        generic_arguments.appendAssumeCapacity(try views.genericArgumentView(graph, @enumFromInt(@as(u32, @intCast(raw)))));

    // From this point onward no fallible work remains: atomically replace the
    // split representation while preserving the logical ordering used by IDs.
    graph.types.deinit(allocator);
    graph.types = .empty;
    graph.fields.deinit(allocator);
    graph.fields = .empty;
    graph.structural_fields.deinit(allocator);
    graph.structural_fields = .empty;
    graph.choice_variant_entries.deinit(allocator);
    graph.choice_variant_entries = .empty;
    graph.structural_choice_variants.deinit(allocator);
    graph.structural_choice_variants = .empty;
    graph.generic_type_arguments.deinit(allocator);
    graph.generic_type_arguments = .empty;

    graph.semantic.types.deinit(allocator);
    graph.semantic.types = types;
    types = .empty;
    graph.semantic.fields.deinit(allocator);
    graph.semantic.fields = fields;
    fields = .empty;
    graph.semantic.variants.deinit(allocator);
    graph.semantic.variants = variants;
    variants = .empty;
    graph.semantic.generic_arguments.deinit(allocator);
    graph.semantic.generic_arguments = generic_arguments;
    generic_arguments = .empty;

    // Field/variant overlays have been folded into their canonical rows.
    graph.semantic.field_semantics.deinit(allocator);
    graph.semantic.field_semantics = .empty;
    graph.semantic.variant_semantics.deinit(allocator);
    graph.semantic.variant_semantics = .empty;
    graph.semantic.compatibility_bases = .{
        .types = 0,
        .fields = 0,
        .variants = 0,
        .generic_arguments = 0,
    };
}

pub fn hasCompatibilityPrefixes(graph: *const graph_mod.ModuleSemanticGraph) bool {
    return graph.types.items.len != 0 or
        graph.fields.items.len != 0 or
        graph.structural_fields.items.len != 0 or
        graph.choice_variant_entries.items.len != 0 or
        graph.structural_choice_variants.items.len != 0 or
        graph.generic_type_arguments.items.len != 0;
}

test "canonicalization preserves logical type IDs while draining prefixes" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.semantic.types.append(allocator, .{ .resolved = .{ .pointer = .{
        .child = @enumFromInt(0),
        .mutability = .read_only,
    } } });

    try run(allocator, &graph);
    try std.testing.expect(!hasCompatibilityPrefixes(&graph));
    try std.testing.expectEqual(@as(usize, 2), graph.semantic.types.items.len);
    try std.testing.expectEqual(@import("../primitives/schema.zig").BuiltinType.Int32, graph.semantic.types.items[0].resolved.builtin);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(graph.semantic.types.items[1].resolved.pointer.child));
}

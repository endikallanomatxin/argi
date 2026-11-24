const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const standard_contracts = @import("../global/standard_contracts.zig");
const facts = @import("facts.zig");

/// A proof about the value's current contents. Callers separately check loans,
/// live dependencies and the transfer of destruction authority.
pub fn proves(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, value: facts.ValueFacts) bool {
    return provesValue(graph, ty, value, standard_contracts.standardDefinition(graph, "Transferable"), 0);
}

fn provesValue(
    graph: *const graph_mod.GlobalSemanticGraph,
    ty: graph_mod.GlobalTypeId,
    value: facts.ValueFacts,
    marker: ?graph_mod.GlobalFamilyDefinitionId,
    depth: usize,
) bool {
    if (depth >= 64) return false;
    const semantic = graph.resolvedSemanticType(ty) orelse return false;
    // A capture's mode is a value guarantee. Execution admission separately
    // authenticates receiver and region targets and establishes their loans.
    if (semantic == .virtual) return value.concurrent_receiver;
    if (semantic == .pointer) return semantic.pointer.mutability == .concurrent;
    if (marker) |declaration| {
        for (graph.contract_conformances.items) |evidence| {
            if (evidence.declaration != declaration or !evidence.declaration_validated or evidence.participants.len != 1) continue;
            const participant = graph.generic_arguments.items[evidence.participants.start].value.type;
            if (types.equal(graph, ty, participant)) return true;
        }
    }
    // The destructor may access resources not described by the value layout.
    // Such types need a published guarantee covering their cleanup.
    if (types.hasDestructor(graph, ty) or @import("../global/c_abi.zig").isRawPointer(graph, ty) or
        @import("../global/c_abi.zig").isFunctionPointer(graph, ty)) return false;
    if (semantic == .builtin)
        return semantic.builtin != .Any and semantic.builtin != .Type;
    if (types.arrayElement(graph, ty)) |element| {
        const count = types.arrayLength(graph, ty) orelse return false;
        if (count == 0) return value.fields.len == 0;
        if (value.fields.len == 0) return provesValue(graph, element, .{}, marker, depth + 1);
        const missing_proves = provesValue(graph, element, .{}, marker, depth + 1);
        if (!missing_proves and value.fields.len != count) return false;
        for (value.fields, 0..) |entry, index| {
            if (entry.index >= count or (!missing_proves and entry.index != index)) return false;
            if (!provesValue(graph, element, entry.value.*, marker, depth + 1)) return false;
        }
        return true;
    }
    if (types.fields(graph, ty)) |fields| {
        for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
            if (!provesValue(graph, field.ty, fieldValue(value, index), marker, depth + 1)) return false;
        }
        return true;
    }
    if (types.variants(graph, ty)) |variants| {
        if (value.known_choice_variant) |index| if (index >= variants.len) return false;
        for (graph.variants.items[variants.start..][0..variants.len], 0..) |variant, index| {
            if (value.known_choice_variant) |known| if (known != index) continue;
            const payload = variant.payload_type orelse continue;
            const selected = for (value.variants) |entry| {
                if (entry.index == index) break entry.value.*;
            } else facts.ValueFacts{};
            if (!provesValue(graph, payload, selected, marker, depth + 1)) return false;
        }
        return true;
    }
    return false;
}

fn fieldValue(value: facts.ValueFacts, index: usize) facts.ValueFacts {
    for (value.fields) |field| if (field.index == index) return field.value.*;
    return .{};
}

test "erased transfer evidence belongs to the captured value" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .virtual = @enumFromInt(0) });
    const ty: graph_mod.GlobalTypeId = @enumFromInt(0);
    const receiver: facts.DomainFacts = .{
        .domain_index = @import("access_bounds.zig").receiver_domain,
        .storages = &.{.{ .root = @enumFromInt(0) }},
    };
    try std.testing.expect(!proves(&graph, ty, .{ .domains = &.{receiver} }));
    try std.testing.expect(proves(&graph, ty, .{ .concurrent_receiver = true, .domains = &.{receiver} }));
    try std.testing.expect(proves(&graph, ty, .{
        .concurrent_receiver = true,
        .reference_target_incomplete = true,
    }));
}

test "an aggregate proof follows its current erased field" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .virtual = @enumFromInt(0) },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
    });
    try graph.fields.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .ty = @enumFromInt(0),
        .source = .{ .file_index = 0, .offset = 0 },
    });
    const receiver: facts.DomainFacts = .{
        .domain_index = @import("access_bounds.zig").receiver_domain,
        .storages = &.{.{ .root = @enumFromInt(0) }},
    };
    var handle: facts.ValueFacts = .{ .concurrent_receiver = true, .domains = &.{receiver} };
    const record: facts.ValueFacts = .{ .fields = &.{.{ .index = 0, .value = &handle }} };
    try std.testing.expect(proves(&graph, @enumFromInt(1), record));
    handle.concurrent_receiver = false;
    try std.testing.expect(!proves(&graph, @enumFromInt(1), record));
}

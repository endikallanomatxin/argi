const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const standard_contracts = @import("../global/standard_contracts.zig");
const std = @import("std");
const facts = @import("facts.zig");

/// A proof about the value's current contents. Callers separately check loans,
/// live dependencies and the transfer of destruction authority.
pub fn proves(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, value: facts.ValueFacts) bool {
    return failure(graph, ty, value) == null;
}

pub fn failure(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, value: facts.ValueFacts) ?Failure {
    return valueFailure(graph, ty, value, .{
        .unconditional = standard_contracts.standardDefinition(graph, "Transferable"),
        .structural = standard_contracts.standardDefinition(graph, "StructurallyTransferable"),
    }, null, 0);
}

const Markers = struct {
    unconditional: ?graph_mod.GlobalFamilyDefinitionId,
    structural: ?graph_mod.GlobalFamilyDefinitionId,
};

pub const Failure = enum {
    unsupported,
    erased_receiver,
    ordinary_reference,
    unproved_backing,
    cleanup,
    incomplete_aggregate,

    pub fn message(self: Failure) []const u8 {
        return switch (self) {
            .unsupported => "the value has no supported transfer proof",
            .erased_receiver => "an erased capability lacks a concurrent receiver guarantee",
            .ordinary_reference => "an ordinary reference does not point to transferable backing",
            .unproved_backing => "an address is not proved to refer to backing owned by the value",
            .cleanup => "a destructor has no verified cross-execution guarantee",
            .incomplete_aggregate => "some possible elements lack transfer evidence",
        };
    }
};

fn valueFailure(
    graph: *const graph_mod.GlobalSemanticGraph,
    ty: graph_mod.GlobalTypeId,
    value: facts.ValueFacts,
    markers: Markers,
    enclosing_owner: ?facts.ValidityRootId,
    depth: usize,
) ?Failure {
    if (depth >= 64) return .unsupported;
    const semantic = graph.resolvedSemanticType(ty) orelse return .unsupported;
    // Capture mode is a value guarantee. Admission separately checks
    // authority over the receiver's possible targets and published regions.
    if (semantic == .virtual) return if (value.concurrent_receiver) null else .erased_receiver;
    if (semantic == .pointer) {
        const proven = observesTransferredBacking(value, enclosing_owner) or switch (semantic.pointer.mutability) {
            .concurrent => true,
            .read_only => observesImmutableModuleScalar(graph, value),
            .read_write => false,
        };
        return if (proven) null else .ordinary_reference;
    }
    const guarantee = if (semantic == .nominal or semantic == .generic)
        nominalGuarantee(graph, ty, markers)
    else
        .none;
    if (guarantee == .unconditional) return null;
    const owner = backingOwner(value, enclosing_owner);
    // A whole-container dependency can survive address replacement.
    if (@import("../global/c_abi.zig").isRawPointer(graph, ty))
        return if (observesTransferredBacking(fieldValue(value, 0), owner)) null else .unproved_backing;
    if (guarantee != .structural and types.hasDestructor(graph, ty)) return .cleanup;
    if (@import("../global/c_abi.zig").isFunctionPointer(graph, ty)) return .unsupported;
    if (semantic == .builtin)
        return if (semantic.builtin != .Any and semantic.builtin != .Type) null else .unsupported;
    if (types.arrayElement(graph, ty)) |element| {
        const count = types.arrayLength(graph, ty) orelse return .unsupported;
        if (count == 0) return if (value.fields.len == 0) null else .incomplete_aggregate;
        if (value.fields.len == 0) return valueFailure(graph, element, .{}, markers, owner, depth + 1);
        const missing_proves = valueFailure(graph, element, .{}, markers, owner, depth + 1) == null;
        if (!missing_proves and value.fields.len != count) return .incomplete_aggregate;
        for (value.fields, 0..) |entry, index| {
            if (entry.index >= count or (!missing_proves and entry.index != index)) return .incomplete_aggregate;
            if (valueFailure(graph, element, entry.value.*, markers, owner, depth + 1)) |reason| return reason;
        }
        return null;
    }
    if (types.fields(graph, ty)) |fields| {
        for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
            if (valueFailure(graph, field.ty, fieldValue(value, index), markers, owner, depth + 1)) |reason| return reason;
        }
        return null;
    }
    if (types.variants(graph, ty)) |variants| {
        if (value.known_choice_variant) |index| if (index >= variants.len) return .incomplete_aggregate;
        for (graph.variants.items[variants.start..][0..variants.len], 0..) |variant, index| {
            if (value.known_choice_variant) |known| if (known != index) continue;
            const payload = variant.payload_type orelse continue;
            const selected = facts.representedProjection(value, .{ .variant = @intCast(index) }) orelse facts.ValueFacts{};
            if (valueFailure(graph, payload, selected, markers, owner, depth + 1)) |reason| return reason;
        }
        return null;
    }
    return .unsupported;
}

/// An exact read-only observation of immutable scalar backing can be
/// retained across executions, including after erasure to &Any. The actual
/// target supplies the guarantee; a read-only reference type alone cannot.
pub fn observesImmutableModuleScalar(graph: *const graph_mod.GlobalSemanticGraph, value: facts.ValueFacts) bool {
    if (value.reference_target_incomplete or value.symbolic_pointees.len != 0) return false;
    const place = value.referenced_place orelse return false;
    if (place.projections.len != 0) return false;
    for (value.mutation_places) |candidate| if (!candidate.eql(place)) return false;
    return isImmutableModuleScalar(graph, place.root);
}

pub fn isImmutableModuleScalar(graph: *const graph_mod.GlobalSemanticGraph, root: graph_mod.GlobalBindingId) bool {
    if (!graph.isModuleBinding(root)) return false;
    const binding = graph.binding(root);
    if (binding.mutability != .constant) return false;
    const backing = graph.resolvedSemanticType(binding.ty) orelse return false;
    return backing == .builtin and backing.builtin != .Any and backing.builtin != .Type;
}

const NominalGuarantee = enum { none, structural, unconditional };

fn nominalGuarantee(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, markers: Markers) NominalGuarantee {
    if (markers.unconditional == null and markers.structural == null) return .none;
    var guarantee: NominalGuarantee = .none;
    for (graph.contract_conformances.items) |evidence| {
        if (evidence.declaration != markers.unconditional and evidence.declaration != markers.structural) continue;
        if (!evidence.declaration_validated or evidence.participants.len != 1) continue;
        const participant = graph.generic_arguments.items[evidence.participants.start].value.type;
        if (!types.equal(graph, ty, participant)) continue;
        if (evidence.declaration == markers.unconditional) return .unconditional;
        guarantee = .structural;
    }
    return guarantee;
}

/// Only local custody establishes a new enclosing backing relationship.
pub fn backingOwner(value: facts.ValueFacts, enclosing_owner: ?facts.ValidityRootId) ?facts.ValidityRootId {
    const root = value.intrinsic_backing_owner orelse return enclosing_owner;
    return if (std.mem.indexOfScalar(facts.ValidityRootId, value.owned_roots, root) != null) root else null;
}

/// A reference may travel inside the owner of its backing. The enclosing
/// value must establish custody independently of the reference, and every
/// retained dependency must travel with that custody.
pub fn observesTransferredBacking(reference: facts.ValueFacts, owner: ?facts.ValidityRootId) bool {
    const root = owner orelse return false;
    if (!observesOwnedBacking(reference, root)) return false;
    for (reference.dependencies) |dependency| if (dependency.root != root) return false;
    return true;
}

/// Additional lifetime anchors do not change a proven physical observation.
pub fn observesOwnedBacking(reference: facts.ValueFacts, owner: ?facts.ValidityRootId) bool {
    const root = owner orelse return false;
    if (reference.owned_backing != root or reference.reference_target_incomplete or
        reference.referenced_place != null or reference.mutation_places.len != 0 or
        reference.symbolic_pointees.len != 0 or reference.opaque_provenance.len != 0 or
        reference.domains.len != 0 or reference.execution_receipts.len != 0 or
        reference.fields.len != 0 or reference.variants.len != 0 or
        reference.guarded_values.len != 0 or reference.generation_outcomes.len != 0 or reference.completed_executions.len != 0)
        return false;
    for (reference.dependencies) |dependency| if (dependency.root == root) return true;
    return false;
}

test "backing observation does not transfer independent lifetime anchors" {
    const root: facts.ValidityRootId = @enumFromInt(1);
    const reference: facts.ValueFacts = .{
        .owned_backing = root,
        .dependencies = &.{ .{ .root = root }, .{ .root = @enumFromInt(2) } },
    };
    try std.testing.expect(observesOwnedBacking(reference, root));
    try std.testing.expect(!observesTransferredBacking(reference, root));
}

/// An opaque native result slot currently transports bytes and cleanup custody.
pub fn requiresResultMetadata(value: facts.ValueFacts, depth: usize) bool {
    if (depth >= 64) return true;

    // The native slot has no fact payload. Structural shape and the known
    // discriminant may be forgotten: the result still carries their bytes.
    // Any other evidence needs an explicit transport rule before admission.
    var metadata = value;
    metadata.fields = &.{};
    metadata.variants = &.{};
    metadata.known_choice_variant = null;
    if (!facts.isEmptyValue(metadata)) return true;

    var children = value.structuralChildren();
    while (children.next()) |child| if (requiresResultMetadata(child.*, depth + 1)) return true;
    return false;
}

fn fieldValue(value: facts.ValueFacts, index: usize) facts.ValueFacts {
    return facts.representedProjection(value, .{ .field = @intCast(index) }) orelse .{};
}

test "erased transfer evidence belongs to the captured value" {
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

test "native task result transport rejects execution and storage evidence in a payload" {
    var child: facts.ValueFacts = .{};
    const result: facts.ValueFacts = .{ .variants = &.{.{ .index = 0, .value = &child }} };
    try std.testing.expect(!requiresResultMetadata(result, 0));

    child.generation_outcomes = &.{.{
        .storage = .{ .place = .{ .root = @enumFromInt(0) } },
        .generation = @enumFromInt(0),
        .guard = 1,
        .invalidates = true,
    }};
    try std.testing.expect(requiresResultMetadata(result, 0));

    child = .{ .owned_backing = @enumFromInt(0) };
    try std.testing.expect(requiresResultMetadata(result, 0));

    child = .{ .intrinsic_backing_owner = @enumFromInt(0) };
    try std.testing.expect(requiresResultMetadata(result, 0));

    child = .{ .concurrent_receiver = true };
    try std.testing.expect(requiresResultMetadata(result, 0));

    child = .{ .completed_executions = &.{@enumFromInt(0)} };
    try std.testing.expect(requiresResultMetadata(result, 0));
}

test "owned backing transport requires matching custody and no external loan" {
    const owned: facts.ValidityRootId = @enumFromInt(0);
    const external: facts.ValidityRootId = @enumFromInt(1);
    var reference: facts.ValueFacts = .{
        .owned_backing = owned,
        .dependencies = &.{.{ .root = owned }},
    };
    try std.testing.expect(observesTransferredBacking(reference, owned));
    try std.testing.expect(!observesTransferredBacking(reference, null));
    try std.testing.expect(!observesTransferredBacking(reference, external));
    reference.dependencies = &.{ .{ .root = owned }, .{ .root = external } };
    try std.testing.expect(!observesTransferredBacking(reference, owned));
    reference.dependencies = &.{.{ .root = owned }};
    const hidden: facts.ValueFacts = .{ .dependencies = &.{.{ .root = external }} };
    reference.fields = &.{.{ .index = 0, .value = &hidden }};
    try std.testing.expect(!observesTransferredBacking(reference, owned));
    reference.fields = &.{};
    reference.reference_target_incomplete = true;
    try std.testing.expect(!observesTransferredBacking(reference, owned));
}

test "structural transfer distinguishes an internal reference from a detached one" {
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .UInt8 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
    });
    try graph.fields.append(a, .{
        .name = .{ .start = 0, .len = 0 },
        .ty = @enumFromInt(1),
        .source = .{ .file_index = 0, .offset = 0 },
    });
    const backing: facts.ValidityRootId = @enumFromInt(0);
    const reference: facts.ValueFacts = .{ .owned_backing = backing, .dependencies = &.{.{ .root = backing }} };
    var container: facts.ValueFacts = .{
        .owned_roots = &.{backing},
        .intrinsic_backing_owner = backing,
        .fields = &.{.{ .index = 0, .value = &reference }},
    };
    try std.testing.expect(proves(&graph, @enumFromInt(2), container));
    try std.testing.expect(!proves(&graph, @enumFromInt(1), reference));
    container.owned_roots = &.{};
    try std.testing.expect(!proves(&graph, @enumFromInt(2), container));
    container.owned_roots = &.{backing};
    container.intrinsic_backing_owner = null;
    try std.testing.expect(!proves(&graph, @enumFromInt(2), container));
}

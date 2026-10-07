const std = @import("std");
const facts = @import("safety_facts.zig");

/// Contracts describe permitted effects, rather than a concrete method's exact
/// summary. Keeping their identities in input/output coordinates allows the
/// same contract to be checked before receiver layout is erased.
pub const Output = struct {
    dependencies: []const facts.InputPath = &.{},
    ownership_transfers: []const facts.InputPath = &.{},
};

/// This first contract representation covers output provenance and preservation.
/// Stateful protocols need explicit post-state/domain contracts before they can
/// use it; unsupported effects are rejected, never silently discarded.
pub const Contract = struct {
    outputs: []const Output,
};

pub fn fromDeclaration(allocator: std.mem.Allocator, declaration: @import("../primitives/schema.zig").MethodSafetyContract) !Contract {
    const outputs = try allocator.alloc(Output, declaration.output_count);
    for (outputs, 0..) |*output, index| {
        var paths: std.ArrayList(facts.InputPath) = .empty;
        for (declaration.dependencies) |dependency| {
            if (dependency.output_index == index) try paths.append(allocator, .{ .input_index = dependency.input_index });
        }
        output.* = .{ .dependencies = try paths.toOwnedSlice(allocator) };
    }
    return .{ .outputs = outputs };
}

pub const Failure = struct {
    kind: enum {
        output_count,
        undeclared_dependency,
        undeclared_ownership_transfer,
        unsupported_post_state,
        unsupported_opaque_effect,
        unsupported_capability_effect,
    },
    output_index: ?u32 = null,
    input: ?facts.InputPath = null,

    pub fn description(self: Failure) []const u8 {
        return switch (self.kind) {
            .output_count => "the number of outputs differs",
            .undeclared_dependency => "undeclared output dependency",
            .undeclared_ownership_transfer => "undeclared ownership transfer",
            .unsupported_post_state => "a storage transition is not permitted by this preservation contract",
            .unsupported_opaque_effect => "an opaque storage effect is not permitted by this preservation contract",
            .unsupported_capability_effect => "storage capability consumption is not permitted by this contract",
        };
    }
};

/// Check each implementation independently. No result depends on which other
/// implementations are linked into the program. Local escapes must already
/// have passed the ordinary function-output check: a contract never authorizes
/// an expired local generation or certifies physical pointer validity.
pub fn check(contract: Contract, summary: facts.SafetySummary) ?Failure {
    if (contract.outputs.len != summary.outputs.len) return .{ .kind = .output_count };
    for (contract.outputs, summary.outputs, 0..) |allowed, actual, index| {
        if (checkValue(allowed, actual)) |failure| {
            var result = failure;
            result.output_index = @intCast(index);
            return result;
        }
    }
    // Ordinary writes are compatible with preservation only if they cannot
    // introduce new dependencies, transfer ownership, or change generations.
    // Type-aware normalization removes private scalar writes before this check.
    for (summary.input_post_states) |state| {
        if (!preserves(state)) return .{ .kind = .unsupported_post_state, .input = state.target };
    }
    for (summary.outcome_post_states) |outcome| {
        for (outcome.input_post_states) |state| {
            if (!preserves(state)) return .{ .kind = .unsupported_post_state, .input = state.target };
        }
    }
    if (summary.opaque_storage_effects.len != 0) return .{
        .kind = .unsupported_opaque_effect,
        .input = summary.opaque_storage_effects[0].storage,
    };
    if (summary.opaque_storage_empties.len != 0) return .{
        .kind = .unsupported_opaque_effect,
        .input = summary.opaque_storage_empties[0],
    };
    if (summary.storage_capability_uses.len != 0) return .{
        .kind = .unsupported_capability_effect,
        .input = summary.storage_capability_uses[0].target,
    };
    if (summary.storage_capability_conflicts.len != 0) return .{
        .kind = .unsupported_capability_effect,
        .input = summary.storage_capability_conflicts[0].first,
    };
    return null;
}

fn checkValue(allowed: Output, actual: facts.ValueEffect) ?Failure {
    for (actual.input_dependencies) |dependency| {
        const paths = if (dependency.transfers_ownership) allowed.ownership_transfers else allowed.dependencies;
        if (!covers(paths, dependency.path)) return .{
            .kind = if (dependency.transfers_ownership) .undeclared_ownership_transfer else .undeclared_dependency,
            .input = dependency.path,
        };
    }
    const dependencies = [_][]const facts.InputPath{
        actual.input_places,
        actual.input_generation_dependencies,
        actual.input_place_values,
        actual.input_owned_roots,
        actual.opaque_generation_dependencies,
        actual.opaque_storage_dependencies,
    };
    for (dependencies) |paths| {
        for (paths) |path| {
            if (!covers(allowed.dependencies, path)) return .{ .kind = .undeclared_dependency, .input = path };
        }
    }
    for (actual.fields) |field| {
        if (checkValue(allowed, field.value.*)) |failure| return failure;
    }
    for (actual.variants) |variant| {
        if (checkValue(allowed, variant.value.*)) |failure| return failure;
    }
    // Fresh roots have no input provenance. Their ownership/liveness relation
    // is checked by ordinary safety, not turned into a dependency on the receiver.
    // Raw address/capability facts likewise do not establish safe references.
    return null;
}

fn covers(allowed: []const facts.InputPath, actual: facts.InputPath) bool {
    for (allowed) |path| {
        if (path.input_index != actual.input_index or path.projections.len > actual.projections.len) continue;
        var matches = true;
        for (path.projections, actual.projections[0..path.projections.len]) |a, b| {
            if (!a.eql(b)) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

fn preserves(state: facts.PlacePostState) bool {
    if (state.initializedness != .initialized or state.ends_previous_roots or
        state.refreshes_storage_generation or state.requires_available_destination or
        state.opaque_ownership != .none or state.opaque_storage != null or
        state.may_repopulate_opaque_storage) return false;
    return emptyValue(state.value);
}

fn emptyValue(value: facts.ValueEffect) bool {
    if (value.explicit_dependency or value.input_dependencies.len != 0 or
        value.input_storage_capabilities.len != 0 or value.input_places.len != 0 or
        value.input_generation_dependencies.len != 0 or value.input_place_values.len != 0 or
        value.input_owned_roots.len != 0 or value.opaque_generation_dependencies.len != 0 or
        value.opaque_storage_dependencies.len != 0 or value.fresh_dependencies.len != 0 or
        value.fresh_owned_roots.len != 0 or value.fresh_storage_capabilities.len != 0 or
        value.unavailable_fresh_storage.len != 0 or value.integer_address or value.foreign_storage) return false;
    for (value.fields) |field| if (!emptyValue(field.value.*)) return false;
    for (value.variants) |variant| if (!emptyValue(variant.value.*)) return false;
    return true;
}

test "safety contracts permit fewer dependencies and independent implementations" {
    const allowed = Contract{ .outputs = &.{.{ .dependencies = &.{.{ .input_index = 0 }} }} };
    const independent = facts.SafetySummary{ .outputs = &.{.{}} };
    const dependent = facts.SafetySummary{ .outputs = &.{.{ .input_dependencies = &.{.{ .path = .{ .input_index = 0 } }} }} };
    try std.testing.expect(check(allowed, independent) == null);
    try std.testing.expect(check(allowed, dependent) == null);
    const unrelated = facts.SafetySummary{ .outputs = &.{.{ .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }} }} };
    try std.testing.expectEqual(.undeclared_dependency, check(allowed, unrelated).?.kind);
    try std.testing.expect(check(allowed, independent) == null);
}

test "safety contracts check dependencies through fields and choice payloads" {
    const hidden = facts.ValueEffect{ .opaque_storage_dependencies = &.{.{ .input_index = 1 }} };
    const field = facts.ValueEffect{ .fields = &.{.{ .index = 2, .value = &hidden }} };
    const summary = facts.SafetySummary{ .outputs = &.{.{ .variants = &.{.{ .index = 0, .value = &field }} }} };
    const allowed = Contract{ .outputs = &.{.{ .dependencies = &.{.{ .input_index = 0 }} }} };
    const failure = check(allowed, summary).?;
    try std.testing.expectEqual(.undeclared_dependency, failure.kind);
    try std.testing.expectEqual(@as(?u32, 0), failure.output_index);
    try std.testing.expectEqual(@as(u32, 1), failure.input.?.input_index);
}

test "safety contracts keep validity and ownership permissions separate" {
    const path = facts.InputPath{ .input_index = 0 };
    const summary = facts.SafetySummary{ .outputs = &.{.{ .input_dependencies = &.{.{ .path = path, .transfers_ownership = true }} }} };
    try std.testing.expectEqual(.undeclared_ownership_transfer, check(.{ .outputs = &.{.{ .dependencies = &.{path} }} }, summary).?.kind);
    try std.testing.expect(check(.{ .outputs = &.{.{ .ownership_transfers = &.{path} }} }, summary) == null);
}

test "safety contracts distinguish sibling storage paths" {
    const projections = @import("place.zig").Projection;
    const storage = facts.InputPath{ .input_index = 0, .projections = &[_]projections{.{ .field = 1 }} };
    const child = facts.InputPath{ .input_index = 0, .projections = &[_]projections{ .{ .field = 1 }, .{ .field = 3 } } };
    const sibling = facts.InputPath{ .input_index = 0, .projections = &[_]projections{.{ .field = 2 }} };
    const allowed = Contract{ .outputs = &.{.{ .dependencies = &.{storage} }} };
    try std.testing.expect(check(allowed, .{ .outputs = &.{.{ .input_generation_dependencies = &.{child} }} }) == null);
    try std.testing.expectEqual(.undeclared_dependency, check(allowed, .{ .outputs = &.{.{ .input_generation_dependencies = &.{sibling} }} }).?.kind);
}

test "safety contracts reject undeclared transitions on individual outcomes" {
    const allowed = Contract{ .outputs = &.{.{}} };
    const state = facts.PlacePostState{ .target = .{ .input_index = 0 }, .initializedness = .initialized, .refreshes_storage_generation = true };
    try std.testing.expectEqual(.unsupported_post_state, check(allowed, .{
        .outputs = &.{.{}},
        .outcome_post_states = &.{.{ .variant_index = 1, .input_post_states = &.{state} }},
    }).?.kind);
    try std.testing.expect(check(allowed, .{ .outputs = &.{.{}}, .input_post_states = &.{.{ .target = .{ .input_index = 0 }, .initializedness = .initialized }} }) == null);
}

test "safety contracts reject hidden storage and capability effects" {
    const allowed = Contract{ .outputs = &.{} };
    const path = facts.InputPath{ .input_index = 0 };
    try std.testing.expectEqual(.unsupported_opaque_effect, check(allowed, .{
        .opaque_storage_effects = &.{.{ .storage = path, .hidden_dependencies = .{} }},
    }).?.kind);
    try std.testing.expectEqual(.unsupported_opaque_effect, check(allowed, .{ .opaque_storage_empties = &.{path} }).?.kind);
    try std.testing.expectEqual(.unsupported_capability_effect, check(allowed, .{
        .storage_capability_uses = &.{.{ .target = path }},
    }).?.kind);
}

test "safety contracts cover every transitive input validity channel" {
    const path = facts.InputPath{ .input_index = 2 };
    const effects = [_]facts.ValueEffect{
        .{ .input_dependencies = &.{.{ .path = path, .validity_only = true }} },
        .{ .input_places = &.{path} },
        .{ .input_generation_dependencies = &.{path} },
        .{ .input_place_values = &.{path} },
        .{ .input_owned_roots = &.{path} },
        .{ .opaque_generation_dependencies = &.{path} },
        .{ .opaque_storage_dependencies = &.{path} },
    };
    for (effects) |effect| {
        const summary = facts.SafetySummary{ .outputs = &.{effect} };
        try std.testing.expectEqual(.undeclared_dependency, check(.{ .outputs = &.{.{}} }, summary).?.kind);
        try std.testing.expect(check(.{ .outputs = &.{.{ .dependencies = &.{path} }} }, summary) == null);
    }
}

test "safety contracts allow fresh owner outputs without receiver dependence" {
    const summary = facts.SafetySummary{ .outputs = &.{.{
        .fresh_owned_roots = &.{7},
        .fields = &.{.{ .index = 0, .value = &.{ .fresh_dependencies = &.{7} } }},
    }} };
    // Normal output checking establishes whether these fresh facts represent a
    // legal owner return. This matcher checks only the input provenance bound.
    try std.testing.expect(check(.{ .outputs = &.{.{}} }, summary) == null);
    try std.testing.expectEqual(.output_count, check(.{ .outputs = &.{} }, summary).?.kind);
}

test "safety contracts reject ownership and generation changes despite initialized outputs" {
    const path = facts.InputPath{ .input_index = 0 };
    const changes = [_]facts.PlacePostState{
        .{ .target = path, .initializedness = .initialized, .ends_previous_roots = true },
        .{ .target = path, .initializedness = .initialized, .opaque_ownership = .conditional },
        .{ .target = path, .initializedness = .initialized, .may_repopulate_opaque_storage = true },
        .{ .target = path, .initializedness = .deinitialized },
        .{ .target = path, .initializedness = .initialized, .value = .{ .fields = &.{.{
            .index = 1,
            .value = &.{ .input_owned_roots = &.{path} },
        }} } },
    };
    for (changes) |state| {
        try std.testing.expectEqual(.unsupported_post_state, check(.{ .outputs = &.{} }, .{ .input_post_states = &.{state} }).?.kind);
    }
}

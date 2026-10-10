const std = @import("std");
const facts = @import("safety_facts.zig");

/// Contracts describe permitted effects, rather than a concrete method's exact
/// summary. Keeping their identities in input/output coordinates allows the
/// same contract to be checked before receiver layout is erased.
pub const Output = struct {
    dependencies: []const facts.InputPath = &.{},
    ownership_transfers: []const facts.InputPath = &.{},
    referent: ?facts.InputPath = null,
    domains: []const facts.InputDomain = &.{},
    fresh_owner: bool = false,
    outcomes: []const Outcome = &.{},
    pub const Outcome = struct { variant_index: u32, value: *const Output };
};

/// Payload provenance and guarded generation transitions are separate views.
/// Resource consumption and hidden-state replacement require their own checked
/// permissions; unsupported effects are rejected, never silently discarded.
pub const Contract = struct {
    outputs: []const Output,
    outcomes: []const Outcome = &.{},
    /// Definite destruction guarantees for caller-owned input places.
    consumed_inputs: []const facts.InputPath = &.{},
    relocations: []const Relocation = &.{},
    /// Paths are resolved domain mappings, not source field names. Ending a
    /// generation permits invalidating references, but grants no permission to
    /// consume owned resources or replace hidden dependency contents.
    invalidates: []const facts.InputPath = &.{},
    invalidated_domains: []const facts.InputDomain = &.{},

    pub const Relocation = struct { destination: facts.InputPath, source: facts.InputPath };
    pub const Outcome = struct { output_index: u32, parent_variants: []const u32 = &.{}, variant_index: u32, effects: *const Contract };
};

pub fn fromDeclaration(allocator: std.mem.Allocator, declaration: @import("../primitives/schema.zig").MethodSafetyContract) anyerror!Contract {
    const outputs = try allocator.alloc(Output, declaration.output_count);
    for (outputs, 0..) |*output, index| {
        var paths: std.ArrayList(facts.InputPath) = .empty;
        for (declaration.dependencies) |dependency| {
            if (dependency.output_index == index) try paths.append(allocator, .{ .input_index = dependency.input_index });
        }
        for (declaration.transfers) |transfer| {
            if (transfer.output_index == index) try paths.append(allocator, .{ .input_index = transfer.input_index });
        }
        output.* = .{ .dependencies = try paths.toOwnedSlice(allocator) };
        for (declaration.referents) |referent| {
            if (referent.output_index == index) output.referent = .{ .input_index = referent.input_index };
        }
        var domains: std.ArrayList(facts.InputDomain) = .empty;
        for (declaration.domain_dependencies) |dependency| {
            if (dependency.output_index == index) try domains.append(allocator, .{ .path = .{ .input_index = dependency.input.input_index }, .domain_index = dependency.input.domain_index });
        }
        output.domains = try domains.toOwnedSlice(allocator);
        for (declaration.owned_outputs) |owned| if (owned == index) {
            output.fresh_owner = true;
            break;
        };
        var transfers: std.ArrayList(facts.InputPath) = .empty;
        for (declaration.transfers) |transfer| if (transfer.output_index == index) try transfers.append(allocator, .{ .input_index = transfer.input_index });
        output.ownership_transfers = try transfers.toOwnedSlice(allocator);
    }
    const invalidates = try allocator.alloc(facts.InputPath, declaration.invalidates.len);
    for (outputs, 0..) |*target, output_index| {
        var outcomes: std.ArrayList(Output.Outcome) = .empty;
        for (declaration.outcomes) |outcome| {
            if (outcome.output_index != output_index) continue;
            const contract = try fromDeclaration(allocator, .{
                .output_count = declaration.output_count,
                .dependencies = outcome.dependencies,
                .domain_dependencies = outcome.domain_dependencies,
                .owned_outputs = outcome.owned_outputs,
                .invalidates = outcome.invalidates,
                .invalidated_domains = outcome.invalidated_domains,
                .outcomes = outcome.outcomes,
                .source = outcome.source,
            });
            const output = try allocator.create(Output);
            output.* = contract.outputs[output_index];
            // Every nested payload inherits the enclosing permissions. Applying
            // this recursively prevents a child selector from cancelling them.
            try inheritOutputPermissions(allocator, output, target.*);
            try outcomes.append(allocator, .{ .variant_index = outcome.variant_index orelse return error.UnresolvedOutcomeContract, .value = output });
        }
        target.outcomes = try outcomes.toOwnedSlice(allocator);
    }
    for (declaration.invalidates, invalidates) |index, *path| path.* = .{ .input_index = index };
    const invalidated_domains = try allocator.alloc(facts.InputDomain, declaration.invalidated_domains.len);
    for (declaration.invalidated_domains, invalidated_domains) |domain, *input| input.* = .{ .path = .{ .input_index = domain.input_index }, .domain_index = domain.domain_index };
    var conditional: std.ArrayList(Contract.Outcome) = .empty;
    const consumed_inputs = try allocator.alloc(facts.InputPath, declaration.consumed_inputs.len);
    for (declaration.consumed_inputs, consumed_inputs) |index, *path| path.* = .{ .input_index = index };
    try appendConditionalContracts(allocator, declaration.output_count, declaration.outcomes, &.{}, invalidates, invalidated_domains, consumed_inputs, &conditional);
    const relocations = try allocator.alloc(Contract.Relocation, declaration.relocations.len);
    for (declaration.relocations, relocations) |declared, *relocation| relocation.* = .{ .destination = .{ .input_index = declared.destination }, .source = .{ .input_index = declared.source } };
    for (conditional.items) |outcome| {
        @constCast(outcome.effects).relocations = relocations;
    }
    return .{ .outputs = outputs, .consumed_inputs = consumed_inputs, .relocations = relocations, .invalidates = invalidates, .invalidated_domains = invalidated_domains, .outcomes = try conditional.toOwnedSlice(allocator) };
}

fn appendConditionalContracts(allocator: std.mem.Allocator, output_count: u32, outcomes: []const @import("../primitives/schema.zig").MethodSafetyContract.Outcome, parents: []const u32, common_invalidates: []const facts.InputPath, common_domains: []const facts.InputDomain, common_consumed: []const facts.InputPath, result: *std.ArrayList(Contract.Outcome)) anyerror!void {
    for (outcomes) |outcome| {
        const effects = try allocator.create(Contract);
        effects.* = try fromDeclaration(allocator, .{
            .output_count = output_count,
            .invalidates = outcome.invalidates,
            .consumed_inputs = outcome.consumed_inputs,
            .invalidated_domains = outcome.invalidated_domains,
            .source = outcome.source,
        });
        effects.invalidates = try std.mem.concat(allocator, facts.InputPath, &.{ common_invalidates, effects.invalidates });
        effects.invalidated_domains = try std.mem.concat(allocator, facts.InputDomain, &.{ common_domains, effects.invalidated_domains });
        effects.consumed_inputs = try std.mem.concat(allocator, facts.InputPath, &.{ common_consumed, effects.consumed_inputs });
        const variant = outcome.variant_index orelse return error.UnresolvedOutcomeContract;
        try result.append(allocator, .{ .output_index = outcome.output_index, .parent_variants = parents, .variant_index = variant, .effects = effects });
        const child_parents = try std.mem.concat(allocator, u32, &.{ parents, &.{variant} });
        try appendConditionalContracts(allocator, output_count, outcome.outcomes, child_parents, effects.invalidates, effects.invalidated_domains, effects.consumed_inputs, result);
    }
}

pub fn selectorCovers(expected: anytype, actual: anytype) bool {
    if (expected.output_index != actual.output_index or expected.parent_variants.len > actual.parent_variants.len) return false;
    if (!std.mem.eql(u32, expected.parent_variants, actual.parent_variants[0..expected.parent_variants.len])) return false;
    const selected = if (expected.parent_variants.len == actual.parent_variants.len) actual.variant_index else actual.parent_variants[expected.parent_variants.len];
    return expected.variant_index == selected;
}

pub fn effectsForSelector(contract: Contract, selector: anytype) Contract {
    var selected = contract;
    var depth: ?usize = null;
    for (contract.outcomes) |outcome| {
        if (!selectorCovers(outcome, selector)) continue;
        if (depth == null or depth.? < outcome.parent_variants.len) {
            selected = outcome.effects.*;
            depth = outcome.parent_variants.len;
        }
    }
    return selected;
}

fn inheritOutputPermissions(allocator: std.mem.Allocator, output: *Output, common: Output) anyerror!void {
    output.dependencies = try std.mem.concat(allocator, facts.InputPath, &.{ common.dependencies, output.dependencies });
    output.domains = try std.mem.concat(allocator, facts.InputDomain, &.{ common.domains, output.domains });
    output.fresh_owner = output.fresh_owner or common.fresh_owner;
    output.referent = common.referent;
    output.ownership_transfers = common.ownership_transfers;
    for (output.outcomes) |outcome| try inheritOutputPermissions(allocator, @constCast(outcome.value), common);
}

pub const Failure = struct {
    kind: enum {
        output_count,
        undeclared_dependency,
        undeclared_ownership_transfer,
        incompatible_referent,
        undeclared_fresh_owner,
        unsupported_post_state,
        missing_consumption,
        missing_relocation,
        unsupported_opaque_effect,
        unsupported_capability_effect,
    },
    output_index: ?u32 = null,
    input: ?facts.InputPath = null,
    outcome: ?struct { output_index: u32, parent_variants: []const u32 = &.{}, variant_index: u32 } = null,

    pub fn description(self: Failure) []const u8 {
        return switch (self.kind) {
            .output_count => "the number of outputs differs",
            .undeclared_dependency => "undeclared output dependency",
            .undeclared_ownership_transfer => "undeclared ownership transfer",
            .incompatible_referent => "the output must refer to the same storage as the declared input",
            .undeclared_fresh_owner => "undeclared fresh output ownership; declare owns(output)",
            .missing_relocation => "cannot prove relocates: move the source into an available destination on every returning path",
            .missing_consumption => "cannot prove consumes: the input must be deinitialized on every returning path",
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
    for (contract.relocations) |relocation| {
        if (!provesRelocation(relocation, summary.input_post_states)) return .{ .kind = .missing_relocation, .input = relocation.destination };
    }
    // Consumption is a guarantee, not merely permission to sometimes destroy
    // a value. A caller can disable cleanup only after every exit proves it.
    for (contract.consumed_inputs) |input| {
        var consumed = false;
        for (summary.input_post_states) |state| if (samePath(state.target, input) and
            state.initializedness == .deinitialized and state.ends_previous_roots)
        {
            consumed = true;
            break;
        };
        if (!consumed) return .{ .kind = .missing_consumption, .input = input };
    }

    for (summary.invalidated_domains) |domain| {
        if (permitsDomain(contract, domain)) continue;
        var permitted = false;
        for (contract.outcomes) |outcome| for (summary.outcome_post_states) |actual| {
            if (selectorCovers(outcome, actual) and permitsDomain(outcome.effects.*, domain)) permitted = true;
        };
        if (!permitted) return .{ .kind = .unsupported_post_state, .input = domain.path };
    }
    if (contract.outputs.len != summary.outputs.len) return .{ .kind = .output_count };
    for (contract.outputs, summary.outputs, 0..) |allowed, actual, index| {
        if (checkValue(allowed, actual)) |failure| {
            var result = failure;
            result.output_index = @intCast(index);
            return result;
        }
    }
    // The fallback is a union of may-effects. It is permitted only when each
    // represented outcome separately satisfies its common-plus-variant contract.
    for (summary.input_post_states) |state| {
        if (permitsPostState(contract, state)) continue;
        var permitted = false;
        for (contract.outcomes) |outcome| {
            var has_proof = false;
            for (summary.outcome_post_states) |actual| if (selectorCovers(outcome, actual)) {
                has_proof = true;
                break;
            };
            if (has_proof and permitsMayPostState(outcome.effects.*, state)) permitted = true;
        }
        if (!permitted) return .{ .kind = .unsupported_post_state, .input = state.target };
    }
    for (contract.outcomes) |required| {
        for (required.effects.relocations) |relocation| {
            var represented = false;
            for (summary.outcome_post_states) |actual| if (selectorCovers(required, actual)) {
                represented = true;
                break;
            };
            if (!represented) return .{ .kind = .missing_relocation, .input = relocation.destination };
        }
        if (required.effects.consumed_inputs.len == 0) continue;
        var represented = false;
        for (summary.outcome_post_states) |actual| if (selectorCovers(required, actual)) {
            represented = true;
            break;
        };
        if (!represented) return .{ .kind = .missing_consumption, .input = required.effects.consumed_inputs[0] };
    }
    for (summary.outcome_post_states) |outcome| {
        if (!outcome.reachable) continue;
        const allowed = effectsForSelector(contract, outcome);
        for (allowed.relocations) |relocation| {
            if (!provesRelocation(relocation, outcome.input_post_states)) return .{ .kind = .missing_relocation, .input = relocation.destination, .outcome = .{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index } };
        }
        for (allowed.consumed_inputs) |input| {
            var consumed = false;
            for (outcome.input_post_states) |state| if (samePath(state.target, input) and state.initializedness == .deinitialized and state.ends_previous_roots) {
                consumed = true;
                break;
            };
            if (!consumed) return .{ .kind = .missing_consumption, .input = input, .outcome = .{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index } };
        }
        for (outcome.input_post_states) |state| {
            if (!permitsPostState(allowed, state)) return .{ .kind = .unsupported_post_state, .input = state.target, .outcome = .{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index } };
        }
        for (outcome.invalidated_domains) |domain| if (!permitsDomain(allowed, domain)) return .{ .kind = .unsupported_post_state, .input = domain.path, .outcome = .{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index } };
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
    if ((actual.fresh_cleanup_obligation or actual.fresh_owned_roots.len != 0) and !allowed.fresh_owner) return .{ .kind = .undeclared_fresh_owner };
    for (actual.input_domains) |domain| {
        var permitted = false;
        for (allowed.domains) |expected| if (domain.domain_index == expected.domain_index and samePath(domain.path, expected.path)) {
            permitted = true;
            break;
        };
        if (!permitted) return .{ .kind = .undeclared_dependency, .input = domain.path };
    }
    if (allowed.referent) |path| {
        if (!hasExactReferent(actual, path)) return .{ .kind = .incompatible_referent, .input = path };
    }
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
        actual.input_captured_storages,
        actual.input_receiver_values,
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
        var selected = allowed;
        selected.outcomes = &.{};
        for (allowed.outcomes) |outcome| if (outcome.variant_index == variant.index) {
            selected = outcome.value.*;
            break;
        };
        if (checkValue(selected, variant.value.*)) |failure| return failure;
    }
    for (actual.domain_values) |domain| {
        if (checkValue(allowed, domain.value.*)) |failure| return failure;
    }
    // Fresh roots have no input provenance. Their ownership/liveness relation
    // is checked by ordinary safety, not turned into a dependency on the receiver.
    // Raw address/capability facts likewise do not establish safe references.
    return null;
}

fn samePath(a: facts.InputPath, b: facts.InputPath) bool {
    if (a.input_index != b.input_index or a.projections.len != b.projections.len) return false;
    for (a.projections, b.projections) |x, y| if (!x.eql(y)) return false;
    return true;
}

/// Reject summary provenance incompatible with an exact referent. This is not
/// a must-alias proof: summaries may forget independent alternatives. The
/// concrete checker additionally proves direct forwarding before accepting a
/// declaration. Lifetime-only anchors cannot select an output's storage.
fn hasExactReferent(actual: facts.ValueEffect, expected: facts.InputPath) bool {
    if (actual.input_place_values.len != 0 or actual.fields.len != 0 or actual.variants.len != 0 or
        actual.fresh_cleanup_obligation or actual.fresh_dependencies.len != 0 or actual.fresh_owned_roots.len != 0 or
        actual.fresh_storage_capabilities.len != 0 or actual.unavailable_fresh_storage.len != 0 or
        actual.integer_address or actual.foreign_storage or actual.input_storage_capabilities.len != 0) return false;
    var established = false;
    for (actual.input_places) |path| {
        if (!samePath(path, expected)) return false;
        established = true;
    }
    for (actual.input_dependencies) |dependency| {
        if (dependency.validity_only) continue;
        if (dependency.transfers_ownership or !samePath(dependency.path, expected)) return false;
        established = true;
    }
    return established;
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

fn permitsDomain(contract: Contract, actual: facts.InputDomain) bool {
    for (contract.invalidated_domains) |domain| if (domain.domain_index == actual.domain_index and samePath(domain.path, actual.path)) return true;
    return false;
}

/// Exact whole-place provenance preserves all ownership and capability facts.
/// Additional effects cannot be hidden inside an initialization guarantee.
fn exactRelocatedValue(actual: facts.ValueEffect, source: facts.InputPath) bool {
    if (actual.input_place_values.len != 1 or !samePath(actual.input_place_values[0], source)) return false;
    var remaining = actual;
    remaining.input_place_values = &.{};
    return emptyValue(remaining);
}

fn provesRelocation(relocation: Contract.Relocation, states: []const facts.PlacePostState) bool {
    var source_moved = false;
    var destination_initialized = false;
    const permission = Contract{ .outputs = &.{}, .relocations = &.{relocation} };
    for (states) |state| {
        if (!permitsPostState(permission, state)) continue;
        if (samePath(state.target, relocation.source)) source_moved = true;
        if (samePath(state.target, relocation.destination)) destination_initialized = true;
    }
    return source_moved and destination_initialized;
}

/// A union of exit effects is not a guarantee. Only the fallback can admit a
/// possibly moved source or initialized destination; each represented exit
/// must independently prove the complete transition and exact provenance.
fn permitsMayPostState(contract: Contract, state: facts.PlacePostState) bool {
    if (permitsPostState(contract, state)) return true;
    if (state.initializedness != .maybe_initialized) return false;
    for (contract.relocations) |relocation| {
        var definite = state;
        if (samePath(state.target, relocation.source)) {
            var value = state.value;
            for (value.input_place_values) |path| if (!samePath(path, relocation.source)) return false;
            value.input_place_values = &.{};
            if (!emptyValue(value)) return false;
            definite.initializedness = .moved;
            definite.value = .{};
        } else if (samePath(state.target, relocation.destination)) {
            definite.initializedness = .initialized;
        } else continue;
        return permitsPostState(contract, definite);
    }
    return false;
}

fn permitsPostState(contract: Contract, state: facts.PlacePostState) bool {
    for (contract.relocations) |relocation| {
        if (samePath(state.target, relocation.source)) return state.initializedness == .moved and
            !state.ends_previous_roots and !state.refreshes_storage_generation and
            !state.requires_available_destination and state.opaque_ownership == .none and
            state.opaque_storage == null and !state.may_repopulate_opaque_storage and emptyValue(state.value);
        if (samePath(state.target, relocation.destination)) return state.initializedness == .initialized and
            !state.ends_previous_roots and state.requires_available_destination and state.refreshes_storage_generation and
            state.opaque_ownership == .none and state.opaque_storage == null and
            !state.may_repopulate_opaque_storage and exactRelocatedValue(state.value, relocation.source);
    }
    if (covers(contract.consumed_inputs, state.target)) {
        // Destroying a value may update its owned fields before their final
        // cleanup. Dereferencing a borrowed field still reaches external
        // storage and is not authorized by consumption of its containing slot.
        for (state.target.projections) |projection| if (projection == .dereference) return false;
        if (state.opaque_ownership != .none or state.opaque_storage != null or state.requires_available_destination or
            state.may_repopulate_opaque_storage) return false;
        if (state.initializedness == .deinitialized or state.initializedness == .moved or state.initializedness == .maybe_initialized) return emptyValue(state.value);
        return state.initializedness == .initialized and emptyValue(state.value);
    }

    if (state.initializedness != .initialized or state.ends_previous_roots or state.requires_available_destination or
        state.opaque_ownership != .none or state.opaque_storage != null or
        state.may_repopulate_opaque_storage) return false;
    if (state.refreshes_storage_generation and !covers(contract.invalidates, state.target)) return false;
    var value = state.value;
    for (value.input_place_values) |path| if (!samePath(path, state.target)) return false;
    value.input_place_values = &.{};
    return emptyValue(value);
}

fn emptyValue(value: facts.ValueEffect) bool {
    if (value.fresh_cleanup_obligation or value.explicit_dependency or value.input_dependencies.len != 0 or
        value.input_storage_capabilities.len != 0 or value.input_places.len != 0 or
        value.input_generation_dependencies.len != 0 or value.input_captured_storages.len != 0 or value.input_receiver_values.len != 0 or value.input_place_values.len != 0 or
        value.input_owned_roots.len != 0 or value.input_domains.len != 0 or value.domain_values.len != 0 or value.opaque_generation_dependencies.len != 0 or
        value.opaque_storage_dependencies.len != 0 or value.fresh_dependencies.len != 0 or
        value.fresh_owned_roots.len != 0 or value.fresh_storage_capabilities.len != 0 or
        value.unavailable_fresh_storage.len != 0 or value.integer_address or value.foreign_storage) return false;
    for (value.fields) |field| if (!emptyValue(field.value.*)) return false;
    for (value.variants) |variant| if (!emptyValue(variant.value.*)) return false;
    return true;
}

test "safety contracts distinguish exact referents from lifetime anchors" {
    const path = facts.InputPath{ .input_index = 1 };
    const contract = Contract{ .outputs = &.{.{ .dependencies = &.{path}, .referent = path }} };
    try std.testing.expect(check(contract, .{ .outputs = &.{.{ .input_dependencies = &.{.{ .path = path }} }} }) == null);
    try std.testing.expectEqual(.incompatible_referent, check(contract, .{ .outputs = &.{.{ .input_dependencies = &.{.{ .path = path, .validity_only = true }} }} }).?.kind);
    try std.testing.expectEqual(.incompatible_referent, check(contract, .{ .outputs = &.{.{}} }).?.kind);
    try std.testing.expectEqual(.incompatible_referent, check(contract, .{ .outputs = &.{.{ .input_places = &.{.{ .input_index = 1, .projections = &.{.{ .field = 0 }} }} }} }).?.kind);
}

test "safety contracts limit generation invalidation to mapped storage" {
    const domain = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 1 }} };
    const child = facts.InputPath{ .input_index = 0, .projections = &.{ .{ .field = 1 }, .{ .field = 2 } } };
    const sibling = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 3 }} };
    const contract = Contract{ .outputs = &.{}, .invalidates = &.{domain} };
    const permitted = facts.SafetySummary{ .input_post_states = &.{.{ .target = child, .initializedness = .initialized, .refreshes_storage_generation = true }} };
    try std.testing.expect(check(contract, permitted) == null);
    try std.testing.expectEqual(.unsupported_post_state, check(.{ .outputs = &.{} }, permitted).?.kind);
    try std.testing.expectEqual(.unsupported_post_state, check(contract, .{ .input_post_states = &.{.{ .target = sibling, .initializedness = .initialized, .refreshes_storage_generation = true }} }).?.kind);
    try std.testing.expectEqual(.unsupported_post_state, check(contract, .{ .input_post_states = &.{.{ .target = .{ .input_index = 0 }, .initializedness = .initialized, .refreshes_storage_generation = true }} }).?.kind);
}

test "safety contracts do not turn invalidation into ownership consumption" {
    const path = facts.InputPath{ .input_index = 0, .projections = &.{.{ .field = 1 }} };
    const contract = Contract{ .outputs = &.{}, .invalidates = &.{path} };
    const states = [_]facts.PlacePostState{
        .{ .target = path, .initializedness = .initialized, .refreshes_storage_generation = true, .ends_previous_roots = true },
        .{ .target = path, .initializedness = .deinitialized, .refreshes_storage_generation = true },
        .{ .target = path, .initializedness = .initialized, .opaque_ownership = .definite },
        .{ .target = path, .initializedness = .initialized, .value = .{ .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }} } },
    };
    for (states) |state| try std.testing.expectEqual(.unsupported_post_state, check(contract, .{ .input_post_states = &.{state} }).?.kind);
    try std.testing.expectEqual(.unsupported_capability_effect, check(contract, .{ .storage_capability_uses = &.{.{ .target = path }} }).?.kind);
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
    try std.testing.expectEqual(.undeclared_fresh_owner, check(.{ .outputs = &.{.{}} }, summary).?.kind);
    try std.testing.expect(check(.{ .outputs = &.{.{ .fresh_owner = true }} }, summary) == null);
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

test "named output outcomes retain common permissions independently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const contract = try fromDeclaration(arena.allocator(), .{
        .output_count = 3,
        .dependencies = &.{.{ .output_index = 1, .input_index = 0 }},
        .outcomes = &.{
            .{ .output_index = 1, .variant = .{ .start = 0, .len = 0 }, .variant_index = 0, .source = .{ .file_index = 0, .offset = 0 } },
            .{ .output_index = 2, .variant = .{ .start = 0, .len = 0 }, .variant_index = 0, .dependencies = &.{.{ .output_index = 2, .input_index = 1 }}, .source = .{ .file_index = 0, .offset = 0 } },
        },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try std.testing.expectEqual(@as(usize, 0), contract.outputs[0].outcomes.len);
    try std.testing.expectEqual(@as(u32, 0), contract.outputs[1].outcomes[0].value.dependencies[0].input_index);
    try std.testing.expectEqual(@as(u32, 1), contract.outputs[2].outcomes[0].value.dependencies[0].input_index);
}

test "safety contracts consumption requires destruction without hidden storage replacement" {
    const contract = Contract{ .outputs = &.{}, .consumed_inputs = &.{.{ .input_index = 0 }} };
    const consumed = facts.PlacePostState{ .target = .{ .input_index = 0 }, .initializedness = .deinitialized, .ends_previous_roots = true };
    try std.testing.expect(check(contract, .{ .input_post_states = &.{consumed} }) == null);
    try std.testing.expectEqual(.missing_consumption, check(contract, .{}).?.kind);
    const replacement = facts.PlacePostState{
        .target = .{ .input_index = 0, .projections = &.{.{ .field = 0 }} },
        .initializedness = .initialized,
        .may_repopulate_opaque_storage = true,
    };
    try std.testing.expectEqual(.unsupported_post_state, check(contract, .{ .input_post_states = &.{ consumed, replacement } }).?.kind);
}

test "safety contracts relocation guarantees both transitions and exact ownership provenance" {
    const source = facts.InputPath{ .input_index = 1 };
    const destination = facts.InputPath{ .input_index = 2 };
    const contract = Contract{ .outputs = &.{}, .relocations = &.{.{ .destination = destination, .source = source }} };
    const moved = facts.PlacePostState{ .target = source, .initializedness = .moved };
    const initialized = facts.PlacePostState{
        .target = destination,
        .initializedness = .initialized,
        .value = .{ .input_place_values = &.{source} },
        .requires_available_destination = true,
        .refreshes_storage_generation = true,
    };
    try std.testing.expect(check(contract, .{ .input_post_states = &.{ moved, initialized } }) == null);
    try std.testing.expectEqual(.missing_relocation, check(contract, .{ .input_post_states = &.{initialized} }).?.kind);
    var wrong = initialized;
    wrong.value = .{};
    try std.testing.expectEqual(.missing_relocation, check(contract, .{ .input_post_states = &.{ moved, wrong } }).?.kind);
    wrong = moved;
    wrong.ends_previous_roots = true;
    try std.testing.expectEqual(.missing_relocation, check(contract, .{ .input_post_states = &.{ wrong, initialized } }).?.kind);
    wrong = initialized;
    wrong.requires_available_destination = false;
    try std.testing.expectEqual(.missing_relocation, check(contract, .{ .input_post_states = &.{ moved, wrong } }).?.kind);
}

test "safety contracts conditional relocation requires both transitions on the selected exit" {
    const source = facts.InputPath{ .input_index = 1 };
    const destination = facts.InputPath{ .input_index = 2 };
    const relocation = Contract{ .outputs = &.{}, .relocations = &.{.{ .destination = destination, .source = source }} };
    const preserving = Contract{ .outputs = &.{} };
    const contract = Contract{
        .outputs = &.{ .{}, .{} },
        .outcomes = &.{
            .{ .output_index = 1, .variant_index = 0, .effects = &relocation },
            .{ .output_index = 1, .variant_index = 1, .effects = &preserving },
        },
    };
    const moved = facts.PlacePostState{ .target = source, .initializedness = .moved };
    const initialized = facts.PlacePostState{
        .target = destination,
        .initializedness = .initialized,
        .value = .{ .input_place_values = &.{source} },
        .requires_available_destination = true,
        .refreshes_storage_generation = true,
    };
    var possible_source = moved;
    possible_source.initializedness = .maybe_initialized;
    possible_source.value = .{ .input_place_values = &.{source} };
    var possible_destination = initialized;
    possible_destination.initializedness = .maybe_initialized;
    var exits = [_]facts.OutcomePostStates{
        .{ .output_index = 1, .variant_index = 0, .input_post_states = &.{ moved, initialized } },
        .{ .output_index = 1, .variant_index = 1, .input_post_states = &.{} },
    };
    const summary = facts.SafetySummary{
        .outputs = &.{ .{}, .{} },
        .input_post_states = &.{ possible_source, possible_destination },
        .outcome_post_states = &exits,
    };
    try std.testing.expect(check(contract, summary) == null);

    exits[0].input_post_states = &.{initialized};
    try std.testing.expectEqual(.missing_relocation, check(contract, summary).?.kind);
    exits[0].input_post_states = &.{ moved, possible_destination };
    try std.testing.expectEqual(.missing_relocation, check(contract, summary).?.kind);
    var wrong = initialized;
    wrong.value = .{};
    exits[0].input_post_states = &.{ moved, wrong };
    try std.testing.expectEqual(.missing_relocation, check(contract, summary).?.kind);
    exits[0].input_post_states = &.{ moved, initialized };
    var invalid_union = summary;
    var foreign_source = possible_source;
    foreign_source.value = .{ .input_place_values = &.{destination} };
    invalid_union.input_post_states = &.{ foreign_source, possible_destination };
    try std.testing.expectEqual(.unsupported_post_state, check(contract, invalid_union).?.kind);
    exits[1].input_post_states = &.{ moved, initialized };
    try std.testing.expectEqual(.unsupported_post_state, check(contract, summary).?.kind);

    var missing = summary;
    missing.input_post_states = &.{};
    missing.outcome_post_states = &.{exits[1]};
    try std.testing.expectEqual(.missing_relocation, check(contract, missing).?.kind);
    missing.outcome_post_states = &.{.{ .output_index = 1, .variant_index = 0, .reachable = false, .input_post_states = &.{} }};
    try std.testing.expect(check(contract, missing) == null);

    const nested = Contract{
        .outputs = &.{ .{}, .{} },
        .outcomes = &.{.{ .output_index = 1, .parent_variants = &.{0}, .variant_index = 0, .effects = &relocation }},
    };
    var nested_summary = summary;
    nested_summary.outcome_post_states = &.{.{ .output_index = 1, .parent_variants = &.{0}, .variant_index = 0, .input_post_states = &.{ moved, initialized } }};
    try std.testing.expect(check(nested, nested_summary) == null);
    nested_summary.outcome_post_states = &.{.{ .output_index = 1, .parent_variants = &.{1}, .variant_index = 0, .input_post_states = &.{ moved, initialized } }};
    try std.testing.expect(check(nested, nested_summary) != null);
}

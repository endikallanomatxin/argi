const std = @import("std");
const facts = @import("safety_facts.zig");

/// Contracts describe permitted effects, rather than a concrete method's exact
/// summary. Keeping their identities in input/output coordinates allows the
/// same contract to be checked before receiver layout is erased.
pub const Output = struct {
    dependencies: []const facts.InputPath = &.{},
    ownership_transfers: []const facts.InputPath = &.{},
    storage_sources: []const facts.InputPath = &.{},
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
    general_conditions: bool = false,
    outputs: []const Output,
    outcomes: []const Outcome = &.{},
    /// Each complete conditional contract must be proved under its whole guard.
    guarded_effects: []const Guarded = &.{},
    /// Definite destruction guarantees for caller-owned input places.
    consumed_inputs: []const facts.InputPath = &.{},
    relocations: []const Relocation = &.{},
    retained_inputs: []const Retention = &.{},
    emptied_inputs: []const facts.InputPath = &.{},
    /// Paths are resolved domain mappings, not source field names. Ending a
    /// generation permits invalidating references, but grants no permission to
    /// consume owned resources or replace hidden dependency contents.
    invalidates: []const facts.InputPath = &.{},
    invalidated_domains: []const facts.InputDomain = &.{},

    pub const Guarded = struct {
        conditions: facts.ChoiceConditions,
        effects: *const Contract,
    };

    pub const Relocation = struct { destination: facts.InputPath, source: facts.InputPath };
    pub const Retention = struct { storage: facts.InputPath, input: facts.InputPath };
    pub const Outcome = struct { output_index: u32, parent_variants: []const u32 = &.{}, variant_index: u32, effects: *const Contract };
};

pub fn fromDeclaration(allocator: std.mem.Allocator, declaration: @import("../primitives/schema.zig").MethodSafetyContract) anyerror!Contract {
    if (declaration.general_conditions) {
        var common = declaration;
        common.general_conditions = false;
        common.outcomes = &.{};
        var result = try fromDeclaration(allocator, common);
        var guarded: std.ArrayList(Contract.Guarded) = .empty;
        try appendGeneralContracts(allocator, declaration.outcomes, .{}, result, &guarded);
        result.general_conditions = true;
        result.guarded_effects = try guarded.toOwnedSlice(allocator);
        return result;
    }
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
        var storage_sources: std.ArrayList(facts.InputPath) = .empty;
        for (declaration.storage_sources) |source| if (source.output_index == index) try storage_sources.append(allocator, storageInputPath(source.storage));
        output.storage_sources = try storage_sources.toOwnedSlice(allocator);
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
                .storage_sources = outcome.storage_sources,
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
    const relocations = try allocator.alloc(Contract.Relocation, declaration.relocations.len);
    for (declaration.relocations, relocations) |declared, *relocation| relocation.* = .{ .destination = .{ .input_index = declared.destination }, .source = .{ .input_index = declared.source } };

    const retained = try allocator.alloc(Contract.Retention, declaration.retained_inputs.len);
    for (declaration.retained_inputs, retained) |declared, *retention| retention.* = .{ .storage = storageInputPath(declared.storage), .input = .{ .input_index = declared.input } };
    const emptied = try allocator.alloc(facts.InputPath, declaration.emptied_inputs.len);
    for (declaration.emptied_inputs, emptied) |input, *path| path.* = storageInputPath(input);
    try appendConditionalContracts(allocator, declaration.output_count, declaration.outcomes, &.{}, invalidates, invalidated_domains, consumed_inputs, relocations, emptied, &conditional);
    return .{ .outputs = outputs, .consumed_inputs = consumed_inputs, .relocations = relocations, .retained_inputs = retained, .emptied_inputs = emptied, .invalidates = invalidates, .invalidated_domains = invalidated_domains, .outcomes = try conditional.toOwnedSlice(allocator) };
}

fn appendGeneralContracts(allocator: std.mem.Allocator, outcomes: []const @import("../primitives/schema.zig").MethodSafetyContract.Outcome, enclosing: facts.ChoiceConditions, common: Contract, result: *std.ArrayList(Contract.Guarded)) anyerror!void {
    for (outcomes) |outcome| {
        const offset: usize = if (outcome.input_dereference) 1 else 0;
        const projections = try allocator.alloc(@import("place.zig").Projection, outcome.parent_variants.len + offset);
        if (offset != 0) projections[0] = .dereference;
        for (outcome.parent_variants, projections[offset..]) |variant, *projection| projection.* = .{ .variant = variant };
        const selector = try @import("choice_conditions.zig").normalize(allocator, &.{.{
            .subject = if (outcome.input_index != null) .entry_input else .output,
            .index = outcome.input_index orelse outcome.output_index,
            .projections = projections,
            .variant_index = outcome.variant_index orelse return error.UnresolvedOutcomeContract,
        }});
        const conditions = try @import("choice_conditions.zig").conjoin(allocator, enclosing, selector);
        var clause = try fromDeclaration(allocator, .{
            .output_count = @intCast(common.outputs.len),
            .dependencies = outcome.dependencies,
            .domain_dependencies = outcome.domain_dependencies,
            .owned_outputs = outcome.owned_outputs,
            .storage_sources = outcome.storage_sources,
            .emptied_inputs = outcome.emptied_inputs,
            .consumed_inputs = outcome.consumed_inputs,
            .relocations = outcome.relocations,
            .invalidates = outcome.invalidates,
            .invalidated_domains = outcome.invalidated_domains,
            .source = outcome.source,
        });
        const outputs = try allocator.dupe(Output, clause.outputs);
        for (outputs, 0..) |*output, index| {
            var selected: ?facts.ChoiceCondition = null;
            for (conditions.terms) |term| if (term.subject == .output and term.index == index and (selected == null or term.projections.len > selected.?.projections.len)) {
                selected = term;
            };
            if (selected) |term| {
                const leaf = try allocator.create(Output);
                leaf.* = output.*;
                output.* = .{ .outcomes = try allocator.dupe(Output.Outcome, &.{.{ .variant_index = term.variant_index, .value = leaf }}) };
                var depth = term.projections.len;
                while (depth != 0) {
                    depth -= 1;
                    const child = try allocator.create(Output);
                    child.* = output.*;
                    output.* = .{ .outcomes = try allocator.dupe(Output.Outcome, &.{.{ .variant_index = term.projections[depth].variant, .value = child }}) };
                }
            }
        }
        clause.outputs = outputs;
        const effects = try allocator.create(Contract);
        effects.* = try mergeContracts(allocator, common, clause);
        try result.append(allocator, .{ .conditions = conditions, .effects = effects });
        try appendGeneralContracts(allocator, outcome.outcomes, conditions, effects.*, result);
    }
}

pub fn mergeContracts(allocator: std.mem.Allocator, a: Contract, b: Contract) anyerror!Contract {
    if (a.outputs.len != b.outputs.len) return error.InvalidContractOutput;
    const outputs = try allocator.alloc(Output, a.outputs.len);
    for (a.outputs, b.outputs, outputs) |left, right, *output| output.* = try mergeOutputs(allocator, left, right);
    return .{
        .outputs = outputs,
        .consumed_inputs = try mergeEffectSets(allocator, facts.InputPath, a.consumed_inputs, b.consumed_inputs),
        .relocations = try mergeEffectSets(allocator, Contract.Relocation, a.relocations, b.relocations),
        .retained_inputs = try mergeEffectSets(allocator, Contract.Retention, a.retained_inputs, b.retained_inputs),
        .emptied_inputs = try mergeEffectSets(allocator, facts.InputPath, a.emptied_inputs, b.emptied_inputs),
        .invalidates = try mergeEffectSets(allocator, facts.InputPath, a.invalidates, b.invalidates),
        .invalidated_domains = try mergeEffectSets(allocator, facts.InputDomain, a.invalidated_domains, b.invalidated_domains),
    };
}

fn effectPathEqual(a: facts.InputPath, b: facts.InputPath) bool {
    if (a.input_index != b.input_index or a.storage_domain != b.storage_domain or a.projections.len != b.projections.len) return false;
    for (a.projections, b.projections) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
}

fn effectEqual(comptime T: type, a: T, b: T) bool {
    if (T == facts.InputPath) return effectPathEqual(a, b);
    if (T == facts.InputDomain) return a.domain_index == b.domain_index and effectPathEqual(a.path, b.path);
    if (T == Contract.Relocation) return effectPathEqual(a.source, b.source) and effectPathEqual(a.destination, b.destination);
    if (T == Contract.Retention) return effectPathEqual(a.storage, b.storage) and effectPathEqual(a.input, b.input);
    @compileError("Unsupported contract effect set");
}

fn mergeEffectSets(allocator: std.mem.Allocator, comptime T: type, a: []const T, b: []const T) ![]const T {
    var result: std.ArrayList(T) = .empty;
    for ([_][]const T{ a, b }) |set| for (set) |effect| {
        var duplicate = false;
        for (result.items) |existing| if (effectEqual(T, existing, effect)) {
            duplicate = true;
            break;
        };
        if (!duplicate) try result.append(allocator, effect);
    };
    return try result.toOwnedSlice(allocator);
}

fn mergeOutputs(allocator: std.mem.Allocator, a: Output, b: Output) anyerror!Output {
    var outcomes: std.ArrayList(Output.Outcome) = .empty;
    try outcomes.appendSlice(allocator, a.outcomes);
    for (b.outcomes) |right| {
        var found = false;
        for (outcomes.items) |*left| if (left.variant_index == right.variant_index) {
            const merged = try allocator.create(Output);
            merged.* = try mergeOutputs(allocator, left.value.*, right.value.*);
            left.value = merged;
            found = true;
            break;
        };
        if (!found) try outcomes.append(allocator, right);
    }
    return .{
        .dependencies = try std.mem.concat(allocator, facts.InputPath, &.{ a.dependencies, b.dependencies }),
        .ownership_transfers = try std.mem.concat(allocator, facts.InputPath, &.{ a.ownership_transfers, b.ownership_transfers }),
        .storage_sources = try std.mem.concat(allocator, facts.InputPath, &.{ a.storage_sources, b.storage_sources }),
        .referent = a.referent orelse b.referent,
        .domains = try std.mem.concat(allocator, facts.InputDomain, &.{ a.domains, b.domains }),
        .fresh_owner = a.fresh_owner or b.fresh_owner,
        .outcomes = try outcomes.toOwnedSlice(allocator),
    };
}

/// Close a guard over every still-compatible conditional permission. A parent
/// clause alone must not erase dependencies introduced by unresolved children.
pub fn effectsUnderConditions(allocator: std.mem.Allocator, contract: Contract, known: facts.ChoiceConditions) !Contract {
    var result = contract;
    result.general_conditions = false;
    result.guarded_effects = &.{};
    for (contract.guarded_effects) |guarded| {
        const status = guarded.conditions.evaluate(known);
        if (status == .contradicted) continue;
        var effects = guarded.effects.*;
        if (status != .satisfied) {
            effects.consumed_inputs = &.{};
            effects.relocations = &.{};
            effects.emptied_inputs = &.{};
        }
        result = try mergeContracts(allocator, result, effects);
    }
    return result;
}

/// Unknown dispatch uses all possible permissions, never conditional guarantees.
pub fn possibleEffects(allocator: std.mem.Allocator, contract: Contract) !Contract {
    var result = contract;
    result.general_conditions = false;
    result.guarded_effects = &.{};
    for (contract.guarded_effects) |guarded| {
        if (guarded.conditions.impossible) continue;
        var permissions = guarded.effects.*;
        permissions.consumed_inputs = &.{};
        permissions.relocations = &.{};
        permissions.emptied_inputs = &.{};
        result = try mergeContracts(allocator, result, permissions);
    }
    return result;
}

fn appendConditionalContracts(allocator: std.mem.Allocator, output_count: u32, outcomes: []const @import("../primitives/schema.zig").MethodSafetyContract.Outcome, parents: []const u32, common_invalidates: []const facts.InputPath, common_domains: []const facts.InputDomain, common_consumed: []const facts.InputPath, common_relocations: []const Contract.Relocation, common_emptied: []const facts.InputPath, result: *std.ArrayList(Contract.Outcome)) anyerror!void {
    for (outcomes) |outcome| {
        const effects = try allocator.create(Contract);
        effects.* = try fromDeclaration(allocator, .{
            .output_count = output_count,
            .invalidates = outcome.invalidates,
            .consumed_inputs = outcome.consumed_inputs,
            .relocations = outcome.relocations,
            .emptied_inputs = outcome.emptied_inputs,
            .invalidated_domains = outcome.invalidated_domains,
            .source = outcome.source,
        });
        effects.invalidates = try std.mem.concat(allocator, facts.InputPath, &.{ common_invalidates, effects.invalidates });
        effects.invalidated_domains = try std.mem.concat(allocator, facts.InputDomain, &.{ common_domains, effects.invalidated_domains });
        effects.consumed_inputs = try std.mem.concat(allocator, facts.InputPath, &.{ common_consumed, effects.consumed_inputs });
        // Selected exits retain every enclosing transfer guarantee, including
        // those declared before an otherwise empty nested selector.
        effects.relocations = try std.mem.concat(allocator, Contract.Relocation, &.{ common_relocations, effects.relocations });
        effects.emptied_inputs = try std.mem.concat(allocator, facts.InputPath, &.{ common_emptied, effects.emptied_inputs });
        const variant = outcome.variant_index orelse return error.UnresolvedOutcomeContract;
        try result.append(allocator, .{ .output_index = outcome.output_index, .parent_variants = parents, .variant_index = variant, .effects = effects });
        const child_parents = try std.mem.concat(allocator, u32, &.{ parents, &.{variant} });
        try appendConditionalContracts(allocator, output_count, outcome.outcomes, child_parents, effects.invalidates, effects.invalidated_domains, effects.consumed_inputs, effects.relocations, effects.emptied_inputs, result);
    }
}

test "relocation declarations retain common and nested guarantees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const contract = try fromDeclaration(arena.allocator(), .{
        .output_count = 1,
        .source = source,
        .relocations = &.{.{ .source = 0, .destination = 1 }},
        .outcomes = &.{.{
            .variant = .{ .start = 0, .len = 0 },
            .variant_index = 0,
            .source = source,
            .relocations = &.{.{ .source = 2, .destination = 3 }},
            .outcomes = &.{.{ .variant = .{ .start = 0, .len = 0 }, .variant_index = 1, .source = source }},
        }},
    });
    try std.testing.expectEqual(@as(usize, 1), contract.relocations.len);
    try std.testing.expectEqual(@as(usize, 2), contract.outcomes.len);
    for (contract.outcomes) |outcome| {
        try std.testing.expectEqual(@as(usize, 2), outcome.effects.relocations.len);
        try std.testing.expectEqual(@as(u32, 0), outcome.effects.relocations[0].source.input_index);
        try std.testing.expectEqual(@as(u32, 2), outcome.effects.relocations[1].source.input_index);
    }
}

pub fn selectorCovers(expected: anytype, actual: anytype) bool {
    if (expected.output_index != actual.output_index or expected.parent_variants.len > actual.parent_variants.len) return false;
    if (!std.mem.eql(u32, expected.parent_variants, actual.parent_variants[0..expected.parent_variants.len])) return false;
    const selected = if (expected.parent_variants.len == actual.parent_variants.len) actual.variant_index else actual.parent_variants[expected.parent_variants.len];
    return expected.variant_index == selected;
}

/// Translate the declaration's payload and input-transition views together.
/// This runs after concrete domain resolution so both views retain actual
/// input paths. Conditional records inherit common provenance permissions;
/// selected guarantees remain distinct from the unconditional contract.
pub fn withOutcomeGuards(allocator: std.mem.Allocator, contract: Contract) !Contract {
    if (contract.guarded_effects.len != 0 or contract.outcomes.len == 0) return contract;
    var guarded: std.ArrayList(Contract.Guarded) = .empty;
    defer guarded.deinit(allocator);
    for (contract.outcomes) |outcome| {
        // A refined payload is partitioned at its leaves. Their contracts
        // already inherit every enclosing guarantee; the parent is not an
        // additional unconditional preservation promise over differing leaves.
        var refined = false;
        for (contract.outcomes) |child| {
            if (child.output_index != outcome.output_index or child.parent_variants.len <= outcome.parent_variants.len) continue;
            if (std.mem.eql(u32, child.parent_variants[0..outcome.parent_variants.len], outcome.parent_variants) and child.parent_variants[outcome.parent_variants.len] == outcome.variant_index) {
                refined = true;
                break;
            }
        }
        if (refined) continue;
        const projections = try allocator.alloc(@import("place.zig").Projection, outcome.parent_variants.len);
        for (outcome.parent_variants, projections) |variant, *projection| projection.* = .{ .variant = variant };
        const conditions = try @import("choice_conditions.zig").normalize(allocator, &.{.{
            .subject = .output,
            .index = outcome.output_index,
            .projections = projections,
            .variant_index = outcome.variant_index,
        }});
        const effects = try allocator.create(Contract);
        effects.* = outcome.effects.*;
        effects.outputs = contract.outputs;
        effects.retained_inputs = contract.retained_inputs;
        effects.outcomes = &.{};
        effects.guarded_effects = &.{};
        try guarded.append(allocator, .{ .conditions = conditions, .effects = effects });
    }
    var result = contract;
    result.guarded_effects = try guarded.toOwnedSlice(allocator);
    return result;
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
    selected.retained_inputs = contract.retained_inputs;

    return selected;
}

fn permitsEmptyStorage(contract: Contract, storage: facts.InputPath) bool {
    if (containsExactPath(contract.emptied_inputs, storage)) return true;
    for (contract.outcomes) |outcome| if (containsExactPath(outcome.effects.emptied_inputs, storage)) return true;
    return false;
}

// Consumption permits emptying storage owned by that input, after definite
// destruction is proved. It grants no retention or borrowed-storage effects.
fn permitsConsumedStorageEmpty(contract: Contract, storage: facts.InputPath, states: []const facts.PlacePostState) bool {
    for (storage.projections) |projection| if (projection == .dereference) return false;
    for (contract.consumed_inputs) |input| {
        if (!covers(&.{input}, storage)) continue;
        for (states) |state| if (samePath(state.target, input) and
            state.initializedness == .deinitialized and state.ends_previous_roots) return true;
    }
    return false;
}

fn inheritOutputPermissions(allocator: std.mem.Allocator, output: *Output, common: Output) anyerror!void {
    output.dependencies = try std.mem.concat(allocator, facts.InputPath, &.{ common.dependencies, output.dependencies });
    output.domains = try std.mem.concat(allocator, facts.InputDomain, &.{ common.domains, output.domains });
    output.fresh_owner = output.fresh_owner or common.fresh_owner;
    output.referent = common.referent;
    output.ownership_transfers = common.ownership_transfers;
    // Hidden provenance is an output permission, not an input post-state.
    // Preserve enclosing permissions while adding this payload's own sources.
    output.storage_sources = try std.mem.concat(allocator, facts.InputPath, &.{ common.storage_sources, output.storage_sources });
    for (output.outcomes) |outcome| try inheritOutputPermissions(allocator, @constCast(outcome.value), common);
}

pub const Failure = struct {
    pub const Kind = enum {
        output_count,
        undeclared_dependency,
        undeclared_ownership_transfer,
        incompatible_referent,
        undeclared_fresh_owner,
        unsupported_post_state,
        missing_consumption,
        missing_relocation,
        missing_empty_storage,
        unsupported_opaque_effect,
        unsupported_capability_effect,
        unsupported_alias_obligation,
        missing_choice_relation,
    };
    kind: Kind,
    output_index: ?u32 = null,
    conditions: ?facts.ChoiceConditions = null,
    input: ?facts.InputPath = null,
    outcome: ?struct { output_index: u32, parent_variants: []const u32 = &.{}, variant_index: u32 } = null,

    pub fn description(self: Failure) []const u8 {
        return switch (self.kind) {
            .missing_choice_relation => "cannot prove the complete input/output choice condition; partial selector evidence is insufficient",
            .output_count => "the number of outputs differs",
            .undeclared_dependency => "undeclared output dependency",
            .undeclared_ownership_transfer => "undeclared ownership transfer",
            .incompatible_referent => "the output must refer to the same storage as the declared input",
            .undeclared_fresh_owner => "undeclared fresh output ownership; declare owns(output)",
            .missing_relocation => "cannot prove relocates: move the source into an available destination on every returning path",
            .missing_consumption => "cannot prove consumes: the input must be deinitialized on every returning path",
            .missing_empty_storage => "cannot prove empties: discharge the storage's hidden contents on every returning path",
            .unsupported_post_state => "a storage transition is not permitted by this preservation contract",
            .unsupported_opaque_effect => "an opaque storage effect is not permitted by this preservation contract",
            .unsupported_capability_effect => "storage capability consumption is not permitted by this contract",
            .unsupported_alias_obligation => "a caller-side storage alias obligation is not represented by this contract",
        };
    }
};

// A concrete call retains the implementation's complete inferred summary at
// its caller. Only alias preconditions can be checked there; output and storage
// guarantees still have to satisfy the declared contract without weakening it.
pub fn checkStatic(contract: Contract, summary: facts.SafetySummary) ?Failure {
    var guarantees = summary;
    guarantees.storage_observation_conflicts = &.{};
    return check(contract, guarantees);
}

/// Check each implementation independently. No result depends on which other
/// implementations are linked into the program. Local escapes must already
/// have passed the ordinary function-output check: a contract never authorizes
/// an expired local generation or certifies physical pointer validity.
pub fn check(contract: Contract, summary: facts.SafetySummary) ?Failure {
    if (summary.storage_observation_conflicts.len != 0) return .{
        .kind = .unsupported_alias_obligation,
        .input = summary.storage_observation_conflicts[0].consumed,
    };
    if (contract.general_conditions) return checkGeneralContract(contract, summary);
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
        for (required.effects.emptied_inputs) |storage| {
            var represented = false;
            for (summary.outcome_post_states) |actual| if (selectorCovers(required, actual)) {
                represented = true;
                break;
            };
            if (!represented) return .{ .kind = .missing_empty_storage, .input = storage };
        }
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
        for (allowed.emptied_inputs) |storage| if (!containsExactPath(outcome.opaque_storage_empties, storage) and !containsExactPath(summary.opaque_storage_empties, storage)) return .{ .kind = .missing_empty_storage, .input = storage, .outcome = .{ .output_index = outcome.output_index, .parent_variants = outcome.parent_variants, .variant_index = outcome.variant_index } };
        for (outcome.opaque_storage_empties) |storage| if (!containsExactPath(allowed.emptied_inputs, storage) and !permitsConsumedStorageEmpty(allowed, storage, outcome.input_post_states)) return .{ .kind = .unsupported_opaque_effect, .input = storage };
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
    for (summary.opaque_storage_effects) |effect| {
        if (!permitsRetention(contract, effect.storage, effect.hidden_dependencies)) return .{ .kind = .unsupported_opaque_effect, .input = effect.storage };
    }
    for (summary.opaque_storage_empties) |path| {
        if (!permitsEmptyStorage(contract, path) and !permitsConsumedStorageEmpty(contract, path, summary.input_post_states)) return .{ .kind = .unsupported_opaque_effect, .input = path };
    }
    for (contract.emptied_inputs) |path| {
        if (!containsExactPath(summary.opaque_storage_empties, path)) return .{ .kind = .missing_empty_storage, .input = path };
    }
    if (summary.storage_capability_uses.len != 0) return .{
        .kind = .unsupported_capability_effect,
        .input = summary.storage_capability_uses[0].target,
    };
    if (summary.storage_capability_conflicts.len != 0) return .{
        .kind = .unsupported_capability_effect,
        .input = summary.storage_capability_conflicts[0].first,
    };
    return checkGuardedRelations(contract.guarded_effects, summary);
}

fn checkGeneralContract(contract: Contract, summary: facts.SafetySummary) ?Failure {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var represented = false;
    for (summary.guarded_effects) |actual| {
        if (actual.conditions.impossible) continue;
        represented = true;
        if (checkGeneralRegion(arena.allocator(), contract, actual.conditions, actual.effects.*) catch return .{ .kind = .missing_choice_relation }) |failure| return failure;
    }
    if (!represented or !summary.guarded_returns_complete) {
        var fallback = summary;
        fallback.guarded_effects = &.{};
        const known = knownOutputConditions(arena.allocator(), summary.outputs) catch return .{ .kind = .missing_choice_relation };
        if (checkGeneralRegion(arena.allocator(), contract, known, fallback) catch return .{ .kind = .missing_choice_relation }) |failure| return failure;
    }
    return null;
}

fn checkGeneralRegion(allocator: std.mem.Allocator, contract: Contract, conditions: facts.ChoiceConditions, summary: facts.SafetySummary) !?Failure {
    var allowed = contract;
    allowed.general_conditions = false;
    allowed.guarded_effects = &.{};
    for (contract.guarded_effects) |clause| if (conditions.implies(clause.conditions)) {
        allowed = try mergeContracts(allocator, allowed, clause.effects.*);
    };
    var actual = summary;
    actual.guarded_effects = &.{};
    actual.outcome_post_states = &.{};
    if (check(allowed, actual)) |failure| {
        var result = failure;
        result.conditions = conditions;
        return result;
    }
    // A region with unresolved selectors may not use their permissions. It
    // still has to establish promises for every compatible selected exit.
    for (contract.guarded_effects) |required| {
        if (required.conditions.evaluate(conditions) != .unknown) continue;
        allowed.consumed_inputs = try std.mem.concat(allocator, facts.InputPath, &.{ allowed.consumed_inputs, required.effects.consumed_inputs });
        allowed.relocations = try std.mem.concat(allocator, Contract.Relocation, &.{ allowed.relocations, required.effects.relocations });
        allowed.emptied_inputs = try std.mem.concat(allocator, facts.InputPath, &.{ allowed.emptied_inputs, required.effects.emptied_inputs });
    }
    if (check(allowed, actual)) |failure| {
        var result = failure;
        result.conditions = conditions;
        return result;
    }
    return null;
}

pub fn knownOutputConditions(allocator: std.mem.Allocator, outputs: []const facts.ValueEffect) !facts.ChoiceConditions {
    var terms: std.ArrayList(facts.ChoiceCondition) = .empty;
    defer terms.deinit(allocator);
    for (outputs, 0..) |output, index| try appendKnownOutputConditions(allocator, output, @intCast(index), &.{}, &terms);
    return @import("choice_conditions.zig").normalize(allocator, terms.items);
}

fn appendKnownOutputConditions(allocator: std.mem.Allocator, value: facts.ValueEffect, index: u32, projections: []const @import("place.zig").Projection, terms: *std.ArrayList(facts.ChoiceCondition)) anyerror!void {
    if (value.known_choice_variant) |variant| {
        try terms.append(allocator, .{ .subject = .output, .index = index, .projections = projections, .variant_index = variant });
        for (value.variants) |payload| if (payload.index == variant) try appendKnownOutputConditions(allocator, payload.value.*, index, try std.mem.concat(allocator, @import("place.zig").Projection, &.{ projections, &.{.{ .variant = variant }} }), terms);
    }
    for (value.fields) |field| try appendKnownOutputConditions(allocator, field.value.*, index, try std.mem.concat(allocator, @import("place.zig").Projection, &.{ projections, &.{.{ .field = field.index }} }), terms);
}

/// A declared conjunction can use an approximation proved under a weaker
/// condition, but not one proved only under a stricter subset of its exits.
/// The unconditional summary is also a valid proof when it already establishes
/// the requested guarantee. Unrelated singleton partitions cannot be combined.
pub fn checkGuardedRelations(required: []const Contract.Guarded, summary: facts.SafetySummary) ?Failure {
    for (required) |relation| {
        if (relation.conditions.impossible or guardHasUnreachableOutcome(relation.conditions, summary)) continue;
        var has_partition = false;
        var last_failure: ?Failure = null;
        for (summary.guarded_effects) |actual| {
            if (!relation.conditions.implies(actual.conditions)) continue;
            has_partition = true;
            if (check(relation.effects.*, actual.effects.*)) |failure| {
                last_failure = failure;
            } else {
                last_failure = null;
                break;
            }
        }
        if (has_partition and last_failure == null) continue;
        // Output partitions are authoritative compact records. Consult their
        // current fields directly instead of retaining duplicate guarded summaries.
        for (summary.outcome_post_states) |outcome| {
            if (!outcome.reachable or !relation.conditions.impliesOutput(outcome.output_index, outcome.parent_variants, outcome.variant_index)) continue;
            has_partition = true;
            if (check(relation.effects.*, summary.outcomeEffects(outcome))) |failure| {
                last_failure = failure;
            } else {
                last_failure = null;
                break;
            }
        }
        if (has_partition and last_failure == null) continue;
        var fallback = summary;
        fallback.guarded_effects = &.{};
        if (check(relation.effects.*, fallback) == null) continue;
        if (last_failure) |failure| {
            var result = failure;
            result.conditions = relation.conditions;
            return result;
        }
        return .{ .kind = .missing_choice_relation, .conditions = relation.conditions };
    }
    return null;
}

fn guardHasUnreachableOutcome(conditions: facts.ChoiceConditions, summary: facts.SafetySummary) bool {
    for (summary.outcome_post_states) |outcome| {
        if (outcome.reachable) continue;
        for (conditions.terms) |term| {
            if (term.subject != .output or term.index != outcome.output_index or term.variant_index != outcome.variant_index or term.projections.len != outcome.parent_variants.len) continue;
            var matches = true;
            for (term.projections, outcome.parent_variants) |projection, variant| {
                if (projection != .variant or projection.variant != variant) {
                    matches = false;
                    break;
                }
            }
            if (matches) return true;
        }
    }
    return false;
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
    };
    for (dependencies) |paths| {
        for (paths) |path| {
            if (!covers(allowed.dependencies, path)) return .{ .kind = .undeclared_dependency, .input = path };
        }
    }
    for (actual.opaque_storage_dependencies) |path| {
        if (!covers(allowed.storage_sources, path) and !covers(allowed.dependencies, path)) return .{ .kind = .undeclared_dependency, .input = path };
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

fn storageInputPath(input: @import("../primitives/schema.zig").MethodSafetyContract.StorageInput) facts.InputPath {
    return .{ .input_index = input.input_index, .storage_domain = input.domain_index };
}

fn samePath(a: facts.InputPath, b: facts.InputPath) bool {
    if (a.input_index != b.input_index or a.storage_domain != b.storage_domain or a.projections.len != b.projections.len) return false;
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

fn containsExactPath(paths: []const facts.InputPath, target: facts.InputPath) bool {
    for (paths) |path| if (samePath(path, target)) return true;
    return false;
}

/// Retention is an upper bound on hidden input provenance, including ownership
/// already transferred by value. It grants no fresh resource or generation.
fn permitsRetention(contract: Contract, storage: facts.InputPath, value: facts.ValueEffect) bool {
    var represented = false;
    for (contract.retained_inputs) |retained| if (samePath(retained.storage, storage)) {
        represented = true;
        break;
    };
    if (!represented) return false;
    return retainedValueAllowed(contract, storage, value);
}

fn retainedPathAllowed(contract: Contract, storage: facts.InputPath, path: facts.InputPath) bool {
    for (contract.retained_inputs) |retained| {
        if (samePath(retained.storage, storage) and covers(&.{retained.input}, path)) return true;
    }
    return false;
}

fn retainedValueAllowed(contract: Contract, storage: facts.InputPath, value: facts.ValueEffect) bool {
    if (value.fresh_cleanup_obligation or value.fresh_dependencies.len != 0 or value.fresh_owned_roots.len != 0 or value.fresh_storage_capabilities.len != 0 or value.unavailable_fresh_storage.len != 0 or value.input_domains.len != 0 or value.domain_values.len != 0) return false;
    for (value.input_dependencies) |dependency| if (!retainedPathAllowed(contract, storage, dependency.path)) return false;
    for ([_][]const facts.InputPath{ value.input_places, value.input_generation_dependencies, value.input_captured_storages, value.input_receiver_values, value.input_place_values, value.input_owned_roots, value.input_storage_capabilities, value.opaque_generation_dependencies, value.opaque_storage_dependencies }) |paths| {
        for (paths) |path| if (!retainedPathAllowed(contract, storage, path)) return false;
    }
    for (value.fields) |field| if (!retainedValueAllowed(contract, storage, field.value.*)) return false;
    for (value.variants) |variant| if (!retainedValueAllowed(contract, storage, variant.value.*)) return false;
    return true;
}

fn covers(allowed: []const facts.InputPath, actual: facts.InputPath) bool {
    for (allowed) |path| {
        if (path.input_index != actual.input_index or path.storage_domain != actual.storage_domain or path.projections.len > actual.projections.len) continue;
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
    for (contract.retained_inputs) |retained| {
        if (!samePath(state.target, retained.input)) continue;
        // These inputs are passed by value. Consuming their local owner into
        // opaque storage creates no additional caller-place cleanup transition.
        if (state.opaque_ownership == .none and state.opaque_storage == null and
            (state.initializedness == .moved or state.initializedness == .deinitialized) and
            !state.refreshes_storage_generation and !state.requires_available_destination and
            !state.may_repopulate_opaque_storage and emptyValue(state.value)) return true;
        if (state.opaque_ownership != .definite and state.opaque_ownership != .conditional) continue;
        if (state.opaque_storage) |storage| if (samePath(storage, retained.storage)) return state.initializedness == .initialized and !state.ends_previous_roots and
            !state.refreshes_storage_generation and !state.requires_available_destination and
            !state.may_repopulate_opaque_storage and emptyValue(state.value);
    }
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
    try std.testing.expectEqual(.unsupported_alias_obligation, check(contract, .{
        .storage_observation_conflicts = &.{.{ .consumed = path, .observed = .{ .input_index = 1 } }},
    }).?.kind);
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

test "opaque retention permits only declared input provenance" {
    const storage = facts.InputPath{ .input_index = 1 };
    const input = facts.InputPath{ .input_index = 2 };
    const unrelated = facts.InputPath{ .input_index = 3 };
    const contract = Contract{ .outputs = &.{}, .retained_inputs = &.{.{ .storage = storage, .input = input }} };
    const retained = facts.ValueEffect{ .input_dependencies = &.{.{ .path = input, .transfers_ownership = true }} };
    try std.testing.expect(check(contract, .{ .opaque_storage_effects = &.{.{ .storage = storage, .hidden_dependencies = retained }} }) == null);
    try std.testing.expect(check(contract, .{ .opaque_storage_effects = &.{.{ .storage = unrelated, .hidden_dependencies = retained }} }) != null);
    const nested = facts.ValueEffect{ .fields = &.{.{ .index = 0, .value = &.{ .input_generation_dependencies = &.{unrelated} } }} };
    try std.testing.expect(check(contract, .{ .opaque_storage_effects = &.{.{ .storage = storage, .hidden_dependencies = nested }} }) != null);
    try std.testing.expect(check(contract, .{ .opaque_storage_effects = &.{.{ .storage = storage, .hidden_dependencies = .{ .fresh_owned_roots = &.{1} } }} }) != null);
}

test "opaque empty guarantees require every returning exit" {
    const storage = facts.InputPath{ .input_index = 1 };
    const contract = Contract{ .outputs = &.{}, .emptied_inputs = &.{storage} };
    try std.testing.expectEqual(.missing_empty_storage, check(contract, .{}).?.kind);
    try std.testing.expect(check(contract, .{ .opaque_storage_empties = &.{storage} }) == null);
    try std.testing.expect(check(.{ .outputs = &.{} }, .{ .opaque_storage_empties = &.{storage} }) != null);
}

test "opaque output provenance does not authorize backing storage references" {
    const storage = facts.InputPath{ .input_index = 1 };
    const contract = Contract{ .outputs = &.{.{ .storage_sources = &.{storage} }} };
    try std.testing.expect(check(contract, .{ .outputs = &.{.{ .opaque_storage_dependencies = &.{storage} }} }) == null);
    try std.testing.expect(check(contract, .{ .outputs = &.{.{ .input_places = &.{storage} }} }) != null);
    try std.testing.expect(check(contract, .{ .outputs = &.{.{ .input_dependencies = &.{.{ .path = storage, .transfers_ownership = true }} }} }) != null);
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

test "conditional opaque sources retain common and nested permissions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const contract = try fromDeclaration(arena.allocator(), .{
        .output_count = 1,
        .source = source,
        .storage_sources = &.{.{ .output_index = 0, .storage = .{ .input_index = 1 } }},
        .outcomes = &.{
            .{
                .variant = .{ .start = 0, .len = 0 },
                .variant_index = 0,
                .source = source,
                .storage_sources = &.{.{ .output_index = 0, .storage = .{ .input_index = 2, .domain_index = 3 } }},
                .outcomes = &.{.{
                    .variant = .{ .start = 0, .len = 0 },
                    .variant_index = 0,
                    .source = source,
                    .storage_sources = &.{.{ .output_index = 0, .storage = .{ .input_index = 4 } }},
                }},
            },
            .{ .variant = .{ .start = 0, .len = 0 }, .variant_index = 1, .source = source },
        },
    });
    const output = contract.outputs[0];
    try std.testing.expectEqual(@as(usize, 1), output.storage_sources.len);
    const selected = output.outcomes[0].value.*;
    try std.testing.expectEqual(@as(usize, 2), selected.storage_sources.len);
    const nested = selected.outcomes[0].value.*;
    try std.testing.expectEqual(@as(usize, 3), nested.storage_sources.len);
    try std.testing.expect(covers(nested.storage_sources, .{ .input_index = 1 }));
    try std.testing.expect(covers(nested.storage_sources, .{ .input_index = 2, .storage_domain = 3 }));
    try std.testing.expect(covers(nested.storage_sources, .{ .input_index = 4 }));
    try std.testing.expectEqual(@as(usize, 1), output.outcomes[1].value.storage_sources.len);

    const hidden = facts.ValueEffect{ .opaque_storage_dependencies = &.{.{ .input_index = 2, .storage_domain = 3 }} };
    try std.testing.expect(check(contract, .{ .outputs = &.{.{ .variants = &.{.{ .index = 0, .value = &hidden }} }} }) == null);
    try std.testing.expectEqual(.undeclared_dependency, check(contract, .{
        .outputs = &.{.{ .variants = &.{.{ .index = 1, .value = &hidden }} }},
    }).?.kind);
}

test "conditional opaque empty guarantees are checked per selected exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const storage = facts.InputPath{ .input_index = 1 };
    const contract = try fromDeclaration(arena.allocator(), .{
        .output_count = 1,
        .source = source,
        .outcomes = &.{.{
            .variant = .{ .start = 0, .len = 0 },
            .variant_index = 1,
            .source = source,
            .emptied_inputs = &.{.{ .input_index = 1 }},
        }},
    });
    const exits = [_]facts.OutcomePostStates{
        .{ .variant_index = 0, .input_post_states = &.{} },
        .{ .variant_index = 1, .input_post_states = &.{}, .opaque_storage_empties = &.{storage} },
    };
    try std.testing.expect(check(contract, .{ .outputs = &.{.{}}, .outcome_post_states = &exits }) == null);
    const missing = [_]facts.OutcomePostStates{
        .{ .variant_index = 0, .input_post_states = &.{} },
        .{ .variant_index = 1, .input_post_states = &.{} },
    };
    try std.testing.expectEqual(.missing_empty_storage, check(contract, .{ .outputs = &.{.{}}, .outcome_post_states = &missing }).?.kind);
    const wrong = [_]facts.OutcomePostStates{
        .{ .variant_index = 0, .input_post_states = &.{}, .opaque_storage_empties = &.{storage} },
        exits[1],
    };
    try std.testing.expectEqual(.unsupported_opaque_effect, check(contract, .{ .outputs = &.{.{}}, .outcome_post_states = &wrong }).?.kind);
    const unreachable_exits = [_]facts.OutcomePostStates{.{ .variant_index = 1, .reachable = false, .input_post_states = &.{} }};
    try std.testing.expect(check(contract, .{ .outputs = &.{.{}}, .outcome_post_states = &unreachable_exits }) == null);
}

test "joint safety contracts require one complete conditional proof" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const choices = @import("choice_conditions.zig");
    const input = try choices.normalize(allocator, &.{.{ .subject = .entry_input, .index = 0, .variant_index = 1 }});
    const output = try choices.normalize(allocator, &.{.{ .subject = .output, .index = 0, .variant_index = 2 }});
    const joint = try choices.conjoin(allocator, input, output);
    const empty_storage = [_]facts.InputPath{.{ .input_index = 1 }};
    const effects: Contract = .{ .outputs = &.{}, .emptied_inputs = &empty_storage };
    const required = [_]Contract.Guarded{.{ .conditions = joint, .effects = &effects }};
    const empty: facts.SafetySummary = .{};
    const emptied: facts.SafetySummary = .{ .opaque_storage_empties = &empty_storage };
    const correct: facts.SafetySummary = .{ .guarded_effects = &.{.{ .conditions = joint, .effects = &emptied }} };
    try std.testing.expect(checkGuardedRelations(&required, correct) == null);
    try std.testing.expect(check(.{ .outputs = &.{}, .guarded_effects = &required }, correct) == null);
    try std.testing.expectEqual(Failure.Kind.missing_choice_relation, check(.{ .outputs = &.{}, .guarded_effects = &required }, empty).?.kind);
    try std.testing.expectEqual(Failure.Kind.missing_choice_relation, checkGuardedRelations(&required, empty).?.kind);
    const unrelated: facts.SafetySummary = .{ .guarded_effects = &.{
        .{ .conditions = input, .effects = &empty },
        .{ .conditions = output, .effects = &empty },
    } };
    try std.testing.expect(checkGuardedRelations(&required, unrelated) != null);
    // A guarantee already established under an input condition remains true
    // when an output condition is also selected.
    const weaker: facts.SafetySummary = .{ .guarded_effects = &.{.{ .conditions = input, .effects = &emptied }} };
    try std.testing.expect(checkGuardedRelations(&required, weaker) == null);
    const stronger = try choices.conjoin(allocator, joint, try choices.normalize(allocator, &.{.{ .subject = .output, .index = 1, .variant_index = 3 }}));
    const partial: facts.SafetySummary = .{ .guarded_effects = &.{.{ .conditions = stronger, .effects = &emptied }} };
    try std.testing.expect(checkGuardedRelations(&required, partial) != null);
    try std.testing.expect(checkGuardedRelations(&required, emptied) == null);
}

test "guarded conformance reports violations and ignores contradictory selectors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const choices = @import("choice_conditions.zig");
    const guard = try choices.normalize(allocator, &.{.{ .subject = .output, .index = 0, .variant_index = 1 }});
    const effects: Contract = .{ .outputs = &.{}, .consumed_inputs = &.{.{ .input_index = 0 }} };
    const empty: facts.SafetySummary = .{};
    const invalid: facts.SafetySummary = .{ .guarded_effects = &.{.{ .conditions = guard, .effects = &empty }} };
    const required = [_]Contract.Guarded{.{ .conditions = guard, .effects = &effects }};
    const failure = checkGuardedRelations(&required, invalid).?;
    try std.testing.expectEqual(Failure.Kind.missing_consumption, failure.kind);
    try std.testing.expect(failure.conditions.?.eql(guard));
    try std.testing.expect(checkGuardedRelations(&.{.{ .conditions = .{ .impossible = true }, .effects = &effects }}, empty) == null);
}

test "joint guards distinguish effect permissions from resource guarantees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const choices = @import("choice_conditions.zig");
    const condition = try choices.normalize(allocator, &.{
        .{ .subject = .entry_input, .index = 0, .variant_index = 1 },
        .{ .subject = .output, .index = 1, .variant_index = 2 },
    });
    const effects: Contract = .{
        .outputs = &.{.{ .dependencies = &.{.{ .input_index = 0 }} }},
        .invalidates = &.{.{ .input_index = 1 }},
    };
    const permitted: facts.SafetySummary = .{
        .outputs = &.{.{ .input_dependencies = &.{.{ .path = .{ .input_index = 0 } }} }},
        .input_post_states = &.{.{ .target = .{ .input_index = 1 }, .initializedness = .initialized, .refreshes_storage_generation = true }},
    };
    const required = [_]Contract.Guarded{.{ .conditions = condition, .effects = &effects }};
    var summary: facts.SafetySummary = .{ .outputs = &.{.{}}, .guarded_effects = &.{.{ .conditions = condition, .effects = &permitted }} };
    try std.testing.expect(checkGuardedRelations(&required, summary) == null);
    var bad = permitted;
    bad.outputs = &.{.{ .input_dependencies = &.{.{ .path = .{ .input_index = 3 } }} }};
    // Both unconditional and selected facts contain the undeclared dependency;
    // no complete sound approximation can establish the contract.
    summary.outputs = bad.outputs;
    summary.guarded_effects = &.{.{ .conditions = condition, .effects = &bad }};
    try std.testing.expectEqual(Failure.Kind.undeclared_dependency, checkGuardedRelations(&required, summary).?.kind);
    var consumes = effects;
    consumes.consumed_inputs = &.{.{ .input_index = 1 }};
    try std.testing.expectEqual(Failure.Kind.missing_consumption, checkGuardedRelations(&.{.{ .conditions = condition, .effects = &consumes }}, summary).?.kind);
}

test "legacy contracts convert payload permissions and authoritative input guarantees together" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const declared = try fromDeclaration(allocator, .{
        .output_count = 1,
        .source = source,
        .dependencies = &.{.{ .output_index = 0, .input_index = 1 }},
        .outcomes = &.{.{
            .variant = .{ .start = 0, .len = 0 },
            .variant_index = 0,
            .emptied_inputs = &.{.{ .input_index = 0 }},
            .source = source,
        }},
    });
    const converted = try withOutcomeGuards(allocator, declared);
    try std.testing.expectEqual(@as(usize, 1), converted.guarded_effects.len);
    const effects = converted.guarded_effects[0].effects;
    try std.testing.expectEqual(@as(usize, 1), effects.outputs.len);
    try std.testing.expectEqual(@as(u32, 1), effects.outputs[0].dependencies[0].input_index);
    try std.testing.expectEqual(@as(u32, 0), effects.emptied_inputs[0].input_index);
    try std.testing.expectEqual(@as(usize, 0), converted.emptied_inputs.len);
}

test "unreachable legacy output guards establish vacuous joint guarantees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const conditions = try @import("choice_conditions.zig").normalize(allocator, &.{
        .{ .subject = .entry_input, .index = 0, .variant_index = 1 },
        .{ .subject = .output, .index = 1, .projections = &.{.{ .variant = 2 }}, .variant_index = 3 },
    });
    const guarantee: Contract = .{ .outputs = &.{}, .emptied_inputs = &.{.{ .input_index = 0 }} };
    const summary: facts.SafetySummary = .{ .outcome_post_states = &.{.{ .reachable = false, .output_index = 1, .parent_variants = &.{2}, .variant_index = 3, .input_post_states = &.{} }} };
    try std.testing.expect(checkGuardedRelations(&.{.{ .conditions = conditions, .effects = &guarantee }}, summary) == null);
    var reachable = summary;
    reachable.outcome_post_states = &.{.{ .output_index = 1, .parent_variants = &.{2}, .variant_index = 3, .input_post_states = &.{} }};
    try std.testing.expect(checkGuardedRelations(&.{.{ .conditions = conditions, .effects = &guarantee }}, reachable) != null);
}

test "outcome conversion partitions nested contracts at leaves and retains enclosing guarantees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const declared = try fromDeclaration(allocator, .{
        .output_count = 1,
        .source = source,
        .outcomes = &.{.{
            .variant = .{ .start = 0, .len = 0 },
            .variant_index = 0,
            .emptied_inputs = &.{.{ .input_index = 0 }},
            .source = source,
            .outcomes = &.{
                .{ .variant = .{ .start = 0, .len = 0 }, .variant_index = 0, .source = source, .consumed_inputs = &.{1} },
                .{ .variant = .{ .start = 0, .len = 0 }, .variant_index = 1, .source = source },
            },
        }},
    });
    const converted = try withOutcomeGuards(allocator, declared);
    try std.testing.expectEqual(@as(usize, 2), converted.guarded_effects.len);
    for (converted.guarded_effects) |guarded| {
        try std.testing.expectEqual(@as(usize, 2), guarded.conditions.terms.len);
        try std.testing.expectEqual(@as(u32, 0), guarded.effects.emptied_inputs[0].input_index);
    }
    try std.testing.expectEqual(@as(usize, 1), converted.guarded_effects[0].effects.consumed_inputs.len);
    try std.testing.expectEqual(@as(usize, 0), converted.guarded_effects[1].effects.consumed_inputs.len);
}

test "general conformance cannot mistake sparse promises for complete return coverage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const condition = try @import("choice_conditions.zig").normalize(allocator, &.{.{ .subject = .output, .index = 0, .variant_index = 1 }});
    const allowed: Contract = .{ .outputs = &.{.{ .dependencies = &.{.{ .input_index = 0 }} }} };
    const precise: facts.SafetySummary = .{ .outputs = &.{.{ .input_dependencies = &.{.{ .path = .{ .input_index = 0 } }} }} };
    const contract: Contract = .{ .general_conditions = true, .outputs = &.{.{}}, .guarded_effects = &.{.{ .conditions = condition, .effects = &allowed }} };
    var summary: facts.SafetySummary = .{
        .outputs = &.{.{ .input_dependencies = &.{.{ .path = .{ .input_index = 1 } }} }},
        .guarded_effects = &.{.{ .conditions = condition, .effects = &precise }},
    };
    try std.testing.expectEqual(Failure.Kind.undeclared_dependency, check(contract, summary).?.kind);
    // Exhaustive body inference can validate the selected regions directly.
    summary.guarded_returns_complete = true;
    try std.testing.expect(check(contract, summary) == null);
}

test "inherited general contract transitions apply once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const common: Contract = .{
        .outputs = &.{.{}},
        .consumed_inputs = &.{.{ .input_index = 0 }},
        .relocations = &.{.{ .source = .{ .input_index = 1 }, .destination = .{ .input_index = 2 } }},
        .retained_inputs = &.{.{ .storage = .{ .input_index = 3 }, .input = .{ .input_index = 4 } }},
    };
    const merged = try mergeContracts(allocator, common, common);
    try std.testing.expectEqual(@as(usize, 1), merged.consumed_inputs.len);
    try std.testing.expectEqual(@as(usize, 1), merged.relocations.len);
    try std.testing.expectEqual(@as(usize, 1), merged.retained_inputs.len);
}

test "consumption permits emptying owned storage without borrowed or retention effects" {
    const input: facts.InputPath = .{ .input_index = 0 };
    const storage: facts.InputPath = .{ .input_index = 0, .projections = &.{.{ .field = 0 }} };
    const consumed: facts.PlacePostState = .{ .target = input, .initializedness = .deinitialized, .ends_previous_roots = true };
    const contract: Contract = .{ .outputs = &.{}, .consumed_inputs = &.{input} };
    try std.testing.expect(check(contract, .{ .input_post_states = &.{consumed}, .opaque_storage_empties = &.{storage} }) == null);
    try std.testing.expectEqual(.missing_consumption, check(contract, .{ .opaque_storage_empties = &.{storage} }).?.kind);
    const external = [_]facts.InputPath{
        .{ .input_index = 0, .projections = &.{ .{ .field = 0 }, .dereference } },
        .{ .input_index = 1, .projections = &.{.{ .field = 0 }} },
        .{ .input_index = 0, .storage_domain = 0 },
    };
    for (external) |path| try std.testing.expectEqual(.unsupported_opaque_effect, check(contract, .{ .input_post_states = &.{consumed}, .opaque_storage_empties = &.{path} }).?.kind);
    try std.testing.expectEqual(.unsupported_opaque_effect, check(contract, .{ .input_post_states = &.{consumed}, .opaque_storage_effects = &.{.{ .storage = storage, .hidden_dependencies = .{} }} }).?.kind);
}

test "selected consumption only permits owned storage empties on that outcome" {
    const input: facts.InputPath = .{ .input_index = 0 };
    const storage: facts.InputPath = .{ .input_index = 0, .projections = &.{.{ .field = 0 }} };
    const consumed: facts.PlacePostState = .{ .target = input, .initializedness = .deinitialized, .ends_previous_roots = true };
    const selected: Contract = .{ .outputs = &.{.{}}, .consumed_inputs = &.{input} };
    const contract: Contract = .{ .outputs = &.{.{}}, .outcomes = &.{.{ .output_index = 0, .variant_index = 1, .effects = &selected }} };
    var summary: facts.SafetySummary = .{ .outputs = &.{.{}}, .outcome_post_states = &.{.{ .output_index = 0, .variant_index = 1, .input_post_states = &.{consumed}, .opaque_storage_empties = &.{storage} }} };
    try std.testing.expect(check(contract, summary) == null);
    summary.outcome_post_states = &.{
        .{ .output_index = 0, .variant_index = 1, .input_post_states = &.{consumed}, .opaque_storage_empties = &.{storage} },
        .{ .output_index = 0, .variant_index = 0, .input_post_states = &.{}, .opaque_storage_empties = &.{storage} },
    };
    try std.testing.expectEqual(.unsupported_opaque_effect, check(contract, summary).?.kind);
}

test "static contract checks preserve guarantees while callers retain alias obligations" {
    const path = facts.InputPath{ .input_index = 0 };
    const contract: Contract = .{ .outputs = &.{} };
    const summary: facts.SafetySummary = .{ .outputs = &.{}, .storage_observation_conflicts = &.{.{ .consumed = path, .observed = .{ .input_index = 1 } }} };
    try std.testing.expect(checkStatic(contract, summary) == null);
    try std.testing.expectEqual(.unsupported_alias_obligation, check(contract, summary).?.kind);
    var effectful = summary;
    effectful.storage_capability_uses = &.{.{ .target = path }};
    try std.testing.expectEqual(.unsupported_capability_effect, checkStatic(contract, effectful).?.kind);
    try std.testing.expectEqual(@as(usize, 1), summary.storage_observation_conflicts.len);
}

test "guarded contracts read normalized output partitions without derived summary copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const conditions = try @import("choice_conditions.zig").normalize(a, &.{
        .{ .subject = .entry_input, .index = 0, .variant_index = 1 },
        .{ .subject = .output, .index = 1, .projections = &.{.{ .variant = 2 }}, .variant_index = 3 },
    });
    const required_effects: Contract = .{ .outputs = &.{}, .consumed_inputs = &.{.{ .input_index = 4 }} };
    const required = [_]Contract.Guarded{.{ .conditions = conditions, .effects = &required_effects }};
    var partitions = [_]facts.OutcomePostStates{.{ .output_index = 1, .parent_variants = &.{2}, .variant_index = 3, .input_post_states = &.{.{ .target = .{ .input_index = 4 }, .initializedness = .deinitialized, .ends_previous_roots = true }} }};
    const summary: facts.SafetySummary = .{ .outcome_post_states = &partitions };
    try std.testing.expectEqual(@as(usize, 0), summary.guarded_effects.len);
    try std.testing.expect(checkGuardedRelations(&required, summary) == null);
    partitions[0].input_post_states = &.{};
    try std.testing.expectEqual(Failure.Kind.missing_consumption, checkGuardedRelations(&required, summary).?.kind);
    partitions[0].reachable = false;
    try std.testing.expect(checkGuardedRelations(&required, summary) == null);
}

test "independent output partitions cannot prove a joint consumption guarantee" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const conditions = try @import("choice_conditions.zig").normalize(arena.allocator(), &.{
        .{ .subject = .output, .index = 0, .variant_index = 1 },
        .{ .subject = .output, .index = 1, .variant_index = 1 },
    });
    const required_effects: Contract = .{ .outputs = &.{}, .consumed_inputs = &.{ .{ .input_index = 0 }, .{ .input_index = 1 } } };
    const summary: facts.SafetySummary = .{ .outcome_post_states = &.{
        .{ .output_index = 0, .variant_index = 1, .input_post_states = &.{.{ .target = .{ .input_index = 0 }, .initializedness = .deinitialized, .ends_previous_roots = true }} },
        .{ .output_index = 1, .variant_index = 1, .input_post_states = &.{.{ .target = .{ .input_index = 1 }, .initializedness = .deinitialized, .ends_previous_roots = true }} },
    } };
    try std.testing.expect(checkGuardedRelations(&.{.{ .conditions = conditions, .effects = &required_effects }}, summary) != null);
}

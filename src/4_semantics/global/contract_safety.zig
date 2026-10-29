//! Declaration-level safety validation shared by static and virtual evidence.
const std = @import("std");
const global_sg = @import("graph.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");

const Resolver = @import("contracts.zig").Resolver;
const LocatedContractDefinition = Resolver.LocatedContractDefinition;
fn opaqueStorageTransitionConflict(contract: anytype, storage: primitives.MethodSafetyContract.StorageInput) bool {
    for (contract.consumed_inputs) |input| if (input == storage.input_index) return true;
    for (contract.invalidates) |input| if (input == storage.input_index) return true;
    for (contract.invalidated_domains) |domain| if (domain.input_index == storage.input_index and (storage.domain_index == null or storage.domain_index.? == domain.domain_index)) return true;
    for (contract.relocations) |relocation| if (relocation.source == storage.input_index or relocation.destination == storage.input_index) return true;
    for (contract.outcomes) |outcome| if (opaqueStorageTransitionConflict(outcome, storage)) return true;
    return false;
}

fn conditionalOpaqueEmptyConflict(contract: primitives.MethodSafetyContract, outcomes: []const primitives.MethodSafetyContract.Outcome) bool {
    for (outcomes) |outcome| {
        for (outcome.emptied_inputs) |storage| if (opaqueStorageTransitionConflict(contract, storage)) return true;
        if (conditionalOpaqueEmptyConflict(contract, outcome.outcomes)) return true;
    }
    return false;
}

// Exact identity clauses apply to the complete output, including its payloads.
// Conditional provenance cannot weaken an enclosing identity guarantee.
fn outcomeHasStorageSource(outcomes: []const primitives.MethodSafetyContract.Outcome, output_index: u32) bool {
    for (outcomes) |outcome| {
        for (outcome.storage_sources) |source| if (source.output_index == output_index) return true;
        if (outcomeHasStorageSource(outcome.outcomes, output_index)) return true;
    }
    return false;
}

// Outcome clauses inherit enclosing guarantees and add their own. Compare every descendant
// before flattening: independent outputs cannot select a shared resource state.
fn relocationInheritanceFailure(contract: primitives.MethodSafetyContract) ?[]const u8 {
    for (contract.outcomes) |outcome| {
        if (relocationDescendantFailure(contract, outcome)) |reason| return reason;
        const child = primitives.MethodSafetyContract{
            .output_count = contract.output_count,
            .relocations = outcome.relocations,
            .consumed_inputs = outcome.consumed_inputs,
            .invalidates = outcome.invalidates,
            .outcomes = outcome.outcomes,
            .source = outcome.source,
        };
        if (relocationInheritanceFailure(child)) |reason| return reason;
        for (contract.outcomes) |other| {
            if (outcome.output_index == other.output_index) {
                if (relocationAlternativesOverlap(outcome, other)) return "alternative relocates clauses sharing an input must describe the same source and destination";
                continue;
            }
            if (relocationAcrossOutputs(outcome, other)) return "relocation effects on shared inputs across outputs require correlated result facts";
        }
    }
    return null;
}

fn relocationDescendantFailure(parent: primitives.MethodSafetyContract, child: primitives.MethodSafetyContract.Outcome) ?[]const u8 {
    for (parent.relocations) |relocation| {
        for (child.consumed_inputs) |input| if (input == relocation.source or input == relocation.destination) return "relocates and consumes cannot target the same input";
        for (child.invalidates) |input| if (input == relocation.source or input == relocation.destination) return "relocates already defines its source and destination generations";
        for (child.relocations) |nested| if (nested.source == relocation.source or nested.source == relocation.destination or nested.destination == relocation.source or nested.destination == relocation.destination) return "inherited relocates clauses cannot share source or destination inputs";
    }
    for (child.relocations) |relocation| {
        for (parent.consumed_inputs) |input| if (input == relocation.source or input == relocation.destination) return "relocates and consumes cannot target the same input";
        for (parent.invalidates) |input| if (input == relocation.source or input == relocation.destination) return "relocates already defines its source and destination generations";
    }
    for (child.outcomes) |nested| if (relocationDescendantFailure(parent, nested)) |reason| return reason;
    return null;
}

fn relocationAcrossOutputs(a: primitives.MethodSafetyContract.Outcome, b: primitives.MethodSafetyContract.Outcome) bool {
    for (a.relocations) |relocation| if (relocationConflictsWithOutcome(relocation, b, true)) return true;
    for (a.outcomes) |child| if (relocationAcrossOutputs(child, b)) return true;
    return false;
}

fn relocationAlternativesOverlap(a: primitives.MethodSafetyContract.Outcome, b: primitives.MethodSafetyContract.Outcome) bool {
    for (a.relocations) |relocation| if (relocationConflictsWithOutcome(relocation, b, false)) return true;
    for (a.outcomes) |child| if (relocationAlternativesOverlap(child, b)) return true;
    return false;
}

fn relocationConflictsWithOutcome(relocation: primitives.MethodSafetyContract.Relocation, outcome: primitives.MethodSafetyContract.Outcome, independent_output: bool) bool {
    for (outcome.relocations) |other| {
        if (!independent_output and relocation.source == other.source and relocation.destination == other.destination) continue;
        if (relocation.source == other.source or relocation.source == other.destination or relocation.destination == other.source or relocation.destination == other.destination) return true;
    }
    if (independent_output) {
        for (outcome.consumed_inputs) |input| if (input == relocation.source or input == relocation.destination) return true;
        for (outcome.invalidates) |input| if (input == relocation.source or input == relocation.destination) return true;
    }
    for (outcome.outcomes) |child| if (relocationConflictsWithOutcome(relocation, child, independent_output)) return true;
    return false;
}

fn outcomeSafetyContractFailure(self: *Resolver, inputs: global_sg.FieldRange, choice_ty: global_sg.GlobalTypeId, output_type: global_sg.GlobalTypeId, contract_ty: global_sg.GlobalTypeId, located: LocatedContractDefinition, outcome: primitives.MethodSafetyContract.Outcome, erased_participant: bool) anyerror!?[]const u8 {
    if (global_types.variants(self.graph, choice_ty) == null) return "on requires a choice-valued output payload";
    const name = self.modules[located.module_index].text(outcome.variant);
    const hit = global_types.findVariant(self.graph, choice_ty, name) orelse return "outcome contract names an unknown output variant";
    if (try methodSafetyContractFailure(self, inputs, .{ .start = 0, .len = 0 }, output_type, contract_ty, located, .{
        .output_count = 0,
        .dependencies = outcome.dependencies,
        .storage_sources = outcome.storage_sources,
        .emptied_inputs = outcome.emptied_inputs,
        .consumed_inputs = outcome.consumed_inputs,
        .relocations = outcome.relocations,
        .domain_dependencies = outcome.domain_dependencies,
        .invalidates = outcome.invalidates,
        .invalidated_domains = outcome.invalidated_domains,
        .source = outcome.source,
    }, erased_participant)) |message| return message;
    for (outcome.outcomes, 0..) |child, index| {
        if (child.output_index != outcome.output_index) return "nested on must follow the selected output payload";
        const payload = hit.variant.payload_type orelse return "nested on requires a choice-valued output payload";
        if (try outcomeSafetyContractFailure(self, inputs, payload, output_type, contract_ty, located, child, erased_participant)) |message| return message;
        for (outcome.outcomes[0..index]) |previous| if (std.mem.eql(u8, self.modules[located.module_index].text(previous.variant), self.modules[located.module_index].text(child.variant))) return "duplicate outcome contract";
    }
    return null;
}

fn generalOutcomeClauseFailure(self: *Resolver, inputs: global_sg.FieldRange, outputs: global_sg.FieldRange, output_type: global_sg.GlobalTypeId, contract_ty: global_sg.GlobalTypeId, located: LocatedContractDefinition, outcome: primitives.MethodSafetyContract.Outcome, erased_participant: bool) anyerror!?[]const u8 {
    // Cleanup transitions need exact caller owner identities, beyond a
    // conjunction of payload provenance permissions.
    if (outcome.consumed_inputs.len != 0 or outcome.relocations.len != 0)
        return "joint choice conditions cannot conditionally consume or relocate owners; use a single output choice for the ownership transition";
    if (outcome.input_index) |input| {
        if (input >= inputs.len) return "choice condition names an unknown input";
    } else if (outcome.output_index >= outputs.len) return "choice condition names an unknown output";
    if (try methodSafetyContractFailure(self, inputs, outputs, output_type, contract_ty, located, .{
        .output_count = outputs.len,
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
    }, erased_participant)) |message| return message;
    for (outcome.outcomes) |child| if (try generalOutcomeClauseFailure(self, inputs, outputs, output_type, contract_ty, located, child, erased_participant)) |message| return message;
    return null;
}

fn opaqueStorageInputFailure(self: *Resolver, inputs: global_sg.FieldRange, contract_ty: global_sg.GlobalTypeId, storage: primitives.MethodSafetyContract.StorageInput, mutable: bool, erased_participant: bool, domain_count: usize) ?[]const u8 {
    const ty = self.graph.semanticType(self.graph.fields.items[inputs.start + storage.input_index].ty);
    if (ty != .pointer) return "opaque storage clauses require a reference to a known storage input";
    if (mutable and ty.pointer.mutability != .read_write) return "retains and empties require mutable storage references";
    if (storage.domain_index) |domain| {
        if (domain >= domain_count) return "unknown Contract storage domain";
        if (!global_types.equal(self.graph, ty.pointer.child, contract_ty)) return "opaque storage domains must be rooted at the participant receiver";
        return null;
    }
    if (erased_participant and global_types.equal(self.graph, ty.pointer.child, contract_ty)) return "opaque storage clauses on an erased participant require mapped hidden storage identities; select a participant domain or use a known storage input";
    return null;
}

pub fn methodSafetyContractFailure(self: *Resolver, inputs: global_sg.FieldRange, outputs: global_sg.FieldRange, output_type: global_sg.GlobalTypeId, contract_ty: global_sg.GlobalTypeId, located: LocatedContractDefinition, contract: primitives.MethodSafetyContract, erased_participant: bool) !?[]const u8 {
    if (relocationInheritanceFailure(contract)) |message| return message;
    for (contract.transfers) |transfer| if (outcomeHasStorageSource(contract.outcomes, transfer.output_index)) return "from_storage cannot be combined with exact transfers for the same output";
    for (contract.referents) |referent| if (outcomeHasStorageSource(contract.outcomes, referent.output_index)) return "from_storage cannot be combined with exact refers_to for the same output";
    if (conditionalOpaqueEmptyConflict(contract, contract.outcomes)) return "opaque storage clauses cannot overlap generation replacement, consumption or relocation";
    for (contract.retained_inputs, 0..) |retained, retained_index| {
        if (opaqueStorageInputFailure(self, inputs, contract_ty, retained.storage, true, erased_participant, located.definition.domains.len)) |message| return message;
        if (self.graph.semanticType(self.graph.fields.items[inputs.start + retained.input].ty) == .pointer) return "retains currently requires a value input; wrap borrowed references in a value instead of moving through a reference input";
        for (contract.retained_inputs[0..retained_index]) |other| if (other.input == retained.input) return "a retained value input requires one storage identity";
        for (contract.transfers) |transfer| if (transfer.input_index == retained.input) return "retains cannot also promise an exact output transfer of the same input";
        for (contract.emptied_inputs) |empty| if (std.meta.eql(empty, retained.storage)) return "retains and empties cannot target the same storage";
        if (opaqueStorageTransitionConflict(contract, retained.storage)) return "opaque storage clauses cannot overlap generation replacement, consumption or relocation";
    }
    for (contract.emptied_inputs) |empty| {
        if (opaqueStorageInputFailure(self, inputs, contract_ty, empty, true, erased_participant, located.definition.domains.len)) |message| return message;
        if (opaqueStorageTransitionConflict(contract, empty)) return "opaque storage clauses cannot overlap generation replacement, consumption or relocation";
    }
    for (contract.storage_sources) |source| {
        if (opaqueStorageInputFailure(self, inputs, contract_ty, source.storage, false, erased_participant, located.definition.domains.len)) |message| return message;
        for (contract.transfers) |transfer| if (transfer.output_index == source.output_index) return "from_storage cannot be combined with exact transfers for the same output";
        for (contract.referents) |referent| if (referent.output_index == source.output_index) return "from_storage cannot be combined with exact refers_to for the same output";
    }
    var reason: ?[]const u8 = null;
    for (contract.outcomes, 0..) |outcome, outcome_index| {
        if (contract.general_conditions) {
            if (try generalOutcomeClauseFailure(self, inputs, outputs, output_type, contract_ty, located, outcome, erased_participant)) |message| return message;
            continue;
        }
        if (outcome.output_index >= outputs.len) return "outcome contract names an unknown output";
        const output_ty = self.graph.fields.items[outputs.start + outcome.output_index].ty;
        if (try outcomeSafetyContractFailure(self, inputs, output_ty, output_type, contract_ty, located, outcome, erased_participant)) |message| return message;
        const outcome_name = self.modules[located.module_index].text(outcome.variant);
        for (contract.outcomes[0..outcome_index]) |previous| {
            if (previous.output_index == outcome.output_index and std.mem.eql(u8, self.modules[located.module_index].text(previous.variant), outcome_name)) return "duplicate outcome contract";
        }
    }
    for (contract.dependencies) |dependency| {
        if (dependency.input_index >= inputs.len) {
            reason = "dependency names an unknown input";
            break;
        }
    }
    for (contract.transfers) |transfer| {
        const input_ty = self.graph.semanticType(self.graph.fields.items[inputs.start + transfer.input_index].ty);
        if (input_ty == .pointer) {
            reason = "transfers requires a by-value owning input; references do not transfer ownership";
            break;
        }
        if (!global_types.equal(self.graph, self.graph.fields.items[inputs.start + transfer.input_index].ty, self.graph.fields.items[outputs.start + transfer.output_index].ty)) {
            reason = "transfers requires matching input and output value types";
            break;
        }
        for (contract.owned_outputs) |owned| if (owned == transfer.output_index) {
            reason = "fresh and transferred ownership require separate outcome contracts";
            break;
        };
    }

    for (contract.domain_dependencies) |dependency| {
        if (dependency.input.domain_index >= located.definition.domains.len) {
            reason = "unknown Contract storage domain";
            break;
        }
        const input_ty = self.graph.semanticType(self.graph.fields.items[inputs.start + dependency.input.input_index].ty);
        if (input_ty != .pointer or !global_types.equal(self.graph, input_ty.pointer.child, contract_ty)) {
            reason = "Contract storage domains must be rooted at the participant receiver";
            break;
        }
    }
    for (contract.invalidated_domains) |domain| {
        if (domain.domain_index >= located.definition.domains.len) {
            reason = "unknown Contract storage domain";
            break;
        }
        const input_ty = self.graph.semanticType(self.graph.fields.items[inputs.start + domain.input_index].ty);
        if (input_ty != .pointer or !global_types.equal(self.graph, input_ty.pointer.child, contract_ty) or input_ty.pointer.mutability != .read_write) {
            reason = "invalidating a Contract storage domain requires a mutable participant receiver";
            break;
        }
    }
    for (contract.relocations) |relocation| {
        const destination = self.graph.semanticType(self.graph.fields.items[inputs.start + relocation.destination].ty);
        const source = self.graph.semanticType(self.graph.fields.items[inputs.start + relocation.source].ty);
        if (destination != .pointer or source != .pointer or destination.pointer.mutability != .read_write or source.pointer.mutability != .read_write) return "relocates requires mutable reference source and destination inputs";
        if (!global_types.equal(self.graph, destination.pointer.child, source.pointer.child)) return "relocates requires matching source and destination value types";
        if (erased_participant and global_types.equal(self.graph, destination.pointer.child, contract_ty)) return "relocates on an erased participant requires receiver cleanup identities; use known resource inputs";
        for (contract.consumed_inputs) |consumed| if (consumed == relocation.destination or consumed == relocation.source) return "relocates and consumes cannot target the same input";
        for (contract.invalidates) |invalidated| if (invalidated == relocation.destination or invalidated == relocation.source) return "relocates already defines its source and destination generations";
    }
    for (contract.consumed_inputs) |input_index| {
        const input_ty = self.graph.semanticType(self.graph.fields.items[inputs.start + input_index].ty);
        if (input_ty != .pointer or input_ty.pointer.mutability != .read_write) {
            reason = "consumes requires a mutable reference input; by-value inputs already transfer their local ownership";
            break;
        }
        if (erased_participant and global_types.equal(self.graph, input_ty.pointer.child, contract_ty)) {
            reason = "consumes on an erased participant requires receiver cleanup identities; name a known resource input instead";
            break;
        }
    }
    for (contract.invalidates) |input_index| {
        if (outputs.len != 0) {
            reason = "invalidates with outputs requires post-invalidation result contracts; use a no-result method for now";
            break;
        }
        const input_ty = self.graph.semanticType(self.graph.fields.items[inputs.start + input_index].ty);
        if (input_ty != .pointer or input_ty.pointer.mutability != .read_write) {
            reason = "invalidates requires a mutable reference input";
            break;
        }
        if (erased_participant and global_types.equal(self.graph, input_ty.pointer.child, contract_ty)) {
            reason = "invalidating an erased receiver requires a mapped storage domain; name a known reference input instead";
            break;
        }
        const child = self.graph.semanticType(input_ty.pointer.child);
        if (child != .builtin) {
            reason = "invalidates currently requires scalar referent storage; aggregate domains need explicit mappings";
            break;
        }
        switch (child.builtin) {
            .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64, .Bool => {},
            else => {
                reason = "invalidates currently requires scalar referent storage; aggregate domains need explicit mappings";
                break;
            },
        }
    }
    for (contract.referents) |referent| {
        const input_ty = self.graph.semanticType(self.graph.fields.items[inputs.start + referent.input_index].ty);
        const output_ty = self.graph.semanticType(self.graph.fields.items[outputs.start + referent.output_index].ty);
        if (input_ty != .pointer or output_ty != .pointer) {
            reason = "refers_to requires a reference output and a reference input";
            break;
        }
        if (erased_participant and global_types.equal(self.graph, input_ty.pointer.child, contract_ty)) {
            reason = "refers_to cannot expose erased participant storage; name a known reference input instead";
            break;
        }
        if (!global_types.equal(self.graph, input_ty.pointer.child, output_ty.pointer.child)) {
            reason = "refers_to requires matching input and output referent types";
            break;
        }
        if (input_ty.pointer.mutability == .read_only and output_ty.pointer.mutability == .read_write) {
            reason = "refers_to cannot grant mutable access from a read-only input";
            break;
        }
    }
    for (self.graph.fields.items[outputs.start..][0..outputs.len], 0..) |field, index| {
        var preserves_identity = false;
        for (contract.transfers) |transfer| if (transfer.output_index == index) {
            preserves_identity = true;
            break;
        };
        for (contract.referents) |referent| if (referent.output_index == index) {
            preserves_identity = true;
            break;
        };
        if (!preserves_identity and try containsMappedVirtual(self, field.ty)) {
            reason = "returning mapped Virtual storage requires transfers or refers_to to preserve its domain identities";
            break;
        }
    }
    return reason;
}

fn containsMappedVirtual(self: *Resolver, ty: global_sg.GlobalTypeId) !bool {
    var visited = std.AutoHashMap(global_sg.GlobalTypeId, void).init(self.allocator);
    defer visited.deinit();
    return containsMappedVirtualVisited(self, ty, &visited);
}

fn containsMappedVirtualVisited(self: *Resolver, ty: global_sg.GlobalTypeId, visited: *std.AutoHashMap(global_sg.GlobalTypeId, void)) anyerror!bool {
    if (visited.contains(ty)) return false;
    try visited.put(ty, {});
    switch (self.graph.semanticType(ty)) {
        .virtual => |contract_ty| {
            const use = self.contractUse(contract_ty) orelse return false;
            const located = self.findContractDefinition(use.declaration) orelse return false;
            return located.definition.domains.len != 0;
        },
        .pointer => |pointer| return containsMappedVirtualVisited(self, pointer.child, visited),
        .array => |array| return containsMappedVirtualVisited(self, array.element, visited),
        else => {},
    }
    if (global_types.fields(self.graph, ty)) |fields| {
        for (self.graph.fields.items[fields.start..][0..fields.len]) |field| {
            if (try containsMappedVirtualVisited(self, field.ty, visited)) return true;
        }
    }
    if (global_types.variants(self.graph, ty)) |variants| {
        for (self.graph.variants.items[variants.start..][0..variants.len]) |variant| {
            if (variant.payload_type) |payload| if (try containsMappedVirtualVisited(self, payload, visited)) return true;
        }
    }
    return false;
}

pub fn containsErasedParticipant(self: *Resolver, ty: global_sg.GlobalTypeId, erased: global_sg.GlobalTypeId) !bool {
    var visited = std.AutoHashMap(global_sg.GlobalTypeId, void).init(self.allocator);
    defer visited.deinit();
    return containsErasedParticipantVisited(self, ty, erased, &visited);
}

fn containsErasedParticipantVisited(self: *Resolver, ty: global_sg.GlobalTypeId, erased: global_sg.GlobalTypeId, visited: *std.AutoHashMap(global_sg.GlobalTypeId, void)) !bool {
    if (global_types.equal(self.graph, ty, erased)) return true;
    if (visited.contains(ty)) return false;
    try visited.put(ty, {});
    switch (self.graph.semanticType(ty)) {
        .pointer => |pointer| return containsErasedParticipantVisited(self, pointer.child, erased, visited),
        .nullable, .inferred_errable => |child| return containsErasedParticipantVisited(self, child, erased, visited),
        .array => |array| return containsErasedParticipantVisited(self, array.element, erased, visited),
        .generic => |generic| {
            for (self.graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| {
                if (argument.value == .type and try containsErasedParticipantVisited(self, argument.value.type, erased, visited)) return true;
            }
        },
        // An explicit virtual handle has a fixed representation regardless
        // of the concrete implementation behind its own table.
        .virtual => return false,
        else => {},
    }
    if (global_types.fields(self.graph, ty)) |fields| {
        for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
            if (try containsErasedParticipantVisited(self, field.ty, erased, visited)) return true;
    }
    if (global_types.variants(self.graph, ty)) |variants| {
        for (self.graph.variants.items[variants.start..][0..variants.len]) |variant|
            if (variant.payload_type) |payload| if (try containsErasedParticipantVisited(self, payload, erased, visited)) return true;
    }
    return false;
}

fn globalSafetyOutcome(self: *Resolver, module_index: usize, outcome: *primitives.MethodSafetyContract.Outcome, choice_ty: global_sg.GlobalTypeId) anyerror!void {
    const name = self.modules[module_index].text(outcome.variant);
    const hit = global_types.findVariant(self.graph, choice_ty, name) orelse return error.UnknownOutcomeContractVariant;
    outcome.variant_index = hit.index;
    outcome.variant = hit.variant.name;
    outcome.source = self.sourceFor(module_index, outcome.source);
    const children = try (try self.graph.safetyAllocator(self.allocator)).dupe(primitives.MethodSafetyContract.Outcome, outcome.outcomes);
    for (children, 0..) |*child, index| {
        if (child.output_index != outcome.output_index) return error.InvalidOutcomeContract;
        try globalSafetyOutcome(self, module_index, child, hit.variant.payload_type orelse return error.InvalidOutcomeContract);
        for (children[0..index]) |previous| if (previous.variant_index == child.variant_index) return error.DuplicateOutcomeContract;
    }
    outcome.outcomes = children;
}

const SelectedContractChoice = struct {
    input_index: ?u32,
    output_index: u32,
    payload: ?global_sg.GlobalTypeId,
    variants: []const u32,
};

fn globalGeneralOutcome(self: *Resolver, module_index: usize, outcome: *primitives.MethodSafetyContract.Outcome, inputs: global_sg.FieldRange, outputs: global_sg.FieldRange, parents: []const SelectedContractChoice) anyerror!void {
    const fields = if (outcome.input_index != null) inputs else outputs;
    const index = outcome.input_index orelse outcome.output_index;
    if (index >= fields.len) return error.InvalidOutcomeContract;
    var ty = self.graph.fields.items[fields.start + index].ty;
    if (outcome.input_index != null and self.graph.semanticType(ty) == .pointer) {
        outcome.input_dereference = true;
        ty = self.graph.semanticType(ty).pointer.child;
    }
    var ancestors: []const u32 = &.{};
    var parent_index = parents.len;
    while (parent_index != 0) {
        parent_index -= 1;
        const parent = parents[parent_index];
        if (parent.input_index != outcome.input_index or parent.output_index != outcome.output_index) continue;
        ty = parent.payload orelse return error.InvalidOutcomeContract;
        ancestors = parent.variants;
        break;
    }
    const hit = global_types.findVariant(self.graph, ty, self.modules[module_index].text(outcome.variant)) orelse return error.UnknownOutcomeContractVariant;
    outcome.variant_index = hit.index;
    outcome.variant = hit.variant.name;
    outcome.parent_variants = ancestors;
    outcome.source = self.sourceFor(module_index, outcome.source);
    const selected: SelectedContractChoice = .{
        .input_index = outcome.input_index,
        .output_index = outcome.output_index,
        .payload = hit.variant.payload_type,
        .variants = try std.mem.concat(try self.graph.safetyAllocator(self.allocator), u32, &.{ ancestors, &.{hit.index} }),
    };
    const context = try std.mem.concat(try self.graph.safetyAllocator(self.allocator), SelectedContractChoice, &.{ parents, &.{selected} });
    const children = try (try self.graph.safetyAllocator(self.allocator)).dupe(primitives.MethodSafetyContract.Outcome, outcome.outcomes);
    for (children, 0..) |*child, child_index| {
        try globalGeneralOutcome(self, module_index, child, inputs, outputs, context);
        for (children[0..child_index]) |previous| if (previous.input_index == child.input_index and previous.output_index == child.output_index and previous.variant_index == child.variant_index) return error.DuplicateOutcomeContract;
    }
    outcome.outcomes = children;
}

pub fn globalSafetyContract(self: *Resolver, module_index: usize, declared: primitives.MethodSafetyContract, inputs: global_sg.FieldRange, output_type: global_sg.GlobalTypeId) !primitives.MethodSafetyContract {
    var contract = declared;
    contract.source = self.sourceFor(module_index, contract.source);
    if (declared.outcomes.len != 0) {
        const fields = global_types.fields(self.graph, output_type) orelse return error.InvalidContractRequirementOutput;
        const outcomes = try (try self.graph.safetyAllocator(self.allocator)).dupe(primitives.MethodSafetyContract.Outcome, declared.outcomes);
        for (outcomes, 0..) |*outcome, index| {
            if (declared.general_conditions) {
                try globalGeneralOutcome(self, module_index, outcome, inputs, fields, &.{});
                for (outcomes[0..index]) |previous| if (previous.input_index == outcome.input_index and previous.output_index == outcome.output_index and previous.variant_index == outcome.variant_index) return error.DuplicateOutcomeContract;
                continue;
            }
            if (outcome.output_index >= fields.len) return error.InvalidOutcomeContract;
            const output_ty = self.graph.fields.items[fields.start + outcome.output_index].ty;
            try globalSafetyOutcome(self, module_index, outcome, output_ty);
            for (outcomes[0..index]) |previous| if (previous.output_index == outcome.output_index and previous.variant_index == outcome.variant_index) return error.DuplicateOutcomeContract;
        }
        contract.outcomes = outcomes;
    }
    return contract;
}

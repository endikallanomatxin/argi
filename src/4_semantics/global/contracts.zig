const standard_contracts = @import("standard_contracts.zig");
const type_arguments = @import("../module/type_arguments.zig");
const std = @import("std");
const module_views = @import("../module/views.zig");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const parameterized_storage = @import("../module/parameterized/storage.zig");
const ir = @import("../module/parameterized/ir.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const generic_mod = @import("generics.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");
const reach_context = @import("reach_context.zig");

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

pub const Stats = struct {
    checks: u32 = 0,
    implementation_scans: u64 = 0,
    implementation_candidates: u64 = 0,
    implementation_scan_ns: u64 = 0,
};

pub const ContractUse = struct {
    declaration: global_sg.GlobalDeclId,
    arguments: primitives.Range(global_sg.GlobalGenericArgId),
};

pub const ParticipantConformanceFailure = struct {
    is_projection: bool = false,
    is_value_projection: bool = false,
    source: primitives.SourceRef,
    contract_name: []const u8,
    reason: []const u8,
    operation: ?[]const u8 = null,
    input: ?global_sg.GlobalTypeId = null,
    output: ?global_sg.GlobalTypeId = null,
};

pub const GenericTypeConstraintFailure = struct {
    generic_decl: global_sg.GlobalDeclId,
    contract_decl: global_sg.GlobalDeclId,
    actual: global_sg.GlobalTypeId,
    parameter_name: []const u8,
    source: primitives.SourceRef,
};

pub const VirtualSignatureFailure = struct {
    static_contract: bool = false,
    source: primitives.SourceRef,
    method_name: []const u8,
    reason: []const u8,
};

pub const Resolver = struct {
    pub const ResolutionCheckpoint = struct {
        participant_failure: ?ParticipantConformanceFailure,
    };
    const ConstraintKey = struct {
        module_index: u32,
        constraint: parameterized_storage.ContractConstraintId,
    };
    const ContractRefKey = struct {
        module_index: u32,
        external: module_entities.ExternalRefId,
        kind: primitives.DeclarationKind,
    };

    allocator: std.mem.Allocator,
    function_context: ?*anyopaque = null,
    instantiate_function: ?*const fn (*anyopaque, global_sg.GlobalDeclId, primitives.Range(global_sg.GlobalGenericArgId)) anyerror!global_sg.GlobalFunctionId = null,

    instantiate_alias: ?*const fn (*anyopaque, global_sg.GlobalDeclId, global_sg.GlobalTypeId) anyerror!global_sg.GlobalFunctionId = null,

    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    virtual_signature_failure: ?VirtualSignatureFailure = null,
    participant_conformance_failure: ?ParticipantConformanceFailure = null,
    stats: Stats = .{},
    profile_implementation_scans: bool = false,
    profile_io: ?std.Io = null,
    constraint_declarations: std.AutoHashMapUnmanaged(ConstraintKey, global_sg.GlobalDeclId) = .empty,
    resolved_contract_refs: std.AutoHashMapUnmanaged(ContractRefKey, global_sg.GlobalDeclId) = .empty,
    pub fn deinit(self: *Resolver) void {
        self.constraint_declarations.deinit(self.allocator);
        self.resolved_contract_refs.deinit(self.allocator);
    }

    pub fn checkpointResolution(self: *const Resolver) ResolutionCheckpoint {
        return .{ .participant_failure = self.participant_conformance_failure };
    }

    pub fn rollbackResolution(self: *Resolver, saved: ResolutionCheckpoint) void {
        self.participant_conformance_failure = saved.participant_failure;
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_call => |value| try self.resolveVirtualCall(module_index, module, o, value),
            .resolve_contract => |value| blk: {
                const declaration = globalizer.globalDecl(o, value.declaration);
                const ty = self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse break :blk .deferred;
                const contract_decl = try self.resolveExternalContract(module_index, value.contract_ref);
                break :blk resolution.Result.fromBool(try self.implements(ty, contract_decl));
            },
            else => .not_applicable,
        };
    }

    fn resolveVirtualCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        const input = globalizer.globalNode(o, value.input);
        if (std.mem.eql(u8, module.text(reference.name), "to_virtual")) {
            const node = (try self.makeVirtualize(module_index, reference, input, if (value.expected_type) |ty| globalizer.globalType(o, ty) else null)) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            return .resolved;
        }
        if (!self.ownsVirtualCall(module_index, module, reference, input)) return .not_applicable;
        const node = (try self.makeVirtualCall(
            module_index,
            reference,
            input,
            .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset },
            reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
        )) orelse return .deferred;
        self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
        return .resolved;
    }

    fn ownsVirtualCall(
        self: *const Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
    ) bool {
        if (reference.module_path != null or reference.generic_arguments != null) return false;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |item| item,
            else => return false,
        };
        const method_name = module.text(reference.name);
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |actual| {
            const actual_ty = self.graph.nodes.items[@intFromEnum(actual.value)].ty orelse continue;
            const pointee = switch (self.graph.types.items[@intFromEnum(actual_ty)]) {
                .pointer => |pointer| pointer.child,
                else => continue,
            };
            const contract_ty = switch (self.graph.types.items[@intFromEnum(pointee)]) {
                .virtual => |contract_type| contract_type,
                else => pointee,
            };
            const contract_use = self.contractUse(contract_ty) orelse continue;
            const located = self.findContractDefinition(contract_use.declaration) orelse continue;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len]) |requirement| {
                if (std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), method_name)) return true;
            }
        }
        _ = module_index;
        return false;
    }

    fn makeVirtualize(
        self: *Resolver,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        expected: ?global_sg.GlobalTypeId,
    ) !?global_sg.Node {
        const arguments = if (reference.generic_arguments) |local|
            try self.generics.relocateModuleArguments(module_index, local)
        else
            primitives.Range(global_sg.GlobalGenericArgId){ .start = 0, .len = 0 };
        return self.makeVirtualizeWithArguments(module_index, reference, input, arguments, expected);
    }

    // Instantiated function bodies already carry global generic arguments;
    // they must use the same virtual-handle establishment as source calls.
    pub fn makeVirtualizeWithArguments(
        self: *Resolver,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        expected: ?global_sg.GlobalTypeId,
    ) !?global_sg.Node {
        if (arguments.len > 1) {
            self.virtual_signature_failure = .{ .source = self.sourceFor(module_index, reference.source), .method_name = "to_virtual", .reason = "to_virtual accepts one compile-time contract argument" };
            return null;
        }
        var contract_type: ?global_sg.GlobalTypeId = null;
        for (self.graph.generic_arguments.items[arguments.start..][0..arguments.len]) |argument| {
            if (!type_arguments.isVirtualContractParameter(self.graph.text(argument.name)) and
                self.graph.text(argument.name).len != 0)
            {
                self.virtual_signature_failure = .{ .source = self.sourceFor(module_index, reference.source), .method_name = "to_virtual", .reason = "unknown virtual compile-time argument; use .contract: Contract" };
                return null;
            }
            contract_type = switch (argument.value) {
                .type => |ty| ty,
                else => return null,
            };
        }
        // Virtual conversion has an output-only comptime argument. Infer it
        // from a contextual result type, never from names or implementation
        // enumeration: a concrete type can implement several contracts.
        if (contract_type == null) if (expected) |ty| {
            contract_type = switch (self.graph.types.items[@intFromEnum(ty)]) {
                .virtual => |contract| contract,
                else => null,
            };
        };
        const contract_ty = contract_type orelse return null;
        const contract_use = self.contractUse(contract_ty) orelse return null;
        const contract_decl = contract_use.declaration;
        const located = self.findContractDefinition(contract_decl) orelse return null;
        if (located.definition.participants.len != 1 or contract_use.arguments.len != located.definition.parameters.len) {
            self.virtual_signature_failure = .{ .source = self.sourceFor(module_index, reference.source), .method_name = "to_virtual", .reason = if (located.definition.participants.len != 1) "explicit participants require joint virtual evidence, which is not supported yet" else "unary virtual evidence requires every associated element to be bound" };
            return null;
        }

        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        var value: ?global_sg.GlobalNodeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (std.mem.eql(u8, self.graph.text(field.name), "value") or
                (literal.fields.len == 1 and self.graph.text(field.name).len == 0)) value = field.value;
        }
        const handle = value orelse return null;
        const handle_ty = self.graph.nodes.items[@intFromEnum(handle)].ty orelse return null;
        const pointer = switch (self.graph.types.items[@intFromEnum(handle_ty)]) {
            .pointer => |pointer| pointer,
            else => return null,
        };
        const concrete = pointer.child;
        if (!try self.validateVirtualContract(contract_ty, located, self.sourceFor(module_index, reference.source), pointer.mutability)) return null;
        var evidence_bindings = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
        defer evidence_bindings.deinit(self.allocator);
        const evidence = try self.selectConformance(contract_decl, &.{concrete}, &evidence_bindings, 0, null) orelse {
            self.virtual_signature_failure = .{ .source = self.sourceFor(module_index, reference.source), .method_name = "to_virtual", .reason = "the concrete type has no selected conformance for this contract" };
            return null;
        };
        if (!try self.associatedArgumentsMatch(located, &evidence_bindings, contract_use.arguments)) {
            self.virtual_signature_failure = .{ .source = self.sourceFor(module_index, reference.source), .method_name = "to_virtual", .reason = "selected conformance has incompatible associated elements for the virtual interface" };
            return null;
        }

        var methods: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
        defer methods.deinit(self.allocator);
        var receiver_indices: std.ArrayList(u32) = .empty;
        defer receiver_indices.deinit(self.allocator);
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, method_index| {
            const instance = (try self.requirementInstanceForContractUse(contract_use, concrete, located, requirement, @intCast(method_index))) orelse return null;
            // A virtual table freezes the selected evidence. Scoped operations
            // never re-enter global overload lookup when a type is erased.
            const implementation = try self.resolveOperationBinding(self.graph.contract_conformances.items[evidence.tuple], method_index);
            if (self.fallibleOutput(instance.output)) try self.core.ensureErrorTracerInput(implementation);
            try methods.append(self.allocator, implementation);
            const erased = (try self.requirementInstanceForContractUse(contract_use, contract_ty, located, requirement, @intCast(method_index))) orelse return null;
            const fields = global_types.fields(self.graph, erased.input) orelse return error.InvalidContractRequirementInput;
            for (self.graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
                const ty = self.graph.semanticType(field.ty);
                if (ty == .pointer and global_types.equal(self.graph, ty.pointer.child, contract_ty)) {
                    try receiver_indices.append(self.allocator, @intCast(index));
                    break;
                }
            }
        }
        const method_start: u32 = @intCast(self.graph.function_refs.items.len);
        try self.graph.function_refs.appendSlice(self.allocator, methods.items);
        const safety_start: u32 = @intCast(self.graph.virtual_registry_refs.items.len);
        for (methods.items, 0..) |_, index| {
            const registry: global_sg.GlobalVirtualRegistryId = @enumFromInt(@as(u32, @intCast(self.graph.virtual_registries.items.len)));
            try self.graph.virtual_registries.append(self.allocator, .{
                .implementations = .{ .start = method_start + @as(u32, @intCast(index)), .len = 1 },
                .receiver_input_index = receiver_indices.items[index],
            });
            try self.graph.virtual_registry_refs.append(self.allocator, registry);
        }
        const virtual_ty = try self.generics.internType(.{ .virtual = contract_ty });
        const domains = (try self.resolveStorageDomains(contract_use, concrete, located, self.sourceFor(module_index, reference.source))) orelse return null;
        const virtualize: global_sg.GlobalVirtualizeId = @enumFromInt(@as(u32, @intCast(self.graph.virtualizes.items.len)));
        try self.graph.virtualizes.append(self.allocator, .{
            .value = handle,
            .concrete_type = concrete,
            .contract_decl = contract_decl,
            .virtual_type = virtual_ty,
            .methods = .{ .start = method_start, .len = @intCast(methods.items.len) },
            .safety_methods = .{ .start = safety_start, .len = @intCast(methods.items.len) },
            .source = self.sourceFor(module_index, reference.source),
            .domains = domains,
        });
        return .{
            .source = self.sourceFor(module_index, reference.source),
            .ty = virtual_ty,
            .content = .{ .virtualize = virtualize },
        };
    }

    const MethodSelection = union(enum) {
        missing,
        ambiguous,
        incompatible_output,
        function: global_sg.GlobalFunctionId,
    };

    fn resolveStorageDomains(self: *Resolver, use: ContractUse, concrete: global_sg.GlobalTypeId, located: LocatedContractDefinition, source: primitives.SourceRef) !?[]const primitives.StorageDomainMapping {
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        if (try self.selectConformance(use.declaration, &.{concrete}, &bindings, 0, null)) |selection| {
            if (try self.associatedArgumentsMatch(located, &bindings, use.arguments)) {
                const evidence = self.graph.contract_conformances.items[selection.tuple];
                const owner: usize = @intFromEnum(evidence.context);
                for (self.modules[owner].semantic.parameterized_storage.contract_conformances.items) |template| {
                    if (std.meta.eql(self.sourceFor(owner, template.source), evidence.source))
                        return self.resolveDomainPaths(owner, template.domains, concrete, located, source);
                }
            }
        }
        if (located.definition.domains.len == 0) return &.{};
        return self.domainFailure(source, "storage domains require an explicit implementation mapping for this contract");
    }

    fn domainFailure(self: *Resolver, source: primitives.SourceRef, message: []const u8) ?[]const primitives.StorageDomainMapping {
        self.virtual_signature_failure = .{ .source = source, .method_name = "to_virtual", .reason = message };
        return null;
    }

    fn resolveDomainPaths(self: *Resolver, module_index: usize, mappings: []const parameterized_storage.DomainMapping, concrete: global_sg.GlobalTypeId, located: LocatedContractDefinition, source: primitives.SourceRef) !?[]const primitives.StorageDomainMapping {
        if (mappings.len != located.definition.domains.len) return self.domainFailure(source, "every Contract storage domain requires exactly one implementation mapping");
        var result: std.ArrayList(primitives.StorageDomainMapping) = .empty;
        defer result.deinit(self.allocator);
        for (mappings) |mapping| {
            var domain_index: ?u32 = null;
            for (located.definition.domains, 0..) |domain, index| {
                if (std.mem.eql(u8, self.modules[module_index].text(mapping.name), self.modules[located.module_index].text(domain))) domain_index = @intCast(index);
            }
            const index = domain_index orelse return self.domainFailure(source, "implementation mapping names an unknown Contract storage domain");
            for (result.items) |existing| if (existing.domain_index == index) return self.domainFailure(source, "duplicate implementation storage domain mapping");
            var paths: std.ArrayList(primitives.StorageDomainMapping.Path) = .empty;
            defer paths.deinit(self.allocator);
            for (mapping.paths) |path| {
                var ty = concrete;
                var fields: std.ArrayList(u32) = .empty;
                defer fields.deinit(self.allocator);
                for (path.fields) |name| {
                    if (self.graph.semanticType(ty) == .pointer) ty = self.graph.semanticType(ty).pointer.child;
                    const field_name = self.modules[module_index].text(name);
                    if (std.mem.startsWith(u8, field_name, "_")) {
                        const nominal = switch (self.graph.semanticType(ty)) {
                            .declared => |declaration| declaration,
                            .generic => |identity| identity.base,
                            else => null,
                        };
                        if (nominal) |declaration| if (self.graph.moduleForDeclaration(declaration)) |owner| {
                            if (@intFromEnum(owner) != module_index and !(self.modules[module_index].is_bundled_core and self.graph.modules.items[@intFromEnum(owner)].is_bundled_core))
                                return self.domainFailure(source, "storage domain mappings cannot access private fields of another module");
                        };
                    }
                    const range = global_types.fields(self.graph, ty) orelse return self.domainFailure(source, "storage domain paths must select concrete record fields");
                    var selected: ?u32 = null;
                    for (self.graph.fields.items[range.start..][0..range.len], 0..) |field, field_index| {
                        if (std.mem.eql(u8, self.graph.text(field.name), self.modules[module_index].text(name))) {
                            selected = @intCast(field_index);
                            ty = field.ty;
                            break;
                        }
                    }
                    try fields.append(self.allocator, selected orelse return self.domainFailure(source, "storage domain mapping selects an unknown concrete field"));
                }
                try paths.append(self.allocator, .{ .fields = try fields.toOwnedSlice(self.allocator) });
            }
            try result.append(self.allocator, .{ .domain_index = index, .paths = try paths.toOwnedSlice(self.allocator) });
        }
        var symbolic: std.ArrayList(@import("../safety/domains.zig").Mapping) = .empty;
        defer symbolic.deinit(self.allocator);
        for (result.items) |mapping| {
            const paths = try self.allocator.alloc(@import("../safety/safety_facts.zig").InputPath, mapping.paths.len);
            for (mapping.paths, paths) |path, *resolved| {
                const projections = try self.allocator.alloc(@import("../safety/place.zig").Projection, path.fields.len);
                for (path.fields, projections) |field, *projection| projection.* = .{ .field = field };
                resolved.* = .{ .input_index = 0, .projections = projections };
            }
            try symbolic.append(self.allocator, .{ .domain = @enumFromInt(mapping.domain_index), .paths = paths });
        }
        if (@import("../safety/domains.zig").validate(symbolic.items, 0) != null) return self.domainFailure(source, "implementation storage domains overlap or have an invalid mapping");
        return try result.toOwnedSlice(self.allocator);
    }

    fn inputFieldsSatisfyRequirement(
        self: *const Resolver,
        required: global_sg.FieldRange,
        implementation: global_sg.FieldRange,
    ) bool {
        if (implementation.len < required.len) return false;
        for (0..required.len) |index| {
            const expected = self.graph.fields.items[required.start + @as(u32, @intCast(index))];
            const actual = self.graph.fields.items[implementation.start + @as(u32, @intCast(index))];
            if (!global_types.equal(self.graph, expected.ty, actual.ty)) return false;
        }
        // Implementations may expose additional optional/reached parameters:
        // callers satisfying the contract must still be able to invoke
        // the function using only the requirement's inputs.
        for (required.len..implementation.len) |index| {
            const extra = self.graph.fields.items[implementation.start + @as(u32, @intCast(index))];
            if (extra.default_value == null) return false;
        }
        return true;
    }

    pub fn resolveNestedCall(
        self: *Resolver,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
        reach: reach_context.Context,
    ) anyerror!?global_sg.Node {
        return self.makeVirtualCall(module_index, reference, input, source, reach);
    }

    pub fn contractDeclarationForType(self: *const Resolver, ty: global_sg.GlobalTypeId) ?global_sg.GlobalDeclId {
        return self.contractDeclFromType(ty);
    }

    pub fn concreteImplements(self: *Resolver, concrete: global_sg.GlobalTypeId, contract_type: global_sg.GlobalTypeId) bool {
        const declaration = switch (self.graph.types.items[@intFromEnum(contract_type)]) {
            .declared => |value| value,
            else => return false,
        };
        if (self.findContractDefinition(declaration) == null) return false;
        return self.implements(concrete, declaration) catch false;
    }

    fn associatedArgumentsMatch(self: *Resolver, located: LocatedContractDefinition, bindings: *const generic_mod.Resolver.Bindings, expected: primitives.Range(global_sg.GlobalGenericArgId)) !bool {
        if (expected.len != located.definition.parameters.len) return false;
        if (expected.len == 0) return true;
        var wanted = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
        defer wanted.deinit(self.allocator);
        self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, expected, &wanted) catch return false;
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        for (located.definition.parameters.start..located.definition.parameters.start + located.definition.parameters.len) |raw| {
            switch (storage.comptime_parameters.items[raw].kind) {
                .type => {
                    const actual = bindings.types[raw] orelse return false;
                    if (!global_types.equal(self.graph, actual, wanted.types[raw].?)) return false;
                },
                .comptime_int => if ((bindings.ints[raw] orelse return false) != wanted.ints[raw].?) return false,
            }
        }
        return true;
    }

    pub fn materializeFieldAccessTypes(self: *Resolver) !bool {
        var changed = false;
        // Access nodes keep the effective runtime representation in their
        // type. This is what lets later reach traversal and codegen stay
        // entirely static once the backing implementer is known.
        for (self.graph.nodes.items) |*node| {
            const access = switch (node.content) {
                .struct_field_access => |value| value,
                else => continue,
            };
            const base_ty = self.graph.node(access.value).ty orelse continue;
            const struct_ty = switch (self.graph.types.items[@intFromEnum(base_ty)]) {
                .pointer => |pointer| pointer.child,
                else => base_ty,
            };
            const fields = global_types.fields(self.graph, struct_ty) orelse continue;
            if (access.field_index >= fields.len) return error.InvalidContractFieldIndex;
            const effective = (self.graph.fields.items[fields.start + access.field_index]).ty;
            if (node.ty == null or !global_types.equal(self.graph, node.ty.?, effective)) {
                node.ty = effective;
                changed = true;
            }
        }
        return changed;
    }

    fn fallibleOutput(self: *const Resolver, output: global_sg.GlobalTypeId) bool {
        const fields = global_types.fields(self.graph, output) orelse return false;
        if (fields.len != 1) return false;
        const result = self.graph.fields.items[fields.start].ty;
        const error_variant = global_types.findVariant(self.graph, result, "error") orelse return false;
        const payload = error_variant.variant.payload_type orelse return false;
        return global_types.findField(self.graph, payload, "tracer") != null;
    }

    // A fallible virtual slot needs a uniform capability input, including for
    // implementations that return only success. This prevents a late reached
    // dependency from changing the concrete function's ABI behind its vtable.
    fn virtualInputType(self: *Resolver, input: global_sg.GlobalTypeId, output: global_sg.GlobalTypeId) !global_sg.GlobalTypeId {
        if (!self.fallibleOutput(output) or global_types.findField(self.graph, input, "error_tracer") != null) return input;
        const field = self.core.errorTracerField() orelse return input;
        const fields = global_types.fields(self.graph, input) orelse return input;
        const copied = try self.allocator.dupe(global_sg.Field, self.graph.fields.items[fields.start..][0..fields.len]);
        defer self.allocator.free(copied);
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.allocator, copied);
        try self.graph.fields.append(self.allocator, field);
        return self.generics.internType(.{ .structural = .{ .fields = .{ .start = start, .len = fields.len + 1 } } });
    }

    fn makeVirtualCall(
        self: *Resolver,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
        reach: reach_context.Context,
    ) !?global_sg.Node {
        if (reference.module_path != null or reference.generic_arguments != null) return null;
        return self.makeVirtualOperationCall(self.modules[module_index].text(reference.name), null, input, source, reach, null);
    }

    fn makeVirtualOperationCall(
        self: *Resolver,
        method_name: []const u8,
        contract: ?global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
        reach: reach_context.Context,
        expected_associations: ?primitives.Range(global_sg.GlobalGenericArgId),
    ) !?global_sg.Node {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |item| item,
            else => return null,
        };
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |actual| {
            const actual_ty = self.graph.nodes.items[@intFromEnum(actual.value)].ty orelse continue;
            const pointee = switch (self.graph.types.items[@intFromEnum(actual_ty)]) {
                .pointer => |pointer| pointer.child,
                else => continue,
            };
            const contract_ty = switch (self.graph.types.items[@intFromEnum(pointee)]) {
                .virtual => |contract_type| contract_type,
                else => pointee,
            };
            const contract_use = self.contractUse(contract_ty) orelse continue;
            if (contract) |declaration| if (declaration != contract_use.declaration) continue;
            const located = self.findContractDefinition(contract_use.declaration) orelse continue;
            if (expected_associations) |expected| {
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                if (!self.bindContractUseArguments(contract_use, located, &bindings) or !try self.associatedArgumentsMatch(located, &bindings, expected)) {
                    self.participant_conformance_failure = .{
                        .source = source,
                        .contract_name = self.modules[located.module_index].text(self.modules[located.module_index].declarations.items[@intFromEnum(located.definition.declaration)].name),
                        .operation = method_name,
                        .reason = "virtual receiver has incompatible associated elements for the operation interface",
                    };
                    return null;
                }
            }
            if (!try self.validateVirtualContract(contract_ty, located, source, null)) return null;
            const parameterized_forms_storage = &self.modules[located.module_index].semantic.parameterized_storage;
            for (parameterized_forms_storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, method_index| {
                if (!std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), method_name)) continue;
                const instance = (try self.requirementInstanceForContractUse(
                    contract_use,
                    contract_ty,
                    located,
                    requirement,
                    @intCast(method_index),
                )) orelse continue;
                const input_ty = try self.virtualInputType(instance.input, instance.output);
                const output_ty = instance.output;
                const input_fields = global_types.fields(self.graph, input_ty) orelse continue;
                const output_fields = global_types.fields(self.graph, output_ty) orelse continue;
                switch (try self.core.matchCallInputWithReach(input_fields, input, reach)) {
                    .score => {},
                    else => continue,
                }
                if (!try self.core.completeCallInputFieldsWithReach(input_fields, input, reach)) continue;

                var self_index: ?u32 = null;
                var permission: primitives.PointerMutability = .read_only;
                for (0..input_fields.len) |field_index| {
                    const field = self.graph.fields.items[input_fields.start + @as(u32, @intCast(field_index))];
                    switch (self.graph.types.items[@intFromEnum(field.ty)]) {
                        .pointer => |pointer| if (global_types.equal(self.graph, pointer.child, contract_ty)) {
                            self_index = @intCast(field_index);
                            permission = pointer.mutability;
                            break;
                        },
                        else => {},
                    }
                }
                const index = self_index orelse continue;
                const completed = self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal;
                const handle = self.graph.value_fields.items[completed.fields.start + index].value;
                const registry: global_sg.GlobalVirtualRegistryId = @enumFromInt(@as(u32, @intCast(self.graph.virtual_registries.items.len)));
                try self.graph.virtual_registries.append(self.allocator, .{ .implementations = .{ .start = @intCast(self.graph.function_refs.items.len), .len = 0 }, .receiver_input_index = index });
                const call_id: global_sg.GlobalVirtualCallId = @enumFromInt(@as(u32, @intCast(self.graph.virtual_calls.items.len)));
                try self.graph.virtual_calls.append(self.allocator, .{
                    .handle = handle,
                    .input = input,
                    .self_input_index = index,
                    .method_index = @intCast(method_index),
                    .method_count = located.definition.requirements.len,
                    .method_name = try self.graph.addString(self.allocator, method_name),
                    .input_type = input_ty,
                    .output_type = output_ty,
                    .self_permission = permission,
                    .safety_methods = registry,
                });
                return .{
                    .source = source,
                    .ty = try self.core.outputTypeForFields(output_fields),
                    .content = .{ .virtual_call = call_id },
                };
            }
        }
        return null;
    }

    const LocatedContractDefinition = struct {
        module_index: usize,
        definition: parameterized_storage.ContractDefinition,
    };

    const RequirementInstance = struct {
        declaration: global_sg.GlobalDeclId,
        method_index: u32,
        input: global_sg.GlobalTypeId,
        output: global_sg.GlobalTypeId,
    };

    fn bindContractUseArguments(
        self: *Resolver,
        contract_use: ContractUse,
        located: LocatedContractDefinition,
        bindings: *generic_mod.Resolver.Bindings,
    ) bool {
        if (located.definition.participants.len != 1) return false;
        if (contract_use.arguments.len != located.definition.parameters.len) return false;
        self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, contract_use.arguments, bindings) catch return false;
        return true;
    }

    fn validateVirtualContract(self: *Resolver, contract_ty: global_sg.GlobalTypeId, located: LocatedContractDefinition, source: primitives.SourceRef, conversion_permission: ?primitives.PointerMutability) !bool {
        const module = &self.modules[located.module_index];
        const storage = &module.semantic.parameterized_storage;
        for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, index| {
            const name = module.text(requirement.name);
            var reason: ?[]const u8 = null;
            // Bind the handle's associated arguments before erasing its participant.
            const contract_use = self.contractUse(contract_ty) orelse return false;
            const instance = (try self.requirementInstanceForContractUse(contract_use, contract_ty, located, requirement, @intCast(index))) orelse {
                self.virtual_signature_failure = .{ .source = source, .method_name = name, .reason = "virtual associated parameters must be fully bound" };
                return false;
            };
            const inputs = global_types.fields(self.graph, instance.input) orelse return error.InvalidContractRequirementInput;
            const outputs = global_types.fields(self.graph, instance.output) orelse return error.InvalidContractRequirementOutput;
            var receivers: usize = 0;
            for (self.graph.fields.items[inputs.start..][0..inputs.len]) |field| {
                const ty = self.graph.semanticType(field.ty);
                if (ty == .pointer and global_types.equal(self.graph, ty.pointer.child, contract_ty)) {
                    receivers += 1;
                    if (conversion_permission == .read_only and ty.pointer.mutability == .read_write)
                        reason = "a mutable participant receiver requires a mutable concrete reference ($&T) at conversion";
                } else if (try self.containsErasedParticipant(field.ty, contract_ty)) {
                    reason = "the hidden participant is only allowed as a direct borrowed receiver (&T or $&T)";
                }
            }
            if (reason == null and receivers != 1)
                reason = "a virtual operation requires exactly one borrowed participant receiver; runtime multiple dispatch is not supported";
            for (self.graph.fields.items[outputs.start..][0..outputs.len]) |field| {
                if (try self.containsErasedParticipant(field.ty, contract_ty))
                    reason = "the hidden participant cannot appear in a virtual operation result; return a known type or an explicit virtual handle";
            }
            if (reason == null) if (requirement.safety_contract) |contract| {
                reason = try self.methodSafetyContractFailure(inputs, outputs, instance.output, contract_ty, located, contract, true);
            };
            if (reason == null and requirement.safety_contract == null)
                reason = "virtual methods require a declared safety contract; use where {} for preservation or declare output dependencies and storage effects";
            if (reason) |message| {
                self.virtual_signature_failure = .{ .source = source, .method_name = name, .reason = message };
                return false;
            }
        }
        return true;
    }

    fn outcomeSafetyContractFailure(self: *Resolver, inputs: global_sg.FieldRange, choice_ty: global_sg.GlobalTypeId, output_type: global_sg.GlobalTypeId, contract_ty: global_sg.GlobalTypeId, located: LocatedContractDefinition, outcome: primitives.MethodSafetyContract.Outcome, erased_participant: bool) anyerror!?[]const u8 {
        if (global_types.variants(self.graph, choice_ty) == null) return "on requires a choice-valued output payload";
        const name = self.modules[located.module_index].text(outcome.variant);
        const hit = global_types.findVariant(self.graph, choice_ty, name) orelse return "outcome contract names an unknown output variant";
        if (try self.methodSafetyContractFailure(inputs, .{ .start = 0, .len = 0 }, output_type, contract_ty, located, .{
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
            if (try self.outcomeSafetyContractFailure(inputs, payload, output_type, contract_ty, located, child, erased_participant)) |message| return message;
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
        if (try self.methodSafetyContractFailure(inputs, outputs, output_type, contract_ty, located, .{
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
        for (outcome.outcomes) |child| if (try self.generalOutcomeClauseFailure(inputs, outputs, output_type, contract_ty, located, child, erased_participant)) |message| return message;
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

    fn methodSafetyContractFailure(self: *Resolver, inputs: global_sg.FieldRange, outputs: global_sg.FieldRange, output_type: global_sg.GlobalTypeId, contract_ty: global_sg.GlobalTypeId, located: LocatedContractDefinition, contract: primitives.MethodSafetyContract, erased_participant: bool) !?[]const u8 {
        if (relocationInheritanceFailure(contract)) |message| return message;
        for (contract.transfers) |transfer| if (outcomeHasStorageSource(contract.outcomes, transfer.output_index)) return "from_storage cannot be combined with exact transfers for the same output";
        for (contract.referents) |referent| if (outcomeHasStorageSource(contract.outcomes, referent.output_index)) return "from_storage cannot be combined with exact refers_to for the same output";
        if (conditionalOpaqueEmptyConflict(contract, contract.outcomes)) return "opaque storage clauses cannot overlap generation replacement, consumption or relocation";
        for (contract.retained_inputs, 0..) |retained, retained_index| {
            if (self.opaqueStorageInputFailure(inputs, contract_ty, retained.storage, true, erased_participant, located.definition.domains.len)) |message| return message;
            if (self.graph.semanticType(self.graph.fields.items[inputs.start + retained.input].ty) == .pointer) return "retains currently requires a value input; wrap borrowed references in a value instead of moving through a reference input";
            for (contract.retained_inputs[0..retained_index]) |other| if (other.input == retained.input) return "a retained value input requires one storage identity";
            for (contract.transfers) |transfer| if (transfer.input_index == retained.input) return "retains cannot also promise an exact output transfer of the same input";
            for (contract.emptied_inputs) |empty| if (std.meta.eql(empty, retained.storage)) return "retains and empties cannot target the same storage";
            if (opaqueStorageTransitionConflict(contract, retained.storage)) return "opaque storage clauses cannot overlap generation replacement, consumption or relocation";
        }
        for (contract.emptied_inputs) |empty| {
            if (self.opaqueStorageInputFailure(inputs, contract_ty, empty, true, erased_participant, located.definition.domains.len)) |message| return message;
            if (opaqueStorageTransitionConflict(contract, empty)) return "opaque storage clauses cannot overlap generation replacement, consumption or relocation";
        }
        for (contract.storage_sources) |source| {
            if (self.opaqueStorageInputFailure(inputs, contract_ty, source.storage, false, erased_participant, located.definition.domains.len)) |message| return message;
            for (contract.transfers) |transfer| if (transfer.output_index == source.output_index) return "from_storage cannot be combined with exact transfers for the same output";
            for (contract.referents) |referent| if (referent.output_index == source.output_index) return "from_storage cannot be combined with exact refers_to for the same output";
        }
        var reason: ?[]const u8 = null;
        for (contract.outcomes, 0..) |outcome, outcome_index| {
            if (contract.general_conditions) {
                if (try self.generalOutcomeClauseFailure(inputs, outputs, output_type, contract_ty, located, outcome, erased_participant)) |message| return message;
                continue;
            }
            if (outcome.output_index >= outputs.len) return "outcome contract names an unknown output";
            const output_ty = self.graph.fields.items[outputs.start + outcome.output_index].ty;
            if (try self.outcomeSafetyContractFailure(inputs, output_ty, output_type, contract_ty, located, outcome, erased_participant)) |message| return message;
            const outcome_name = self.modules[located.module_index].text(outcome.variant);
            for (contract.outcomes[0..outcome_index]) |previous| {
                if (previous.output_index == outcome.output_index and std.mem.eql(u8, self.modules[located.module_index].text(previous.variant), outcome_name)) return "duplicate outcome contract";
            }
        }
        for (contract.dependencies) |dependency| {
            if (dependency.input_index >= inputs.len and !(dependency.input_index == inputs.len and self.fallibleOutput(output_type))) {
                reason = "error_tracer is only implicit for fallible contract operations";
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
                .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64, .Char, .Bool => {},
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
            if (!preserves_identity and try self.containsMappedVirtual(field.ty)) {
                reason = "returning mapped Virtual storage requires transfers or refers_to to preserve its domain identities";
                break;
            }
        }
        return reason;
    }

    fn containsMappedVirtual(self: *Resolver, ty: global_sg.GlobalTypeId) !bool {
        var visited = std.AutoHashMap(global_sg.GlobalTypeId, void).init(self.allocator);
        defer visited.deinit();
        return self.containsMappedVirtualVisited(ty, &visited);
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
            .pointer => |pointer| return self.containsMappedVirtualVisited(pointer.child, visited),
            .array => |array| return self.containsMappedVirtualVisited(array.element, visited),
            else => {},
        }
        if (global_types.fields(self.graph, ty)) |fields| {
            for (self.graph.fields.items[fields.start..][0..fields.len]) |field| {
                if (try self.containsMappedVirtualVisited(field.ty, visited)) return true;
            }
        }
        if (global_types.variants(self.graph, ty)) |variants| {
            for (self.graph.variants.items[variants.start..][0..variants.len]) |variant| {
                if (variant.payload_type) |payload| if (try self.containsMappedVirtualVisited(payload, visited)) return true;
            }
        }
        return false;
    }

    fn containsErasedParticipant(self: *Resolver, ty: global_sg.GlobalTypeId, erased: global_sg.GlobalTypeId) !bool {
        var visited = std.AutoHashMap(global_sg.GlobalTypeId, void).init(self.allocator);
        defer visited.deinit();
        return self.containsErasedParticipantVisited(ty, erased, &visited);
    }

    fn containsErasedParticipantVisited(self: *Resolver, ty: global_sg.GlobalTypeId, erased: global_sg.GlobalTypeId, visited: *std.AutoHashMap(global_sg.GlobalTypeId, void)) !bool {
        if (global_types.equal(self.graph, ty, erased)) return true;
        if (visited.contains(ty)) return false;
        try visited.put(ty, {});
        switch (self.graph.semanticType(ty)) {
            .pointer => |pointer| return self.containsErasedParticipantVisited(pointer.child, erased, visited),
            .nullable, .inferred_errable => |child| return self.containsErasedParticipantVisited(child, erased, visited),
            .array => |array| return self.containsErasedParticipantVisited(array.element, erased, visited),
            .generic => |generic| {
                for (self.graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| {
                    if (argument.value == .type and try self.containsErasedParticipantVisited(argument.value.type, erased, visited)) return true;
                }
            },
            // An explicit virtual handle has a fixed representation regardless
            // of the concrete implementation behind its own table.
            .virtual => return false,
            else => {},
        }
        if (global_types.fields(self.graph, ty)) |fields| {
            for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
                if (try self.containsErasedParticipantVisited(field.ty, erased, visited)) return true;
        }
        if (global_types.variants(self.graph, ty)) |variants| {
            for (self.graph.variants.items[variants.start..][0..variants.len]) |variant|
                if (variant.payload_type) |payload| if (try self.containsErasedParticipantVisited(payload, erased, visited)) return true;
        }
        return false;
    }

    fn requirementInstanceForContractUse(
        self: *Resolver,
        contract_use: ContractUse,
        self_type: global_sg.GlobalTypeId,
        located: LocatedContractDefinition,
        requirement: parameterized_storage.ContractRequirement,
        method_index: u32,
    ) !?RequirementInstance {
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        if (!self.bindContractUseArguments(contract_use, located, &bindings)) return null;
        // The unary participant is hidden by this handle; its fixed signature
        // uses the erased receiver identity.
        if (located.definition.participants.len != 1) return null;
        bindings.types[located.definition.participants.start] = self_type;
        return .{
            .declaration = contract_use.declaration,
            .method_index = method_index,
            .input = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings),
            .output = try self.generics.instantiateParameterizedType(located.module_index, requirement.output, &bindings),
        };
    }

    fn findContractDefinition(self: *const Resolver, declaration: global_sg.GlobalDeclId) ?LocatedContractDefinition {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return null;
        const module_index: usize = @intFromEnum(owner);
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.parameterized_storage.contract_definitions.items) |definition|
            if (definition.declaration == local) return .{ .module_index = module_index, .definition = definition };
        return null;
    }

    const ConformanceSelection = struct { tuple: usize };

    /// Source forms differ only while matching candidates. A selected conformance
    /// binds every participant and associated element as ordinary parameters.
    fn selectConformance(self: *Resolver, declaration: global_sg.GlobalDeclId, participants: []const global_sg.GlobalTypeId, bindings: ?*generic_mod.Resolver.Bindings, depth: u8, deferred: ?*bool) anyerror!?ConformanceSelection {
        const scan_start = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        defer if (self.profile_io) |io| {
            self.stats.implementation_scan_ns += @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - scan_start);
        };
        if (self.profile_implementation_scans) self.stats.implementation_scans += 1;
        if (depth >= 64) return null;
        const located = self.findContractDefinition(declaration) orelse return null;
        if (participants.len != located.definition.participants.len) return null;
        for (self.graph.contract_conformances.items, 0..) |conformance, index| {
            if (conformance.declaration != declaration) continue;
            if (self.profile_implementation_scans) self.stats.implementation_candidates += 1;
            var equal = true;
            for (participants, 0..) |actual, position| {
                const expected = self.graph.generic_arguments.items[conformance.participants.start + position].value.type;
                if (!self.typeSelectionReady(expected, 0)) {
                    if (deferred) |flag| flag.* = true;
                    equal = false;
                    break;
                }
                if (!global_types.equal(self.graph, actual, expected)) {
                    equal = false;
                    break;
                }
            }
            if (!equal) continue;
            if (bindings) |target| {
                try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, conformance.participants, target);
                try self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, conformance.associated_arguments, target);
            }
            return .{ .tuple = index };
        }
        return self.selectGenericParticipantConformance(declaration, participants, bindings);
    }

    /// This conservative query only restricts implicit copying. An unknown
    /// provider never establishes conformance or selects an operation.
    pub fn mayImplementFirstParticipant(self: *Resolver, name: []const u8, concrete: global_sg.GlobalTypeId) anyerror!bool {
        for (self.graph.contract_conformances.items) |conformance| {
            if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(conformance.declaration)].name), name)) continue;
            if (conformance.participants.len == 0) continue;
            const first = self.graph.generic_arguments.items[conformance.participants.start].value;
            if (first == .type and global_types.equal(self.graph, first.type, concrete)) return true;
        }
        for (self.modules, 0..) |*module, module_index| {
            const storage = &module.semantic.parameterized_storage;
            for (storage.contract_conformances.items) |template| {
                if (template.participants.len == 0) continue;
                const declaration = try self.resolveDeclarationRef(module_index, template.contract_ref, .contract_type);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                const first = storage.ir.generic_arguments.items[template.participants.start].value;
                if (first != .type or !try self.inferConstraintTypePattern(module_index, first.type, concrete, &bindings)) continue;
                var matches = true;
                for (template.parameters.start..template.parameters.start + template.parameters.len) |raw| {
                    const parameter = storage.comptime_parameters.items[raw];
                    const constraint_id = parameter.constraint orelse continue;
                    const bound = bindings.types[raw] orelse continue;
                    const constraint = storage.contract_constraints.items[@intFromEnum(constraint_id)];
                    // Constraints mentioning unknown participants remain possible.
                    if (constraint.arguments.len != 0) {
                        _ = self.generics.instantiateParameterizedArguments(module_index, constraint.arguments, &bindings) catch |err| switch (err) {
                            error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => continue,
                            else => return err,
                        };
                    }
                    if (!try self.inferConstraintBindings(module_index, constraint_id, bound, &bindings)) {
                        matches = false;
                        break;
                    }
                }
                if (matches) return true;
            }
        }
        return false;
    }

    fn selectGenericParticipantConformance(self: *Resolver, declaration: global_sg.GlobalDeclId, participants: []const global_sg.GlobalTypeId, target: ?*generic_mod.Resolver.Bindings) anyerror!?ConformanceSelection {
        const located = self.findContractDefinition(declaration) orelse return null;
        const Candidate = struct { module: usize, template: parameterized_storage.ContractConformance, bindings: generic_mod.Resolver.Bindings };
        var candidates: std.ArrayList(Candidate) = .empty;
        defer {
            for (candidates.items) |*candidate| candidate.bindings.deinit(self.allocator);
            candidates.deinit(self.allocator);
        }
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.contract_conformances.items) |template| {
                if (template.parameters.len == 0 or template.participants.len != participants.len) continue;
                if (try self.resolveDeclarationRef(module_index, template.contract_ref, .contract_type) != declaration) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
                var keep = false;
                defer if (!keep) bindings.deinit(self.allocator);
                var matches = true;
                for (module.semantic.parameterized_storage.ir.generic_arguments.items[template.participants.start..][0..template.participants.len], participants) |pattern, actual| {
                    if (pattern.value != .type or !try self.inferConstraintTypePattern(module_index, pattern.value.type, actual, &bindings)) {
                        matches = false;
                        break;
                    }
                }
                if (!matches or !try self.validateParameterizedImplementationConstraints(module_index, template.parameters, &bindings)) continue;
                try candidates.append(self.allocator, .{ .module = module_index, .template = template, .bindings = bindings });
                keep = true;
            }
        }
        var selected: ?usize = null;
        for (candidates.items, 0..) |candidate, index| {
            var dominated = false;
            for (candidates.items, 0..) |other, other_index| {
                if (index == other_index) continue;
                const covers_other = try self.patternTupleCovers(candidate.module, candidate.template, other.module, other.template);
                const covers_candidate = try self.patternTupleCovers(other.module, other.template, candidate.module, candidate.template);
                if (covers_other and !covers_candidate) {
                    dominated = true;
                    break;
                }
            }
            if (dominated) continue;
            if (selected != null) {
                self.participant_conformance_failure = .{
                    .source = self.sourceFor(candidate.module, candidate.template.source),
                    .contract_name = self.modules[located.module_index].text(self.modules[located.module_index].declarations.items[@intFromEnum(located.definition.declaration)].name),
                    .reason = "overlapping generic implementations have ambiguous maximal patterns",
                };
                return error.InvalidContractConformance;
            }
            selected = index;
        }
        const candidate = &candidates.items[selected orelse return null];
        const module_index = candidate.module;
        const selected_template = candidate.template;
        const bindings = &candidate.bindings;
        const actual = try self.generics.instantiateParameterizedArguments(module_index, selected_template.participants, bindings);
        const associated = try self.generics.instantiateParameterizedArguments(module_index, selected_template.associated_arguments, bindings);
        var contract_bindings = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
        defer contract_bindings.deinit(self.allocator);
        try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, actual, &contract_bindings);
        try self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, associated, &contract_bindings);
        var failure: ParticipantConformanceFailure = .{ .source = self.sourceFor(module_index, selected_template.source), .contract_name = self.graph.text(self.graph.declaration(declaration).name), .reason = "" };
        const operations = try self.prepareOperationBindings(module_index, located, selected_template, &failure);
        const implementation = try self.publishImplementationArguments(module_index, selected_template.parameters, bindings);
        const index = self.graph.contract_conformances.items.len;
        try self.graph.contract_conformances.append(self.allocator, .{
            .context = @enumFromInt(@as(u32, @intCast(module_index))),
            .declaration = declaration,
            .participants = try self.publishConformanceArguments(located, located.definition.participants, &contract_bindings),
            .associated_arguments = try self.publishConformanceArguments(located, located.definition.parameters, &contract_bindings),
            .implementation_arguments = implementation,
            .operation_bindings = operations,
            .source = failure.source,
        });
        if (target) |destination| {
            try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, actual, destination);
            try self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, associated, destination);
        }
        return .{ .tuple = index };
    }

    const SymbolicPattern = struct { module: usize, ty: ir.ParameterizedTypeId };
    const SymbolicIntPattern = struct { module: usize, expression: ir.ParameterizedIntExprId };
    const PatternSubstitutions = struct {
        types: std.AutoHashMap(ir.ComptimeParameterId, SymbolicPattern),
        integers: std.AutoHashMap(ir.ComptimeParameterId, SymbolicIntPattern),
    };

    fn symbolicIntsEqual(self: *Resolver, a: SymbolicIntPattern, b: SymbolicIntPattern) bool {
        const left = self.modules[a.module].semantic.parameterized_storage.ir.int_expressions.items[@intFromEnum(a.expression)];
        const right = self.modules[b.module].semantic.parameterized_storage.ir.int_expressions.items[@intFromEnum(b.expression)];
        return switch (left) {
            .literal => |value| right == .literal and value == right.literal,
            .parameter => |parameter| right == .parameter and a.module == b.module and parameter == right.parameter,
            else => a.module == b.module and a.expression == b.expression,
        };
    }

    fn patternIntCovers(self: *Resolver, general: SymbolicIntPattern, specific: SymbolicIntPattern, substitutions: *PatternSubstitutions) !bool {
        const expression = self.modules[general.module].semantic.parameterized_storage.ir.int_expressions.items[@intFromEnum(general.expression)];
        if (expression == .parameter) {
            if (substitutions.integers.get(expression.parameter)) |previous| return self.symbolicIntsEqual(previous, specific);
            try substitutions.integers.put(expression.parameter, specific);
            return true;
        }
        return self.symbolicIntsEqual(general, specific);
    }

    pub fn patternTupleCovers(self: *Resolver, general_module: usize, general: parameterized_storage.ContractConformance, specific_module: usize, specific: parameterized_storage.ContractConformance) !bool {
        var substitutions = PatternSubstitutions{
            .types = std.AutoHashMap(ir.ComptimeParameterId, SymbolicPattern).init(self.allocator),
            .integers = std.AutoHashMap(ir.ComptimeParameterId, SymbolicIntPattern).init(self.allocator),
        };
        defer substitutions.types.deinit();
        defer substitutions.integers.deinit();
        const left = self.modules[general_module].semantic.parameterized_storage.ir.generic_arguments.items[general.participants.start..][0..general.participants.len];
        const right = self.modules[specific_module].semantic.parameterized_storage.ir.generic_arguments.items[specific.participants.start..][0..specific.participants.len];
        for (left, right) |a, b| {
            if (a.value != .type or b.value != .type) return false;
            if (!try self.patternTypeCovers(.{ .module = general_module, .ty = a.value.type }, .{ .module = specific_module, .ty = b.value.type }, &substitutions)) return false;
        }
        return true;
    }

    fn nominalPatternsCover(self: *Resolver, a: SymbolicPattern, b: SymbolicPattern, substitutions: ?*PatternSubstitutions) !bool {
        const left = self.modules[a.module].semantic.parameterized_storage.ir.types.items[@intFromEnum(a.ty)].resolved.generic;
        const right = self.modules[b.module].semantic.parameterized_storage.ir.types.items[@intFromEnum(b.ty)].resolved.generic;
        const declaration = try self.generics.resolveParameterizedDeclaration(a.module, left.base);
        if (declaration != try self.generics.resolveParameterizedDeclaration(b.module, right.base)) return false;
        const located = self.generics.findTypeParameterized(declaration) orelse return false;
        if (left.arguments.len != located.parameterized.parameters.len or right.arguments.len != left.arguments.len) return false;
        for (0..located.parameterized.parameters.len) |position| {
            const parameter = self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items[located.parameterized.parameters.start + position];
            const name = self.modules[located.module_index].text(parameter.name);
            const l = self.generics.findPatternArgument(a.module, left.arguments, position, name) orelse return false;
            const r = self.generics.findPatternArgument(b.module, right.arguments, position, name) orelse return false;
            if (l.value == .type and r.value == .type) {
                const lp: SymbolicPattern = .{ .module = a.module, .ty = l.value.type };
                const rp: SymbolicPattern = .{ .module = b.module, .ty = r.value.type };
                if (substitutions) |mapping| {
                    if (!try self.patternTypeCovers(lp, rp, mapping)) return false;
                } else if (!try self.symbolicTypesEqual(lp, rp)) return false;
            } else if (l.value == .comptime_int and r.value == .comptime_int) {
                const lp: SymbolicIntPattern = .{ .module = a.module, .expression = l.value.comptime_int };
                const rp: SymbolicIntPattern = .{ .module = b.module, .expression = r.value.comptime_int };
                if (substitutions) |mapping| {
                    if (!try self.patternIntCovers(lp, rp, mapping)) return false;
                } else if (!self.symbolicIntsEqual(lp, rp)) return false;
            } else return false;
        }
        return true;
    }

    fn symbolicTypesEqual(self: *Resolver, a: SymbolicPattern, b: SymbolicPattern) !bool {
        const left = self.modules[a.module].semantic.parameterized_storage.ir.types.items[@intFromEnum(a.ty)];
        const right = self.modules[b.module].semantic.parameterized_storage.ir.types.items[@intFromEnum(b.ty)];
        if (left == .parameter or right == .parameter)
            return left == .parameter and right == .parameter and a.module == b.module and left.parameter == right.parameter;
        if (left == .array and right == .array) {
            if (!self.symbolicIntsEqual(.{ .module = a.module, .expression = left.array.length }, .{ .module = b.module, .expression = right.array.length })) return false;
            return self.symbolicTypesEqual(.{ .module = a.module, .ty = left.array.element }, .{ .module = b.module, .ty = right.array.element });
        }
        if (left == .resolved and right == .resolved and left.resolved == .pointer and right.resolved == .pointer) {
            if (left.resolved.pointer.mutability != right.resolved.pointer.mutability) return false;
            return self.symbolicTypesEqual(.{ .module = a.module, .ty = left.resolved.pointer.child }, .{ .module = b.module, .ty = right.resolved.pointer.child });
        }
        if (left == .resolved and right == .resolved and left.resolved == .structural and right.resolved == .structural) {
            const l = left.resolved.structural.fields;
            const r = right.resolved.structural.fields;
            if (l.len != r.len) return false;
            for (self.modules[a.module].semantic.parameterized_storage.ir.fields.items[l.start..][0..l.len], self.modules[b.module].semantic.parameterized_storage.ir.fields.items[r.start..][0..r.len]) |lf, rf| {
                if (!std.mem.eql(u8, self.modules[a.module].text(lf.name), self.modules[b.module].text(rf.name))) return false;
                if (!try self.symbolicTypesEqual(.{ .module = a.module, .ty = lf.ty }, .{ .module = b.module, .ty = rf.ty })) return false;
            }
            return true;
        }
        if (left == .resolved and right == .resolved and left.resolved == .generic and right.resolved == .generic)
            return self.nominalPatternsCover(a, b, null);
        var left_bindings = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[a.module].semantic.parameterized_storage.comptime_parameters.items.len);
        defer left_bindings.deinit(self.allocator);
        var right_bindings = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[b.module].semantic.parameterized_storage.comptime_parameters.items.len);
        defer right_bindings.deinit(self.allocator);
        const l = self.generics.instantiateParameterizedType(a.module, a.ty, &left_bindings) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
        const r = self.generics.instantiateParameterizedType(b.module, b.ty, &right_bindings) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
        return global_types.equal(self.graph, l, r);
    }

    fn patternTypeCovers(self: *Resolver, general: SymbolicPattern, specific: SymbolicPattern, substitutions: *PatternSubstitutions) !bool {
        const ty = self.modules[general.module].semantic.parameterized_storage.ir.types.items[@intFromEnum(general.ty)];
        if (ty == .parameter) {
            if (substitutions.types.get(ty.parameter)) |previous| return self.symbolicTypesEqual(previous, specific);
            try substitutions.types.put(ty.parameter, specific);
            return true;
        }
        const other = self.modules[specific.module].semantic.parameterized_storage.ir.types.items[@intFromEnum(specific.ty)];
        if (ty == .array and other == .array) {
            if (!try self.patternIntCovers(.{ .module = general.module, .expression = ty.array.length }, .{ .module = specific.module, .expression = other.array.length }, substitutions)) return false;
            return self.patternTypeCovers(.{ .module = general.module, .ty = ty.array.element }, .{ .module = specific.module, .ty = other.array.element }, substitutions);
        }
        if (ty == .resolved and ty.resolved == .pointer and other == .resolved and other.resolved == .pointer) {
            if (ty.resolved.pointer.mutability != other.resolved.pointer.mutability) return false;
            return self.patternTypeCovers(.{ .module = general.module, .ty = ty.resolved.pointer.child }, .{ .module = specific.module, .ty = other.resolved.pointer.child }, substitutions);
        }
        if (ty == .resolved and other == .resolved and ty.resolved == .structural and other.resolved == .structural) {
            const a = ty.resolved.structural.fields;
            const b = other.resolved.structural.fields;
            if (a.len != b.len) return false;
            const general_fields = self.modules[general.module].semantic.parameterized_storage.ir.fields.items[a.start..][0..a.len];
            const specific_fields = self.modules[specific.module].semantic.parameterized_storage.ir.fields.items[b.start..][0..b.len];
            for (general_fields, specific_fields) |wanted, given| {
                if (!std.mem.eql(u8, self.modules[general.module].text(wanted.name), self.modules[specific.module].text(given.name))) return false;
                if (!try self.patternTypeCovers(.{ .module = general.module, .ty = wanted.ty }, .{ .module = specific.module, .ty = given.ty }, substitutions)) return false;
            }
            return true;
        }
        if (ty == .resolved and other == .resolved and ty.resolved == .generic and other.resolved == .generic)
            return self.nominalPatternsCover(general, specific, substitutions);
        return self.symbolicTypesEqual(general, specific);
    }

    fn publishImplementationArguments(self: *Resolver, module_index: usize, parameters: primitives.Range(ir.ComptimeParameterId), bindings: *generic_mod.Resolver.Bindings) !primitives.Range(global_sg.GlobalGenericArgId) {
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = self.modules[module_index].semantic.parameterized_storage.comptime_parameters.items[raw];
            try self.graph.generic_arguments.append(self.allocator, .{ .name = try self.graph.addString(self.allocator, self.modules[module_index].text(parameter.name)), .value = switch (parameter.kind) {
                .type => .{ .type = bindings.types[raw].? },
                .comptime_int => .{ .comptime_int = bindings.ints[raw].? },
            } });
        }
        return .{ .start = start, .len = parameters.len };
    }

    fn implementsDepth(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        contract_decl: global_sg.GlobalDeclId,
        depth: u8,
    ) !bool {
        if (depth >= 64) return false;
        const located = self.findContractDefinition(contract_decl) orelse return false;
        if (located.definition.participants.len != 1) return false;
        if (self.graph.semanticType(concrete) == .virtual) {
            const evidence = self.contractUse(self.graph.semanticType(concrete).virtual) orelse return false;
            return evidence.declaration == contract_decl and evidence.arguments.len == 0 and located.definition.parameters.len == 0;
        }
        return try self.selectConformance(contract_decl, &.{concrete}, null, depth, null) != null;
    }

    pub fn findGenericTypeConstraintFailure(self: *Resolver) !?GenericTypeConstraintFailure {
        for (self.graph.types.items) |ty| {
            const identity = switch (ty) {
                .generic => |value| value,
                else => continue,
            };
            const located = self.generics.findTypeParameterized(identity.base) orelse continue;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            var bindings = try generic_mod.Resolver.Bindings.init(
                self.allocator,
                storage.comptime_parameters.items.len,
            );
            defer bindings.deinit(self.allocator);
            self.generics.bindGlobalArguments(
                located.module_index,
                located.parameterized.parameters,
                identity.arguments,
                &bindings,
            ) catch continue;

            for (located.parameterized.parameters.start..located.parameterized.parameters.start + located.parameterized.parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                const constraint_id = parameter.constraint orelse continue;
                if (parameter.kind != .type) continue;
                const actual = bindings.types[raw] orelse continue;
                if (try self.inferConstraintBindings(
                    located.module_index,
                    constraint_id,
                    actual,
                    &bindings,
                )) continue;

                const constraint = storage.contract_constraints.items[@intFromEnum(constraint_id)];
                return .{
                    .generic_decl = identity.base,
                    .contract_decl = try self.resolveDeclarationRef(
                        located.module_index,
                        constraint.contract_ref,
                        .contract_type,
                    ),
                    .actual = actual,
                    .parameter_name = self.modules[located.module_index].text(parameter.name),
                    .source = self.sourceFor(located.module_index, constraint.source),
                };
            }
        }
        return null;
    }

    fn conformanceArgumentFailure(err: anyerror) ?[]const u8 {
        return switch (err) {
            error.TooManyGenericArguments => "too many arguments",
            error.UnknownGenericArgument => "unknown argument name",
            error.DuplicateGenericArgument => "duplicate argument",
            error.MissingGenericArgument => "missing argument",
            error.GenericArgumentKindMismatch => "argument kind does not match its parameter",
            else => null,
        };
    }

    fn publishConformanceArguments(self: *Resolver, located: LocatedContractDefinition, parameters: primitives.Range(ir.ComptimeParameterId), bindings: *generic_mod.Resolver.Bindings) !primitives.Range(global_sg.GlobalGenericArgId) {
        const module = &self.modules[located.module_index];
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (module.semantic.parameterized_storage.comptime_parameters.items[parameters.start..][0..parameters.len], 0..) |parameter, index| {
            const raw = parameters.start + @as(u32, @intCast(index));
            const name = try self.graph.addString(self.allocator, module.text(parameter.name));
            try self.graph.generic_arguments.append(self.allocator, .{
                .name = name,
                .value = switch (parameter.kind) {
                    .type => .{ .type = bindings.types[raw].? },
                    .comptime_int => .{ .comptime_int = bindings.ints[raw].? },
                },
            });
        }
        return .{ .start = start, .len = parameters.len };
    }

    pub fn resolveScopedOperation(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, offsets: globalizer.Offsets, call: anytype) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
        const context = reach_context.Context.fromModule(module, offsets, call.visible_bindings, call.owner_function);
        const node = try self.makeScopedOperationCall(module_index, globalizer.globalType(offsets, call.contract_type.?), module.text(reference.name), globalizer.globalNode(offsets, call.input), context, self.sourceFor(module_index, reference.source)) orelse
            return if (self.participant_conformance_failure != null) .invalid else .deferred;
        self.graph.nodes.items[@intFromEnum(globalizer.globalNode(offsets, call.node))] = node;
        return .resolved;
    }

    pub const OperationCandidate = struct {
        declaration: global_sg.GlobalDeclId,
        participants: []global_sg.GlobalTypeId,
        virtual: bool = false,
    };

    pub const OperationCandidates = struct {
        items: std.ArrayList(OperationCandidate) = .empty,
        deferred: bool = false,
        failure: ?ParticipantConformanceFailure = null,

        pub fn deinit(self: *OperationCandidates, allocator: std.mem.Allocator) void {
            for (self.items.items) |candidate| allocator.free(candidate.participants);
            self.items.deinit(allocator);
        }
    };

    /// Compare operation identities using their input signatures. Conformance
    /// specificity determines associated signatures within one identity, never
    /// a priority between contracts. Probes publish no evidence or runtime body.
    pub fn operationCandidates(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context) !OperationCandidates {
        return self.operationCandidatesFiltered(module_index, name, input, context, null);
    }

    pub fn operationCandidatesFiltered(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context, module_filter: ?global_sg.GlobalModuleId) !OperationCandidates {
        var result: OperationCandidates = .{};
        errdefer result.deinit(self.allocator);
        if (std.mem.startsWith(u8, name, "_")) return result;
        for (self.modules, 0..) |module, owner| {
            for (module.semantic.parameterized_storage.contract_definitions.items) |definition| {
                if (!definition.hasExplicitParticipants()) continue;
                const declaration = globalizer.globalDecl(self.offsets[owner], definition.declaration);
                if (!self.core.declarationVisible(module_index, declaration, module_filter)) continue;
                const storage = &module.semantic.parameterized_storage;
                for (storage.contract_requirements.items[definition.requirements.start..][0..definition.requirements.len]) |requirement| {
                    if (!std.mem.eql(u8, module.text(requirement.name), name)) continue;
                    if (try self.probeOperationCandidate(.{ .module_index = owner, .definition = definition }, declaration, requirement, input, context, &result.deferred, &result.failure)) |candidate|
                        try result.items.append(self.allocator, candidate);
                }
            }
        }
        return result;
    }

    // Call inputs permit a mutable loan to satisfy a readonly parameter.
    // Conformance participant patterns remain exact: this adaptation belongs
    // to ordinary argument matching, not implementation specialization.
    fn inferOperationInputPattern(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, actual: global_sg.GlobalTypeId, bindings: *generic_mod.Resolver.Bindings) !bool {
        const expected = self.modules[module_index].semantic.parameterized_storage.ir.types.items[@intFromEnum(pattern)];
        const supplied = self.graph.semanticType(actual);
        if (expected == .resolved and expected.resolved == .pointer and supplied == .pointer and expected.resolved.pointer.mutability == .read_only)
            return self.inferConstraintTypePattern(module_index, expected.resolved.pointer.child, supplied.pointer.child, bindings);
        return self.inferConstraintTypePattern(module_index, pattern, actual, bindings);
    }

    fn probeOperationCandidate(self: *Resolver, located: LocatedContractDefinition, declaration: global_sg.GlobalDeclId, requirement: parameterized_storage.ContractRequirement, input: global_sg.GlobalNodeId, context: reach_context.Context, deferred: *bool, failure: *?ParticipantConformanceFailure) !?OperationCandidate {
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        const checkpoint = self.graph.checkpoint();
        const caches = self.checkpointResolution();
        const comptime_failure = self.generics.comptime_failure;
        const argument_failure = self.generics.argument_failure;
        defer {
            self.graph.rollback(checkpoint);
            self.rollbackResolution(caches);
            self.generics.comptime_failure = comptime_failure;
            self.generics.argument_failure = argument_failure;
        }
        const module = &self.modules[located.module_index];
        const storage = &module.semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        const fields = storage.ir.types.items[@intFromEnum(requirement.input)].resolved.structural.fields;
        var virtual = false;
        var unresolved_actual = false;
        for (storage.ir.fields.items[fields.start..][0..fields.len], 0..) |field, position| {
            var explicit = false;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |actual, index| {
                const name = self.graph.text(actual.name);
                if (!((name.len == 0 and position == index) or std.mem.eql(u8, name, module.text(field.name)))) continue;
                explicit = true;
                const actual_ty = self.graph.node(actual.value).ty orelse {
                    // An associated input can be a contextual record/choice
                    // literal. Other inputs select participants first; the
                    // selected signature supplies its type below.
                    unresolved_actual = true;
                    continue;
                };
                if (!self.typeSelectionReady(actual_ty, 0)) {
                    unresolved_actual = true;
                    continue;
                }
                const ty = self.graph.semanticType(actual_ty);
                const pattern = storage.ir.types.items[@intFromEnum(field.ty)];
                if (located.definition.participants.len == 1 and pattern == .resolved and pattern.resolved == .pointer and
                    self.isUnaryReceiverParticipantType(located, pattern.resolved.pointer.child) and ty == .pointer)
                {
                    const child = self.graph.semanticType(ty.pointer.child);
                    if (child == .virtual) {
                        const use = self.contractUse(child.virtual) orelse return null;
                        if (use.declaration == declaration) {
                            if (!self.bindContractUseArguments(use, located, &bindings)) return null;
                            bindings.types[located.definition.participants.start] = child.virtual;
                            virtual = true;
                            continue;
                        }
                        // A different virtual interface is a known wrapper type,
                        // and may participate in a static adapter conformance.
                    }
                }
                // Input patterns can mention associated elements. Infer what is
                // available now, then check the entire selected signature below.
                _ = try self.inferOperationInputPattern(located.module_index, field.ty, actual_ty, &bindings);
            }
            if (!explicit) if (field.default_value) |value| {
                const reach = try self.generics.instantiateReachDefault(located.module_index, value) orelse continue;
                const ty = self.core.probeReachedType(context, reach, deferred) orelse continue;
                const pattern = storage.ir.types.items[@intFromEnum(field.ty)];
                const actual = self.graph.semanticType(ty);
                if (located.definition.participants.len == 1 and pattern == .resolved and pattern.resolved == .pointer and
                    self.isUnaryReceiverParticipantType(located, pattern.resolved.pointer.child) and actual == .pointer)
                {
                    const child = self.graph.semanticType(actual.pointer.child);
                    if (child == .virtual) {
                        const use = self.contractUse(child.virtual) orelse continue;
                        if (use.declaration == declaration) {
                            if (!self.bindContractUseArguments(use, located, &bindings)) continue;
                            bindings.types[located.definition.participants.start] = child.virtual;
                            virtual = true;
                            continue;
                        }
                    }
                }
                _ = try self.inferOperationInputPattern(located.module_index, field.ty, ty, &bindings);
            };
        }
        const participants = try self.allocator.alloc(global_sg.GlobalTypeId, located.definition.participants.len);
        errdefer self.allocator.free(participants);
        for (participants, 0..) |*participant, index| {
            participant.* = bindings.types[located.definition.participants.start + index] orelse {
                if (unresolved_actual) deferred.* = true;
                self.allocator.free(participants);
                return null;
            };
        }
        if (!virtual) {
            const selected = self.selectConformance(declaration, participants, &bindings, 0, deferred) catch |err| {
                self.allocator.free(participants);
                if (err == error.OutOfMemory) return err;
                if (self.participant_conformance_failure) |diagnostic| {
                    var retained = diagnostic;
                    // Probe-local signature IDs disappear on rollback. Names
                    // and source locations belong to immutable module data.
                    retained.input = null;
                    retained.output = null;
                    failure.* = retained;
                }
                return null;
            };
            if (selected == null) {
                self.allocator.free(participants);
                return null;
            }
        }
        const required = self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings) catch |err| {
            self.allocator.free(participants);
            if (err == error.OutOfMemory) return err;
            return null;
        };
        switch (try self.core.matchCallInputWithReach(global_types.fields(self.graph, required) orelse return error.InvalidContractRequirementInput, input, context)) {
            .score => return .{ .declaration = declaration, .participants = participants, .virtual = virtual },
            .deferred => deferred.* = true,
            .no_match => {},
        }
        self.allocator.free(participants);
        return null;
    }

    pub fn callOperationCandidate(self: *Resolver, module_index: usize, candidate: OperationCandidate, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context, source: primitives.SourceRef) !?global_sg.Node {
        if (candidate.virtual) {
            const located = self.findContractDefinition(candidate.declaration) orelse return null;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            const requirement = for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len]) |requirement| {
                if (std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), name)) break requirement;
            } else return null;
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            const interface = self.contractUse(candidate.participants[0]) orelse return null;
            if (!self.bindContractUseArguments(interface, located, &bindings)) return null;
            bindings.types[located.definition.participants.start] = candidate.participants[0];
            const required = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings);
            if (!try self.core.completeCallInputFieldsWithReach(global_types.fields(self.graph, required).?, input, context)) return null;
        }
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        if (!candidate.virtual) for (candidate.participants) |participant|
            try self.graph.generic_arguments.append(self.allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = participant } });
        const base = try self.generics.internType(.{ .generic = .{ .base = candidate.declaration, .arguments = .{ .start = start, .len = if (candidate.virtual) 0 else @intCast(candidate.participants.len) } } });
        return self.makeScopedOperationCall(module_index, base, name, input, context, source);
    }

    pub fn makeScopedOperationCall(self: *Resolver, module_index: usize, base: global_sg.GlobalTypeId, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context, source: primitives.SourceRef) !?global_sg.Node {
        const use = self.typeContractUse(base) orelse return null;
        const located = self.findContractDefinition(use.declaration) orelse return null;
        var failure: ParticipantConformanceFailure = .{
            .source = source,
            .contract_name = self.modules[located.module_index].text(self.modules[located.module_index].declarations.items[@intFromEnum(located.definition.declaration)].name),
            .operation = name,
            .reason = "",
        };
        if (std.mem.startsWith(u8, name, "_") and module_index != located.module_index and
            !(self.modules[module_index].is_bundled_core and self.modules[located.module_index].is_bundled_core))
        {
            failure.reason = "contract operation is private to its defining module";
            self.participant_conformance_failure = failure;
            return null;
        }
        if (!located.definition.hasExplicitParticipants()) {
            failure.reason = "qualified contract operations require explicit participants";
            self.participant_conformance_failure = failure;
            return null;
        }
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        const interface_arguments = blk: {
            if (located.definition.participants.len != 1) break :blk false;
            if (use.arguments.len == 0) break :blk true;
            for (self.graph.generic_arguments.items[use.arguments.start..][0..use.arguments.len]) |argument| {
                const label = self.graph.text(argument.name);
                if (label.len == 0) break :blk false;
                for (storage.comptime_parameters.items[located.definition.parameters.start..][0..located.definition.parameters.len]) |parameter| {
                    if (std.mem.eql(u8, label, self.modules[located.module_index].text(parameter.name))) break;
                } else break :blk false;
            }
            break :blk true;
        };
        if (interface_arguments and use.arguments.len == 0) {
            if (try self.makeVirtualOperationCall(name, use.declaration, input, source, context, if (use.arguments.len == 0) null else use.arguments)) |node| return node;
            const participant = try self.inferUnaryOperationParticipant(located, name, input) orelse return null;
            const start: u32 = @intCast(self.graph.generic_arguments.items.len);
            try self.graph.generic_arguments.append(self.allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = participant } });
            const bound = try self.generics.internType(.{ .generic = .{ .base = use.declaration, .arguments = .{ .start = start, .len = 1 } } });
            return self.makeScopedOperationCall(module_index, bound, name, input, context, source);
        }
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        if (interface_arguments) {
            // Associated bindings constrain the selected evidence; they do not
            // select the participant. Recover it from the declared receiver.
            if (try self.makeVirtualOperationCall(name, use.declaration, input, source, context, if (use.arguments.len == 0) null else use.arguments)) |node| return node;
            bindings.types[located.definition.participants.start] = try self.inferUnaryOperationParticipant(located, name, input) orelse return null;
        } else self.generics.bindGlobalArguments(located.module_index, located.definition.participants, use.arguments, &bindings) catch |err| {
            failure.reason = conformanceArgumentFailure(err) orelse return err;
            self.participant_conformance_failure = failure;
            return null;
        };
        const participants = try self.allocator.alloc(global_sg.GlobalTypeId, located.definition.participants.len);
        defer self.allocator.free(participants);
        for (participants, 0..) |*participant, position| {
            participant.* = bindings.types[located.definition.participants.start + position].?;
            if (!self.typeSelectionReady(participant.*, 0)) return null;
        }
        const selected = try self.selectConformance(use.declaration, participants, &bindings, 0, null) orelse {
            failure.reason = "no conformance for the qualified operation's participants";
            self.participant_conformance_failure = failure;
            return null;
        };
        if (interface_arguments and !try self.associatedArgumentsMatch(located, &bindings, use.arguments)) {
            failure.reason = "selected conformance has incompatible associated elements for the operation interface";
            self.participant_conformance_failure = failure;
            return null;
        }
        const conformance = self.graph.contract_conformances.items[selected.tuple];
        const method_index = for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, index| {
            if (std.mem.eql(u8, name, self.modules[located.module_index].text(requirement.name))) break index;
        } else {
            failure.reason = "unknown contract operation";
            self.participant_conformance_failure = failure;
            return null;
        };
        const method = try self.resolveOperationBinding(conformance, method_index);
        const requirement = storage.contract_requirements.items[located.definition.requirements.start + method_index];
        const required_type = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings);
        const required_fields = global_types.fields(self.graph, required_type) orelse return error.InvalidContractRequirementInput;
        if (!try self.core.completeCallInputFieldsWithReach(required_fields, input, context)) return null;
        const function = self.graph.function(method);
        switch (self.core.matchCallInput(function.input, input)) {
            .deferred => return null,
            .no_match => {
                failure.reason = "arguments do not match the selected contract operation";
                self.participant_conformance_failure = failure;
                return null;
            },
            .score => {},
        }
        if (!try self.core.completeCallInputFieldsWithReach(function.input, input, context)) return null;
        try self.core.trackReachedCall(method, input, context, false);
        return .{
            .source = source,
            .ty = try self.core.functionOutputType(method),
            .content = .{ .function_call = .{
                .contract_operation = .{ .conformance = @intCast(selected.tuple), .index = @intCast(method_index) },
                .callee = method,
                .input = input,
            } },
        };
    }

    // An unbound unary operation still has a fixed identity. Infer its sole
    // participant from a direct value/reference input, then use the ordinary
    // selected-evidence path. Outputs and implementation enumeration never infer it.
    fn inferUnaryOperationParticipant(self: *Resolver, located: LocatedContractDefinition, name: []const u8, input: global_sg.GlobalNodeId) !?global_sg.GlobalTypeId {
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        const requirement = for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len]) |requirement| {
            if (std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), name)) break requirement;
        } else return null;
        const fields = storage.ir.types.items[@intFromEnum(requirement.input)].resolved.structural.fields;
        for (storage.ir.fields.items[fields.start..][0..fields.len], 0..) |field, position| {
            const pattern = storage.ir.types.items[@intFromEnum(field.ty)];
            const pointer = pattern == .resolved and pattern.resolved == .pointer and
                self.isUnaryReceiverParticipantType(located, pattern.resolved.pointer.child);
            if (!pointer and !self.isUnaryReceiverParticipantType(located, field.ty)) continue;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |actual, index| {
                const label = self.graph.text(actual.name);
                if (!((label.len == 0 and index == position) or std.mem.eql(u8, label, self.modules[located.module_index].text(field.name)))) continue;
                var ty = self.graph.node(actual.value).ty orelse return null;
                if (!self.typeSelectionReady(ty, 0)) return null;
                if (pointer) {
                    const actual_type = self.graph.semanticType(ty);
                    if (actual_type != .pointer) return null;
                    ty = actual_type.pointer.child;
                }
                // A fixed virtual interface can defer while reached capability
                // inputs are being materialized. It must never fall through to
                // static conformance selection for the erased handle type.
                if (self.graph.semanticType(ty) == .virtual or self.contractUse(ty) != null) return null;
                return ty;
            }
        }
        return null;
    }

    fn templateParticipantOwner(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId) !?global_sg.GlobalModuleId {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const declaration = switch (storage.types.items[@intFromEnum(pattern)]) {
            .concrete => |local| return global_types.conformanceParticipantOwner(self.graph, globalizer.globalType(self.offsets[module_index], local)),
            .external => |external| try self.core.resolveDeclaration(
                module_index,
                self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)],
                &.{.type},
            ),
            .resolved => |resolved| switch (resolved) {
                .pointer => |pointer| return self.templateParticipantOwner(module_index, pointer.child),
                .generic => |nominal| try self.generics.resolveParameterizedDeclaration(module_index, nominal.base),
                .declared => |reference| try self.generics.resolveParameterizedDeclaration(module_index, reference),
                else => return null,
            },
            else => return null,
        };
        return self.graph.moduleForDeclaration(declaration);
    }

    fn templateOwnsParticipant(self: *Resolver, module_index: usize, conformance: parameterized_storage.ContractConformance) !bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        for (storage.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len]) |argument| {
            if (argument.value != .type) continue;
            if (try self.templateParticipantOwner(module_index, argument.value.type)) |owner|
                if (@intFromEnum(owner) == module_index) return true;
        }
        return false;
    }

    // Dormant templates still extend an operation identity. Reject foreign
    // ownership and equivalent patterns before any concrete call selects them.
    fn validateConformanceTemplates(self: *Resolver) !void {
        const Template = struct { module: usize, conformance: parameterized_storage.ContractConformance, declaration: global_sg.GlobalDeclId };
        var previous: std.ArrayList(Template) = .empty;
        defer previous.deinit(self.allocator);
        for (self.modules, 0..) |module, module_index| {
            for (module.semantic.parameterized_storage.contract_conformances.items) |conformance| {
                const declaration = self.resolveDeclarationRef(module_index, conformance.contract_ref, .contract_type) catch |err| switch (err) {
                    error.UnknownGlobalDeclaration, error.AmbiguousGlobalDeclaration, error.UnknownModuleReference, error.AmbiguousModuleReference => continue,
                    else => return err,
                };
                const located = self.findContractDefinition(declaration) orelse continue;
                if (!located.definition.hasExplicitParticipants()) continue;
                var failure: ParticipantConformanceFailure = .{
                    .source = self.sourceFor(module_index, conformance.source),
                    .contract_name = self.graph.text(self.graph.declaration(declaration).name),
                    .reason = "",
                };
                if (conformance.parameters.len != 0 and located.module_index != module_index and
                    !(module.is_bundled_core and self.modules[located.module_index].is_bundled_core) and
                    !try self.templateOwnsParticipant(module_index, conformance))
                {
                    failure.reason = "an implementation must belong to the contract module or a nominal participant module";
                    self.participant_conformance_failure = failure;
                    return;
                }
                for (previous.items) |other| {
                    if (conformance.parameters.len == 0 and other.conformance.parameters.len == 0) continue;
                    if (other.declaration != declaration or other.conformance.participants.len != conformance.participants.len) continue;
                    if (try self.patternTupleCovers(module_index, conformance, other.module, other.conformance) and
                        try self.patternTupleCovers(other.module, other.conformance, module_index, conformance))
                    {
                        failure.reason = "equivalent implementation participant patterns are not allowed";
                        self.participant_conformance_failure = failure;
                        return;
                    }
                }
                try previous.append(self.allocator, .{ .module = module_index, .conformance = conformance, .declaration = declaration });
            }
        }
    }

    pub fn prepareParticipantConformances(self: *Resolver) !void {
        try self.validateConformanceTemplates();
        if (self.participant_conformance_failure != null) return;
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.contract_conformances.items) |conformance| {
                const contract_name = module.text(switch (conformance.contract_ref) {
                    .module => |declaration| module.declarations.items[@intFromEnum(declaration)].name,
                    .external => |external| module.semantic.external_refs.items[@intFromEnum(external)].name,
                });
                var failure: ParticipantConformanceFailure = .{ .source = self.sourceFor(module_index, conformance.source), .contract_name = contract_name, .reason = "" };
                const declaration = self.resolveDeclarationRef(module_index, conformance.contract_ref, .contract_type) catch |err| {
                    failure.reason = switch (err) {
                        error.UnknownGlobalDeclaration => "unknown or inaccessible contract",
                        error.AmbiguousGlobalDeclaration => "ambiguous contract name",
                        else => return err,
                    };
                    self.participant_conformance_failure = failure;
                    return;
                };
                const located = self.findContractDefinition(declaration) orelse return error.InvalidContractDeclaration;
                if (!located.definition.hasExplicitParticipants()) {
                    failure.reason = "implement requires a contract with explicit participants";
                    self.participant_conformance_failure = failure;
                    return;
                }
                if (conformance.parameters.len != 0) {
                    // Templates are instantiated from participants by selection.
                    _ = try self.prepareOperationBindings(module_index, located, conformance, &failure);
                    continue;
                }
                const storage = &self.modules[located.module_index].semantic.parameterized_storage;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                var implementation_bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
                defer implementation_bindings.deinit(self.allocator);
                const participants = try self.generics.instantiateParameterizedArguments(module_index, conformance.participants, &implementation_bindings);
                self.generics.bindGlobalArguments(located.module_index, located.definition.participants, participants, &bindings) catch |err| {
                    failure.reason = conformanceArgumentFailure(err) orelse return err;
                    self.participant_conformance_failure = failure;
                    return;
                };
                const associated = try self.generics.instantiateParameterizedArguments(module_index, conformance.associated_arguments, &implementation_bindings);
                self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, associated, &bindings) catch |err| {
                    failure.reason = conformanceArgumentFailure(err) orelse return err;
                    self.participant_conformance_failure = failure;
                    return;
                };
                for (self.graph.contract_conformances.items) |previous| {
                    if (previous.declaration != declaration) continue;
                    var equal = true;
                    for (0..located.definition.participants.len) |position| {
                        const actual = bindings.types[located.definition.participants.start + position].?;
                        const old = self.graph.generic_arguments.items[previous.participants.start + position].value.type;
                        if (!global_types.equal(self.graph, actual, old)) {
                            equal = false;
                            break;
                        }
                    }
                    if (equal) {
                        failure.reason = "ambiguous conformances for the same participant tuple";
                        self.participant_conformance_failure = failure;
                        return;
                    }
                }
                const operations = self.prepareOperationBindings(module_index, located, conformance, &failure) catch |err| {
                    if (err != error.InvalidContractConformance) return err;
                    self.participant_conformance_failure = failure;
                    return;
                };
                // Make canonical associations available before checking operation signatures.
                // This provisional evidence cannot escape a failed compilation.
                const canonical_participants = try self.publishConformanceArguments(located, located.definition.participants, &bindings);
                const canonical_associated = try self.publishConformanceArguments(located, located.definition.parameters, &bindings);
                try self.graph.contract_conformances.append(self.allocator, .{
                    .context = @enumFromInt(@as(u32, @intCast(module_index))),
                    .declaration = declaration,
                    .participants = canonical_participants,
                    .associated_arguments = canonical_associated,
                    .operation_bindings = operations,
                    .source = failure.source,
                });
            }
        }
    }

    fn prepareOperationBindings(self: *Resolver, module_index: usize, located: LocatedContractDefinition, conformance: parameterized_storage.ContractConformance, failure: *ParticipantConformanceFailure) !primitives.Range(global_sg.ContractOperationBindingId) {
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        const required_storage = &self.modules[located.module_index].semantic.parameterized_storage;
        const requirements = required_storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len];
        const supplied = storage.contract_operations.items[conformance.operations.start..][0..conformance.operations.len];
        for (supplied) |operation| {
            const name = self.modules[module_index].text(operation.name);
            var found = false;
            for (requirements) |requirement| if (std.mem.eql(u8, name, self.modules[located.module_index].text(requirement.name))) {
                found = true;
                break;
            };
            if (!found) {
                failure.source = self.sourceFor(module_index, operation.source);
                failure.operation = name;
                failure.reason = "unknown implementation operation";
                return error.InvalidContractConformance;
            }
        }
        var functions: std.ArrayList(global_sg.ContractOperationBinding) = .empty;
        defer functions.deinit(self.allocator);
        for (requirements, 0..) |requirement, requirement_index| {
            const name = self.modules[located.module_index].text(requirement.name);
            const operation = for (supplied) |operation| {
                if (std.mem.eql(u8, name, self.modules[module_index].text(operation.name))) break operation;
            } else {
                failure.operation = name;
                failure.reason = "missing implementation operation";
                return error.InvalidContractConformance;
            };
            failure.operation = name;
            const declaration = self.resolveDeclarationRef(module_index, operation.function, .function) catch |err| {
                failure.source = self.sourceFor(module_index, operation.source);
                failure.reason = switch (err) {
                    error.UnknownGlobalDeclaration => "unknown or inaccessible implementation function",
                    error.AmbiguousGlobalDeclaration => "implementation operation must identify one ordinary function",
                    else => return err,
                };
                return error.InvalidContractConformance;
            };
            try functions.append(self.allocator, .{
                .contract_declaration = globalizer.globalDecl(self.offsets[located.module_index], located.definition.declaration),
                .requirement_index = @intCast(requirement_index),
                .requirement_source = self.sourceFor(located.module_index, requirement.source),
                .implementation_source = self.sourceFor(module_index, operation.source),
                .alias_source = switch (operation.function) {
                    .external => |external| self.sourceFor(module_index, self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)].source),
                    .module => null,
                },
                .name = try self.graph.addString(self.allocator, name),
                .declaration = declaration,
                .instantiate_associated = operation.instantiate_associated,
            });
        }
        const start: u32 = @intCast(self.graph.contract_operation_bindings.items.len);
        try self.graph.contract_operation_bindings.appendSlice(self.allocator, functions.items);
        return .{ .start = start, .len = @intCast(functions.items.len) };
    }

    fn resolveOperationBinding(self: *Resolver, conformance: global_sg.ContractConformance, index: usize) !global_sg.GlobalFunctionId {
        if (index < conformance.operations.len)
            return self.graph.function_refs.items[conformance.operations.start + index];
        const method = try self.resolveOperationBody(conformance, index);
        if (standard_contracts.standardDeclaration(self.graph, "Deinit") == conformance.declaration)
            return self.makeDestructorOperation(method, try self.core.functionOutputType(method), conformance.source);
        return method;
    }

    fn resolveOperationBody(self: *Resolver, conformance: global_sg.ContractConformance, index: usize) !global_sg.GlobalFunctionId {
        const binding = self.graph.contract_operation_bindings.items[conformance.operation_bindings.start + index];
        if (self.graph.declaration(binding.declaration).function_id) |function| {
            return function;
        }
        if (!binding.instantiate_associated) {
            const located = self.findContractDefinition(conformance.declaration) orelse return error.InvalidContractDeclaration;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, conformance.participants, &bindings);
            try self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, conformance.associated_arguments, &bindings);
            const requirement = storage.contract_requirements.items[located.definition.requirements.start + index];
            const input = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings);
            const instantiate_alias = self.instantiate_alias orelse return error.MissingOperationInstantiator;
            return instantiate_alias(self.function_context.?, binding.declaration, input) catch |err| {
                if (err == error.OutOfMemory) return err;
                // Preserve a dependency's specific failure instead of masking
                // it behind an alias-specialization error.
                if (err == error.InvalidContractOperation and self.participant_conformance_failure != null) return err;
                self.participant_conformance_failure = .{
                    .source = conformance.source,
                    .contract_name = self.modules[located.module_index].text(self.modules[located.module_index].declarations.items[@intFromEnum(located.definition.declaration)].name),
                    .operation = self.modules[located.module_index].text(requirement.name),
                    .reason = switch (err) {
                        error.OperationAliasMissingParameter => "generic operation alias parameters must be inferred from the selected input signature",
                        error.OperationAliasInputMismatch => "the selected input signature does not match the generic operation alias",
                        error.OperationAliasConstraintMismatch => "the selected input signature does not satisfy the generic operation alias bounds",
                        else => "the generic operation alias body could not be specialized for the selected input signature",
                    },
                };
                return error.InvalidContractOperation;
            };
        }
        const instantiate = self.instantiate_function orelse return error.MissingOperationInstantiator;
        if (conformance.implementation_arguments.len == 0)
            return instantiate(self.function_context.?, binding.declaration, conformance.associated_arguments);
        var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        try arguments.appendSlice(self.allocator, self.graph.generic_arguments.items[conformance.implementation_arguments.start..][0..conformance.implementation_arguments.len]);
        try arguments.appendSlice(self.allocator, self.graph.generic_arguments.items[conformance.associated_arguments.start..][0..conformance.associated_arguments.len]);
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);
        return instantiate(self.function_context.?, binding.declaration, .{ .start = start, .len = @intCast(arguments.items.len) });
    }

    pub fn validateParticipantConformances(self: *Resolver) !void {
        var index: usize = 0;
        // Validating an operation body can select evidence for a dependency.
        // Include those new entries in this pass rather than publishing calls
        // whose selected conformance has never been checked.
        while (index < self.graph.contract_conformances.items.len) : (index += 1) {
            const conformance = self.graph.contract_conformances.items[index];
            if (conformance.operations.len != 0) continue;
            const module_index: usize = @intFromEnum(conformance.context);
            const located = self.findContractDefinition(conformance.declaration) orelse return error.InvalidContractDeclaration;
            if (!located.definition.hasExplicitParticipants()) continue;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, conformance.participants, &bindings);
            try self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, conformance.associated_arguments, &bindings);
            var failure: ParticipantConformanceFailure = .{
                .source = conformance.source,
                .contract_name = self.modules[located.module_index].text(self.modules[located.module_index].declarations.items[@intFromEnum(located.definition.declaration)].name),
                .reason = "",
            };
            if (located.module_index != module_index and
                !(self.modules[module_index].is_bundled_core and self.modules[located.module_index].is_bundled_core))
            {
                var owns_participant = false;
                for (self.graph.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len]) |argument| {
                    if (global_types.conformanceParticipantOwner(self.graph, argument.value.type)) |owner|
                        if (@intFromEnum(owner) == module_index) {
                            owns_participant = true;
                            break;
                        };
                }
                if (!owns_participant) {
                    for (self.graph.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len]) |argument| {
                        if (self.graph.isTypeUnresolved(argument.value.type)) {
                            failure.reason = "an implementation participant type is unknown or unresolved";
                            self.participant_conformance_failure = failure;
                            return;
                        }
                    }
                    failure.reason = "an implementation must belong to the contract module or a nominal participant module";
                    self.participant_conformance_failure = failure;
                    return;
                }
            }
            inline for (.{ located.definition.participants, located.definition.parameters }) |parameters| {
                for (parameters.start..parameters.start + parameters.len) |raw| {
                    const parameter = storage.comptime_parameters.items[raw];
                    if (parameter.constraint) |constraint| {
                        if (!try self.inferConstraintBindings(located.module_index, constraint, bindings.types[raw].?, &bindings)) {
                            failure.reason = "a participant or associated type does not satisfy its declared bound";
                            self.participant_conformance_failure = failure;
                            return;
                        }
                    }
                }
            }
            // Dependencies preserve the referenced contract's operation identity.
            // A conformance proves those dependencies; it does not copy their
            // operations into its own namespace or accept replacement members.
            for (0..located.definition.composition.len) |position| {
                const constraint: parameterized_storage.ContractConstraintId = @enumFromInt(located.definition.composition.start + @as(u32, @intCast(position)));
                const participant = self.graph.generic_arguments.items[conformance.participants.start].value.type;
                if (!try self.inferConstraintBindings(located.module_index, constraint, participant, &bindings)) {
                    failure.reason = "a required contract dependency is not satisfied";
                    self.participant_conformance_failure = failure;
                    return;
                }
            }
            // Projection resolution can make initially distinct holes identical.
            // Recheck uniqueness before evidence becomes an accepted proof.
            for (self.graph.contract_conformances.items[0..index]) |previous| {
                if (previous.declaration != conformance.declaration) continue;
                var equal = true;
                for (0..conformance.participants.len) |position| {
                    const actual = self.graph.generic_arguments.items[conformance.participants.start + position].value.type;
                    const old = self.graph.generic_arguments.items[previous.participants.start + position].value.type;
                    if (!global_types.equal(self.graph, actual, old)) {
                        equal = false;
                        break;
                    }
                }
                if (equal) {
                    failure.reason = "ambiguous conformances for the same participant tuple";
                    self.participant_conformance_failure = failure;
                    return;
                }
            }
            var operations: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer operations.deinit(self.allocator);
            const first = bindings.types[located.definition.participants.start].?;
            for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, operation_index| {
                const name = self.modules[located.module_index].text(requirement.name);
                const input = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings);
                const output = try self.generics.instantiateParameterizedType(located.module_index, requirement.output, &bindings);
                const selected: MethodSelection = selected: {
                    const method = try self.resolveOperationBinding(conformance, operation_index);
                    const function = self.graph.function(method);
                    const required_inputs = global_types.fields(self.graph, input).?;
                    const required_outputs = global_types.fields(self.graph, output).?;
                    if (!self.inputFieldsSatisfyRequirement(required_inputs, function.input)) break :selected .missing;
                    for (0..required_inputs.len) |position| {
                        if (!std.mem.eql(u8, self.graph.text(self.graph.fields.items[required_inputs.start + position].name), self.graph.text(self.graph.fields.items[function.input.start + position].name))) break :selected .missing;
                    }
                    if (required_outputs.len != function.output.len) break :selected .incompatible_output;
                    for (0..required_outputs.len) |position| {
                        const required = self.graph.fields.items[required_outputs.start + position];
                        const actual = self.graph.fields.items[function.output.start + position];
                        if (!global_types.equal(self.graph, required.ty, actual.ty) or !std.mem.eql(u8, self.graph.text(required.name), self.graph.text(actual.name))) break :selected .incompatible_output;
                    }
                    break :selected .{ .function = method };
                };
                if (selected != .function) {
                    failure.operation = name;
                    failure.input = input;
                    failure.output = output;
                    failure.reason = switch (selected) {
                        .missing => "implementation operation has an incompatible input signature",
                        .ambiguous => "ambiguous operation",
                        .incompatible_output => if (standard_contracts.standardDeclaration(self.graph, "Equal") == conformance.declaration) "Equal.equal must return exactly (.ok: Bool)" else "operation returns an incompatible associated result",
                        .function => unreachable,
                    };
                    self.participant_conformance_failure = failure;
                    return;
                }
                if (standard_contracts.standardDeclaration(self.graph, "Init") == conformance.declaration) {
                    const required_inputs = global_types.fields(self.graph, input).?;
                    const required_outputs = global_types.fields(self.graph, output).?;
                    const arguments = self.graph.fields.items[required_inputs.start].ty;
                    _ = try self.generics.ensureGenericInstance(arguments);
                    if (global_types.fields(self.graph, arguments) == null) {
                        failure.reason = "Init.Args must be a record type describing construction arguments";
                        self.participant_conformance_failure = failure;
                        return;
                    }
                    const result = self.graph.fields.items[required_outputs.start].ty;
                    if (!self.graph.isTypeUnresolved(result) and !global_types.resultMatchesTarget(self.graph, result, first)) {
                        failure.reason = "Init.Result must be its participant type or one Errable containing that type";
                        self.participant_conformance_failure = failure;
                        return;
                    }
                }

                if (standard_contracts.standardDeclaration(self.graph, "Convert") == conformance.declaration) {
                    const required_outputs = global_types.fields(self.graph, output).?;
                    const result = self.graph.fields.items[required_outputs.start].ty;
                    const target = self.graph.generic_arguments.items[conformance.participants.start + 1].value.type;
                    if (!self.graph.isTypeUnresolved(result) and !global_types.resultMatchesTarget(self.graph, result, target)) {
                        failure.reason = "Convert.Result must be its target participant type or one Errable containing that type";
                        self.participant_conformance_failure = failure;
                        return;
                    }
                }

                try self.recordStaticSafetyContract(located, requirement, &bindings, first, selected.function, output, failure.source);
                try operations.append(self.allocator, selected.function);
            }
            const operation_start: u32 = @intCast(self.graph.function_refs.items.len);
            try self.graph.function_refs.appendSlice(self.allocator, operations.items);
            self.graph.contract_conformances.items[index].operations = .{ .start = operation_start, .len = @intCast(operations.items.len) };
        }
    }

    fn makeDestructorOperation(self: *Resolver, body: global_sg.GlobalFunctionId, output: global_sg.GlobalTypeId, source: primitives.SourceRef) !global_sg.GlobalFunctionId {
        // Reusing an ordinary function must not change its safety effects.
        // The wrapper is selected before publishing any static operation call.
        for (self.graph.functions.items, 0..) |candidate, raw| {
            if (!candidate.flags.is_deinit or candidate.declaration != self.graph.function(body).declaration) continue;
            const block = self.graph.blocks.items[@intFromEnum(candidate.body orelse continue)];
            if (block.nodes.len != 1) continue;
            const node = self.graph.node(self.graph.node_refs.items[block.nodes.start]);
            if (node.content == .function_call and node.content.function_call.callee == body)
                return @enumFromInt(@as(u32, @intCast(raw)));
        }
        const function = self.graph.function(body);
        // Optional/reached capabilities remain logical inputs of the operation.
        // Invalid signatures are rejected by ordinary conformance validation.
        if (function.input.len == 0 or function.output.len != 0) return body;
        const binding_start: u32 = @intCast(self.graph.binding_refs.items.len);
        var visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer visible.deinit(self.allocator);
        var values: std.ArrayList(global_sg.ValueField) = .empty;
        defer values.deinit(self.allocator);
        const fields = try self.allocator.dupe(global_sg.Field, self.graph.fields.items[function.input.start..][0..function.input.len]);
        defer self.allocator.free(fields);
        for (fields) |field| {
            const binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.graph.bindings.items.len)));
            try self.graph.bindings.append(self.allocator, .{ .name = field.name, .source = source, .ty = field.ty, .mutability = .constant });
            try self.graph.binding_refs.append(self.allocator, binding);
            try visible.append(self.allocator, binding);
            const value: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
            try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = field.ty, .content = .{ .binding_use = binding } });
            try values.append(self.allocator, .{ .name = field.name, .value = value });
        }
        const value_start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.appendSlice(self.allocator, values.items);
        const input_type = try self.generics.internType(.{ .structural = .{ .fields = function.input } });
        const input: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = input_type, .content = .{ .struct_value_literal = .{ .fields = .{ .start = value_start, .len = function.input.len } } } });
        const call: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = output, .content = .{ .function_call = .{ .callee = body, .input = input } } });
        const node_start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.append(self.allocator, call);
        const block: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.graph.blocks.items.len)));
        try self.graph.blocks.append(self.allocator, .{ .nodes = .{ .start = node_start, .len = 1 } });
        const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(self.graph.functions.items.len)));
        try self.graph.functions.append(self.allocator, .{
            .declaration = function.declaration,
            .input = function.input,
            .output = function.output,
            .body = block,
            .input_bindings = .{ .start = binding_start, .len = function.input.len },
            .flags = .{ .is_deinit = true, .has_declared_body = true, .is_generic_instantiation = true },
        });
        // Function/operator metadata shares FunctionId indexing, including
        // synthetic lifecycle bodies that do not represent an operator.
        try self.core.trackReachedCall(body, input, reach_context.Context.fromGlobal(visible.items, id), false);
        return id;
    }

    pub fn resolveAssociatedType(context: *anyopaque, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef) anyerror!global_sg.GlobalTypeId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        return (try self.resolveAssociatedElement(base, member, source, true)).type;
    }

    pub fn resolveAssociatedInt(context: *anyopaque, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef) anyerror!i64 {
        const self: *Resolver = @ptrCast(@alignCast(context));
        return (try self.resolveAssociatedElement(base, member, source, false)).comptime_int;
    }

    fn resolveAssociatedElement(self: *Resolver, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef, want_type: bool) anyerror!global_sg.GenericArgument.Value {
        if (self.graph.isTypeUnresolved(base)) return error.UnresolvedAssociatedType;
        const generic = switch (self.graph.types.items[@intFromEnum(base)]) {
            .generic => |value| value,
            else => return self.associatedProjectionError(want_type, source, "associated projection requires a participant contract", member),
        };
        const located = self.findContractDefinition(generic.base) orelse
            return self.associatedProjectionError(want_type, source, "associated projection requires a participant contract", member);
        if (!located.definition.hasExplicitParticipants())
            return self.associatedProjectionError(want_type, source, "associated projection requires explicit contract participants", member);
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        self.generics.bindGlobalArguments(located.module_index, located.definition.participants, generic.arguments, &bindings) catch |err| {
            return self.associatedProjectionError(want_type, source, conformanceArgumentFailure(err) orelse return err, member);
        };
        for (located.definition.participants.start..located.definition.participants.start + located.definition.participants.len) |raw| {
            if (!self.typeSelectionReady(bindings.types[raw].?, 0)) return error.UnresolvedAssociatedType;
        }
        var position: ?usize = null;
        for (0..located.definition.parameters.len) |i| {
            const parameter = storage.comptime_parameters.items[located.definition.parameters.start + i];
            if (std.mem.eql(u8, self.modules[located.module_index].text(parameter.name), member)) {
                if ((parameter.kind == .type) != want_type) return self.associatedProjectionError(want_type, source, if (want_type) "associated element is not a type" else "associated element is not an integer constant", member);
                position = i;
                break;
            }
        }
        const associated_index = position orelse return self.associatedProjectionError(want_type, source, if (want_type) "unknown associated type" else "unknown associated constant", member);
        var participants: std.ArrayList(global_sg.GlobalTypeId) = .empty;
        defer participants.deinit(self.allocator);
        for (located.definition.participants.start..located.definition.participants.start + located.definition.participants.len) |raw|
            try participants.append(self.allocator, bindings.types[raw].?);
        var deferred = false;
        if (try self.selectConformance(generic.base, participants.items, &bindings, 0, &deferred)) |selection| {
            const conformance = self.graph.contract_conformances.items[selection.tuple];
            const result = self.graph.generic_arguments.items[conformance.associated_arguments.start + associated_index].value;
            if (result == .type and !self.typeSelectionReady(result.type, 0)) return error.UnresolvedAssociatedType;
            return result;
        }
        if (deferred) return error.UnresolvedAssociatedType;
        return self.associatedProjectionError(want_type, source, "no conformance for the projected participant tuple", member);
    }

    fn typeSelectionReady(self: *const Resolver, ty: global_sg.GlobalTypeId, depth: usize) bool {
        if (depth > 128 or self.graph.isTypeUnresolved(ty)) return false;
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .pointer => |value| self.typeSelectionReady(value.child, depth + 1),
            .array => |value| self.typeSelectionReady(value.element, depth + 1),
            .nullable, .inferred_errable, .virtual => |child| self.typeSelectionReady(child, depth + 1),
            .generic => |value| blk: {
                for (self.graph.generic_arguments.items[value.arguments.start..][0..value.arguments.len]) |argument| {
                    if (argument.value == .type and !self.typeSelectionReady(argument.value.type, depth + 1)) break :blk false;
                }
                break :blk true;
            },
            .structural => |value| blk: {
                for (self.graph.fields.items[value.fields.start..][0..value.fields.len]) |field|
                    if (!self.typeSelectionReady(field.ty, depth + 1)) break :blk false;
                break :blk true;
            },
            .structural_choice => |value| blk: {
                for (self.graph.variants.items[value.variants.start..][0..value.variants.len]) |variant|
                    if (variant.payload_type) |child| if (!self.typeSelectionReady(child, depth + 1)) break :blk false;
                break :blk true;
            },
            else => true,
        };
    }

    fn associatedProjectionError(self: *Resolver, want_type: bool, source: primitives.SourceRef, reason: []const u8, member: []const u8) error{InvalidAssociatedTypeProjection} {
        self.participant_conformance_failure = .{ .is_projection = true, .is_value_projection = !want_type, .source = source, .contract_name = member, .reason = reason };
        return error.InvalidAssociatedTypeProjection;
    }

    fn projectionError(self: *Resolver, source: primitives.SourceRef, reason: []const u8, member: []const u8) error{InvalidAssociatedTypeProjection} {
        self.participant_conformance_failure = .{ .is_projection = true, .source = source, .contract_name = member, .reason = reason };
        return error.InvalidAssociatedTypeProjection;
    }

    pub fn resolveAssociatedTypes(self: *Resolver) !void {
        var remaining: usize = 0;
        while (true) {
            var changed = false;
            remaining = 0;
            for (self.modules, 0..) |*module, module_index| {
                const o = self.offsets[module_index];
                for (0..module_views.typeCount(module)) |raw| {
                    const local: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
                    const value = try module_views.typeView(module, local);
                    const external = switch (value) {
                        .external => |id| id,
                        else => continue,
                    };
                    const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                    if (reference.projection_base == null and reference.computed_type == null) continue;
                    const destination = globalizer.globalType(o, local);
                    if (!self.graph.isTypeUnresolved(destination)) continue;
                    const result = (if (reference.computed_type) |computed| blk: {
                        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
                        defer bindings.deinit(self.allocator);
                        break :blk self.generics.instantiateParameterizedType(module_index, computed, &bindings);
                    } else resolveAssociatedType(self, globalizer.globalType(o, reference.projection_base.?), module.text(reference.name), self.sourceFor(module_index, reference.source))) catch |err| switch (err) {
                        error.UnresolvedAssociatedType => {
                            remaining += 1;
                            continue;
                        },
                        else => return err,
                    };
                    try self.graph.resolveType(destination, self.graph.types.items[@intFromEnum(result)]);
                    changed = true;
                }
            }
            if (remaining == 0) return;
            if (!changed) {
                for (self.modules, 0..) |*module, module_index| {
                    for (0..module_views.typeCount(module)) |raw| {
                        const local: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
                        const value = try module_views.typeView(module, local);
                        const external = switch (value) {
                            .external => |id| id,
                            else => continue,
                        };
                        const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                        if ((reference.projection_base == null and reference.computed_type == null) or !self.graph.isTypeUnresolved(globalizer.globalType(self.offsets[module_index], local))) continue;
                        return self.projectionError(self.sourceFor(module_index, reference.source), "cyclic or unresolved associated type projection", module.text(reference.name));
                    }
                }
                unreachable;
            }
        }
    }

    pub fn constraintDeclaration(
        self: *Resolver,
        module_index: usize,
        constraint_id: parameterized_storage.ContractConstraintId,
    ) !global_sg.GlobalDeclId {
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        const constraint = storage.contract_constraints.items[@intFromEnum(constraint_id)];
        const key = ConstraintKey{ .module_index = @intCast(module_index), .constraint = constraint_id };
        return self.constraint_declarations.get(key) orelse blk: {
            const resolved = try self.resolveDeclarationRef(module_index, constraint.contract_ref, .contract_type);
            try self.constraint_declarations.put(self.allocator, key, resolved);
            break :blk resolved;
        };
    }

    pub fn constraintArgumentsKnown(self: *Resolver, module_index: usize, constraint_id: parameterized_storage.ContractConstraintId, bindings: *generic_mod.Resolver.Bindings) !bool {
        const constraint = self.modules[module_index].semantic.parameterized_storage.contract_constraints.items[@intFromEnum(constraint_id)];
        const definition = self.findContractDefinition(try self.constraintDeclaration(module_index, constraint_id)) orelse return false;
        if (!definition.definition.hasExplicitParticipants()) return false;
        _ = self.generics.instantiateParameterizedArguments(module_index, constraint.arguments, bindings) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
        return true;
    }

    pub fn inferConstraintBindings(
        self: *Resolver,
        module_index: usize,
        constraint_id: parameterized_storage.ContractConstraintId,
        concrete: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage;
        const constraint = storage.contract_constraints.items[@intFromEnum(constraint_id)];
        const contract_decl = try self.constraintDeclaration(module_index, constraint_id);
        const definition = self.findContractDefinition(contract_decl) orelse return false;
        if (!definition.definition.hasExplicitParticipants()) return false;
        if (constraint.arguments.len == 0 and definition.definition.participants.len == 1)
            return self.implementsDepth(concrete, contract_decl, 0);
        return self.inferParticipantConstraint(module_index, constraint, concrete, definition, contract_decl, bindings);
    }

    // Participants select evidence first. Named associated restrictions compare
    // against that evidence; they never participate in choosing an implementation.
    fn inferParticipantConstraint(self: *Resolver, module_index: usize, constraint: parameterized_storage.ContractConstraint, concrete: global_sg.GlobalTypeId, located: LocatedContractDefinition, declaration: global_sg.GlobalDeclId, bindings: *generic_mod.Resolver.Bindings) !bool {
        const module = &self.modules[module_index];
        const target_module = &self.modules[located.module_index];
        const parameters = target_module.semantic.parameterized_storage.comptime_parameters.items;
        const requested = module.semantic.parameterized_storage.ir.generic_arguments.items[constraint.arguments.start..][0..constraint.arguments.len];
        var selected = try generic_mod.Resolver.Bindings.init(self.allocator, parameters.len);
        defer selected.deinit(self.allocator);
        const participants = try self.allocator.alloc(global_sg.GlobalTypeId, located.definition.participants.len);
        defer self.allocator.free(participants);
        for (requested, 0..) |argument, position| {
            const name = module.text(argument.name);
            var participant: ?u32 = null;
            for (0..located.definition.participants.len) |index| {
                const raw = located.definition.participants.start + @as(u32, @intCast(index));
                if ((name.len == 0 and index == position) or std.mem.eql(u8, name, target_module.text(parameters[raw].name))) participant = raw;
            }
            if (participant) |raw| {
                if (argument.value != .type or selected.types[raw] != null) return false;
                selected.types[raw] = self.generics.instantiateParameterizedType(module_index, argument.value.type, bindings) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    return false;
                };
            } else {
                var associated = false;
                for (parameters[located.definition.parameters.start..][0..located.definition.parameters.len]) |parameter|
                    if (name.len != 0 and std.mem.eql(u8, name, target_module.text(parameter.name))) {
                        associated = true;
                        break;
                    };
                if (!associated) return false;
            }
        }
        for (participants, 0..) |*participant, position| {
            const raw = located.definition.participants.start + @as(u32, @intCast(position));
            participant.* = selected.types[raw] orelse if (participants.len == 1) concrete else return false;
        }
        // Unary virtual types carry their fixed interface's selected evidence.
        // Associated virtual interfaces still require their representation work.
        if (participants.len == 1 and self.graph.semanticType(participants[0]) == .virtual)
            return located.definition.parameters.len == 0 and try self.implementsDepth(participants[0], declaration, 0);
        if (try self.selectConformance(declaration, participants, &selected, 0, null) == null) return false;
        for (requested) |argument| {
            const name = module.text(argument.name);
            for (0..located.definition.parameters.len) |index| {
                const raw = located.definition.parameters.start + @as(u32, @intCast(index));
                if (name.len == 0 or !std.mem.eql(u8, name, target_module.text(parameters[raw].name))) continue;
                switch (argument.value) {
                    .type => |pattern| if (!try self.inferConstraintTypePattern(module_index, pattern, selected.types[raw] orelse return false, bindings)) return false,
                    .comptime_int => |pattern| if (!try self.inferConstraintIntPattern(module_index, pattern, selected.ints[raw] orelse return false, bindings)) return false,
                }
            }
        }
        return true;
    }

    pub fn inferConstraintTypePattern(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        actual: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const ir_storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        switch (ir_storage.types.items[@intFromEnum(pattern)]) {
            .parameter => |parameter| {
                const slot = &bindings.types[@intFromEnum(parameter)];
                if (slot.*) |previous|
                    return global_types.equal(self.graph, previous, actual);
                slot.* = actual;
                return true;
            },
            .resolved => |resolved| switch (resolved) {
                .pointer => |pointer| {
                    const actual_pointer = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .pointer => |value| value,
                        else => return false,
                    };
                    if (pointer.mutability != actual_pointer.mutability) return false;
                    return self.inferConstraintTypePattern(module_index, pointer.child, actual_pointer.child, bindings);
                },
                .structural => |record| {
                    const actual_record = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .structural => |value| value,
                        else => return false,
                    };
                    if (record.fields.len != actual_record.fields.len) return false;
                    for (ir_storage.fields.items[record.fields.start..][0..record.fields.len], self.graph.fields.items[actual_record.fields.start..][0..actual_record.fields.len]) |wanted, given| {
                        if (!std.mem.eql(u8, self.modules[module_index].text(wanted.name), self.graph.text(given.name))) return false;
                        if (!try self.inferConstraintTypePattern(module_index, wanted.ty, given.ty, bindings)) return false;
                    }
                    return true;
                },
                .generic => |nominal| {
                    const concrete = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .generic => |value| value,
                        else => return false,
                    };
                    const declaration = try self.generics.resolveParameterizedDeclaration(module_index, nominal.base);
                    if (declaration != concrete.base) return false;
                    const located = self.generics.findTypeParameterized(declaration) orelse return false;
                    if (nominal.arguments.len != located.parameterized.parameters.len or concrete.arguments.len != nominal.arguments.len) return false;
                    for (0..located.parameterized.parameters.len) |position| {
                        const parameter = self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items[located.parameterized.parameters.start + position];
                        const name = self.modules[located.module_index].text(parameter.name);
                        const wanted = self.generics.findPatternArgument(module_index, nominal.arguments, position, name) orelse return false;
                        const given = self.generics.findGlobalArgument(name, concrete.arguments, position) orelse return false;
                        if (wanted.value == .type and given.value == .type) {
                            if (!try self.inferConstraintTypePattern(module_index, wanted.value.type, given.value.type, bindings)) return false;
                        } else if (wanted.value == .comptime_int and given.value == .comptime_int) {
                            if (!try self.inferConstraintIntPattern(module_index, wanted.value.comptime_int, given.value.comptime_int, bindings)) return false;
                        } else return false;
                    }
                    return true;
                },
                else => {},
            },
            .array => |array| {
                const actual_array = switch (self.graph.types.items[@intFromEnum(actual)]) {
                    .array => |value| value,
                    else => return false,
                };
                if (!try self.inferConstraintIntPattern(module_index, array.length, @intCast(actual_array.length), bindings))
                    return false;
                return self.inferConstraintTypePattern(module_index, array.element, actual_array.element, bindings);
            },
            else => {},
        }
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch return false;
        return global_types.equal(self.graph, expected, actual);
    }

    fn inferConstraintIntPattern(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedIntExprId,
        actual: i64,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const ir_storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        return switch (ir_storage.int_expressions.items[@intFromEnum(pattern)]) {
            .literal => |value| value == actual,
            .parameter => |parameter| blk: {
                const slot = &bindings.ints[@intFromEnum(parameter)];
                if (slot.*) |previous| break :blk previous == actual;
                slot.* = actual;
                break :blk true;
            },
            .binary, .projection => (self.generics.evalInt(module_index, pattern, bindings) catch return false) == actual,
        };
    }

    pub fn implements(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        contract_decl: global_sg.GlobalDeclId,
    ) !bool {
        self.stats.checks += 1;
        return self.implementsDepth(concrete, contract_decl, 0);
    }

    pub fn typeContractUse(self: *const Resolver, ty: global_sg.GlobalTypeId) ?ContractUse {
        return self.contractUse(ty);
    }

    pub fn runtimeBindingContract(self: *const Resolver, binding_id: global_sg.GlobalBindingId) ?ContractUse {
        if (self.isFunctionInterfaceBinding(binding_id)) return null;
        const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
        if (self.graph.isBindingTypeUnresolved(binding_id) or self.graph.isTypeUnresolved(binding.ty)) return null;
        return self.contractUse(binding.ty);
    }

    fn contractUse(self: *const Resolver, ty: global_sg.GlobalTypeId) ?ContractUse {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .declared => |declaration| if (self.findContractDefinition(declaration) != null)
                .{ .declaration = declaration, .arguments = .{ .start = 0, .len = 0 } }
            else
                null,
            .generic => |generic| if (self.findContractDefinition(generic.base) != null)
                .{ .declaration = generic.base, .arguments = generic.arguments }
            else
                null,
            else => null,
        };
    }

    fn isFunctionInterfaceBinding(self: *const Resolver, binding_id: global_sg.GlobalBindingId) bool {
        for (self.graph.functions.items) |function| {
            for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |candidate|
                if (candidate == binding_id) return true;
            for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |candidate|
                if (candidate == binding_id) return true;
        }
        return false;
    }

    pub fn validateGenericFunctionInstances(self: *Resolver) !void {
        for (self.graph.generic_function_instances.items) |instance| {
            const owner = self.graph.moduleForDeclaration(instance.parameterized_declaration) orelse return error.InvalidGenericFunctionOwner;
            const module_index: usize = @intFromEnum(owner);
            const parameterized = self.findFunctionParameterized(module_index, instance.parameterized_declaration) orelse {
                continue;
            };
            const module = &self.modules[module_index];
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            try self.generics.bindGlobalArguments(module_index, parameterized.parameters, instance.arguments, &bindings);

            for (0..parameterized.parameters.len) |offset| {
                const param_raw = parameterized.parameters.start + @as(u32, @intCast(offset));
                const parameter = module.semantic.parameterized_storage.comptime_parameters.items[param_raw];
                const constraint_id = parameter.constraint orelse continue;
                const concrete = bindings.types[param_raw] orelse return error.ContractConstraintRequiresTypeParameter;
                const satisfied = try self.inferConstraintBindings(module_index, constraint_id, concrete, &bindings);
                if (!satisfied) return error.GenericContractConstraintNotSatisfied;
            }
        }
    }

    /// Bind each virtual contract to its fixed signature. Implementation lists
    /// describe runtime reachability and once obligations, not safety effects:
    /// Safety generates dispatch summaries from the declaration and checks
    /// each selected concrete method independently.
    pub fn closeVirtualMethodRegistries(self: *Resolver) !void {
        for (self.graph.virtualizes.items) |virtualize| {
            const registries = self.graph.virtual_registry_refs.items[virtualize.safety_methods.start..][0..virtualize.safety_methods.len];
            for (registries, 0..) |registry_id, method_index|
                try self.closeVirtualMethodRegistry(registry_id, self.graph.semanticType(virtualize.virtual_type).virtual, method_index);
        }

        for (self.graph.virtual_calls.items) |call| {
            const contract_ty = self.virtualCallContract(call) orelse continue;
            try self.closeVirtualMethodRegistry(call.safety_methods, contract_ty, call.method_index);
        }
    }

    fn closeVirtualMethodRegistry(
        self: *Resolver,
        registry_id: global_sg.GlobalVirtualRegistryId,
        contract_ty: global_sg.GlobalTypeId,
        method_index: usize,
    ) !void {
        const use = self.contractUse(contract_ty) orelse return error.InvalidVirtualContract;
        const located = self.findContractDefinition(use.declaration) orelse return error.InvalidVirtualContract;
        const requirement = self.modules[located.module_index].semantic.parameterized_storage.contract_requirements.items[located.definition.requirements.start + method_index];
        if (requirement.safety_contract) |declared| {
            const instance = (try self.requirementInstanceForContractUse(use, contract_ty, located, requirement, @intCast(method_index))) orelse return error.InvalidContractRequirement;
            self.graph.virtual_registries.items[@intFromEnum(registry_id)].safety_contract = try self.globalSafetyContract(located.module_index, declared, global_types.fields(self.graph, instance.input) orelse return error.InvalidContractRequirementInput, instance.output);
        }

        var implementations: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
        defer implementations.deinit(self.allocator);

        for (self.graph.virtualizes.items) |candidate| {
            if (!global_types.equal(self.graph, self.graph.semanticType(candidate.virtual_type).virtual, contract_ty) or method_index >= candidate.methods.len) continue;
            const implementation = self.graph.function_refs.items[candidate.methods.start + @as(u32, @intCast(method_index))];
            var exists = false;
            for (implementations.items) |existing| if (existing == implementation) {
                exists = true;
                break;
            };
            if (exists) continue;
            try implementations.append(self.allocator, implementation);
        }

        const start: u32 = @intCast(self.graph.function_refs.items.len);
        try self.graph.function_refs.appendSlice(self.allocator, implementations.items);
        self.graph.virtual_registries.items[@intFromEnum(registry_id)].implementations = .{
            .start = start,
            .len = @intCast(implementations.items.len),
        };
        if (requirement.safety_contract != null) {
            const instance = (try self.requirementInstanceForContractUse(use, contract_ty, located, requirement, @intCast(method_index))) orelse return error.InvalidContractRequirement;
            const input = try self.virtualInputType(instance.input, instance.output);
            const fields = global_types.fields(self.graph, input) orelse return error.InvalidContractRequirementInput;
            self.graph.virtual_registries.items[@intFromEnum(registry_id)].contract_input_count = fields.len;
            self.graph.virtual_registries.items[@intFromEnum(registry_id)].contract_output_type = instance.output;
        }
    }

    fn globalSafetyOutcome(self: *Resolver, module_index: usize, outcome: *primitives.MethodSafetyContract.Outcome, choice_ty: global_sg.GlobalTypeId) anyerror!void {
        const name = self.modules[module_index].text(outcome.variant);
        const hit = global_types.findVariant(self.graph, choice_ty, name) orelse return error.UnknownOutcomeContractVariant;
        outcome.variant_index = hit.index;
        outcome.variant = hit.variant.name;
        outcome.source = self.sourceFor(module_index, outcome.source);
        const children = try self.allocator.dupe(primitives.MethodSafetyContract.Outcome, outcome.outcomes);
        for (children, 0..) |*child, index| {
            if (child.output_index != outcome.output_index) return error.InvalidOutcomeContract;
            try self.globalSafetyOutcome(module_index, child, hit.variant.payload_type orelse return error.InvalidOutcomeContract);
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
            .variants = try std.mem.concat(self.allocator, u32, &.{ ancestors, &.{hit.index} }),
        };
        const context = try std.mem.concat(self.allocator, SelectedContractChoice, &.{ parents, &.{selected} });
        const children = try self.allocator.dupe(primitives.MethodSafetyContract.Outcome, outcome.outcomes);
        for (children, 0..) |*child, child_index| {
            try self.globalGeneralOutcome(module_index, child, inputs, outputs, context);
            for (children[0..child_index]) |previous| if (previous.input_index == child.input_index and previous.output_index == child.output_index and previous.variant_index == child.variant_index) return error.DuplicateOutcomeContract;
        }
        outcome.outcomes = children;
    }

    fn globalSafetyContract(self: *Resolver, module_index: usize, declared: primitives.MethodSafetyContract, inputs: global_sg.FieldRange, output_type: global_sg.GlobalTypeId) !primitives.MethodSafetyContract {
        var contract = declared;
        contract.source = self.sourceFor(module_index, contract.source);
        if (declared.outcomes.len != 0) {
            const fields = global_types.fields(self.graph, output_type) orelse return error.InvalidContractRequirementOutput;
            const outcomes = try self.allocator.dupe(primitives.MethodSafetyContract.Outcome, declared.outcomes);
            for (outcomes, 0..) |*outcome, index| {
                if (declared.general_conditions) {
                    try self.globalGeneralOutcome(module_index, outcome, inputs, fields, &.{});
                    for (outcomes[0..index]) |previous| if (previous.input_index == outcome.input_index and previous.output_index == outcome.output_index and previous.variant_index == outcome.variant_index) return error.DuplicateOutcomeContract;
                    continue;
                }
                if (outcome.output_index >= fields.len) return error.InvalidOutcomeContract;
                const output_ty = self.graph.fields.items[fields.start + outcome.output_index].ty;
                try self.globalSafetyOutcome(module_index, outcome, output_ty);
                for (outcomes[0..index]) |previous| if (previous.output_index == outcome.output_index and previous.variant_index == outcome.variant_index) return error.DuplicateOutcomeContract;
            }
            contract.outcomes = outcomes;
        }
        return contract;
    }

    fn isUnaryReceiverParticipantType(self: *const Resolver, located: LocatedContractDefinition, ty: @import("../module/parameterized/ir.zig").ParameterizedTypeId) bool {
        // Identify the receiver from the requirement's symbolic participant,
        // never from coincident concrete argument types. Explicit unary
        // contracts identify receivers through their declared participant.
        const participant = if (located.definition.participants.len == 1)
            @as(ir.ComptimeParameterId, @enumFromInt(located.definition.participants.start))
        else
            return false;
        const value = self.modules[located.module_index].semantic.parameterized_storage.ir.types.items[@intFromEnum(ty)];
        return value == .parameter and value.parameter == participant;
    }

    fn recordStaticSafetyContract(self: *Resolver, located: LocatedContractDefinition, requirement: parameterized_storage.ContractRequirement, bindings: *generic_mod.Resolver.Bindings, concrete: global_sg.GlobalTypeId, method: global_sg.GlobalFunctionId, output: global_sg.GlobalTypeId, source: primitives.SourceRef) !void {
        const declared = requirement.safety_contract orelse return;
        if (self.fallibleOutput(output)) try self.core.ensureErrorTracerInput(method);
        const function = self.graph.function(method);
        if (try self.methodSafetyContractFailure(function.input, function.output, output, concrete, located, declared, false)) |reason| {
            self.virtual_signature_failure = .{ .source = source, .method_name = self.modules[located.module_index].text(requirement.name), .reason = reason, .static_contract = true };
            return;
        }
        const contract = self.globalSafetyContract(located.module_index, declared, function.input, output) catch |err| switch (err) {
            error.UnknownOutcomeContractVariant, error.DuplicateOutcomeContract, error.InvalidOutcomeContract => {
                self.virtual_signature_failure = .{
                    .source = source,
                    .static_contract = true,
                    .method_name = self.modules[located.module_index].text(requirement.name),
                    .reason = switch (err) {
                        error.UnknownOutcomeContractVariant => "outcome contract names an unknown output variant",
                        error.DuplicateOutcomeContract => "duplicate outcome contract",
                        else => "on requires a choice-valued output",
                    },
                };
                return;
            },
            else => return err,
        };
        for (self.graph.contract_safety_conformances.items) |existing| {
            if (existing.method == method and std.meta.eql(existing.contract.source, contract.source)) return;
        }
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (0..located.definition.parameters.len) |offset| {
            const raw = located.definition.parameters.start + @as(u32, @intCast(offset));
            const parameter = storage.comptime_parameters.items[raw];
            const name = try self.graph.addString(self.allocator, self.modules[located.module_index].text(parameter.name));
            try self.graph.generic_arguments.append(self.allocator, .{
                .name = name,
                .value = switch (parameter.kind) {
                    .type => .{ .type = bindings.types[raw] orelse return error.UnboundGenericTypeParameter },
                    .comptime_int => .{ .comptime_int = bindings.ints[raw] orelse return error.UnboundComptimeParameter },
                },
            });
        }
        const contract_decl = globalizer.globalDecl(self.offsets[located.module_index], located.definition.declaration);
        const use = ContractUse{ .declaration = contract_decl, .arguments = .{ .start = start, .len = located.definition.parameters.len } };
        const domains = if (located.definition.domains.len == 0) &.{} else (try self.resolveStorageDomains(use, concrete, located, source)) orelse return;
        var receiver: ?u32 = null;
        const input = storage.ir.types.items[@intFromEnum(requirement.input)].resolved.structural.fields;
        for (storage.ir.fields.items[input.start..][0..input.len], 0..) |field, index| {
            const ty = storage.ir.types.items[@intFromEnum(field.ty)];
            if (ty == .resolved and ty.resolved == .pointer and
                self.isUnaryReceiverParticipantType(located, ty.resolved.pointer.child))
            {
                receiver = @intCast(index);
                break;
            }
        }
        try self.graph.contract_safety_conformances.append(self.allocator, .{ .method = method, .contract = contract, .receiver_input_index = receiver, .domains = domains, .source = source });
    }

    fn virtualCallContract(self: *const Resolver, call: global_sg.VirtualCall) ?global_sg.GlobalTypeId {
        const handle_ty = self.graph.nodes.items[@intFromEnum(call.handle)].ty orelse return null;
        const handle_child = switch (self.graph.types.items[@intFromEnum(handle_ty)]) {
            .pointer => |pointer| pointer.child,
            else => handle_ty,
        };
        const handle_type = self.graph.semanticType(handle_child);
        if (handle_type == .virtual) return handle_type.virtual;
        if (self.contractUse(handle_child) != null) return handle_child;

        const input_fields = global_types.fields(self.graph, call.input_type) orelse return null;
        if (call.self_input_index >= input_fields.len) return null;
        const self_ty = self.graph.fields.items[input_fields.start + call.self_input_index].ty;
        const self_child = switch (self.graph.types.items[@intFromEnum(self_ty)]) {
            .pointer => |pointer| pointer.child,
            else => self_ty,
        };
        return if (self.contractUse(self_child) != null) self_child else null;
    }

    fn contractDeclFromType(self: *const Resolver, ty: global_sg.GlobalTypeId) ?global_sg.GlobalDeclId {
        const contract_ty = switch (self.graph.types.items[@intFromEnum(ty)]) {
            .virtual => |contract_type| contract_type,
            else => ty,
        };
        return switch (self.graph.types.items[@intFromEnum(contract_ty)]) {
            .declared => |declaration| if (self.findContractDefinition(declaration) != null) declaration else null,
            .generic => |generic| if (self.findContractDefinition(generic.base) != null) generic.base else null,
            else => null,
        };
    }

    pub fn validateParameterizedImplementationConstraints(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *generic_mod.Resolver.Bindings,
    ) anyerror!bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        var made_progress = true;
        while (made_progress) {
            made_progress = false;
            var before: usize = 0;
            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                before += switch (parameter.kind) {
                    .type => @intFromBool(bindings.types[raw] != null),
                    .comptime_int => @intFromBool(bindings.ints[raw] != null),
                };
            }

            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                const constraint_id = parameter.constraint orelse continue;
                if (parameter.kind != .type) return false;
                const bound = bindings.types[raw] orelse continue;
                if (!try self.inferConstraintBindings(module_index, constraint_id, bound, bindings)) return false;
            }

            var after: usize = 0;
            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                after += switch (parameter.kind) {
                    .type => @intFromBool(bindings.types[raw] != null),
                    .comptime_int => @intFromBool(bindings.ints[raw] != null),
                };
            }
            made_progress = after > before;
        }

        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            const constraint_id = parameter.constraint orelse continue;
            if (parameter.kind != .type) return false;
            const bound = bindings.types[raw] orelse return false;
            if (!try self.inferConstraintBindings(module_index, constraint_id, bound, bindings)) return false;
        }
        return true;
    }

    fn resolveExternalContract(self: *Resolver, module_index: usize, id: module_entities.ExternalRefId) !global_sg.GlobalDeclId {
        const reference = self.modules[module_index].semantic.external_refs.items[@intFromEnum(id)];
        return self.core.resolveDeclaration(module_index, reference, &.{.contract_type});
    }

    pub fn resolveDeclarationRef(
        self: *Resolver,
        module_index: usize,
        reference: ir.DeclarationRef,
        kind: primitives.DeclarationKind,
    ) !global_sg.GlobalDeclId {
        return switch (reference) {
            .module => |local| globalizer.globalDecl(self.offsets[module_index], local),
            .external => |external| blk: {
                const key = ContractRefKey{ .module_index = @intCast(module_index), .external = external, .kind = kind };
                if (self.resolved_contract_refs.get(key)) |declaration| break :blk declaration;
                // Module declarations are fixed after relocation. Cache only
                // successful lookups so an unresolved reference can be retried.
                const declaration = try self.core.resolveDeclaration(
                    module_index,
                    self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)],
                    &.{kind},
                );
                try self.resolved_contract_refs.put(self.allocator, key, declaration);
                break :blk declaration;
            },
        };
    }

    fn sourceFor(self: *const Resolver, module_index: usize, source: primitives.SourceRef) primitives.SourceRef {
        return .{ .file_index = self.offsets[module_index].file_base + source.file_index, .offset = source.offset };
    }

    fn findFunctionParameterized(
        self: *Resolver,
        module_index: usize,
        declaration: global_sg.GlobalDeclId,
    ) ?parameterized_storage.ParameterizedFunction {
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.parameterized_storage.parameterized_functions.items) |parameterized|
            if (parameterized.declaration == local) return parameterized;
        return null;
    }
};

test "contract resolver keeps compile-time relation metadata outside GlobalSG" {
    try std.testing.expect(@sizeOf(Stats) <= 40);
    try std.testing.expect(@sizeOf(global_sg.GlobalDeclId) == 4);
}

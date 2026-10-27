const contract_evidence = @import("contract_evidence.zig");
const contract_projections = @import("contract_projections.zig");
const contract_safety = @import("contract_safety.zig");
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

pub const Stats = struct {
    checks: u32 = 0,
    implementation_scans: u64 = 0,
    implementation_candidates: u64 = 0,
    implementation_scan_ns: u64 = 0,
    registration_templates_ns: u64 = 0,
    registration_tuples_ns: u64 = 0,
};

pub const ContractUse = struct {
    declaration: global_sg.GlobalFamilyDefinitionId,
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
    generic_decl: global_sg.GlobalFamilyDefinitionId,
    contract_decl: global_sg.GlobalFamilyDefinitionId,
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
    const RegistrationCursor = struct { module: u32 = 0, conformance: u32 = 0 };
    pub const ResolutionCheckpoint = struct {
        participant_failure: ?ParticipantConformanceFailure,
        registration: RegistrationCursor,
        caches: [2]usize,
        templates: usize,
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
    const TemplateGroup = struct { declaration: global_sg.GlobalFamilyDefinitionId, arity: usize };
    const ImplementationTemplate = struct { module: usize, index: usize };
    const TemplateRewrite = struct {
        key: TemplateGroup,
        previous: ?struct { entries: usize, modules: usize },
    };
    const TemplateIndex = struct {
        entries: std.ArrayList(ImplementationTemplate) = .empty,
        module_count: usize = 0,
    };

    allocator: std.mem.Allocator,
    function_context: ?*anyopaque = null,
    instantiate_function: ?*const fn (*anyopaque, global_sg.GlobalDeclId, primitives.Range(global_sg.GlobalGenericArgId), global_sg.GlobalTypeId, global_sg.GlobalTypeId) anyerror!global_sg.GlobalFunctionId = null,

    instantiate_alias: ?*const fn (*anyopaque, global_sg.GlobalDeclId, global_sg.GlobalTypeId) anyerror!global_sg.GlobalFunctionId = null,
    infer_operation_parameters: ?*const fn (*anyopaque, usize, parameterized_storage.ContractRequirement, global_sg.GlobalNodeId, *generic_mod.Resolver.Bindings, reach_context.Context) anyerror!bool = null,
    instantiate_generic_operation: ?*const fn (*anyopaque, global_sg.GlobalDeclId, primitives.Range(global_sg.GlobalGenericArgId), global_sg.GlobalTypeId, global_sg.GlobalTypeId, bool) anyerror!global_sg.GlobalFunctionId = null,

    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    virtual_signature_failure: ?VirtualSignatureFailure = null,
    participant_conformance_failure: ?ParticipantConformanceFailure = null,
    registration: RegistrationCursor = .{},
    stats: Stats = .{},
    profile_implementation_scans: bool = false,
    profile_io: ?std.Io = null,
    constraint_declarations: @import("identity_cache.zig").IdentityCache(ConstraintKey, global_sg.GlobalFamilyDefinitionId) = .empty,
    resolved_contract_refs: @import("identity_cache.zig").IdentityCache(ContractRefKey, global_sg.GlobalFamilyDefinitionId) = .empty,
    implementation_templates: std.AutoHashMapUnmanaged(TemplateGroup, TemplateIndex) = .empty,
    template_rewrites: std.ArrayList(TemplateRewrite) = .empty,
    pub fn deinit(self: *Resolver) void {
        self.constraint_declarations.deinit(self.allocator);
        self.resolved_contract_refs.deinit(self.allocator);
        var templates = self.implementation_templates.valueIterator();
        while (templates.next()) |group| group.entries.deinit(self.allocator);
        self.implementation_templates.deinit(self.allocator);
        self.template_rewrites.deinit(self.allocator);
    }

    pub fn checkpointResolution(self: *const Resolver) ResolutionCheckpoint {
        return .{ .participant_failure = self.participant_conformance_failure, .registration = self.registration, .caches = .{ self.constraint_declarations.checkpoint(), self.resolved_contract_refs.checkpoint() }, .templates = self.template_rewrites.items.len };
    }

    pub fn rollbackResolution(self: *Resolver, saved: ResolutionCheckpoint) void {
        self.participant_conformance_failure = saved.participant_failure;
        self.registration = saved.registration;
        self.constraint_declarations.rollback(saved.caches[0]);
        self.resolved_contract_refs.rollback(saved.caches[1]);
        while (self.template_rewrites.items.len > saved.templates) {
            const rewrite = self.template_rewrites.pop().?;
            if (rewrite.previous) |previous| {
                const group = self.implementation_templates.getPtr(rewrite.key).?;
                group.entries.shrinkRetainingCapacity(previous.entries);
                group.module_count = previous.modules;
            } else {
                var removed = self.implementation_templates.fetchRemove(rewrite.key).?.value;
                removed.entries.deinit(self.allocator);
            }
        }
    }

    pub fn commitCaches(self: *Resolver) void {
        self.constraint_declarations.commit(self.allocator);
        self.resolved_contract_refs.commit(self.allocator);
        self.template_rewrites.deinit(self.allocator);
        self.template_rewrites = .empty;
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
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
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
        try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
        return .resolved;
    }

    fn ownsVirtualCall(
        self: *const Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
    ) bool {
        if (reference.module_path != null or reference.generic_arguments != null or reference.computed_arguments != null) return false;
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
        const arguments = try self.generics.resolveCallArguments(module_index, reference) orelse
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
        if (mappings.len == 0) return &.{};
        const arena = try self.graph.safetyAllocator(self.allocator);
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
                        if (global_types.nominalTypeOwner(self.graph, ty)) |owner| {
                            if (!self.graph.sameModuleNamespace(owner, @enumFromInt(module_index)) and !(self.modules[module_index].is_bundled_core and self.graph.modules.items[@intFromEnum(owner)].is_bundled_core))
                                return self.domainFailure(source, "storage domain mappings cannot access private fields of another module");
                        }
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
                try paths.append(self.allocator, .{ .fields = try arena.dupe(u32, fields.items) });
            }
            try result.append(self.allocator, .{ .domain_index = index, .paths = try arena.dupe(primitives.StorageDomainMapping.Path, paths.items) });
        }
        var temporary = std.heap.ArenaAllocator.init(self.allocator);
        defer temporary.deinit();
        const scratch = temporary.allocator();
        var symbolic: std.ArrayList(@import("../safety/domains.zig").Mapping) = .empty;
        defer symbolic.deinit(scratch);
        for (result.items) |mapping| {
            const paths = try scratch.alloc(@import("../safety/safety_facts.zig").InputPath, mapping.paths.len);
            for (mapping.paths, paths) |path, *resolved| {
                const projections = try scratch.alloc(@import("../safety/place.zig").Projection, path.fields.len);
                for (path.fields, projections) |field, *projection| projection.* = .{ .field = field };
                resolved.* = .{ .input_index = 0, .projections = projections };
            }
            try symbolic.append(scratch, .{ .domain = @enumFromInt(mapping.domain_index), .paths = paths });
        }
        if (@import("../safety/domains.zig").validate(symbolic.items, 0) != null) return self.domainFailure(source, "implementation storage domains overlap or have an invalid mapping");
        return try arena.dupe(primitives.StorageDomainMapping, result.items);
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

    pub fn contractDefinitionForType(self: *const Resolver, ty: global_sg.GlobalTypeId) ?global_sg.GlobalFamilyDefinitionId {
        return self.contractDefinitionFromType(ty);
    }

    pub fn concreteImplements(self: *Resolver, concrete: global_sg.GlobalTypeId, contract_type: global_sg.GlobalTypeId) bool {
        const declaration = switch (self.graph.types.items[@intFromEnum(contract_type)]) {
            .definition => |value| value,
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
                .definition => {
                    const actual = bindings.definitions[raw] orelse return false;
                    const expected_value = wanted.definitions[raw] orelse return false;
                    if (actual.origin != expected_value.origin or !global_types.genericArgumentsEqual(self.graph, actual.captures, expected_value.captures)) return false;
                },
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
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.field_access_types) else null;
        defer if (measurement) |m| m.finish(changed);
        // Access nodes keep the effective runtime representation in their
        // type. This is what lets later reach traversal and codegen stay
        // entirely static once the backing implementer is known.
        for (self.graph.nodes.items, 0..) |node, raw| {
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
                try self.graph.setNodeType(self.allocator, @enumFromInt(raw), effective);
                changed = true;
            }
        }
        return changed;
    }

    pub fn fallibleOutput(self: *const Resolver, output: global_sg.GlobalTypeId) bool {
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
        if (reference.module_path != null or reference.generic_arguments != null or reference.computed_arguments != null) return null;
        return self.makeVirtualOperationCall(self.modules[module_index].text(reference.name), null, input, source, reach, null);
    }

    fn makeVirtualOperationCall(
        self: *Resolver,
        method_name: []const u8,
        contract: ?global_sg.GlobalFamilyDefinitionId,
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
                    .applicable => {},
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
                try self.graph.virtual_registries.append(self.allocator, .{ .receiver_input_index = index });
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
                    .ty = if (output_fields.len > 1) instance.output else try self.core.outputTypeForFields(output_fields),
                    .content = .{ .virtual_call = call_id },
                };
            }
        }
        return null;
    }

    pub const LocatedContractDefinition = struct {
        module_index: usize,
        definition: parameterized_storage.ContractDefinition,
    };

    const RequirementInstance = struct {
        declaration: global_sg.GlobalFamilyDefinitionId,
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
            if (requirement.parameters.len != 0) {
                self.virtual_signature_failure = .{ .source = source, .method_name = name, .reason = "generic contract operations require static specialization and cannot be virtualized" };
                return false;
            }
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
                } else if (try contract_safety.containsErasedParticipant(self, field.ty, contract_ty)) {
                    reason = "the hidden participant is only allowed as a direct borrowed receiver (&T or $&T)";
                }
            }
            if (reason == null and receivers != 1)
                reason = "a virtual operation requires exactly one borrowed participant receiver; runtime multiple dispatch is not supported";
            for (self.graph.fields.items[outputs.start..][0..outputs.len]) |field| {
                if (try contract_safety.containsErasedParticipant(self, field.ty, contract_ty))
                    reason = "the hidden participant cannot appear in a virtual operation result; return a known type or an explicit virtual handle";
            }
            if (reason == null) if (requirement.safety_contract) |contract| {
                reason = try contract_safety.methodSafetyContractFailure(self, inputs, outputs, instance.output, contract_ty, located, contract, true);
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

    pub fn findContractDefinition(self: *const Resolver, definition: global_sg.GlobalFamilyDefinitionId) ?LocatedContractDefinition {
        const family = self.graph.familyDefinition(definition);
        if (family.kind != .contract) return null;
        const module_index = @intFromEnum(self.graph.moduleForFamilyDefinition(definition) orelse return null);
        const index = family.template_index orelse return null;
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        if (index >= storage.contract_definitions.items.len) return null;
        return .{ .module_index = module_index, .definition = storage.contract_definitions.items[index] };
    }

    pub const ConformanceSelection = struct { tuple: usize };

    /// Source-template indexes extend with module fragments. Their entries
    /// retain source identities, while the resolver checkpoint owns each tail.
    fn implementationTemplates(self: *Resolver, declaration: global_sg.GlobalFamilyDefinitionId, arity: usize) ![]const ImplementationTemplate {
        const key: TemplateGroup = .{ .declaration = declaration, .arity = arity };
        if (self.implementation_templates.get(key)) |group| {
            if (self.modules.len < group.module_count) return error.InvalidContractModulePrefix;
            if (self.modules.len == group.module_count) return group.entries.items;
        }
        try self.template_rewrites.ensureUnusedCapacity(self.allocator, 1);
        const indexed = try self.implementation_templates.getOrPut(self.allocator, key);
        const previous: @FieldType(TemplateRewrite, "previous") = if (indexed.found_existing)
            .{ .entries = indexed.value_ptr.entries.items.len, .modules = indexed.value_ptr.module_count }
        else
            null;
        if (!indexed.found_existing) indexed.value_ptr.* = .{};
        self.template_rewrites.appendAssumeCapacity(.{ .key = key, .previous = previous });
        const start = indexed.value_ptr.module_count;
        const count = indexed.value_ptr.entries.items.len;
        errdefer self.implementation_templates.getPtr(key).?.entries.shrinkRetainingCapacity(count);
        for (self.modules[start..], start..) |module, owner| {
            for (module.semantic.parameterized_storage.contract_conformances.items, 0..) |template, index| {
                if (template.parameters.len == 0 or template.participants.len != arity) continue;
                if (try self.resolveDeclarationRef(owner, template.contract_ref, .contract_type) != declaration) continue;
                // Declaration resolution may grow the index. Never keep a map
                // entry pointer across that semantic operation.
                try self.implementation_templates.getPtr(key).?.entries.append(self.allocator, .{ .module = owner, .index = index });
            }
        }
        const completed = self.implementation_templates.getPtr(key).?;
        completed.module_count = self.modules.len;
        return completed.entries.items;
    }

    /// Source forms differ only while matching candidates. A selected conformance
    /// binds every participant and associated element as ordinary parameters.
    pub fn selectConformance(self: *Resolver, declaration: global_sg.GlobalFamilyDefinitionId, participants: []const global_sg.GlobalTypeId, bindings: ?*generic_mod.Resolver.Bindings, depth: u8, deferred: ?*bool) anyerror!?ConformanceSelection {
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
                if (!contract_projections.typeSelectionReady(self, expected, 0)) {
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
        // Nominal scalar declarations retain the primitive representation facts
        // of their base. Only these operation-free bundled facts are inherited;
        // user contracts and implementations still match nominal identities.
        if (participants.len == 1 and located.definition.requirements.len == 0 and located.definition.parameters.len == 0) {
            const represented = global_types.representationType(self.graph, participants[0]);
            const name = self.graph.familyDefinitionName(declaration);
            const fact = std.mem.eql(u8, name, "Int") or std.mem.eql(u8, name, "UInt") or std.mem.eql(u8, name, "Float") or
                std.mem.eql(u8, name, "_BuiltinArithmetic") or std.mem.eql(u8, name, "_BuiltinEquality") or std.mem.eql(u8, name, "_BuiltinOrdering") or
                std.mem.eql(u8, name, "_BuiltinInteger") or std.mem.startsWith(u8, name, "_IntegerFits");
            if (fact and standard_contracts.standardDefinition(self.graph, name) == declaration and
                represented != null and !global_types.equal(self.graph, represented.?, participants[0]) and
                self.graph.semanticType(represented.?) == .builtin and
                try self.selectConformance(declaration, &.{represented.?}, null, depth + 1, deferred) != null)
            {
                const start: u32 = @intCast(self.graph.generic_arguments.items.len);
                const parameter = self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items[located.definition.participants.start];
                try self.graph.generic_arguments.append(self.allocator, .{ .name = try self.graph.addString(self.allocator, self.modules[located.module_index].text(parameter.name)), .value = .{ .type = participants[0] } });
                const arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = start, .len = 1 };
                const index = self.graph.contract_conformances.items.len;
                try self.graph.contract_conformances.append(self.allocator, .{ .declaration = declaration, .context = @enumFromInt(located.module_index), .participants = arguments, .associated_arguments = .{ .start = start, .len = 0 }, .source = self.graph.familyDefinition(declaration).source, .declaration_validated = true });
                if (bindings) |target| try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, arguments, target);
                return .{ .tuple = index };
            }
        }
        // Native C identities have no source-level declaration in bundled core.
        // Publish only their checked, operation-free representation fact; Equal
        // still selects its ordinary generic implementation and operation.
        if (participants.len == 1 and located.definition.requirements.len == 0 and located.definition.parameters.len == 0 and
            standard_contracts.standardDefinition(self.graph, "_BuiltinEquality") == declaration and
            self.core.isForeignEqualityRepresentation(participants[0], participants[0]))
        {
            const definition = self.graph.familyDefinition(declaration);
            const file = self.graph.files.items[definition.source.file_index];
            if (std.mem.eql(u8, std.fs.path.basename(self.graph.text(file.path)), "scalar_arithmetic.rg")) {
                const start: u32 = @intCast(self.graph.generic_arguments.items.len);
                const parameter = self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items[located.definition.participants.start];
                try self.graph.generic_arguments.append(self.allocator, .{ .name = try self.graph.addString(self.allocator, self.modules[located.module_index].text(parameter.name)), .value = .{ .type = participants[0] } });
                const arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = start, .len = 1 };
                const index = self.graph.contract_conformances.items.len;
                try self.graph.contract_conformances.append(self.allocator, .{ .declaration = declaration, .context = @enumFromInt(located.module_index), .participants = arguments, .associated_arguments = .{ .start = start, .len = 0 }, .source = definition.source, .declaration_validated = true });
                if (bindings) |target| try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, arguments, target);
                return .{ .tuple = index };
            }
        }
        return self.selectGenericParticipantConformance(declaration, participants, bindings);
    }

    /// This conservative query only restricts implicit copying. An unknown
    /// provider never establishes conformance or selects an operation.
    pub fn mayImplementFirstParticipant(self: *Resolver, name: []const u8, concrete: global_sg.GlobalTypeId) anyerror!bool {
        for (self.graph.contract_conformances.items) |conformance| {
            if (!std.mem.eql(u8, self.graph.familyDefinitionName(conformance.declaration), name)) continue;
            if (conformance.participants.len == 0) continue;
            const first = self.graph.generic_arguments.items[conformance.participants.start].value;
            if (first == .type and global_types.equal(self.graph, first.type, concrete)) return true;
        }
        for (self.modules, 0..) |*module, module_index| {
            const storage = &module.semantic.parameterized_storage;
            for (storage.contract_conformances.items) |template| {
                if (template.participants.len == 0) continue;
                const declaration = try self.resolveDeclarationRef(module_index, template.contract_ref, .contract_type);
                if (!std.mem.eql(u8, self.graph.familyDefinitionName(declaration), name)) continue;
                const first = storage.ir.generic_arguments.items[template.participants.start].value;
                if (first != .type or !try self.typePatternMayMatch(module_index, first.type, concrete)) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                if (!try self.inferConstraintTypePattern(module_index, first.type, concrete, &bindings)) continue;
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

    fn selectGenericParticipantConformance(self: *Resolver, declaration: global_sg.GlobalFamilyDefinitionId, participants: []const global_sg.GlobalTypeId, target: ?*generic_mod.Resolver.Bindings) anyerror!?ConformanceSelection {
        const located = self.findContractDefinition(declaration) orelse return null;
        const Candidate = struct { module: usize, template: parameterized_storage.ContractConformance, bindings: generic_mod.Resolver.Bindings };
        var candidates: std.ArrayList(Candidate) = .empty;
        defer {
            for (candidates.items) |*candidate| candidate.bindings.deinit(self.allocator);
            candidates.deinit(self.allocator);
        }
        for (try self.implementationTemplates(declaration, participants.len)) |reference| {
            const module_index = reference.module;
            const module = &self.modules[module_index];
            const template = module.semantic.parameterized_storage.contract_conformances.items[reference.index];
            const patterns = module.semantic.parameterized_storage.ir.generic_arguments.items[template.participants.start..][0..template.participants.len];
            var possible = true;
            for (patterns, participants) |pattern, actual| {
                if (pattern.value != .type or !try self.typePatternMayMatch(module_index, pattern.value.type, actual)) {
                    possible = false;
                    break;
                }
            }
            if (!possible) continue;
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
            var keep = false;
            defer if (!keep) bindings.deinit(self.allocator);
            var matches = true;
            for (patterns, participants) |pattern, actual| {
                if (pattern.value != .type or !try self.inferConstraintTypePattern(module_index, pattern.value.type, actual, &bindings)) {
                    matches = false;
                    break;
                }
            }
            if (!matches or !try self.validateParameterizedImplementationConstraints(module_index, template.parameters, &bindings)) continue;
            try candidates.append(self.allocator, .{ .module = module_index, .template = template, .bindings = bindings });
            keep = true;
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
        var failure: ParticipantConformanceFailure = .{ .source = self.sourceFor(module_index, selected_template.source), .contract_name = self.graph.familyDefinitionName(declaration), .reason = "" };
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
        const declaration = try self.generics.resolveParameterizedFamily(a.module, left.base);
        if (declaration != try self.generics.resolveParameterizedFamily(b.module, right.base)) return false;
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
        if (left == .resolved and right == .resolved and left.resolved == .builtin and right.resolved == .builtin)
            return left.resolved.builtin == right.resolved.builtin;
        if (left == .concrete and right == .concrete)
            return global_types.equal(self.graph, globalizer.globalType(self.offsets[a.module], left.concrete), globalizer.globalType(self.offsets[b.module], right.concrete));
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
        // A concrete type cannot equal an incompatible symbolic shape. Use the
        // same conservative filter as selection before allocating substitutions
        // or instantiating a losing nominal pattern.
        if (left == .concrete and !try self.typePatternMayMatch(b.module, b.ty, globalizer.globalType(self.offsets[a.module], left.concrete))) return false;
        if (right == .concrete and !try self.typePatternMayMatch(a.module, a.ty, globalizer.globalType(self.offsets[b.module], right.concrete))) return false;
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
                .definition => .{ .definition = bindings.definitions[raw].? },
            } });
        }
        return .{ .start = start, .len = parameters.len };
    }

    fn implementsDepth(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        contract_decl: global_sg.GlobalFamilyDefinitionId,
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
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.generic_type_constraints) else null;
        defer if (measurement) |m| m.finish(false);
        for (self.graph.types.items) |ty| {
            const identity = switch (ty) {
                .generic => |value| value,
                else => continue,
            };
            const located = self.generics.findTypeParameterized(identity.base) orelse continue;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            const parameters = storage.comptime_parameters.items[located.parameterized.parameters.start..][0..located.parameterized.parameters.len];
            const has_constraints = for (parameters) |parameter| {
                if (parameter.kind == .type and parameter.constraint != null) break true;
            } else false;
            if (!has_constraints) continue;
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

    pub fn conformanceArgumentFailure(err: anyerror) ?[]const u8 {
        return switch (err) {
            error.TooManyGenericArguments => "too many arguments",
            error.UnknownGenericArgument => "unknown argument name",
            error.DuplicateGenericArgument => "duplicate argument",
            error.MissingGenericArgument => "missing argument",
            error.GenericArgumentKindMismatch => "argument kind does not match its parameter",
            error.DefinitionParameterSignatureMismatch => "associated type-family argument does not match its parameter signature",
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
                    .definition => .{ .definition = bindings.definitions[raw] orelse return error.UnboundDefinitionParameter },
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
        const arguments = try self.generics.resolveCallArguments(module_index, reference) orelse primitives.Range(global_sg.GlobalGenericArgId){ .start = 0, .len = 0 };
        const node = try self.makeSpecializedScopedOperationCall(module_index, globalizer.globalType(offsets, call.contract_type.?), module.text(reference.name), arguments, globalizer.globalNode(offsets, call.input), context, self.sourceFor(module_index, reference.source)) orelse
            return if (self.participant_conformance_failure != null) .invalid else .deferred;
        try self.graph.setNode(self.allocator, globalizer.globalNode(offsets, call.node), node);
        return .resolved;
    }

    pub const OperationCandidate = struct {
        declaration: global_sg.GlobalFamilyDefinitionId,
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
        return self.specializedOperationCandidatesFiltered(module_index, name, input, context, module_filter, .{ .start = 0, .len = 0 });
    }

    pub fn specializedOperationCandidatesFiltered(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context, module_filter: ?global_sg.GlobalModuleId, arguments: primitives.Range(global_sg.GlobalGenericArgId)) !OperationCandidates {
        var result: OperationCandidates = .{};
        errdefer result.deinit(self.allocator);
        if (std.mem.startsWith(u8, name, "_")) return result;
        for (self.modules, 0..) |module, owner| {
            for (module.semantic.parameterized_storage.contract_definitions.items) |definition| {
                if (!definition.hasExplicitParticipants()) continue;
                const declaration = self.graph.familyForDeclaration(globalizer.globalDecl(self.offsets[owner], definition.declaration)).?;
                if (!self.core.familyVisible(module_index, declaration, module_filter)) continue;
                const storage = &module.semantic.parameterized_storage;
                for (storage.contract_requirements.items[definition.requirements.start..][0..definition.requirements.len]) |requirement| {
                    if (!std.mem.eql(u8, module.text(requirement.name), name)) continue;
                    if (try self.probeOperationCandidate(.{ .module_index = owner, .definition = definition }, declaration, requirement, input, context, arguments, &result.deferred, &result.failure)) |candidate| {
                        errdefer self.allocator.free(candidate.participants);
                        try result.items.append(self.allocator, candidate);
                    }
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

    fn probeOperationCandidate(self: *Resolver, located: LocatedContractDefinition, declaration: global_sg.GlobalFamilyDefinitionId, requirement: parameterized_storage.ContractRequirement, input: global_sg.GlobalNodeId, context: reach_context.Context, arguments: primitives.Range(global_sg.GlobalGenericArgId), deferred: *bool, failure: *?ParticipantConformanceFailure) !?OperationCandidate {
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        var checkpoint = self.graph.beginTransaction(self.allocator);
        const caches = self.checkpointResolution();
        const type_caches = self.generics.checkpointCaches();
        const comptime_failure = self.generics.comptime_failure;
        const argument_failure = self.generics.argument_failure;
        defer {
            checkpoint.rollback();
            self.rollbackResolution(caches);
            self.generics.rollbackCaches(type_caches);
            self.generics.comptime_failure = comptime_failure;
            self.generics.argument_failure = argument_failure;
        }
        const module = &self.modules[located.module_index];
        const storage = &module.semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        self.generics.bindGlobalArgumentsPartial(located.module_index, requirement.parameters, arguments, &bindings) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return null,
        };
        const input_pattern = storage.ir.representation(requirement.input);
        const fields = if (input_pattern == .resolved and input_pattern.resolved == .structural)
            input_pattern.resolved.structural.fields
        else infer: {
            const infer = self.infer_operation_parameters orelse return error.MissingOperationInstantiator;
            if (!(infer(self.function_context.?, located.module_index, requirement, input, &bindings, context) catch |err| switch (err) {
                error.ConflictingGenericArgument => return null,
                else => return err,
            })) return null;
            break :infer primitives.Range(ir.ParameterizedFieldId){ .start = 0, .len = 0 };
        };
        var virtual = false;
        var unresolved_actual = false;
        for (storage.ir.fields.items[fields.start..][0..fields.len], 0..) |field, position| {
            var explicit = false;
            for ([_]@TypeOf(literal.fields){ literal.fields, literal.assumed_fields }, 0..) |actual_fields, pool_index| {
                if (pool_index == 1 and explicit) break;
                for (self.graph.value_fields.items[actual_fields.start..][0..actual_fields.len], 0..) |actual, index| {
                    const name = self.graph.text(actual.name);
                    if (!((pool_index == 0 and name.len == 0 and position == index) or std.mem.eql(u8, name, module.text(field.name)))) continue;
                    explicit = true;
                    const actual_ty = self.graph.node(actual.value).ty orelse {
                        // An associated input can be a contextual record/choice
                        // literal. Other inputs select participants first; the
                        // selected signature supplies its type below.
                        unresolved_actual = true;
                        continue;
                    };
                    if (!contract_projections.typeSelectionReady(self, actual_ty, 0)) {
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
                    _ = self.inferOperationInputPattern(located.module_index, field.ty, actual_ty, &bindings) catch |err| switch (err) {
                        error.ConflictingGenericArgument => return null,
                        else => return err,
                    };
                }
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
                _ = self.inferOperationInputPattern(located.module_index, field.ty, ty, &bindings) catch |err| switch (err) {
                    error.ConflictingGenericArgument => return null,
                    else => return err,
                };
            };
        }
        const participants = try self.allocator.alloc(global_sg.GlobalTypeId, located.definition.participants.len);
        var transferred = false;
        defer if (!transferred) self.allocator.free(participants);
        for (participants, 0..) |*participant, index| {
            participant.* = bindings.types[located.definition.participants.start + index] orelse {
                if (unresolved_actual) deferred.* = true;
                return null;
            };
        }
        if (!virtual) {
            const selected = self.selectConformance(declaration, participants, &bindings, 0, deferred) catch |err| {
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
                return null;
            }
        }
        if (requirement.parameters.len != 0 and !virtual) {
            const infer = self.infer_operation_parameters orelse return error.MissingOperationInstantiator;
            if (!(infer(self.function_context.?, located.module_index, requirement, input, &bindings, context) catch |err| switch (err) {
                error.ConflictingGenericArgument => return null,
                else => return err,
            })) {
                if (unresolved_actual) deferred.* = true;
                return null;
            }
        }
        const required = self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings) catch |err| {
            if (err == error.OutOfMemory) return err;
            return null;
        };
        switch (try self.core.matchCallInputWithReach(global_types.fields(self.graph, required) orelse return error.InvalidContractRequirementInput, input, context)) {
            .applicable => {
                transferred = true;
                return .{ .declaration = declaration, .participants = participants, .virtual = virtual };
            },
            .deferred => deferred.* = true,
            .no_match => {},
        }
        return null;
    }

    pub fn callOperationCandidate(self: *Resolver, module_index: usize, candidate: OperationCandidate, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context, source: primitives.SourceRef) !?global_sg.Node {
        return self.callSpecializedOperationCandidate(module_index, candidate, name, input, context, source, .{ .start = 0, .len = 0 });
    }

    pub fn callSpecializedOperationCandidate(self: *Resolver, module_index: usize, candidate: OperationCandidate, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context, source: primitives.SourceRef, arguments: primitives.Range(global_sg.GlobalGenericArgId)) !?global_sg.Node {
        if (candidate.virtual) {
            const located = self.findContractDefinition(candidate.declaration) orelse return null;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            const requirement = for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len]) |requirement| {
                if (std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), name)) break requirement;
            } else return null;
            if (requirement.parameters.len != 0) {
                self.virtual_signature_failure = .{ .source = source, .method_name = name, .reason = "generic contract operations require static specialization and cannot be virtualized" };
                return null;
            }
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
        return self.makeSpecializedScopedOperationCall(module_index, base, name, arguments, input, context, source);
    }

    pub fn makeScopedOperationCall(self: *Resolver, module_index: usize, base: global_sg.GlobalTypeId, name: []const u8, input: global_sg.GlobalNodeId, context: reach_context.Context, source: primitives.SourceRef) !?global_sg.Node {
        return self.makeSpecializedScopedOperationCall(module_index, base, name, .{ .start = 0, .len = 0 }, input, context, source);
    }

    pub fn makeSpecializedScopedOperationCall(self: *Resolver, module_index: usize, base: global_sg.GlobalTypeId, name: []const u8, arguments: primitives.Range(global_sg.GlobalGenericArgId), input: global_sg.GlobalNodeId, context: reach_context.Context, source: primitives.SourceRef) !?global_sg.Node {
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
            return self.makeSpecializedScopedOperationCall(module_index, bound, name, arguments, input, context, source);
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
            if (!contract_projections.typeSelectionReady(self, participant.*, 0)) return null;
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
        const requirement = storage.contract_requirements.items[located.definition.requirements.start + method_index];
        self.generics.bindGlobalArgumentsPartial(located.module_index, requirement.parameters, arguments, &bindings) catch |err| {
            failure.reason = switch (err) {
                error.TooManyGenericArguments => "too many compile-time arguments for contract operation",
                error.UnknownGenericArgument => "unknown compile-time argument for contract operation",
                error.DuplicateGenericArgument => "duplicate compile-time argument for contract operation",
                error.GenericArgumentKindMismatch => "compile-time argument kind does not match the operation parameter",
                error.DefinitionParameterSignatureMismatch => "type-family argument does not match the operation parameter signature",
                else => return err,
            };
            self.participant_conformance_failure = failure;
            return null;
        };
        if (requirement.parameters.len != 0) {
            const infer = self.infer_operation_parameters orelse return error.MissingOperationInstantiator;
            if (!try infer(self.function_context.?, located.module_index, requirement, input, &bindings, context)) return null;
        }
        const required_type = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings);
        const required_output = try self.generics.instantiateParameterizedType(located.module_index, requirement.output, &bindings);
        const method = if (requirement.parameters.len == 0)
            try self.resolveOperationBinding(conformance, method_index)
        else generic: {
            const evidence = contract_evidence.operationInConformance(self.graph, conformance, @intCast(method_index)) orelse return error.InvalidContractOperation;
            var captures: std.ArrayList(global_sg.GenericArgument) = .empty;
            defer captures.deinit(self.allocator);
            if (evidence.binding.instantiate_associated) {
                try captures.appendSlice(self.allocator, self.graph.generic_arguments.items[conformance.implementation_arguments.start..][0..conformance.implementation_arguments.len]);
                try captures.appendSlice(self.allocator, self.graph.generic_arguments.items[conformance.associated_arguments.start..][0..conformance.associated_arguments.len]);
            }
            const start: u32 = @intCast(self.graph.generic_arguments.items.len);
            try self.graph.generic_arguments.appendSlice(self.allocator, captures.items);
            const instantiate = self.instantiate_generic_operation orelse return error.MissingOperationInstantiator;
            const method = instantiate(self.function_context.?, evidence.binding.declaration, .{ .start = start, .len = @intCast(captures.items.len) }, required_type, required_output, evidence.binding.instantiate_associated) catch |err| {
                failure.reason = switch (err) {
                    error.ContextualSignatureMismatch, error.OperationAliasInputMismatch => "implementation operation has an incompatible input signature",
                    error.ContextualOutputSignatureMismatch => "operation returns an incompatible associated result",
                    error.OperationAliasConstraintMismatch => "the selected input signature does not satisfy the generic operation implementation bounds",
                    error.GenericFunctionParameterizedNotFound, error.MissingGenericArgument => "the selected operation implementation cannot be specialized from its inputs",
                    else => return err,
                };
                self.participant_conformance_failure = failure;
                return null;
            };
            const function = self.graph.function(method);
            if (!global_types.operationInputsCompatible(self.graph, global_types.fields(self.graph, required_type).?, function.input) or
                !global_types.operationFieldsEqual(self.graph, global_types.fields(self.graph, required_output).?, function.output))
            {
                failure.reason = if (!global_types.operationInputsCompatible(self.graph, global_types.fields(self.graph, required_type).?, function.input))
                    "implementation operation has an incompatible input signature"
                else
                    "operation returns an incompatible associated result";
                self.participant_conformance_failure = failure;
                return null;
            }
            try self.recordStaticSafetyContract(located, requirement, &bindings, participants[0], method, required_output, source, .{ .conformance = @intCast(selected.tuple), .index = @intCast(method_index) });
            break :generic method;
        };
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
            .applicable => {},
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
        const pattern_type = storage.ir.representation(requirement.input);
        if (pattern_type != .resolved or pattern_type.resolved != .structural) return null;
        const fields = pattern_type.resolved.structural.fields;
        for (storage.ir.fields.items[fields.start..][0..fields.len], 0..) |field, position| {
            const pattern = storage.ir.types.items[@intFromEnum(field.ty)];
            const pointer = pattern == .resolved and pattern.resolved == .pointer and
                self.isUnaryReceiverParticipantType(located, pattern.resolved.pointer.child);
            if (!pointer and !self.isUnaryReceiverParticipantType(located, field.ty)) continue;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |actual, index| {
                const label = self.graph.text(actual.name);
                if (!((label.len == 0 and index == position) or std.mem.eql(u8, label, self.modules[located.module_index].text(field.name)))) continue;
                var ty = self.graph.node(actual.value).ty orelse return null;
                if (!contract_projections.typeSelectionReady(self, ty, 0)) return null;
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
            .external => |external| blk: {
                const reference = self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)];
                if (try self.core.resolveDefinitionReference(module_index, reference, &.{.type})) |family| break :blk family;
                const concrete = (try self.core.resolveTypeValue(module_index, reference)) orelse return null;
                return global_types.conformanceParticipantOwner(self.graph, concrete);
            },
            .resolved => |resolved| switch (resolved) {
                .pointer => |pointer| return self.templateParticipantOwner(module_index, pointer.child),
                .generic => |nominal| try self.generics.resolveParameterizedFamily(module_index, nominal.base),
                .nominal => |reference| return self.graph.moduleForTypeDefinition(globalizer.globalTypeDefinition(self.offsets[module_index], reference)),
                else => return null,
            },
            else => return null,
        };
        return self.graph.moduleForFamilyDefinition(declaration);
    }

    fn templateOwnsParticipant(self: *Resolver, module_index: usize, conformance: parameterized_storage.ContractConformance) !bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        for (storage.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len]) |argument| {
            if (argument.value != .type) continue;
            if (try self.templateParticipantOwner(module_index, argument.value.type)) |owner|
                if (self.core.sameDeclarationNamespace(@intFromEnum(owner), module_index)) return true;
        }
        return false;
    }

    // Dormant templates still extend an operation identity. Reject foreign
    // ownership and equivalent patterns before any concrete call selects them.
    fn validateConformanceTemplates(self: *Resolver) !void {
        const Template = struct { module: usize, conformance: parameterized_storage.ContractConformance };
        var groups: std.AutoHashMapUnmanaged(TemplateGroup, std.ArrayList(Template)) = .empty;
        defer {
            var lists = groups.valueIterator();
            while (lists.next()) |list| list.deinit(self.allocator);
            groups.deinit(self.allocator);
        }
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
                    .contract_name = self.graph.familyDefinitionName(declaration),
                    .reason = "",
                };
                if (conformance.parameters.len != 0 and !self.core.sameDeclarationNamespace(located.module_index, module_index) and
                    !(module.is_bundled_core and self.modules[located.module_index].is_bundled_core) and
                    !try self.templateOwnsParticipant(module_index, conformance))
                {
                    failure.reason = "an implementation must belong to the contract module or a nominal participant module";
                    self.participant_conformance_failure = failure;
                    return;
                }
                const group = try groups.getOrPut(self.allocator, .{ .declaration = declaration, .arity = conformance.participants.len });
                if (!group.found_existing) group.value_ptr.* = .empty;
                for (group.value_ptr.items) |other| {
                    if (conformance.parameters.len == 0 and other.conformance.parameters.len == 0) continue;
                    if (try self.patternTupleCovers(module_index, conformance, other.module, other.conformance) and
                        try self.patternTupleCovers(other.module, other.conformance, module_index, conformance))
                    {
                        failure.reason = "equivalent implementation participant patterns are not allowed";
                        self.participant_conformance_failure = failure;
                        return;
                    }
                }
                try group.value_ptr.append(self.allocator, .{ .module = module_index, .conformance = conformance });
            }
        }
    }

    pub fn prepareParticipantConformances(self: *Resolver) !void {
        if (self.registration.module > self.modules.len or self.offsets.len != self.modules.len) return error.InvalidContractModulePrefix;
        if (self.participant_conformance_failure != null) return;
        if (self.registration.module == self.modules.len) return;
        const start = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        try self.validateConformanceTemplates();
        const tuples_start = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        if (self.profile_io != null) self.stats.registration_templates_ns += @intCast(tuples_start - start);
        defer if (self.profile_io) |io| {
            self.stats.registration_tuples_ns += @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - tuples_start);
        };
        if (self.participant_conformance_failure != null) return;
        // Each source conformance is published once. Advance only after its
        // evidence has been registered successfully, including within a module.
        while (self.registration.module < self.modules.len) {
            const conformances = self.modules[self.registration.module].semantic.parameterized_storage.contract_conformances.items;
            while (self.registration.conformance < conformances.len) {
                try self.prepareParticipantConformance(self.registration.module, conformances[self.registration.conformance]);
                if (self.participant_conformance_failure != null) return;
                self.registration.conformance += 1;
            }
            self.registration.module += 1;
            self.registration.conformance = 0;
        }
    }

    fn prepareParticipantConformance(self: *Resolver, module_index: usize, conformance: parameterized_storage.ContractConformance) !void {
        const module = &self.modules[module_index];
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
            return;
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
            const declaration = self.resolveFunctionRef(module_index, operation.function) catch |err| {
                failure.source = self.sourceFor(module_index, operation.source);
                failure.reason = switch (err) {
                    error.UnknownGlobalDeclaration => "unknown or inaccessible implementation function",
                    error.AmbiguousGlobalDeclaration => "implementation operation must identify one ordinary function",
                    else => return err,
                };
                return error.InvalidContractConformance;
            };
            try functions.append(self.allocator, .{
                .contract_definition = self.graph.familyForDeclaration(globalizer.globalDecl(self.offsets[located.module_index], located.definition.declaration)).?,
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
                .parameter_count = requirement.parameters.len,
            });
        }
        const start: u32 = @intCast(self.graph.contract_operation_bindings.items.len);
        try self.graph.contract_operation_bindings.appendSlice(self.allocator, functions.items);
        return .{ .start = start, .len = @intCast(functions.items.len) };
    }

    fn resolveOperationBinding(self: *Resolver, conformance: global_sg.ContractConformance, index: usize) !global_sg.GlobalFunctionId {
        const evidence = contract_evidence.operationInConformance(self.graph, conformance, @intCast(index)) orelse return error.InvalidContractOperation;
        if (evidence.materializedFunction()) |function| return function;
        const method = try self.resolveOperationBody(conformance, index);
        if (standard_contracts.standardDefinition(self.graph, "Deinit") == conformance.declaration)
            return self.makeDestructorOperation(method, try self.core.functionOutputType(method), conformance.source);
        return method;
    }

    fn resolveOperationBody(self: *Resolver, conformance: global_sg.ContractConformance, index: usize) !global_sg.GlobalFunctionId {
        const evidence = contract_evidence.operationInConformance(self.graph, conformance, @intCast(index)) orelse return error.InvalidContractOperation;
        const binding = evidence.binding;
        if (self.graph.declaration(binding.declaration).function_id) |function| {
            return function;
        }
        const located = self.findContractDefinition(conformance.declaration) orelse return error.InvalidContractDeclaration;
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        try self.generics.bindGlobalArguments(located.module_index, located.definition.participants, conformance.participants, &bindings);
        try self.generics.bindGlobalArguments(located.module_index, located.definition.parameters, conformance.associated_arguments, &bindings);
        const requirement = storage.contract_requirements.items[located.definition.requirements.start + index];
        const input = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings);
        const output = try self.generics.instantiateParameterizedType(located.module_index, requirement.output, &bindings);
        if (!binding.instantiate_associated) {
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
            return instantiate(self.function_context.?, binding.declaration, conformance.associated_arguments, input, output);
        var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        try arguments.appendSlice(self.allocator, self.graph.generic_arguments.items[conformance.implementation_arguments.start..][0..conformance.implementation_arguments.len]);
        try arguments.appendSlice(self.allocator, self.graph.generic_arguments.items[conformance.associated_arguments.start..][0..conformance.associated_arguments.len]);
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);
        return instantiate(self.function_context.?, binding.declaration, .{ .start = start, .len = @intCast(arguments.items.len) }, input, output);
    }

    pub fn validateParticipantConformances(self: *Resolver) !void {
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.conformance_validation) else null;
        defer if (measurement) |m| m.finish(false);
        var index: usize = 0;
        // Validating an operation body can select evidence for a dependency.
        // Include those new entries in this pass rather than publishing calls
        // whose selected conformance has never been checked.
        while (index < self.graph.contract_conformances.items.len) : (index += 1) {
            const conformance = self.graph.contract_conformances.items[index];
            if (conformance.declaration_validated) continue;
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
            for (self.graph.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len]) |argument| {
                if (self.graph.isTypeUnresolved(argument.value.type)) {
                    failure.reason = "an implementation participant type is unknown or unresolved";
                    self.participant_conformance_failure = failure;
                    return;
                }
            }
            if (!self.core.sameDeclarationNamespace(located.module_index, module_index) and
                !(self.modules[module_index].is_bundled_core and self.modules[located.module_index].is_bundled_core))
            {
                var owns_participant = false;
                for (self.graph.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len]) |argument| {
                    if (global_types.conformanceParticipantOwner(self.graph, argument.value.type)) |owner|
                        if (self.core.sameDeclarationNamespace(@intFromEnum(owner), module_index)) {
                            owns_participant = true;
                            break;
                        };
                }
                if (!owns_participant) {
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
            var operations: std.ArrayList(struct { index: u32, function: global_sg.GlobalFunctionId }) = .empty;
            defer operations.deinit(self.allocator);
            const first = bindings.types[located.definition.participants.start].?;
            for (storage.contract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, operation_index| {
                const name = self.modules[located.module_index].text(requirement.name);
                if (requirement.parameters.len != 0) continue;
                const input = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings);
                const output = try self.generics.instantiateParameterizedType(located.module_index, requirement.output, &bindings);
                const selected: MethodSelection = selected: {
                    const method = self.resolveOperationBinding(conformance, operation_index) catch |err| switch (err) {
                        error.ContextualSignatureMismatch => break :selected .missing,
                        error.ContextualOutputSignatureMismatch => break :selected .incompatible_output,
                        else => return err,
                    };
                    const function = self.graph.function(method);
                    const required_inputs = global_types.fields(self.graph, input).?;
                    const required_outputs = global_types.fields(self.graph, output).?;
                    if (!global_types.operationInputsCompatible(self.graph, required_inputs, function.input)) break :selected .missing;
                    if (!global_types.operationFieldsEqual(self.graph, required_outputs, function.output)) break :selected .incompatible_output;
                    break :selected .{ .function = method };
                };
                if (selected != .function) {
                    failure.operation = name;
                    failure.input = input;
                    failure.output = output;
                    failure.reason = switch (selected) {
                        .missing => "implementation operation has an incompatible input signature",
                        .ambiguous => "ambiguous operation",
                        .incompatible_output => if (standard_contracts.standardDefinition(self.graph, "Equal") == conformance.declaration) "Equal.equal must return exactly (.ok: Bool)" else "operation returns an incompatible associated result",
                        .function => unreachable,
                    };
                    self.participant_conformance_failure = failure;
                    return;
                }
                if (standard_contracts.standardDefinition(self.graph, "Init") == conformance.declaration) {
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

                if (standard_contracts.standardDefinition(self.graph, "Convert") == conformance.declaration) {
                    const required_outputs = global_types.fields(self.graph, output).?;
                    const result = self.graph.fields.items[required_outputs.start].ty;
                    const target = self.graph.generic_arguments.items[conformance.participants.start + 1].value.type;
                    if (!self.graph.isTypeUnresolved(result) and !global_types.resultMatchesTarget(self.graph, result, target)) {
                        failure.reason = "Convert.Result must be its target participant type or one Errable containing that type";
                        self.participant_conformance_failure = failure;
                        return;
                    }
                }

                try self.recordStaticSafetyContract(located, requirement, &bindings, first, selected.function, output, failure.source, .{ .conformance = @intCast(index), .index = @intCast(operation_index) });
                try operations.append(self.allocator, .{ .index = @intCast(operation_index), .function = selected.function });
            }
            for (operations.items) |operation|
                try self.graph.completeOperationBinding(self.allocator, @enumFromInt(conformance.operation_bindings.start + operation.index), operation.function);
            var completed = self.graph.contract_conformances.items[index];
            // Empty marker contracts are validated too. Keep retrying markers
            // with unresolved arguments so projection/alias resolution cannot
            // hide a later bound failure or duplicate participant tuple.
            completed.declaration_validated = operations.items.len != 0 or self.conformanceArgumentsReady(conformance);
            try self.graph.setContractConformance(self.allocator, @intCast(index), completed);
        }
    }

    fn conformanceArgumentsReady(self: *const Resolver, conformance: global_sg.ContractConformance) bool {
        inline for (.{ conformance.participants, conformance.associated_arguments }) |arguments| {
            for (self.graph.generic_arguments.items[arguments.start..][0..arguments.len]) |argument| {
                if (argument.value == .type and !contract_projections.typeSelectionReady(self, argument.value.type, 0)) return false;
            }
        }
        return true;
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
        const input_type = function.input_type orelse try self.generics.internType(.{ .structural = .{ .fields = function.input } });
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
            .input_type = input_type,
            .output_type = function.output_type,
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
        return contract_projections.resolveAssociatedType(context, base, member, source);
    }

    pub fn resolveAssociatedDefinition(context: *anyopaque, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef) anyerror!global_sg.DefinitionValue {
        return contract_projections.resolveAssociatedDefinition(context, base, member, source);
    }

    pub fn resolveAssociatedInt(context: *anyopaque, base: global_sg.GlobalTypeId, member: []const u8, source: primitives.SourceRef) anyerror!i64 {
        return contract_projections.resolveAssociatedInt(context, base, member, source);
    }

    pub fn resolveAssociatedTypes(self: *Resolver) !void {
        return contract_projections.resolveAssociatedTypes(self);
    }

    pub fn constraintDefinition(
        self: *Resolver,
        module_index: usize,
        constraint_id: parameterized_storage.ContractConstraintId,
    ) !global_sg.GlobalFamilyDefinitionId {
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
        const definition = self.findContractDefinition(try self.constraintDefinition(module_index, constraint_id)) orelse return false;
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
        const contract_decl = try self.constraintDefinition(module_index, constraint_id);
        const definition = self.findContractDefinition(contract_decl) orelse return false;
        if (!definition.definition.hasExplicitParticipants()) return false;
        if (constraint.arguments.len == 0 and definition.definition.participants.len == 1)
            return self.implementsDepth(concrete, contract_decl, 0);
        return self.inferParticipantConstraint(module_index, constraint, concrete, definition, contract_decl, bindings);
    }

    // Participants select evidence first. Named associated restrictions compare
    // against that evidence; they never participate in choosing an implementation.
    fn inferParticipantConstraint(self: *Resolver, module_index: usize, constraint: parameterized_storage.ContractConstraint, concrete: global_sg.GlobalTypeId, located: LocatedContractDefinition, declaration: global_sg.GlobalFamilyDefinitionId, bindings: *generic_mod.Resolver.Bindings) !bool {
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
                    .projection => |projection| {
                        const value = try self.generics.instantiateArgumentProjection(module_index, projection, bindings);
                        const actual: global_sg.GenericArgument.Value = switch (parameters[raw].kind) {
                            .definition => .{ .definition = selected.definitions[raw] orelse return false },
                            .type => .{ .type = selected.types[raw] orelse return false },
                            .comptime_int => .{ .comptime_int = selected.ints[raw] orelse return false },
                        };
                        if (!global_types.genericArgumentValuesEqual(self.graph, value, actual)) return false;
                    },
                    .definition => |pattern| if (!try self.generics.inferDefinitionValue(module_index, pattern, selected.definitions[raw] orelse return false, bindings)) return false,
                    .type => |pattern| if (!try self.inferConstraintTypePattern(module_index, pattern, selected.types[raw] orelse return false, bindings)) return false,
                    .comptime_int => |pattern| if (!try self.inferConstraintIntPattern(module_index, pattern, selected.ints[raw] orelse return false, bindings)) return false,
                }
            }
        }
        return true;
    }

    /// Reject only shapes rejected directly by inference, before reserving
    /// bindings. Aliases, projections and parameters still need full matching.
    fn typePatternMayMatch(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, actual: global_sg.GlobalTypeId) !bool {
        const expected = self.modules[module_index].semantic.parameterized_storage.ir.types.items[@intFromEnum(pattern)];
        const supplied = self.graph.types.items[@intFromEnum(actual)];
        return switch (expected) {
            .array => supplied == .array,
            .resolved => |resolved| switch (resolved) {
                .pointer => |pointer| supplied == .pointer and pointer.mutability == supplied.pointer.mutability,
                .structural => |record| supplied == .structural and record.fields.len == supplied.structural.fields.len,
                .generic => |nominal| blk: {
                    if (supplied != .generic) break :blk false;
                    // Full matching owns diagnostics and ordered inference;
                    // this filter must not report a losing candidate's error.
                    const declaration = self.generics.resolveParameterizedFamily(module_index, nominal.base) catch break :blk true;
                    break :blk declaration == supplied.generic.base;
                },
                else => true,
            },
            else => true,
        };
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
            .definition => {
                const arguments = self.generics.definitionArguments(module_index, pattern, actual) orelse return false;
                for (0..arguments.pattern.len) |position| {
                    const wanted = ir_storage.generic_arguments.items[arguments.pattern.start + position];
                    const given = self.graph.generic_arguments.items[arguments.actual.start + position];
                    switch (wanted.value) {
                        .projection => |projection| if (!global_types.genericArgumentValuesEqual(self.graph, try self.generics.instantiateArgumentProjection(module_index, projection, bindings), given.value)) return false,
                        .definition => |definition_value| {
                            if (given.value != .definition or !try self.generics.inferDefinitionValue(module_index, definition_value, given.value.definition, bindings)) return false;
                        },
                        .type => |ty| {
                            if (given.value != .type or !try self.inferConstraintTypePattern(module_index, ty, given.value.type, bindings)) return false;
                        },
                        .comptime_int => |integer| {
                            if (given.value != .comptime_int or !try self.inferConstraintIntPattern(module_index, integer, given.value.comptime_int, bindings)) return false;
                        },
                    }
                }
                return true;
            },
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
                    const declaration = try self.generics.resolveParameterizedFamily(module_index, nominal.base);
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
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch |err| switch (err) {
            error.ComptimeExecutionPending => return err,
            else => return false,
        };
        return global_types.equal(self.graph, expected, actual);
    }

    pub fn inferConstraintIntPattern(
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
            .binary, .projection, .execution => (self.generics.evalInt(module_index, pattern, bindings) catch |err| switch (err) {
                error.ComptimeExecutionPending => return err,
                else => return false,
            }) == actual,
        };
    }

    // Acquired storage can outlive the command which allocates it. Retain the
    // selected cleanup conformances before lowering its immutable metadata,
    // even when no value of the participant has been constructed yet. This
    // selects evidence only; operation bodies keep their ordinary lazy checks.
    pub fn prepareStorageCleanupEvidence(self: *Resolver, ty: global_sg.GlobalTypeId) !void {
        const declaration = @import("standard_contracts.zig").standardDefinition(self.graph, "Deinit") orelse return;
        var seen: std.AutoHashMapUnmanaged(global_sg.GlobalTypeId, void) = .empty;
        defer seen.deinit(self.allocator);
        try self.prepareStorageCleanupType(ty, declaration, &seen, 0);
    }

    fn prepareStorageCleanupType(self: *Resolver, ty: global_sg.GlobalTypeId, declaration: global_sg.GlobalFamilyDefinitionId, seen: *std.AutoHashMapUnmanaged(global_sg.GlobalTypeId, void), depth: usize) anyerror!void {
        if (depth > 256) return error.InvalidStorageCleanupType;
        if (seen.contains(ty)) return;
        try seen.put(self.allocator, ty, {});
        if (self.graph.semanticType(ty) == .pointer) return;
        _ = try self.implements(ty, declaration);
        // Selection may grow graph pools. Keep ranges and reload each child
        // instead of retaining a slice across recursive conformance resolution.
        if (global_types.arrayElement(self.graph, ty)) |element| {
            try self.prepareStorageCleanupType(element, declaration, seen, depth + 1);
        } else if (global_types.fields(self.graph, ty)) |fields| {
            for (0..fields.len) |index| {
                const child = self.graph.fields.items[fields.start + index].ty;
                try self.prepareStorageCleanupType(child, declaration, seen, depth + 1);
            }
        } else if (global_types.variants(self.graph, ty)) |variants| {
            for (0..variants.len) |index| {
                if (self.graph.variants.items[variants.start + index].payload_type) |child|
                    try self.prepareStorageCleanupType(child, declaration, seen, depth + 1);
            }
        }
    }

    pub fn implements(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        contract_decl: global_sg.GlobalFamilyDefinitionId,
    ) !bool {
        self.stats.checks += 1;
        return self.implementsDepth(concrete, contract_decl, 0);
    }

    pub fn typeContractUse(self: *const Resolver, ty: global_sg.GlobalTypeId) ?ContractUse {
        return self.contractUse(ty);
    }

    pub fn runtimeBindingContract(self: *const Resolver, binding_id: global_sg.GlobalBindingId) ?ContractUse {
        const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
        if (self.graph.isBindingTypeUnresolved(binding_id) or self.graph.isTypeUnresolved(binding.ty)) return null;
        if (@import("types.zig").isStaticBinding(self.graph, binding_id)) return null;
        // Ordinary bindings cannot violate the contract/runtime boundary. Only
        // contract-typed bindings need the interface exception and its lookup.
        const use = self.contractUse(binding.ty) orelse return null;
        if (self.isFunctionInterfaceBinding(binding_id)) return null;
        return use;
    }

    pub fn contractUse(self: *const Resolver, ty: global_sg.GlobalTypeId) ?ContractUse {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .definition => |declaration| if (self.findContractDefinition(declaration) != null)
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
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.generic_function_constraints) else null;
        defer if (measurement) |m| m.finish(false);
        for (self.graph.generic_function_instances.items) |instance| {
            const owner = self.graph.moduleForFamilyDefinition(instance.parameterized_definition) orelse return error.InvalidGenericFunctionOwner;
            const module_index: usize = @intFromEnum(owner);
            const parameterized = self.findFunctionParameterized(module_index, instance.parameterized_definition) orelse {
                continue;
            };
            const module = &self.modules[module_index];
            const parameters = module.semantic.parameterized_storage.comptime_parameters.items[parameterized.parameters.start..][0..parameterized.parameters.len];
            // Argument matching already checked this instance's inputs. Only
            // explicit constraints need a substitution environment here.
            const constrained = for (parameters) |parameter| {
                if (parameter.constraint != null) break true;
            } else false;
            if (!constrained) continue;
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

    /// Complete each erased signature from its contract declaration. Concrete
    /// methods belong to selected handles; they do not alter virtual effects.
    pub fn closeVirtualMethodRegistries(self: *Resolver) !void {
        try self.closeVirtualMethodRegistriesInUnit(null);
    }

    /// Staged evaluation closes only its resolved dependency unit. Unrelated
    /// virtual constructions may still have pending bodies or type bindings.
    pub fn closeVirtualMethodRegistriesInUnit(self: *Resolver, unit: ?*const @import("reachability.zig").FunctionSet) !void {
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.virtual_registry_closure) else null;
        defer if (measurement) |m| m.finish(false);
        var raw: usize = 0;
        while (raw < self.graph.virtualizes.items.len) : (raw += 1) {
            if (unit) |selected| if (!selected.virtualizes.contains(@enumFromInt(raw))) continue;
            const virtualize = self.graph.virtualizes.items[raw];
            for (0..virtualize.safety_methods.len) |method_index| {
                // Resolving a signature may grow any semantic pool. Retain
                // ranges and IDs, then reacquire each row before using it.
                const registry_id = self.graph.virtual_registry_refs.items[virtualize.safety_methods.start + method_index];
                try self.closeVirtualMethodRegistry(registry_id, self.graph.semanticType(virtualize.virtual_type).virtual, method_index);
            }
        }
        var nodes = if (unit) |selected| selected.nodes.keyIterator() else null;
        if (nodes) |*selected| {
            while (selected.next()) |node| {
                const content = self.graph.node(node.*).content;
                if (content != .virtual_call) continue;
                const call = self.graph.virtual_calls.items[@intFromEnum(content.virtual_call)];
                const contract_ty = contract_evidence.virtualContractType(self.graph, call) orelse continue;
                try self.closeVirtualMethodRegistry(call.safety_methods, contract_ty, call.method_index);
            }
        } else {
            raw = 0;
            while (raw < self.graph.virtual_calls.items.len) : (raw += 1) {
                const call = self.graph.virtual_calls.items[raw];
                const contract_ty = contract_evidence.virtualContractType(self.graph, call) orelse continue;
                try self.closeVirtualMethodRegistry(call.safety_methods, contract_ty, call.method_index);
            }
        }
    }

    fn closeVirtualMethodRegistry(
        self: *Resolver,
        registry_id: global_sg.GlobalVirtualRegistryId,
        contract_ty: global_sg.GlobalTypeId,
        method_index: usize,
    ) !void {
        // The descriptor belongs to the erased signature, not the currently
        // known collection of concrete handles. Complete it once.
        if (self.graph.virtual_registries.items[@intFromEnum(registry_id)].contract_input_count != null) return;
        const use = self.contractUse(contract_ty) orelse return error.InvalidVirtualContract;
        const located = self.findContractDefinition(use.declaration) orelse return error.InvalidVirtualContract;
        const requirement = self.modules[located.module_index].semantic.parameterized_storage.contract_requirements.items[located.definition.requirements.start + method_index];
        const declared = requirement.safety_contract orelse return;
        const instance = (try self.requirementInstanceForContractUse(use, contract_ty, located, requirement, @intCast(method_index))) orelse return error.InvalidContractRequirement;
        const signature = global_types.fields(self.graph, instance.input) orelse return error.InvalidContractRequirementInput;
        const contract = try contract_safety.globalSafetyContract(self, located.module_index, declared, signature, instance.output);
        const input = try self.virtualInputType(instance.input, instance.output);
        const fields = global_types.fields(self.graph, input) orelse return error.InvalidContractRequirementInput;
        try self.graph.completeVirtualSignature(self.allocator, registry_id, contract, fields.len, instance.output);
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

    fn recordStaticSafetyContract(self: *Resolver, located: LocatedContractDefinition, requirement: parameterized_storage.ContractRequirement, bindings: *generic_mod.Resolver.Bindings, concrete: global_sg.GlobalTypeId, method: global_sg.GlobalFunctionId, output: global_sg.GlobalTypeId, source: primitives.SourceRef, selection: primitives.ContractOperationIdentity) !void {
        const declared = requirement.safety_contract orelse return;
        if (self.fallibleOutput(output)) try self.core.ensureErrorTracerInput(method);
        const function = self.graph.function(method);
        if (try contract_safety.methodSafetyContractFailure(self, function.input, function.output, output, concrete, located, declared, false)) |reason| {
            self.virtual_signature_failure = .{ .source = source, .method_name = self.modules[located.module_index].text(requirement.name), .reason = reason, .static_contract = true };
            return;
        }
        // The selected proof is immutable. Revalidation must not allocate a
        // second outcome tree that cannot add any information to that proof.
        for (self.graph.contract_safety_conformances.items) |existing| {
            if (std.meta.eql(existing.selection, selection) and existing.method == method) return;
        }
        const contract = contract_safety.globalSafetyContract(self, located.module_index, declared, function.input, output) catch |err| switch (err) {
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
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (0..located.definition.parameters.len) |offset| {
            const raw = located.definition.parameters.start + @as(u32, @intCast(offset));
            const parameter = storage.comptime_parameters.items[raw];
            const name = try self.graph.addString(self.allocator, self.modules[located.module_index].text(parameter.name));
            try self.graph.generic_arguments.append(self.allocator, .{
                .name = name,
                .value = switch (parameter.kind) {
                    .definition => .{ .definition = bindings.definitions[raw] orelse return error.UnboundDefinitionParameter },
                    .type => .{ .type = bindings.types[raw] orelse return error.UnboundGenericTypeParameter },
                    .comptime_int => .{ .comptime_int = bindings.ints[raw] orelse return error.UnboundComptimeParameter },
                },
            });
        }
        const contract_decl = self.graph.familyForDeclaration(globalizer.globalDecl(self.offsets[located.module_index], located.definition.declaration)).?;
        const use = ContractUse{ .declaration = contract_decl, .arguments = .{ .start = start, .len = located.definition.parameters.len } };
        const domains = if (located.definition.domains.len == 0) &.{} else (try self.resolveStorageDomains(use, concrete, located, source)) orelse return;
        var receiver: ?u32 = null;
        for (self.graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index| {
            const ty = self.graph.resolvedSemanticType(field.ty) orelse continue;
            if (ty == .pointer and global_types.equal(self.graph, ty.pointer.child, concrete)) {
                receiver = @intCast(index);
                break;
            }
        }
        try self.graph.contract_safety_conformances.append(self.allocator, .{ .selection = selection, .method = method, .contract = contract, .receiver_input_index = receiver, .domains = domains, .source = source });
    }

    fn contractDefinitionFromType(self: *const Resolver, ty: global_sg.GlobalTypeId) ?global_sg.GlobalFamilyDefinitionId {
        const contract_ty = switch (self.graph.types.items[@intFromEnum(ty)]) {
            .virtual => |contract_type| contract_type,
            else => ty,
        };
        return switch (self.graph.types.items[@intFromEnum(contract_ty)]) {
            .definition => |declaration| if (self.findContractDefinition(declaration) != null) declaration else null,
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
                    .definition => @intFromBool(bindings.definitions[raw] != null),
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
                    .definition => @intFromBool(bindings.definitions[raw] != null),
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

    fn resolveExternalContract(self: *Resolver, module_index: usize, id: module_entities.ExternalRefId) !global_sg.GlobalFamilyDefinitionId {
        const reference = self.modules[module_index].semantic.external_refs.items[@intFromEnum(id)];
        return (try self.core.resolveDefinitionReference(module_index, reference, &.{.contract_type})) orelse error.UnknownGlobalDeclaration;
    }

    pub fn resolveDeclarationRef(self: *Resolver, module_index: usize, reference: ir.DeclarationRef, kind: primitives.DeclarationKind) !global_sg.GlobalFamilyDefinitionId {
        return switch (reference) {
            .module => |local| self.graph.familyForDeclaration(globalizer.globalDecl(self.offsets[module_index], local)) orelse error.ExpectedParameterizedDefinition,
            .external => |external| blk: {
                const key = ContractRefKey{ .module_index = @intCast(module_index), .external = external, .kind = kind };
                if (self.resolved_contract_refs.get(key)) |definition| break :blk definition;
                const definition = (try self.core.resolveDefinitionReference(module_index, self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)], &.{kind})) orelse return error.UnknownGlobalDeclaration;
                try self.resolved_contract_refs.put(self.allocator, key, definition);
                break :blk definition;
            },
        };
    }

    fn resolveFunctionRef(self: *Resolver, module_index: usize, reference: ir.DeclarationRef) !global_sg.GlobalDeclId {
        return switch (reference) {
            .module => |local| globalizer.globalDecl(self.offsets[module_index], local),
            .external => |external| self.core.resolveDeclaration(module_index, self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)], &.{.function}),
        };
    }

    pub fn sourceFor(self: *const Resolver, module_index: usize, source: primitives.SourceRef) primitives.SourceRef {
        return .{ .file_index = self.offsets[module_index].file_base + source.file_index, .offset = source.offset };
    }

    fn findFunctionParameterized(self: *Resolver, module_index: usize, definition: global_sg.GlobalFamilyDefinitionId) ?parameterized_storage.ParameterizedFunction {
        const family = self.graph.familyDefinition(definition);
        if (family.kind != .function) return null;
        const index = family.template_index orelse return null;
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        if (index >= storage.parameterized_functions.items.len) return null;
        return storage.parameterized_functions.items[index];
    }
};

test "contract resolver keeps compile-time relation metadata outside GlobalSG" {
    try std.testing.expect(@sizeOf(Stats) <= 56);
    try std.testing.expect(@sizeOf(global_sg.GlobalFamilyDefinitionId) == 4);
}

test "closed symbolic patterns compare without substitutions or graph mutation" {
    const allocator = std.testing.allocator;
    var module: module_sg.ModuleSemanticGraph = .{};
    defer module.deinit(allocator);
    try module.semantic.parameterized_storage.ir.types.appendSlice(allocator, &.{
        .{ .resolved = .{ .builtin = .Int32 } },
        .{ .resolved = .{ .builtin = .UInt8 } },
        .{ .concrete = @enumFromInt(0) },
        .{ .concrete = @enumFromInt(1) },
        .{ .resolved = .{ .generic = .{ .base = @enumFromInt(0), .arguments = .{ .start = 0, .len = 0 } } } },
    });
    try module.semantic.parameterized_storage.comptime_parameters.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .kind = .type });
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Int32 } });
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    var resolver: Resolver = .{ .allocator = failing.allocator(), .graph = &graph, .modules = &modules, .offsets = &.{std.mem.zeroes(globalizer.Offsets)}, .core = undefined, .generics = undefined };
    const int = Resolver.SymbolicPattern{ .module = 0, .ty = @enumFromInt(0) };
    const byte = Resolver.SymbolicPattern{ .module = 0, .ty = @enumFromInt(1) };
    const concrete = Resolver.SymbolicPattern{ .module = 0, .ty = @enumFromInt(2) };
    const equivalent = Resolver.SymbolicPattern{ .module = 0, .ty = @enumFromInt(3) };
    try std.testing.expect(try resolver.symbolicTypesEqual(int, int));
    try std.testing.expect(!try resolver.symbolicTypesEqual(int, byte));
    try std.testing.expect(try resolver.symbolicTypesEqual(concrete, equivalent));
    const nominal = Resolver.SymbolicPattern{ .module = 0, .ty = @enumFromInt(4) };
    try std.testing.expect(!try resolver.symbolicTypesEqual(concrete, nominal));
    try std.testing.expect(!try resolver.symbolicTypesEqual(nominal, concrete));
    try graph.markTypeUnresolved(allocator, @enumFromInt(1));
    try std.testing.expect(!try resolver.symbolicTypesEqual(concrete, equivalent));
    try std.testing.expectEqual(@as(usize, 2), graph.types.items.len);
}

test "unconstrained generic types and functions need no constraint substitutions" {
    const allocator = std.testing.allocator;
    var module: module_sg.ModuleSemanticGraph = .{};
    defer module.deinit(allocator);
    try module.semantic.parameterized_storage.comptime_parameters.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .kind = .type });
    try module.semantic.parameterized_storage.parameterized_types.append(allocator, .{ .declaration = @enumFromInt(0), .parameters = .{ .start = 0, .len = 1 }, .body = @enumFromInt(0) });
    try module.semantic.parameterized_storage.parameterized_functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .parameters = .{ .start = 0, .len = 1 },
        .input = @enumFromInt(0),
        .output = @enumFromInt(0),
        .body = null,
    });
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.modules.append(allocator, .{ .dir = .{ .start = 0, .len = 0 }, .files = .{ .start = 0, .len = 1 }, .declarations = .{ .start = 0, .len = 1 } });
    try graph.family_definitions.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .kind = .type, .parameter_count = 1, .template_index = 0 });
    try graph.family_definitions.append(allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .kind = .function, .parameter_count = 1, .template_index = 0 });
    try graph.types.append(allocator, .{ .generic = .{ .base = @enumFromInt(0), .arguments = .{ .start = 0, .len = 1 } } });
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.generic_arguments.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = @enumFromInt(1) } });
    try graph.generic_function_instances.append(allocator, .{
        .function = @enumFromInt(0),
        .parameterized_definition = @enumFromInt(1),
        .arguments = .{ .start = 0, .len = 1 },
    });
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    const offsets = [_]globalizer.Offsets{std.mem.zeroes(globalizer.Offsets)};
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    var generics: generic_mod.Resolver = .{ .allocator = failing.allocator(), .graph = &graph, .modules = &modules, .offsets = &offsets, .core = undefined };
    defer generics.deinit();
    var core: core_mod.Resolver = .{ .allocator = failing.allocator(), .graph = &graph, .modules = &modules, .offsets = &offsets };
    defer core.deinit();
    var resolver: Resolver = .{ .allocator = failing.allocator(), .graph = &graph, .modules = &modules, .offsets = &offsets, .core = &core, .generics = &generics };
    defer resolver.deinit();
    try std.testing.expectEqual(null, try resolver.findGenericTypeConstraintFailure());
    try resolver.validateGenericFunctionInstances();
}

fn extendTemplateIndex(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var first: module_sg.ModuleSemanticGraph = .{};
    defer first.deinit(a);
    var second: module_sg.ModuleSemanticGraph = .{};
    defer second.deinit(a);
    const template: parameterized_storage.ContractConformance = .{
        .parameters = .{ .start = 0, .len = 1 },
        .contract_ref = .{ .module = @enumFromInt(0) },
        .participants = .{ .start = 0, .len = 1 },
        .associated_arguments = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
    };
    try second.semantic.parameterized_storage.contract_conformances.appendNTimes(a, template, 32);
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    const offsets = [_]globalizer.Offsets{ std.mem.zeroes(globalizer.Offsets), std.mem.zeroes(globalizer.Offsets) };
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.declarations.append(a, .{ .kind = .contract_type, .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 }, .family_definition = @enumFromInt(0) });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = modules[0..1], .offsets = offsets[0..1], .core = undefined, .generics = undefined };
    defer resolver.deinit();
    const declaration: global_sg.GlobalFamilyDefinitionId = @enumFromInt(0);
    try std.testing.expectEqual(@as(usize, 0), (try resolver.implementationTemplates(declaration, 1)).len);
    const saved = resolver.checkpointResolution();
    resolver.modules = &modules;
    resolver.offsets = &offsets;
    const entries = resolver.implementationTemplates(declaration, 1) catch |err| {
        const group = resolver.implementation_templates.get(.{ .declaration = declaration, .arity = 1 }).?;
        try std.testing.expectEqual(@as(usize, 1), group.module_count);
        try std.testing.expectEqual(@as(usize, 0), group.entries.items.len);
        return err;
    };
    try std.testing.expectEqual(@as(usize, 32), entries.len);
    for (entries, 0..) |entry, index| {
        try std.testing.expectEqual(@as(usize, 1), entry.module);
        try std.testing.expectEqual(index, entry.index);
    }
    try std.testing.expectEqual(@as(usize, 32), (try resolver.implementationTemplates(declaration, 1)).len);
    resolver.modules = modules[0..1];
    try std.testing.expectError(error.InvalidContractModulePrefix, resolver.implementationTemplates(declaration, 1));
    _ = try resolver.implementationTemplates(@enumFromInt(1), 1);
    resolver.rollbackResolution(saved);
    try std.testing.expectEqual(@as(usize, 0), (try resolver.implementationTemplates(declaration, 1)).len);
    try std.testing.expect(resolver.implementation_templates.get(.{ .declaration = @enumFromInt(1), .arity = 1 }) == null);
}

test "contract template indexes extend empty groups transactionally" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, extendTemplateIndex, .{});
}

const std = @import("std");
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

pub const Stats = struct {
    checks: u32 = 0,
    concrete_hits: u32 = 0,
    parameterized_hits: u32 = 0,
    defaults: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    stats: Stats = .{},
    pub fn deinit(self: *Resolver) void {
        _ = self;
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
            .resolve_abstract => |value| blk: {
                const declaration = globalizer.globalDecl(o, value.declaration);
                const ty = self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse break :blk .deferred;
                const abstract_decl = try self.resolveExternalAbstract(module_index, value.abstract_ref);
                break :blk resolution.Result.fromBool(try self.implements(ty, abstract_decl));
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
            const node = (try self.makeVirtualize(module_index, reference, input)) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            return .resolved;
        }
        if (!self.ownsVirtualCall(module_index, module, reference, input)) return .not_applicable;
        const node = (try self.makeVirtualCall(
            module_index,
            reference,
            input,
            .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset },
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
            const abstract_ty = switch (self.graph.types.items[@intFromEnum(pointee)]) {
                .virtual => |abstract_type| abstract_type,
                else => pointee,
            };
            const abstract_decl = switch (self.graph.types.items[@intFromEnum(abstract_ty)]) {
                .declared => |declaration| declaration,
                else => continue,
            };
            const located = self.findAbstractDefinition(abstract_decl) orelse continue;
            if (located.definition.parameters.len != 0) continue;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            for (storage.abstract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len]) |requirement| {
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
    ) !?global_sg.Node {
        const local_arguments = reference.generic_arguments orelse return null;
        const arguments = try self.generics.relocateModuleArguments(module_index, local_arguments);
        var abstract_type: ?global_sg.GlobalTypeId = null;
        for (self.graph.generic_arguments.items[arguments.start..][0..arguments.len]) |argument| {
            if (!std.mem.eql(u8, self.graph.text(argument.name), "abstract")) continue;
            abstract_type = switch (argument.value) {
                .type => |ty| ty,
                else => return null,
            };
        }
        const abstract_ty = abstract_type orelse return null;
        const abstract_decl = switch (self.graph.types.items[@intFromEnum(abstract_ty)]) {
            .declared => |declaration| declaration,
            else => return null,
        };
        const located = self.findAbstractDefinition(abstract_decl) orelse return null;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        var value: ?global_sg.GlobalNodeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (std.mem.eql(u8, self.graph.text(field.name), "value")) value = field.value;
        }
        const handle = value orelse return null;
        const handle_ty = self.graph.nodes.items[@intFromEnum(handle)].ty orelse return null;
        const concrete = switch (self.graph.types.items[@intFromEnum(handle_ty)]) {
            .pointer => |pointer| pointer.child,
            else => return null,
        };
        if (!try self.implements(concrete, abstract_decl)) return null;

        var methods: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
        defer methods.deinit(self.allocator);
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        for (storage.abstract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, method_index| {
            const instance = try self.requirementInstance(abstract_decl, concrete, located, requirement, @intCast(method_index));
            const implementation = self.findConcreteMethod(self.modules[located.module_index].text(requirement.name), instance.input) orelse return null;
            try methods.append(self.allocator, implementation);
        }
        const method_start: u32 = @intCast(self.graph.function_refs.items.len);
        try self.graph.function_refs.appendSlice(self.allocator, methods.items);
        const safety_start: u32 = @intCast(self.graph.virtual_registry_refs.items.len);
        for (methods.items, 0..) |_, index| {
            const registry: global_sg.GlobalVirtualRegistryId = @enumFromInt(@as(u32, @intCast(self.graph.virtual_registries.items.len)));
            try self.graph.virtual_registries.append(self.allocator, .{
                .implementations = .{ .start = method_start + @as(u32, @intCast(index)), .len = 1 },
            });
            try self.graph.virtual_registry_refs.append(self.allocator, registry);
        }
        const virtual_ty = try self.generics.internType(.{ .virtual = abstract_ty });
        const virtualize: global_sg.GlobalVirtualizeId = @enumFromInt(@as(u32, @intCast(self.graph.virtualizes.items.len)));
        try self.graph.virtualizes.append(self.allocator, .{
            .value = handle,
            .concrete_type = concrete,
            .abstract_decl = abstract_decl,
            .virtual_type = virtual_ty,
            .methods = .{ .start = method_start, .len = @intCast(methods.items.len) },
            .safety_methods = .{ .start = safety_start, .len = @intCast(methods.items.len) },
            .source = self.sourceFor(module_index, reference.source),
        });
        return .{
            .source = self.sourceFor(module_index, reference.source),
            .ty = virtual_ty,
            .content = .{ .virtualize = virtualize },
        };
    }

    fn findConcreteMethod(self: *Resolver, name: []const u8, expected_input: global_sg.GlobalTypeId) ?global_sg.GlobalFunctionId {
        const expected_fields = global_types.fields(self.graph, expected_input) orelse return null;
        var found: ?global_sg.GlobalFunctionId = null;
        for (self.graph.functions.items, 0..) |function, raw| {
            const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(declaration.name), name) or function.input.len != expected_fields.len) continue;
            var compatible = true;
            for (0..expected_fields.len) |index| {
                const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(index))];
                const actual = self.graph.fields.items[function.input.start + @as(u32, @intCast(index))];
                if (!std.mem.eql(u8, self.graph.text(expected.name), self.graph.text(actual.name)) or
                    !global_types.equal(self.graph, expected.ty, actual.ty))
                {
                    compatible = false;
                    break;
                }
            }
            if (!compatible) continue;
            if (found != null) return null;
            found = @enumFromInt(@as(u32, @intCast(raw)));
        }
        return found;
    }

    pub fn resolveStaticRequirementCall(
        self: *Resolver,
        module_index: usize,
        abstract_ref: ir.DeclarationRef,
        concrete: global_sg.GlobalTypeId,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !?global_sg.Node {
        if (reference.module_path != null or reference.generic_arguments != null) return null;
        const abstract_decl = try self.resolveDeclarationRef(module_index, abstract_ref, .abstract_type);
        if (!try self.implements(concrete, abstract_decl)) return null;
        const located = self.findAbstractDefinition(abstract_decl) orelse return null;
        // Parameterized abstract requirements need their own abstract argument
        // substitution. The current hidden local-abstract lowering only needs
        // non-parameterized contracts such as Allocator.
        if (located.definition.parameters.len != 0) return null;

        const method_name = self.modules[module_index].text(reference.name);
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        for (storage.abstract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, method_index| {
            if (!std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), method_name)) continue;
            const instance = try self.requirementInstance(abstract_decl, concrete, located, requirement, @intCast(method_index));
            const implementation = self.findConcreteMethod(method_name, instance.input) orelse continue;
            const input_fields = global_types.fields(self.graph, instance.input) orelse continue;
            if (self.core.scoreCallInput(input_fields, input) == null) continue;
            if (!try self.core.completeCallInputFields(input_fields, input)) continue;
            return .{
                .source = source,
                .ty = try self.core.functionOutputType(implementation),
                .content = .{ .function_call = .{ .callee = implementation, .input = input } },
            };
        }
        return null;
    }

    pub fn resolveNestedCall(
        self: *Resolver,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) anyerror!?global_sg.Node {
        return self.makeVirtualCall(module_index, reference, input, source);
    }

    pub fn concreteImplements(self: *Resolver, concrete: global_sg.GlobalTypeId, abstract_type: global_sg.GlobalTypeId) bool {
        const declaration = switch (self.graph.types.items[@intFromEnum(abstract_type)]) {
            .declared => |value| value,
            else => return false,
        };
        if (self.findAbstractDefinition(declaration) == null) return false;
        return self.implements(concrete, declaration) catch false;
    }

    /// Abstract fields use static backing storage. Once an assignment selects
    /// a concrete implementer, every later access and codegen operation must
    /// use that same representation; mixing implementers would make the
    /// aggregate layout depend on control flow.
    pub fn materializeAbstractFieldStorage(self: *Resolver) !bool {
        var changed = false;
        for (self.graph.nodes.items) |*node| {
            const store = switch (node.content) {
                .struct_field_store => |*value| value,
                else => continue,
            };
            const actual_ty = self.graph.node(store.value).ty orelse continue;
            const fields = global_types.fields(self.graph, store.struct_type) orelse continue;
            if (store.field_index >= fields.len) return error.InvalidAbstractFieldIndex;
            const field = &self.graph.fields.items[fields.start + store.field_index];
            if (global_types.equal(self.graph, field.ty, actual_ty)) continue;
            if (!try self.abstractStorageCompatible(field.ty, actual_ty)) continue;
            if (field.storage_type) |existing| {
                if (!global_types.equal(self.graph, existing, actual_ty)) return error.ConflictingAbstractFieldStorage;
            } else {
                field.storage_type = actual_ty;
                changed = true;
            }
            if (!global_types.equal(self.graph, store.field_type, actual_ty)) {
                store.field_type = actual_ty;
                changed = true;
            }
        }
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
            if (access.field_index >= fields.len) return error.InvalidAbstractFieldIndex;
            const effective = global_types.effectiveFieldType(self.graph.fields.items[fields.start + access.field_index]);
            if (node.ty == null or !global_types.equal(self.graph, node.ty.?, effective)) {
                node.ty = effective;
                changed = true;
            }
        }
        return changed;
    }

    fn abstractStorageCompatible(self: *Resolver, expected: global_sg.GlobalTypeId, actual: global_sg.GlobalTypeId) !bool {
        const expected_pointer = switch (self.graph.types.items[@intFromEnum(expected)]) {
            .pointer => |value| value,
            else => return false,
        };
        const actual_pointer = switch (self.graph.types.items[@intFromEnum(actual)]) {
            .pointer => |value| value,
            else => return false,
        };
        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        const abstract_decl = switch (self.graph.types.items[@intFromEnum(expected_pointer.child)]) {
            .declared => |value| value,
            else => return false,
        };
        if (self.findAbstractDefinition(abstract_decl) == null) return false;
        return self.implements(actual_pointer.child, abstract_decl);
    }

    fn makeVirtualCall(
        self: *Resolver,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !?global_sg.Node {
        if (reference.module_path != null or reference.generic_arguments != null) return null;
        const module = &self.modules[module_index];
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |item| item,
            else => return null,
        };
        const method_name = module.text(reference.name);

        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |actual| {
            const actual_ty = self.graph.nodes.items[@intFromEnum(actual.value)].ty orelse continue;
            const pointee = switch (self.graph.types.items[@intFromEnum(actual_ty)]) {
                .pointer => |pointer| pointer.child,
                else => continue,
            };
            const abstract_ty = switch (self.graph.types.items[@intFromEnum(pointee)]) {
                .virtual => |abstract_type| abstract_type,
                else => pointee,
            };
            const abstract_decl = switch (self.graph.types.items[@intFromEnum(abstract_ty)]) {
                .declared => |declaration| declaration,
                else => continue,
            };
            const located = self.findAbstractDefinition(abstract_decl) orelse continue;
            if (located.definition.parameters.len != 0) continue;
            const parameterized_forms_storage = &self.modules[located.module_index].semantic.parameterized_storage;
            for (parameterized_forms_storage.abstract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, method_index| {
                if (!std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), method_name)) continue;
                const instance = try self.requirementInstance(abstract_decl, abstract_ty, located, requirement, @intCast(method_index));
                const input_ty = instance.input;
                const output_ty = instance.output;
                const input_fields = global_types.fields(self.graph, input_ty) orelse continue;
                const output_fields = global_types.fields(self.graph, output_ty) orelse continue;
                if (self.core.scoreCallInput(input_fields, input) == null) continue;
                if (!try self.core.completeCallInputFields(input_fields, input)) continue;

                var self_index: ?u32 = null;
                var permission: primitives.PointerMutability = .read_only;
                for (0..input_fields.len) |field_index| {
                    const field = self.graph.fields.items[input_fields.start + @as(u32, @intCast(field_index))];
                    switch (self.graph.types.items[@intFromEnum(field.ty)]) {
                        .pointer => |pointer| if (global_types.equal(self.graph, pointer.child, abstract_ty)) {
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
                try self.graph.virtual_registries.append(self.allocator, .{ .implementations = .{ .start = @intCast(self.graph.function_refs.items.len), .len = 0 } });
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

    const LocatedAbstractDefinition = struct {
        module_index: usize,
        definition: parameterized_storage.AbstractDefinition,
    };

    const RequirementInstance = struct {
        declaration: global_sg.GlobalDeclId,
        method_index: u32,
        input: global_sg.GlobalTypeId,
        output: global_sg.GlobalTypeId,
    };

    fn requirementInstance(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        self_type: global_sg.GlobalTypeId,
        located: LocatedAbstractDefinition,
        requirement: parameterized_storage.AbstractRequirement,
        method_index: u32,
    ) !RequirementInstance {
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        return .{
            .declaration = declaration,
            .method_index = method_index,
            .input = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings, self_type),
            .output = try self.generics.instantiateParameterizedType(located.module_index, requirement.output, &bindings, self_type),
        };
    }

    fn findAbstractDefinition(self: *const Resolver, declaration: global_sg.GlobalDeclId) ?LocatedAbstractDefinition {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return null;
        const module_index: usize = @intFromEnum(owner);
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.parameterized_storage.abstract_definitions.items) |definition|
            if (definition.declaration == local) return .{ .module_index = module_index, .definition = definition };
        return null;
    }

    fn implementsDepth(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        abstract_decl: global_sg.GlobalDeclId,
        depth: u8,
    ) !bool {
        if (depth >= 64) return false;
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.abstract_implementations.items) |implementation| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, implementation.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                const candidate_type = globalizer.globalType(self.offsets[module_index], implementation.ty);
                if (global_types.equal(self.graph, concrete, candidate_type)) {
                    self.stats.concrete_hits += 1;
                    return true;
                }
                const inherited = switch (self.graph.types.items[@intFromEnum(candidate_type)]) {
                    .declared => |declaration| declaration,
                    else => continue,
                };
                if (inherited == abstract_decl or self.findAbstractDefinition(inherited) == null) continue;
                if (try self.implementsDepth(concrete, inherited, depth + 1)) {
                    self.stats.concrete_hits += 1;
                    return true;
                }
            }
            for (module.semantic.parameterized_storage.parameterized_abstract_implementations.items) |parameterized| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, parameterized.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                if (self.matchesImplementationParameterized(module_index, concrete, parameterized) catch false) {
                    self.stats.parameterized_hits += 1;
                    return true;
                }
            }
        }
        return false;
    }

    pub fn inferConstraintBindings(
        self: *Resolver,
        module_index: usize,
        constraint_id: parameterized_storage.AbstractConstraintId,
        concrete: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage;
        const constraint = storage.abstract_constraints.items[@intFromEnum(constraint_id)];
        const abstract_decl = try self.resolveDeclarationRef(module_index, constraint.abstract_ref, .abstract_type);
        if (!try self.implementsDepth(concrete, abstract_decl, 0)) return false;
        if (constraint.arguments.len == 0) return true;

        const located = self.findAbstractDefinition(abstract_decl) orelse return false;

        for (self.modules, 0..) |*implementation_module, implementation_module_index| {
            const implementation_storage = &implementation_module.semantic.parameterized_storage;
            for (implementation_storage.abstract_implementations.items) |implementation| {
                const candidate_abstract = try self.resolveDeclarationRef(
                    implementation_module_index,
                    implementation.abstract_ref,
                    .abstract_type,
                );
                if (candidate_abstract != abstract_decl) continue;
                const candidate_type = globalizer.globalType(self.offsets[implementation_module_index], implementation.ty);

                if (!global_types.equal(self.graph, concrete, candidate_type)) continue;
                return self.matchDirectConstraintArguments(
                    module_index,
                    constraint,
                    located,
                    implementation_module_index,
                    implementation,
                    bindings,
                );
            }
        }
        return false;
    }

    fn matchDirectConstraintArguments(
        self: *Resolver,
        constraint_module_index: usize,
        constraint: parameterized_storage.AbstractConstraint,
        located: LocatedAbstractDefinition,
        implementation_module_index: usize,
        implementation: parameterized_storage.AbstractImplementation,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        if (implementation.arguments.len != located.definition.parameters.len) return false;
        const constraint_module = &self.modules[constraint_module_index];
        const constraint_ir = &constraint_module.semantic.parameterized_storage.ir;
        const target_module = &self.modules[located.module_index];
        const target_storage = &target_module.semantic.parameterized_storage;
        const implementation_storage = &self.modules[implementation_module_index].semantic.parameterized_storage;

        for (constraint_ir.generic_arguments.items[constraint.arguments.start..][0..constraint.arguments.len], 0..) |requested, requested_position| {
            const requested_name = constraint_module.text(requested.name);
            var target_offset: ?usize = null;
            if (requested_name.len == 0) {
                if (requested_position < located.definition.parameters.len) target_offset = requested_position;
            } else {
                for (0..located.definition.parameters.len) |offset| {
                    const raw = located.definition.parameters.start + @as(u32, @intCast(offset));
                    const parameter = target_storage.comptime_parameters.items[raw];
                    if (std.mem.eql(u8, target_module.text(parameter.name), requested_name)) {
                        target_offset = offset;
                        break;
                    }
                }
            }
            const offset = target_offset orelse return false;
            const associated = implementation_storage.abstract_arguments.items[
                implementation.arguments.start + @as(u32, @intCast(offset))
            ];
            switch (requested.value) {
                .type => |pattern| {
                    const actual = switch (associated) {
                        .type => |local| globalizer.globalType(self.offsets[implementation_module_index], local),
                        else => {
                            return false;
                        },
                    };
                    const matched = try self.inferConstraintTypePattern(constraint_module_index, pattern, actual, bindings);

                    if (!matched) return false;
                },
                .comptime_int => |pattern| {
                    const actual = switch (associated) {
                        .comptime_int => |value| value,
                        else => return false,
                    };
                    if (!try self.inferConstraintIntPattern(constraint_module_index, pattern, actual, bindings))
                        return false;
                },
            }
        }
        return true;
    }

    fn inferConstraintTypePattern(
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
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings, null) catch return false;
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
            .binary => (self.generics.evalInt(module_index, pattern, bindings) catch return false) == actual,
        };
    }

    pub fn implements(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        abstract_decl: global_sg.GlobalDeclId,
    ) !bool {
        self.stats.checks += 1;
        return self.implementsDepth(concrete, abstract_decl, 0);
    }

    pub fn defaultType(
        self: *Resolver,
        abstract_decl: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !?global_sg.GlobalTypeId {
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.abstract_defaults.items) |default| {
                const candidate = try self.resolveDeclarationRef(module_index, default.abstract_ref, .abstract_type);
                if (candidate != abstract_decl) continue;
                self.stats.defaults += 1;
                return globalizer.globalType(self.offsets[module_index], default.ty);
            }
            for (module.semantic.parameterized_storage.parameterized_abstract_defaults.items) |default| {
                const candidate = try self.resolveDeclarationRef(module_index, default.abstract_ref, .abstract_type);
                if (candidate != abstract_decl) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                try self.generics.bindGlobalArguments(module_index, default.parameters, arguments, &bindings);
                self.stats.defaults += 1;
                return try self.generics.instantiateParameterizedType(module_index, default.ty, &bindings, null);
            }
        }
        return null;
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
                const constraint = module.semantic.parameterized_storage.abstract_constraints.items[@intFromEnum(constraint_id)];
                const abstract_decl = try self.resolveDeclarationRef(module_index, constraint.abstract_ref, .abstract_type);
                const concrete = bindings.types[param_raw] orelse return error.AbstractConstraintRequiresTypeParameter;
                const satisfied = try self.implements(concrete, abstract_decl);
                if (!satisfied) return error.GenericAbstractConstraintNotSatisfied;
            }
        }
    }

    /// Virtual call safety is checked against every concrete implementation
    /// that can inhabit the erased abstract type. Resolution records exact
    /// methods on each `virtualize` node for codegen; once the program-wide set
    /// is stable, this pass builds the conservative registries consumed by the
    /// summary engine.
    pub fn closeVirtualMethodRegistries(self: *Resolver) !void {
        for (self.graph.virtualizes.items) |virtualize| {
            const registries = self.graph.virtual_registry_refs.items[virtualize.safety_methods.start..][0..virtualize.safety_methods.len];
            for (registries, 0..) |registry_id, method_index|
                try self.closeVirtualMethodRegistry(registry_id, virtualize.abstract_decl, method_index);
        }

        for (self.graph.virtual_calls.items) |call| {
            const abstract_decl = self.virtualCallAbstract(call) orelse continue;
            try self.closeVirtualMethodRegistry(call.safety_methods, abstract_decl, call.method_index);
        }
    }

    fn closeVirtualMethodRegistry(
        self: *Resolver,
        registry_id: global_sg.GlobalVirtualRegistryId,
        abstract_decl: global_sg.GlobalDeclId,
        method_index: usize,
    ) !void {
        var implementations: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
        defer implementations.deinit(self.allocator);

        for (self.graph.virtualizes.items) |candidate| {
            if (candidate.abstract_decl != abstract_decl or method_index >= candidate.methods.len) continue;
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
    }

    fn virtualCallAbstract(self: *const Resolver, call: global_sg.VirtualCall) ?global_sg.GlobalDeclId {
        const handle_ty = self.graph.nodes.items[@intFromEnum(call.handle)].ty orelse return null;
        const handle_child = switch (self.graph.types.items[@intFromEnum(handle_ty)]) {
            .pointer => |pointer| pointer.child,
            else => handle_ty,
        };
        if (self.abstractDeclFromType(handle_child)) |declaration| return declaration;

        const input_fields = global_types.fields(self.graph, call.input_type) orelse return null;
        if (call.self_input_index >= input_fields.len) return null;
        const self_ty = self.graph.fields.items[input_fields.start + call.self_input_index].ty;
        const self_child = switch (self.graph.types.items[@intFromEnum(self_ty)]) {
            .pointer => |pointer| pointer.child,
            else => self_ty,
        };
        return self.abstractDeclFromType(self_child);
    }

    fn abstractDeclFromType(self: *const Resolver, ty: global_sg.GlobalTypeId) ?global_sg.GlobalDeclId {
        const abstract_ty = switch (self.graph.types.items[@intFromEnum(ty)]) {
            .virtual => |abstract_type| abstract_type,
            else => ty,
        };
        return switch (self.graph.types.items[@intFromEnum(abstract_ty)]) {
            .declared => |declaration| if (self.findAbstractDefinition(declaration) != null) declaration else null,
            else => null,
        };
    }

    fn matchesImplementationParameterized(
        self: *Resolver,
        module_index: usize,
        concrete: global_sg.GlobalTypeId,
        parameterized: parameterized_storage.ParameterizedAbstractImplementation,
    ) !bool {
        const module = &self.modules[module_index];
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);

        if (parameterized.concrete_type_pattern) |pattern|
            return self.inferConstraintTypePattern(module_index, pattern, concrete, &bindings);

        const concrete_name = parameterized.concrete_name orelse return false;
        const wanted = module.text(concrete_name);
        const identity = switch (self.graph.types.items[@intFromEnum(concrete)]) {
            .generic => |value| value,
            .declared => |decl| {
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(decl)].name), wanted)) return false;
                return parameterized.parameters.len == 0;
            },
            else => return false,
        };
        if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(identity.base)].name), wanted)) return false;
        if (identity.arguments.len != parameterized.concrete_parameter_count) return false;

        try self.generics.bindGlobalArguments(module_index, parameterized.parameters, identity.arguments, &bindings);
        return true;
    }

    fn resolveExternalAbstract(self: *Resolver, module_index: usize, id: module_entities.ExternalRefId) !global_sg.GlobalDeclId {
        const reference = self.modules[module_index].semantic.external_refs.items[@intFromEnum(id)];
        return self.core.resolveDeclaration(module_index, reference, &.{.abstract_type});
    }

    fn resolveDeclarationRef(
        self: *Resolver,
        module_index: usize,
        reference: ir.DeclarationRef,
        kind: primitives.DeclarationKind,
    ) !global_sg.GlobalDeclId {
        return switch (reference) {
            .module => |local| globalizer.globalDecl(self.offsets[module_index], local),
            .external => |external| self.core.resolveDeclaration(
                module_index,
                self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)],
                &.{kind},
            ),
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

test "abstract resolver keeps compile-time relation metadata outside GlobalSG" {
    try std.testing.expect(@sizeOf(Stats) <= 16);
    try std.testing.expect(@sizeOf(global_sg.GlobalDeclId) == 4);
}

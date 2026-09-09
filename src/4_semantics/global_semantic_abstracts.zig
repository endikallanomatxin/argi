const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const templates = @import("module_semantic_templates.zig");
const ir = @import("module_semantic_template_ir.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const core_mod = @import("global_semantic_core.zig");
const generic_mod = @import("global_semantic_generics.zig");
const global_types = @import("global_semantic_types.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    checks: u32 = 0,
    concrete_hits: u32 = 0,
    template_hits: u32 = 0,
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
    requirement_instances: std.ArrayList(RequirementInstance) = .empty,

    pub fn deinit(self: *Resolver) void {
        self.requirement_instances.deinit(self.allocator);
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        return switch (operation) {
            .resolve_call => |value| @as(?bool, try self.resolveVirtualCall(module, o, value)),
            .resolve_abstract => |value| blk: {
                const declaration = globalizer.globalDecl(o, value.declaration);
                const ty = self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse break :blk @as(?bool, false);
                const abstract_decl = try self.resolveExternalAbstract(module_index, value.abstract_ref);
                break :blk @as(?bool, try self.implements(ty, abstract_decl));
            },
            else => null,
        };
    }

    fn resolveVirtualCall(
        self: *Resolver,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.module_path != null or reference.generic_arguments != null) return false;
        const input = globalizer.globalNode(o, value.input);
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
            const templates_storage = &self.modules[located.module_index].semantic.templates;
            for (templates_storage.abstract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, method_index| {
                if (!std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), method_name)) continue;
                const instance = try self.requirementInstance(abstract_decl, abstract_ty, located, requirement, @intCast(method_index));
                const input_ty = instance.input;
                const output_ty = instance.output;
                const input_fields = global_types.fields(self.graph, input_ty) orelse continue;
                const output_fields = global_types.fields(self.graph, output_ty) orelse continue;
                if (self.core.scoreCallInput(input_fields, input) == null) continue;
                if (!try self.core.completeCallInputFields(input_fields, input)) continue;

                var self_index: ?u32 = null;
                var permission: syn.PointerMutability = .read_only;
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
                const target = globalizer.globalNode(o, value.node);
                self.graph.nodes.items[@intFromEnum(target)] = .{
                    .source = .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset },
                    .ty = if (value.expected_type) |local| globalizer.globalType(o, local) else try self.core.outputTypeForFields(output_fields),
                    .content = .{ .virtual_call = call_id },
                };
                return true;
            }
        }
        return false;
    }

    const LocatedAbstractDefinition = struct {
        module_index: usize,
        definition: templates.AbstractDefinition,
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
        requirement: templates.AbstractRequirement,
        method_index: u32,
    ) !RequirementInstance {
        for (self.requirement_instances.items) |instance|
            if (instance.declaration == declaration and instance.method_index == method_index) return instance;
        const storage = &self.modules[located.module_index].semantic.templates;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.generic_parameters.items.len);
        defer bindings.deinit(self.allocator);
        const instance = RequirementInstance{
            .declaration = declaration,
            .method_index = method_index,
            .input = try self.generics.instantiateTemplateType(located.module_index, requirement.input, &bindings, self_type),
            .output = try self.generics.instantiateTemplateType(located.module_index, requirement.output, &bindings, self_type),
        };
        try self.requirement_instances.append(self.allocator, instance);
        return instance;
    }

    fn findAbstractDefinition(self: *const Resolver, declaration: global_sg.GlobalDeclId) ?LocatedAbstractDefinition {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return null;
        const module_index: usize = @intFromEnum(owner);
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.templates.abstract_definitions.items) |definition|
            if (definition.declaration == local) return .{ .module_index = module_index, .definition = definition };
        return null;
    }

    pub fn implements(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        abstract_decl: global_sg.GlobalDeclId,
    ) !bool {
        self.stats.checks += 1;
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.templates.abstract_implementations.items) |implementation| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, implementation.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                const candidate_type = globalizer.globalType(self.offsets[module_index], implementation.ty);
                if (global_types.equal(self.graph, concrete, candidate_type)) {
                    self.stats.concrete_hits += 1;
                    return true;
                }
            }
            for (module.semantic.templates.abstract_implementation_templates.items) |template| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, template.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                if (try self.matchesImplementationTemplate(module_index, concrete, template)) {
                    self.stats.template_hits += 1;
                    return true;
                }
            }
        }
        return false;
    }

    pub fn defaultType(
        self: *Resolver,
        abstract_decl: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !?global_sg.GlobalTypeId {
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.templates.abstract_defaults.items) |default| {
                const candidate = try self.resolveDeclarationRef(module_index, default.abstract_ref, .abstract_type);
                if (candidate != abstract_decl) continue;
                self.stats.defaults += 1;
                return globalizer.globalType(self.offsets[module_index], default.ty);
            }
            for (module.semantic.templates.abstract_default_templates.items) |default| {
                const candidate = try self.resolveDeclarationRef(module_index, default.abstract_ref, .abstract_type);
                if (candidate != abstract_decl) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.templates.generic_parameters.items.len);
                defer bindings.deinit(self.allocator);
                try self.generics.bindGlobalArguments(module_index, default.parameters, arguments, &bindings);
                self.stats.defaults += 1;
                return try self.generics.instantiateTemplateType(module_index, default.ty, &bindings, null);
            }
        }
        return null;
    }

    /// Validate constraints after a concrete function instance has been created.
    /// This is deliberately a second pass: function monomorphization stays
    /// independent of the abstract catalog, while no invalid instance can leave
    /// GlobalSema as a final graph.
    pub fn validateGenericFunctionInstances(self: *Resolver) !void {
        for (self.graph.generic_function_instances.items) |instance| {
            const owner = self.graph.moduleForDeclaration(instance.template_declaration) orelse return error.InvalidGenericFunctionOwner;
            const module_index: usize = @intFromEnum(owner);
            const template = self.findFunctionTemplate(module_index, instance.template_declaration) orelse continue;
            const module = &self.modules[module_index];
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.templates.generic_parameters.items.len);
            defer bindings.deinit(self.allocator);
            try self.generics.bindGlobalArguments(module_index, template.parameters, instance.arguments, &bindings);

            for (0..template.parameters.len) |offset| {
                const param_raw = template.parameters.start + @as(u32, @intCast(offset));
                const parameter = module.semantic.templates.generic_parameters.items[param_raw];
                const constraint_id = parameter.constraint orelse continue;
                const constraint = module.semantic.templates.abstract_constraints.items[@intFromEnum(constraint_id)];
                const abstract_decl = try self.resolveDeclarationRef(module_index, constraint.abstract_ref, .abstract_type);
                const concrete = bindings.types[param_raw] orelse return error.AbstractConstraintRequiresTypeParameter;
                if (!try self.implements(concrete, abstract_decl)) return error.GenericAbstractConstraintNotSatisfied;
            }
        }
    }

    fn matchesImplementationTemplate(
        self: *Resolver,
        module_index: usize,
        concrete: global_sg.GlobalTypeId,
        template: templates.AbstractImplementationTemplate,
    ) !bool {
        const module = &self.modules[module_index];
        const concrete_name = template.concrete_name orelse return false;
        const wanted = module.text(concrete_name);

        const identity = switch (self.graph.types.items[@intFromEnum(concrete)]) {
            .generic => |value| value,
            .declared => |decl| {
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(decl)].name), wanted)) return false;
                return template.parameters.len == 0;
            },
            else => return false,
        };
        if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(identity.base)].name), wanted)) return false;
        if (identity.arguments.len != template.concrete_parameter_count) return false;

        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.templates.generic_parameters.items.len);
        defer bindings.deinit(self.allocator);
        try self.generics.bindGlobalArguments(module_index, template.parameters, identity.arguments, &bindings);
        if (template.concrete_type_pattern) |pattern| {
            const expected = try self.generics.instantiateTemplateType(module_index, pattern, &bindings, concrete);
            if (!global_types.equal(self.graph, expected, concrete)) return false;
        }
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

    fn findFunctionTemplate(
        self: *Resolver,
        module_index: usize,
        declaration: global_sg.GlobalDeclId,
    ) ?templates.GenericFunctionTemplate {
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.templates.generic_function_templates.items) |template|
            if (template.declaration == local) return template;
        return null;
    }
};

test "abstract resolver keeps compile-time relation metadata outside GlobalSG" {
    try std.testing.expect(@sizeOf(Stats) <= 16);
    try std.testing.expect(@sizeOf(global_sg.GlobalDeclId) == 4);
}

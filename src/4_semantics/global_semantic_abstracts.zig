const std = @import("std");
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

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        _ = module;
        return switch (operation) {
            .resolve_abstract => |value| blk: {
                const declaration = globalizer.globalDecl(o, value.declaration);
                const ty = self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse break :blk false;
                const abstract_decl = try self.resolveExternalAbstract(module_index, value.abstract_ref);
                break :blk try self.implements(ty, abstract_decl);
            },
            else => null,
        };
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
            .declared => |decl| blk: {
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

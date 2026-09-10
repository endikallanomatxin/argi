const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const parameterized_storage = @import("module_parameterized_storage.zig");
const ir = @import("module_parameterized_ir.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const core_mod = @import("global_semantic_core.zig");
const generic_mod = @import("global_semantic_generics.zig");
const global_types = @import("global_semantic_types.zig");
const primitives = @import("semantic_primitives.zig");

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
    ) !?bool {
        return switch (operation) {
            .resolve_call => |value| @as(?bool, try self.resolveVirtualCall(module_index, module, o, value)),
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
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        const input = globalizer.globalNode(o, value.input);
        if (std.mem.eql(u8, module.text(reference.name), "to_virtual")) {
            const node = (try self.makeVirtualize(module_index, reference, input)) orelse return false;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            return true;
        }
        const node = (try self.makeVirtualCall(
            module_index,
            reference,
            input,
            .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset },
        )) orelse return false;
        self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
        return true;
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
        const registry_start: u32 = @intCast(self.graph.virtual_registries.items.len);
        for (methods.items, 0..) |_, index| try self.graph.virtual_registries.append(self.allocator, .{
            .implementations = .{ .start = method_start + @as(u32, @intCast(index)), .len = 1 },
        });
        const virtual_ty = try self.generics.internType(.{ .virtual = abstract_ty });
        const virtualize: global_sg.GlobalVirtualizeId = @enumFromInt(@as(u32, @intCast(self.graph.virtualizes.items.len)));
        try self.graph.virtualizes.append(self.allocator, .{
            .value = handle,
            .concrete_type = concrete,
            .abstract_decl = abstract_decl,
            .virtual_type = virtual_ty,
            .methods = .{ .start = method_start, .len = @intCast(methods.items.len) },
            .safety_methods = .{ .start = registry_start, .len = @intCast(methods.items.len) },
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

    pub fn resolveNestedCall(
        context: *anyopaque,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) anyerror!?global_sg.Node {
        const self: *Resolver = @ptrCast(@alignCast(context));
        return self.makeVirtualCall(module_index, reference, input, source);
    }

    pub fn concreteImplements(context: *anyopaque, concrete: global_sg.GlobalTypeId, abstract_type: global_sg.GlobalTypeId) bool {
        const self: *Resolver = @ptrCast(@alignCast(context));
        const declaration = switch (self.graph.types.items[@intFromEnum(abstract_type)]) {
            .declared => |value| value,
            else => return false,
        };
        if (self.findAbstractDefinition(declaration) == null) return false;
        return self.implements(concrete, declaration) catch false;
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
        const instance = RequirementInstance{
            .declaration = declaration,
            .method_index = method_index,
            .input = try self.generics.instantiateParameterizedType(located.module_index, requirement.input, &bindings, self_type),
            .output = try self.generics.instantiateParameterizedType(located.module_index, requirement.output, &bindings, self_type),
        };
        return instance;
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

    pub fn implements(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        abstract_decl: global_sg.GlobalDeclId,
    ) !bool {
        self.stats.checks += 1;
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.abstract_implementations.items) |implementation| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, implementation.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                const candidate_type = globalizer.globalType(self.offsets[module_index], implementation.ty);
                if (global_types.equal(self.graph, concrete, candidate_type)) {
                    self.stats.concrete_hits += 1;
                    return true;
                }
            }
            for (module.semantic.parameterized_storage.parameterized_abstract_implementations.items) |parameterized| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, parameterized.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                if (try self.matchesImplementationParameterized(module_index, concrete, parameterized)) {
                    self.stats.parameterized_hits += 1;
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

    /// Validate constraints after a concrete function instance has been created.
    /// This is deliberately a second pass: function monomorphization stays
    /// independent of the abstract catalog, while no invalid instance can leave
    /// GlobalSema as a final graph.
    pub fn validateGenericFunctionInstances(self: *Resolver) !void {
        for (self.graph.generic_function_instances.items) |instance| {
            const owner = self.graph.moduleForDeclaration(instance.parameterized_declaration) orelse return error.InvalidGenericFunctionOwner;
            const module_index: usize = @intFromEnum(owner);
            const parameterized = self.findFunctionParameterized(module_index, instance.parameterized_declaration) orelse continue;
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
                if (!try self.implements(concrete, abstract_decl)) return error.GenericAbstractConstraintNotSatisfied;
            }
        }
    }

    fn matchesImplementationParameterized(
        self: *Resolver,
        module_index: usize,
        concrete: global_sg.GlobalTypeId,
        parameterized: parameterized_storage.ParameterizedAbstractImplementation,
    ) !bool {
        const module = &self.modules[module_index];
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

        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        try self.generics.bindGlobalArguments(module_index, parameterized.parameters, identity.arguments, &bindings);
        if (parameterized.concrete_type_pattern) |pattern| {
            const expected = try self.generics.instantiateParameterizedType(module_index, pattern, &bindings, concrete);
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

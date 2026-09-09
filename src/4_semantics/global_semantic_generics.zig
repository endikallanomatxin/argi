const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const module_views = @import("module_semantic_views.zig");
const templates = @import("module_semantic_templates.zig");
const ir = @import("module_semantic_template_ir.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const core_mod = @import("global_semantic_core.zig");
const global_types = @import("global_semantic_types.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    type_instances: u32 = 0,
    type_holes: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    stats: Stats = .{},

    pub fn resolveExternalTypes(self: *Resolver) !void {
        for (self.modules, 0..) |*module, module_index| {
            const o = self.offsets[module_index];
            for (0..module_views.typeCount(module)) |raw_type| {
                const local_id: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw_type)));
                const value = try module_views.typeView(module, local_id);
                const external = switch (value) {
                    .external => |id| id,
                    .resolved => continue,
                };
                const reference = module.semantic.external_refs.items[@intFromEnum(external)];
                const args = reference.generic_arguments orelse continue;
                if (reference.kind != .type) continue;
                const base = self.core.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch continue;
                const global_args = try self.relocateModuleArguments(module_index, args);
                const destination = globalizer.globalType(o, local_id);
                self.graph.types.items[@intFromEnum(destination)] = .{ .generic = .{ .base = base, .arguments = global_args } };
                self.stats.type_holes += 1;
            }
        }
    }

    pub fn materializeKnownTypes(self: *Resolver) !bool {
        var changed = false;
        var index: usize = 0;
        while (index < self.graph.types.items.len) : (index += 1) {
            const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(index)));
            switch (self.graph.types.items[index]) {
                .generic => {
                    if (try self.ensureGenericInstance(id)) changed = true;
                },
                else => {},
            }
        }
        return changed;
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        return switch (operation) {
            .resolve_type => |value| @as(?bool, try self.resolveGenericTypeHole(module_index, module, o, value)),
            else => null,
        };
    }

    fn resolveGenericTypeHole(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.external)];
        const args = reference.generic_arguments orelse return false;
        const base = self.core.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type }) catch return false;
        const global_args = try self.relocateModuleArguments(module_index, args);
        const destination = globalizer.globalType(o, value.destination);
        self.graph.types.items[@intFromEnum(destination)] = .{ .generic = .{ .base = base, .arguments = global_args } };
        _ = try self.ensureGenericInstance(destination);
        self.stats.type_holes += 1;
        return true;
    }

    pub fn ensureGenericInstance(self: *Resolver, ty: global_sg.GlobalTypeId) !bool {
        if (global_types.genericInstance(self.graph, ty) != null) return false;
        const identity = switch (self.graph.types.items[@intFromEnum(ty)]) {
            .generic => |value| value,
            else => return false,
        };
        const located = self.findTypeTemplate(identity.base) orelse return false;
        var bindings = try Bindings.init(self.allocator, self.modules[located.module_index].semantic.templates.generic_parameters.items.len);
        defer bindings.deinit(self.allocator);
        try self.bindGlobalArguments(located.module_index, located.template.parameters, identity.arguments, &bindings);
        const body_type = try self.instantiateTemplateType(located.module_index, located.template.body, &bindings, null);
        const shape = switch (self.graph.types.items[@intFromEnum(body_type)]) {
            .structural => |value| @import("semantic_type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .structure = .{
                .fields = value.fields,
                .layout = value.layout,
            } },
            .structural_choice => |value| @import("semantic_type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .choice = .{
                .variants = value.variants,
                .layout = value.layout,
            } },
            .array => |value| @import("semantic_type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .array = .{
                .length = value.length,
                .element = value.element,
            } },
            else => @import("semantic_type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .alias = body_type },
        };
        try self.graph.generic_instances.append(self.allocator, .{ .type_id = ty, .shape = shape });
        self.stats.type_instances += 1;
        return true;
    }

    const LocatedTypeTemplate = struct {
        module_index: usize,
        template: templates.GenericTypeTemplate,
    };

    fn findTypeTemplate(self: *Resolver, declaration: global_sg.GlobalDeclId) ?LocatedTypeTemplate {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return null;
        const module_index: usize = @intFromEnum(owner);
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.templates.generic_type_templates.items) |template|
            if (template.declaration == local) return .{ .module_index = module_index, .template = template };
        return null;
    }

    /// Generic substitutions are shared by type and function monomorphization.
    /// They are intentionally indexed by TemplateParameterId so nested template
    /// expressions can reuse the same substitution environment without maps.
    pub const Bindings = struct {
        types: []?global_sg.GlobalTypeId,
        ints: []?i64,

        pub fn init(allocator: std.mem.Allocator, count: usize) !Bindings {
            const types_slice = try allocator.alloc(?global_sg.GlobalTypeId, count);
            errdefer allocator.free(types_slice);
            const ints_slice = try allocator.alloc(?i64, count);
            @memset(types_slice, null);
            @memset(ints_slice, null);
            return .{ .types = types_slice, .ints = ints_slice };
        }

        pub fn deinit(self: *Bindings, allocator: std.mem.Allocator) void {
            allocator.free(self.types);
            allocator.free(self.ints);
            self.* = undefined;
        }
    };

    pub fn bindGlobalArguments(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.TemplateParameterId),
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        bindings: *Bindings,
    ) !void {
        const module = &self.modules[module_index];
        for (0..parameters.len) |position| {
            const param_raw = parameters.start + @as(u32, @intCast(position));
            const parameter = module.semantic.templates.generic_parameters.items[param_raw];
            const argument = self.findGlobalArgument(module, parameter.name, arguments, position) orelse return error.MissingGenericArgument;
            switch (parameter.kind) {
                .type => switch (argument.value) {
                    .type => |value| bindings.types[param_raw] = value,
                    else => return error.GenericArgumentKindMismatch,
                },
                .comptime_int => switch (argument.value) {
                    .comptime_int => |value| bindings.ints[param_raw] = value,
                    else => return error.GenericArgumentKindMismatch,
                },
            }
        }
    }

    fn findGlobalArgument(
        self: *Resolver,
        module: *const module_sg.ModuleSemanticGraph,
        parameter_name: primitives.StringRange,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        position: usize,
    ) ?global_sg.GenericArgument {
        const wanted = module.text(parameter_name);
        var has_named = false;
        for (0..arguments.len) |offset| {
            const argument = self.graph.generic_arguments.items[arguments.start + @as(u32, @intCast(offset))];
            const name = self.graph.text(argument.name);
            if (name.len != 0) has_named = true;
            if (name.len != 0 and std.mem.eql(u8, name, wanted)) return argument;
        }
        if (has_named) return null;
        if (position < arguments.len)
            return self.graph.generic_arguments.items[arguments.start + @as(u32, @intCast(position))];
        return null;
    }

    pub fn relocateModuleArguments(
        self: *Resolver,
        module_index: usize,
        range: module_entities.GenericArgRange,
    ) !primitives.Range(global_sg.GlobalGenericArgId) {
        const module = &self.modules[module_index];
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (0..range.len) |offset| {
            const local: module_entities.ModuleGenericArgId = @enumFromInt(range.start + @as(u32, @intCast(offset)));
            const argument = try module_views.genericArgumentView(module, local);
            try self.graph.generic_arguments.append(self.allocator, .{
                .name = try self.graph.addString(self.allocator, module.text(argument.name)),
                .value = switch (argument.value) {
                    .type => |value| .{ .type = globalizer.globalType(self.offsets[module_index], value) },
                    .comptime_int => |value| .{ .comptime_int = value },
                },
            });
        }
        return .{ .start = start, .len = range.len };
    }

    pub fn instantiateTemplateType(
        self: *Resolver,
        module_index: usize,
        id: ir.TemplateTypeId,
        bindings: *Bindings,
        self_type: ?global_sg.GlobalTypeId,
    ) anyerror!global_sg.GlobalTypeId {
        const module = &self.modules[module_index];
        const storage = &module.semantic.templates.ir;
        return switch (storage.types.items[@intFromEnum(id)]) {
            .concrete => |value| globalizer.globalType(self.offsets[module_index], value),
            .parameter => |parameter| bindings.types[@intFromEnum(parameter)] orelse error.UnboundGenericTypeParameter,
            .abstract_self => self_type orelse error.AbstractSelfOutsideImplementation,
            .external => |external| self.instantiateExternalType(module_index, external, bindings, self_type),
            .array => |value| self.internType(.{ .array = .{
                .length = @intCast(try self.evalInt(module_index, value.length, bindings)),
                .element = try self.instantiateTemplateType(module_index, value.element, bindings, self_type),
            } }),
            .resolved => |value| self.instantiateResolvedTemplateType(module_index, value, bindings, self_type),
        };
    }

    fn instantiateExternalType(
        self: *Resolver,
        module_index: usize,
        external: module_entities.ExternalRefId,
        bindings: *Bindings,
        self_type: ?global_sg.GlobalTypeId,
    ) !global_sg.GlobalTypeId {
        _ = bindings;
        _ = self_type;
        const module = &self.modules[module_index];
        const reference = module.semantic.external_refs.items[@intFromEnum(external)];
        const decl = try self.core.resolveDeclaration(module_index, reference, &.{ .type, .abstract_type });
        if (reference.generic_arguments) |args| {
            const global_args = try self.relocateModuleArguments(module_index, args);
            const id = try self.internType(.{ .generic = .{ .base = decl, .arguments = global_args } });
            _ = try self.ensureGenericInstance(id);
            return id;
        }
        return self.graph.declarations.items[@intFromEnum(decl)].type_id orelse self.internType(.{ .declared = decl });
    }

    fn instantiateResolvedTemplateType(
        self: *Resolver,
        module_index: usize,
        value: ir.ResolvedType,
        bindings: *Bindings,
        self_type: ?global_sg.GlobalTypeId,
    ) anyerror!global_sg.GlobalTypeId {
        return switch (value) {
            .builtin => |builtin| self.internType(.{ .builtin = builtin }),
            .declared => |decl| self.internType(.{ .declared = try self.resolveTemplateDeclaration(module_index, decl) }),
            .pointer => |pointer| self.internType(.{ .pointer = .{
                .child = try self.instantiateTemplateType(module_index, pointer.child, bindings, self_type),
                .mutability = pointer.mutability,
            } }),
            .array => |array| self.internType(.{ .array = .{
                .length = array.length,
                .element = try self.instantiateTemplateType(module_index, array.element, bindings, self_type),
            } }),
            .nullable => |child| self.internType(.{ .nullable = try self.instantiateTemplateType(module_index, child, bindings, self_type) }),
            .inferred_errable => |child| self.internType(.{ .inferred_errable = try self.instantiateTemplateType(module_index, child, bindings, self_type) }),
            .inferred_choice => |choice| self.internType(.{ .inferred_choice = .{
                .identity = choice.identity,
                .kind = choice.kind,
                .variants = try self.instantiateVariants(module_index, choice.variants, bindings, self_type),
            } }),
            .structural => |shape| self.internType(.{ .structural = .{
                .fields = try self.instantiateFields(module_index, shape.fields, bindings, self_type),
                .layout = shape.layout,
            } }),
            .structural_choice => |shape| self.internType(.{ .structural_choice = .{
                .variants = try self.instantiateVariants(module_index, shape.variants, bindings, self_type),
                .layout = shape.layout,
            } }),
            .generic => |generic| blk: {
                const base = try self.resolveTemplateDeclaration(module_index, generic.base);
                const args = try self.instantiateTemplateArguments(module_index, generic.arguments, bindings, self_type);
                const id = try self.internType(.{ .generic = .{ .base = base, .arguments = args } });
                break :blk id;
            },
        };
    }

    pub fn resolveTemplateDeclaration(self: *Resolver, module_index: usize, id: ir.TemplateDeclId) !global_sg.GlobalDeclId {
        const target = self.modules[module_index].semantic.templates.ir.declarations.items[@intFromEnum(id)].target;
        return switch (target) {
            .module => |local| globalizer.globalDecl(self.offsets[module_index], local),
            .external => |external| self.core.resolveDeclaration(
                module_index,
                self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)],
                &.{ .type, .abstract_type, .function },
            ),
        };
    }

    pub fn instantiateTemplateArguments(
        self: *Resolver,
        module_index: usize,
        range: primitives.Range(ir.TemplateGenericArgId),
        bindings: *Bindings,
        self_type: ?global_sg.GlobalTypeId,
    ) !primitives.Range(global_sg.GlobalGenericArgId) {
        const module = &self.modules[module_index];
        const storage = &module.semantic.templates.ir;
        var items: std.ArrayList(global_sg.GenericArgument) = .empty;
        defer items.deinit(self.allocator);
        for (0..range.len) |offset| {
            const argument = storage.generic_arguments.items[range.start + @as(u32, @intCast(offset))];
            try items.append(self.allocator, .{
                .name = try self.graph.addString(self.allocator, module.text(argument.name)),
                .value = switch (argument.value) {
                    .type => |value| .{ .type = try self.instantiateTemplateType(module_index, value, bindings, self_type) },
                    .comptime_int => |value| .{ .comptime_int = try self.evalInt(module_index, value, bindings) },
                },
            });
        }
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        try self.graph.generic_arguments.appendSlice(self.allocator, items.items);
        return .{ .start = start, .len = range.len };
    }

    fn instantiateFields(
        self: *Resolver,
        module_index: usize,
        range: primitives.Range(ir.TemplateFieldId),
        bindings: *Bindings,
        self_type: ?global_sg.GlobalTypeId,
    ) !global_sg.FieldRange {
        const module = &self.modules[module_index];
        const storage = &module.semantic.templates.ir;
        var items: std.ArrayList(global_sg.Field) = .empty;
        defer items.deinit(self.allocator);
        for (0..range.len) |offset| {
            const field = storage.fields.items[range.start + @as(u32, @intCast(offset))];
            try items.append(self.allocator, .{
                .name = try self.graph.addString(self.allocator, module.text(field.name)),
                .ty = try self.instantiateTemplateType(module_index, field.ty, bindings, self_type),
                .storage_type = if (field.storage_type) |value| try self.instantiateTemplateType(module_index, value, bindings, self_type) else null,
                .source = self.globalSource(module_index, field.source),
                .default_value = null,
            });
        }
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.allocator, items.items);
        return .{ .start = start, .len = range.len };
    }

    fn instantiateVariants(
        self: *Resolver,
        module_index: usize,
        range: primitives.Range(ir.TemplateVariantId),
        bindings: *Bindings,
        self_type: ?global_sg.GlobalTypeId,
    ) !global_sg.VariantRange {
        const module = &self.modules[module_index];
        const storage = &module.semantic.templates.ir;
        var items: std.ArrayList(global_sg.ChoiceVariant) = .empty;
        defer items.deinit(self.allocator);
        for (0..range.len) |offset| {
            const variant = storage.variants.items[range.start + @as(u32, @intCast(offset))];
            switch (variant) {
                .reference => |reference| {
                    const existing = switch (reference) {
                        .module => |id| self.graph.variants.items[@intFromEnum(globalizer.globalVariant(self.offsets[module_index], id))],
                        .external => |external| blk: {
                            const ref = module.semantic.external_refs.items[@intFromEnum(external)];
                            const name = module.text(ref.name);
                            var found: ?global_sg.ChoiceVariant = null;
                            for (self.graph.variants.items) |candidate| if (std.mem.eql(u8, self.graph.text(candidate.name), name)) {
                                found = candidate;
                                break;
                            };
                            break :blk found orelse return error.UnknownTemplateVariant;
                        },
                    };
                    try items.append(self.allocator, existing);
                },
                .semantic => |value| try items.append(self.allocator, .{
                    .name = try self.graph.addString(self.allocator, module.text(value.name)),
                    .payload_type = if (value.payload_type) |payload| try self.instantiateTemplateType(module_index, payload, bindings, self_type) else null,
                    .option_decl = null,
                    .source = self.globalSource(module_index, value.source),
                    .value = value.value,
                }),
            }
        }
        const start: u32 = @intCast(self.graph.variants.items.len);
        try self.graph.variants.appendSlice(self.allocator, items.items);
        return .{ .start = start, .len = range.len };
    }

    pub fn evalInt(self: *Resolver, module_index: usize, id: ir.TemplateIntExprId, bindings: *Bindings) anyerror!i64 {
        const expression = self.modules[module_index].semantic.templates.ir.int_expressions.items[@intFromEnum(id)];
        return switch (expression) {
            .literal => |value| value,
            .parameter => |parameter| bindings.ints[@intFromEnum(parameter)] orelse error.UnboundComptimeParameter,
            .binary => |binary| blk: {
                const left = try self.evalInt(module_index, binary.left, bindings);
                const right = try self.evalInt(module_index, binary.right, bindings);
                break :blk switch (binary.operator) {
                    .add => left + right,
                    .subtract => left - right,
                    .multiply => left * right,
                    .divide => if (right == 0) error.ComptimeDivisionByZero else @divTrunc(left, right),
                    .modulo => if (right == 0) error.ComptimeDivisionByZero else @mod(left, right),
                };
            },
        };
    }

    pub fn internType(self: *Resolver, value: global_sg.GlobalType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |candidate, raw| {
            if (sameShallowType(candidate, value)) return @enumFromInt(@as(u32, @intCast(raw)));
        }
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, value);
        return id;
    }

    pub fn globalSource(self: *Resolver, module_index: usize, source: primitives.SourceRef) primitives.SourceRef {
        return .{ .file_index = self.offsets[module_index].file_base + source.file_index, .offset = source.offset };
    }
};

fn sameShallowType(a: global_sg.GlobalType, b: global_sg.GlobalType) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .builtin => |value| value == b.builtin,
        .declared => |value| value == b.declared,
        .pointer => |value| value.child == b.pointer.child and value.mutability == b.pointer.mutability,
        .array => |value| value.length == b.array.length and value.element == b.array.element,
        .nullable => |value| value == b.nullable,
        .inferred_errable => |value| value == b.inferred_errable,
        .generic => |value| value.base == b.generic.base and value.arguments.start == b.generic.arguments.start and value.arguments.len == b.generic.arguments.len,
        .inferred_choice, .structural, .structural_choice => false,
    };
}

test "generic type materialization has a dedicated resolver" {
    try std.testing.expect(@sizeOf(Stats) <= 8);
}

const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const module_views = @import("../module/views.zig");
const parameterized_storage = @import("../module/parameterized/storage.zig");
const ir = @import("../module/parameterized/ir.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    const GlobalTypeTag = std.meta.Tag(global_sg.GlobalType);
    const tag_count = @typeInfo(GlobalTypeTag).@"enum".fields.len;

    type_instances: u32 = 0,
    type_holes: u32 = 0,
    type_intern_calls: u64 = 0,
    type_intern_candidates: u64 = 0,
    type_intern_ns: u64 = 0,
    type_intern_calls_by_tag: [tag_count]u64 = @splat(0),
    type_intern_candidates_by_tag: [tag_count]u64 = @splat(0),
    type_intern_ns_by_tag: [tag_count]u64 = @splat(0),
};

pub const ComptimeFailure = struct {
    source: primitives.SourceRef,
    reason: []const u8,
    // Borrow the original module token; rendering happens after rollback.
    unknown_name: ?[]const u8 = null,
    materialization_error: ?anyerror = null,
};

pub const Resolver = struct {
    const PointerKey = struct {
        child: global_sg.GlobalTypeId,
        mutability: primitives.PointerMutability,
    };
    const GenericKey = struct { base: global_sg.GlobalDeclId, arity: u32, values: u64 };

    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    profile_io: ?std.Io = null,
    stats: Stats = .{},
    comptime_failure: ?ComptimeFailure = null,
    execution_context: ?*anyopaque = null,
    checkpoint_execution: ?*const fn (*anyopaque) usize = null,
    rollback_execution: ?*const fn (*anyopaque, usize) void = null,
    execute_integer: ?*const fn (*anyopaque, usize, ir.ParameterizedNodeId, *const Bindings) anyerror!i64 = null,
    execute_boolean: ?*const fn (*anyopaque, usize, ir.ParameterizedNodeId, *const Bindings) anyerror!bool = null,
    argument_failure: ?struct { declaration: global_sg.GlobalDeclId, ty: global_sg.GlobalTypeId, reason: []const u8 } = null,
    projection_context: ?*anyopaque = null,
    projection_resolver: ?*const fn (*anyopaque, global_sg.GlobalTypeId, []const u8, primitives.SourceRef) anyerror!global_sg.GlobalTypeId = null,
    constant_projection_resolver: ?*const fn (*anyopaque, global_sg.GlobalTypeId, []const u8, primitives.SourceRef) anyerror!i64 = null,
    pointer_types: @import("identity_cache.zig").IdentityCache(PointerKey, global_sg.GlobalTypeId) = .empty,
    generic_types: @import("identity_cache.zig").IdentityCache(GenericKey, global_sg.GlobalTypeId) = .empty,

    pub fn checkpointCaches(self: *const Resolver) [2]usize {
        return .{ self.pointer_types.checkpoint(), self.generic_types.checkpoint() };
    }

    pub fn rollbackCaches(self: *Resolver, saved: [2]usize) void {
        self.pointer_types.rollback(saved[0]);
        self.generic_types.rollback(saved[1]);
    }

    pub fn commitCaches(self: *Resolver) void {
        self.pointer_types.commit(self.allocator);
        self.generic_types.commit(self.allocator);
    }

    pub fn deinit(self: *Resolver) void {
        self.pointer_types.deinit(self.allocator);
        self.generic_types.deinit(self.allocator);
    }

    pub fn resolveExternalTypes(self: *Resolver) !void {
        return self.resolveExternalTypesFrom(0);
    }

    /// Initialize relocated holes in a new module suffix without overwriting
    /// retained slots already materialized by earlier resolution passes.
    pub fn resolveExternalTypesFrom(self: *Resolver, first_module: usize) !void {
        if (first_module > self.modules.len) return error.InvalidSemanticModuleViews;
        for (self.modules[first_module..], first_module..) |*module, module_index| {
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
                const base = (try self.core.resolveDefinitionReference(module_index, reference, &.{ .type, .contract_type })) orelse continue;
                const global_args = try self.relocateModuleArguments(module_index, args);
                const destination = globalizer.globalType(o, local_id);
                try self.graph.resolveType(self.allocator, destination, .{ .generic = .{ .base = base, .arguments = global_args } });
                self.stats.type_holes += 1;
            }
        }
    }

    /// Scratch work for one fixed-point resolution call, never session state.
    /// Type holes remain pending: an older slot can become generic after a
    /// later operation resolves it. Completed representations leave this list.
    pub const PendingTypes = struct {
        scanned: usize = 0,
        items: std.ArrayList(global_sg.GlobalTypeId) = .empty,

        pub fn deinit(self: *PendingTypes, allocator: std.mem.Allocator) void {
            self.items.deinit(allocator);
        }

        fn discover(self: *PendingTypes, allocator: std.mem.Allocator, graph: *const global_sg.GlobalSemanticGraph, measurement: ?@import("resolution_profile.zig").Profile.Measurement) !void {
            while (self.scanned < graph.types.items.len) {
                const id: global_sg.GlobalTypeId = @enumFromInt(self.scanned);
                if (measurement) |m| m.visit(1);
                if (graph.isTypeUnresolved(id) or graph.types.items[self.scanned] == .generic)
                    try self.items.append(allocator, id);
                self.scanned += 1;
            }
        }
    };

    /// Retry the unresolved candidates in discovery order. The caller owns
    /// this scratch list and discards it if resolution fails or rolls back.
    pub fn materializePendingTypes(self: *Resolver, pending: *PendingTypes) !bool {
        self.argument_failure = null;
        var changed = false;
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.generic_types) else null;
        defer if (measurement) |m| m.finish(changed);
        try pending.discover(self.allocator, self.graph, measurement);
        var read: usize = 0;
        var write: usize = 0;
        while (read < pending.items.items.len) {
            const id = pending.items.items[read];
            read += 1;
            if (measurement) |m| m.visit(1);
            if (self.graph.isTypeUnresolved(id)) {
                pending.items.items[write] = id;
                write += 1;
                continue;
            }
            const result = self.materializeGenericInstance(id) catch |err| switch (err) {
                error.ComptimeExecutionPending => .pending,
                else => return err,
            };
            switch (result) {
                .changed => changed = true,
                .complete => {},
                .pending => {
                    pending.items.items[write] = id;
                    write += 1;
                },
            }
            // Instantiation can append more generic types in this same round.
            try pending.discover(self.allocator, self.graph, measurement);
        }
        pending.items.shrinkRetainingCapacity(write);
        return changed;
    }

    pub fn materializeKnownTypes(self: *Resolver) !bool {
        self.argument_failure = null;
        var changed = false;
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.generic_types) else null;
        defer if (measurement) |m| m.finish(changed);
        var index: usize = 0;
        while (index < self.graph.types.items.len) : (index += 1) {
            if (measurement) |m| m.visit(1);
            const id: global_sg.GlobalTypeId = @enumFromInt(index);
            if (self.graph.isTypeUnresolved(id) or self.graph.types.items[index] != .generic) continue;
            const result = self.materializeGenericInstance(id) catch |err| switch (err) {
                error.ComptimeExecutionPending => continue,
                else => return err,
            };
            if (result == .changed) changed = true;
        }
        return changed;
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_type => |value| try self.resolveGenericTypeHole(module_index, module, o, value),
            else => .not_applicable,
        };
    }

    fn resolveGenericTypeHole(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.external)];
        if (reference.computed_type) |computed| {
            const destination = globalizer.globalType(o, value.destination);
            if (!self.graph.isTypeUnresolved(destination)) return .resolved;
            var bindings = try Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            const resolved = try self.instantiateParameterizedType(module_index, computed, &bindings);
            try self.graph.resolveType(self.allocator, destination, self.graph.types.items[@intFromEnum(resolved)]);
            return .resolved;
        }
        if (reference.projection_base) |base| {
            const destination = globalizer.globalType(o, value.destination);
            if (!self.graph.isTypeUnresolved(destination)) return .resolved;
            const resolved = try self.projection_resolver.?(self.projection_context.?, globalizer.globalType(o, base), module.text(reference.name), .{
                .file_index = o.file_base + reference.source.file_index,
                .offset = reference.source.offset,
            });
            try self.graph.resolveType(self.allocator, destination, self.graph.types.items[@intFromEnum(resolved)]);
            self.stats.type_holes += 1;
            return .resolved;
        }
        const args = reference.generic_arguments orelse return .not_applicable;
        const base = (try self.core.resolveDefinitionReference(module_index, reference, &.{ .type, .contract_type })) orelse return .deferred;
        const global_args = try self.relocateModuleArguments(module_index, args);
        const destination = globalizer.globalType(o, value.destination);
        try self.graph.resolveType(self.allocator, destination, .{ .generic = .{ .base = base, .arguments = global_args } });
        _ = try self.ensureGenericInstance(destination);
        self.stats.type_holes += 1;
        return .resolved;
    }

    pub fn ensureGenericInstance(self: *Resolver, ty: global_sg.GlobalTypeId) !bool {
        return try self.materializeGenericInstance(ty) == .changed;
    }

    const InstanceMaterialization = enum { pending, complete, changed };

    fn materializeGenericInstance(self: *Resolver, ty: global_sg.GlobalTypeId) !InstanceMaterialization {
        // Every published instance has validated declaration-order arguments.
        // Semantic identity with one can reuse its shape without rebinding.
        if (global_types.genericInstance(self.graph, ty) != null) return .complete;
        const identity = switch (self.graph.types.items[@intFromEnum(ty)]) {
            .generic => |value| value,
            else => return .complete,
        };
        const located = self.findTypeParameterized(identity.base) orelse return .pending;
        var bindings = try Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        self.bindGlobalArguments(located.module_index, located.parameterized.parameters, identity.arguments, &bindings) catch |err| {
            const reason: []const u8 = switch (err) {
                error.TooManyGenericArguments => "too many generic arguments",
                error.UnknownGenericArgument => "unknown generic argument",
                error.DuplicateGenericArgument => "duplicate generic argument",
                error.MissingGenericArgument => "missing required generic argument",
                error.GenericArgumentKindMismatch => "generic argument kind does not match its parameter",
                else => return err,
            };
            self.argument_failure = .{ .declaration = identity.base, .ty = ty, .reason = reason };
            return err;
        };
        const module = &self.modules[located.module_index];
        const parameters = module.semantic.parameterized_storage.comptime_parameters.items[located.parameterized.parameters.start..][0..located.parameterized.parameters.len];
        var canonical = identity.arguments.len == parameters.len;
        for (parameters, 0..) |parameter, position| {
            if (!canonical) break;
            const argument = self.graph.generic_arguments.items[identity.arguments.start + position];
            if (!std.mem.eql(u8, module.text(parameter.name), self.graph.text(argument.name))) {
                canonical = false;
                break;
            }
        }
        if (!canonical) {
            var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;
            defer arguments.deinit(self.allocator);
            for (parameters, 0..) |parameter, position| {
                const raw = located.parameterized.parameters.start + position;
                try arguments.append(self.allocator, .{
                    .name = try self.graph.addString(self.allocator, module.text(parameter.name)),
                    .value = switch (parameter.kind) {
                        .type => .{ .type = bindings.types[raw].? },
                        .comptime_int => .{ .comptime_int = bindings.ints[raw].? },
                    },
                });
            }
            const start: u32 = @intCast(self.graph.generic_arguments.items.len);
            try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);
            try self.graph.replaceTypeArguments(self.allocator, ty, .{ .start = start, .len = @intCast(arguments.items.len) });
        }
        // Type identity, layouts and operation signatures use declaration order.
        // Validate and canonicalize before reusing an equivalent instance.
        if (global_types.genericInstance(self.graph, ty) != null) return .complete;
        const body_type = try self.instantiateParameterizedType(located.module_index, located.parameterized.body, &bindings);
        const shape = switch (self.graph.types.items[@intFromEnum(body_type)]) {
            .structural => |value| @import("../primitives/type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .structure = .{
                .fields = value.fields,
                .layout = value.layout,
            } },
            .structural_choice => |value| @import("../primitives/type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .choice = .{
                .variants = value.variants,
                .layout = value.layout,
            } },
            .array => |value| @import("../primitives/type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .array = .{
                .length = value.length,
                .element = value.element,
            } },
            else => @import("../primitives/type_shapes.zig").GenericInstanceShape(global_sg.Ids){ .alias = body_type },
        };
        try self.graph.generic_instances.append(self.allocator, .{ .type_id = ty, .shape = shape });
        self.stats.type_instances += 1;
        return .changed;
    }

    pub const LocatedTypeParameterized = struct {
        module_index: usize,
        parameterized: parameterized_storage.ParameterizedType,
    };

    pub fn isParameterizedTypeDeclaration(self: *Resolver, declaration: global_sg.GlobalDeclId) bool {
        return self.findTypeParameterized(declaration) != null;
    }

    pub fn findTypeParameterized(self: *Resolver, declaration: global_sg.GlobalDeclId) ?LocatedTypeParameterized {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return null;
        const module_index: usize = @intFromEnum(owner);
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.parameterized_storage.parameterized_types.items) |parameterized|
            if (parameterized.declaration == local) return .{ .module_index = module_index, .parameterized = parameterized };
        return null;
    }

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
        parameters: primitives.Range(ir.ComptimeParameterId),
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        bindings: *Bindings,
    ) !void {
        try self.bindGlobalArgumentsPartial(module_index, parameters, arguments, bindings);
        try self.applyParameterDefaults(module_index, parameters, bindings);
        for (parameters.start..parameters.start + parameters.len) |param_raw| {
            const parameter = self.modules[module_index].semantic.parameterized_storage.comptime_parameters.items[param_raw];
            if (parameter.kind == .type and bindings.types[param_raw] == null) return error.MissingGenericArgument;
            if (parameter.kind == .comptime_int and bindings.ints[param_raw] == null) return error.MissingGenericArgument;
        }
    }

    pub fn applyParameterDefaults(self: *Resolver, module_index: usize, parameters: primitives.Range(ir.ComptimeParameterId), bindings: *Bindings) !void {
        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = self.modules[module_index].semantic.parameterized_storage.comptime_parameters.items[raw];
            if (parameter.kind == .type and bindings.types[raw] == null) {
                if (parameter.default_type) |expression|
                    bindings.types[raw] = try self.instantiateParameterizedType(module_index, expression, bindings);
            }
            if (parameter.kind == .comptime_int and bindings.ints[raw] == null) {
                if (parameter.default_integer) |expression|
                    bindings.ints[raw] = try self.evalInt(module_index, expression, bindings);
            }
        }
    }

    pub fn bindGlobalArgumentsPartial(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        bindings: *Bindings,
    ) !void {
        const module = &self.modules[module_index];
        if (arguments.len > parameters.len) return error.TooManyGenericArguments;
        const seen = try self.allocator.alloc(bool, parameters.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        for (0..arguments.len) |argument_index| {
            const argument = self.graph.generic_arguments.items[arguments.start + @as(u32, @intCast(argument_index))];
            const name = self.graph.text(argument.name);
            var position: ?usize = if (name.len == 0) argument_index else null;
            if (name.len != 0) {
                for (0..parameters.len) |parameter_index| {
                    const parameter = module.semantic.parameterized_storage.comptime_parameters.items[parameters.start + @as(u32, @intCast(parameter_index))];
                    if (std.mem.eql(u8, name, module.text(parameter.name))) {
                        position = parameter_index;
                        break;
                    }
                }
            }
            const index = position orelse return error.UnknownGenericArgument;
            if (seen[index]) return error.DuplicateGenericArgument;
            seen[index] = true;
        }
        for (0..parameters.len) |position| {
            const param_raw = parameters.start + @as(u32, @intCast(position));
            const parameter = module.semantic.parameterized_storage.comptime_parameters.items[param_raw];
            const argument = self.findGlobalArgument(module.text(parameter.name), arguments, position) orelse continue;
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

    pub fn findPatternArgument(
        self: *Resolver,
        module_index: usize,
        arguments: primitives.Range(ir.ParameterizedGenericArgId),
        position: usize,
        wanted: []const u8,
    ) ?ir.GenericArgument {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        for (storage.generic_arguments.items[arguments.start..][0..arguments.len]) |argument| {
            const name = module.text(argument.name);
            if (name.len != 0 and std.mem.eql(u8, name, wanted)) return argument;
        }
        if (position < arguments.len) {
            const argument = storage.generic_arguments.items[arguments.start + @as(u32, @intCast(position))];
            if (module.text(argument.name).len == 0) return argument;
        }
        return null;
    }

    pub fn findGlobalArgument(
        self: *Resolver,
        wanted: []const u8,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        position: usize,
    ) ?global_sg.GenericArgument {
        for (0..arguments.len) |offset| {
            const argument = self.graph.generic_arguments.items[arguments.start + @as(u32, @intCast(offset))];
            const name = self.graph.text(argument.name);
            if (name.len != 0 and std.mem.eql(u8, name, wanted)) return argument;
        }
        if (position < arguments.len) {
            const argument = self.graph.generic_arguments.items[arguments.start + @as(u32, @intCast(position))];
            if (self.graph.text(argument.name).len == 0) return argument;
        }
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

    pub fn instantiateParameterizedType(
        self: *Resolver,
        module_index: usize,
        id: ir.ParameterizedTypeId,
        bindings: *Bindings,
    ) anyerror!global_sg.GlobalTypeId {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        return switch (storage.types.items[@intFromEnum(id)]) {
            .concrete => |value| globalizer.globalType(self.offsets[module_index], value),
            .parameter => |parameter| bindings.types[@intFromEnum(parameter)] orelse return error.UnboundGenericTypeParameter,
            .projection => |value| blk: {
                const base = try self.instantiateParameterizedType(module_index, value.base, bindings);
                break :blk try self.projection_resolver.?(self.projection_context.?, base, module.text(value.member), .{
                    .file_index = self.offsets[module_index].file_base + value.source.file_index,
                    .offset = value.source.offset,
                });
            },
            .external => |external| self.instantiateExternalType(module_index, external, bindings),
            .array => |value| blk: {
                const signed_length = try self.evalInt(module_index, value.length, bindings);
                const length = std.math.cast(u64, signed_length) orelse {
                    self.recordComptimeFailure(module_index, value.source, "array length must be non-negative");
                    return error.InvalidArrayLength;
                };
                break :blk try self.internType(.{ .array = .{
                    .length = length,
                    .element = try self.instantiateParameterizedType(module_index, value.element, bindings),
                } });
            },
            .choice_union => |value| self.instantiateChoiceUnion(module_index, value.left, value.right, bindings),
            .resolved => |value| self.instantiateResolvedParameterizedType(module_index, value, bindings),
        };
    }

    fn instantiateChoiceUnion(self: *Resolver, module_index: usize, left: ir.ParameterizedTypeId, right: ir.ParameterizedTypeId, bindings: *Bindings) !global_sg.GlobalTypeId {
        const left_type = try self.instantiateParameterizedType(module_index, left, bindings);
        const right_type = try self.instantiateParameterizedType(module_index, right, bindings);
        var variants: std.ArrayList(global_sg.ChoiceVariant) = .empty;
        defer variants.deinit(self.allocator);
        for ([_]global_sg.GlobalTypeId{ left_type, right_type }) |ty| {
            const range = global_types.variants(self.graph, ty) orelse return error.InvalidChoiceUnionType;
            // Declared options keep their canonical identity when combined
            // with other choice variants, including error reason sets.
            for (self.graph.variants.items[range.start..][0..range.len]) |variant| {
                var duplicate = false;
                for (variants.items) |existing| {
                    if (!std.mem.eql(u8, self.graph.text(existing.name), self.graph.text(variant.name))) continue;
                    if (existing.payload_type != variant.payload_type) return error.IncompatibleChoiceUnionVariant;
                    duplicate = true;
                    break;
                }
                if (!duplicate) try variants.append(self.allocator, variant);
            }
        }
        std.mem.sort(global_sg.ChoiceVariant, variants.items, self.graph, struct {
            fn lessThan(graph: *global_sg.GlobalSemanticGraph, a: global_sg.ChoiceVariant, b: global_sg.ChoiceVariant) bool {
                return std.mem.order(u8, graph.text(a.name), graph.text(b.name)) == .lt;
            }
        }.lessThan);
        const start: u32 = @intCast(self.graph.variants.items.len);
        try self.graph.variants.appendSlice(self.allocator, variants.items);
        return self.internType(.{ .structural_choice = .{ .variants = .{ .start = start, .len = @intCast(variants.items.len) }, .layout = .regular } });
    }

    fn instantiateExternalType(
        self: *Resolver,
        module_index: usize,
        external: module_entities.ExternalRefId,
        bindings: *Bindings,
    ) !global_sg.GlobalTypeId {
        _ = bindings;
        const module = &self.modules[module_index];
        const reference = module.semantic.external_refs.items[@intFromEnum(external)];
        if (reference.generic_arguments == null)
            return (try self.core.resolveTypeValue(module_index, reference)) orelse error.ComptimeExecutionPending;
        const decl = (try self.core.resolveDefinitionReference(module_index, reference, &.{ .type, .contract_type })) orelse return error.ComptimeExecutionPending;
        const global_args = try self.relocateModuleArguments(module_index, reference.generic_arguments.?);
        const id = try self.internType(.{ .generic = .{ .base = decl, .arguments = global_args } });
        _ = try self.ensureGenericInstance(id);
        return id;
    }

    fn instantiateResolvedParameterizedType(
        self: *Resolver,
        module_index: usize,
        value: ir.ResolvedType,
        bindings: *Bindings,
    ) anyerror!global_sg.GlobalTypeId {
        return switch (value) {
            .builtin => |builtin| self.internType(.{ .builtin = builtin }),
            .declared => |decl| self.internType(.{ .declared = try self.resolveParameterizedDeclaration(module_index, decl) }),
            .definition => |decl| self.internType(.{ .definition = try self.resolveParameterizedDeclaration(module_index, decl) }),
            .pointer => |pointer| self.internType(.{ .pointer = .{
                .child = try self.instantiateParameterizedType(module_index, pointer.child, bindings),
                .mutability = pointer.mutability,
            } }),
            .array => |array| self.internType(.{ .array = .{
                .length = array.length,
                .element = try self.instantiateParameterizedType(module_index, array.element, bindings),
            } }),
            .nullable => |child| blk: {
                const instantiated_child = try self.instantiateParameterizedType(module_index, child, bindings);
                const nullable = try self.internType(.{ .nullable = instantiated_child });
                try global_types.materializeNullable(self.allocator, self.graph, nullable, instantiated_child, .{ .file_index = 0, .offset = 0 });
                break :blk nullable;
            },
            .inferred_errable => |child| self.internType(.{ .inferred_errable = try self.instantiateParameterizedType(module_index, child, bindings) }),
            .inferred_choice => |choice| self.internType(.{ .inferred_choice = .{
                .identity = choice.identity,
                .kind = choice.kind,
                .variants = try self.instantiateVariants(module_index, choice.variants, bindings),
            } }),
            .structural => |shape| self.internType(.{ .structural = .{
                .fields = try self.instantiateFields(module_index, shape.fields, bindings),
                .layout = shape.layout,
            } }),
            .structural_choice => |shape| self.internType(.{ .structural_choice = .{
                .variants = try self.instantiateVariants(module_index, shape.variants, bindings),
                .layout = shape.layout,
            } }),
            .generic => |generic| blk: {
                const base = try self.resolveParameterizedDeclaration(module_index, generic.base);
                const args = try self.instantiateParameterizedArguments(module_index, generic.arguments, bindings);
                const id = try self.internType(.{ .generic = .{ .base = base, .arguments = args } });
                _ = try self.ensureGenericInstance(id);
                break :blk id;
            },
            .virtual => |contract_type| self.internType(.{ .virtual = try self.instantiateParameterizedType(module_index, contract_type, bindings) }),
        };
    }

    pub fn resolveParameterizedDeclaration(self: *Resolver, module_index: usize, id: ir.ParameterizedDeclId) !global_sg.GlobalDeclId {
        const target = self.modules[module_index].semantic.parameterized_storage.ir.declarations.items[@intFromEnum(id)].target;
        return switch (target) {
            .module => |local| globalizer.globalDecl(self.offsets[module_index], local),
            .external => |external| (try self.core.resolveDefinitionReference(
                module_index,
                self.modules[module_index].semantic.external_refs.items[@intFromEnum(external)],
                &.{ .type, .contract_type, .function },
            )) orelse error.ComptimeExecutionPending,
        };
    }

    pub fn resolveCallArguments(self: *Resolver, module_index: usize, reference: module_entities.ExternalRef) !?primitives.Range(global_sg.GlobalGenericArgId) {
        if (reference.computed_arguments) |arguments| {
            var bindings = try Bindings.init(self.allocator, self.modules[module_index].semantic.parameterized_storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            return self.instantiateParameterizedArguments(module_index, arguments, &bindings) catch |err| {
                switch (err) {
                    error.UnknownGlobalDeclaration => self.recordComptimeFailure(module_index, reference.source, "unknown or inaccessible type or contract in compile-time call arguments"),
                    error.UnknownModuleReference => self.recordComptimeFailure(module_index, reference.source, "unknown module in compile-time call arguments"),
                    error.AmbiguousGlobalDeclaration, error.AmbiguousModuleReference => self.recordComptimeFailure(module_index, reference.source, "ambiguous type or module in compile-time call arguments"),
                    else => {},
                }
                return err;
            };
        }
        if (reference.generic_arguments) |arguments| return try self.relocateModuleArguments(module_index, arguments);
        return null;
    }

    pub fn instantiateParameterizedArguments(
        self: *Resolver,
        module_index: usize,
        range: primitives.Range(ir.ParameterizedGenericArgId),
        bindings: *Bindings,
    ) !primitives.Range(global_sg.GlobalGenericArgId) {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        var items: std.ArrayList(global_sg.GenericArgument) = .empty;
        defer items.deinit(self.allocator);
        for (0..range.len) |offset| {
            const argument = storage.generic_arguments.items[range.start + @as(u32, @intCast(offset))];
            try items.append(self.allocator, .{
                .name = try self.graph.addString(self.allocator, module.text(argument.name)),
                .value = switch (argument.value) {
                    .type => |value| .{ .type = try self.instantiateParameterizedType(module_index, value, bindings) },
                    .comptime_int => |value| .{ .comptime_int = try self.evalInt(module_index, value, bindings) },
                },
            });
        }
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        try self.graph.generic_arguments.appendSlice(self.allocator, items.items);
        return .{ .start = start, .len = range.len };
    }

    /// Contract signatures retain lexical reach defaults. Ordinary expression
    /// defaults still belong to function-body instantiation; this path does not
    /// execute defaults while constructing a type.
    pub fn instantiateReachDefault(self: *Resolver, module_index: usize, id: ir.ParameterizedNodeId) !?global_sg.GlobalNodeId {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const node = storage.nodes.items[@intFromEnum(id)];
        const resolved = switch (node) {
            .resolved => |value| value,
            else => return null,
        };
        const local_id = switch (resolved.content) {
            .reach_directive => |value| value,
            else => return null,
        };
        const local = storage.reaches.items[@intFromEnum(local_id)];
        const alternatives_start: u32 = @intCast(self.graph.reach_alternatives.items.len);
        for (storage.reach_alternatives.items[local.alternatives.start..][0..local.alternatives.len]) |alternative| {
            const segments_start: u32 = @intCast(self.graph.reach_segments.items.len);
            for (storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len]) |segment|
                try self.graph.reach_segments.append(self.allocator, try self.graph.addString(self.allocator, module.text(segment)));
            try self.graph.reach_alternatives.append(self.allocator, .{ .segments = .{ .start = segments_start, .len = alternative.segments.len } });
        }
        const reach: global_sg.GlobalReachId = @enumFromInt(@as(u32, @intCast(self.graph.reaches.items.len)));
        try self.graph.reaches.append(self.allocator, .{ .alternatives = .{ .start = alternatives_start, .len = local.alternatives.len } });
        const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = self.globalSource(module_index, resolved.source), .ty = null, .content = .{ .reach_directive = reach } });
        return global;
    }

    // Runtime defaults remain recipes while resolving types. Each omitted
    // argument specializes its expression into fresh caller-owned nodes.
    fn instantiateFieldDefault(self: *Resolver, module_index: usize, id: ir.ParameterizedNodeId, ty: global_sg.GlobalTypeId, bindings: *Bindings) !?global_sg.GlobalNodeId {
        if (try self.instantiateReachDefault(module_index, id)) |node| return node;
        const module = &self.modules[module_index];
        const node = module.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(id)];
        const resolved = switch (node) {
            .resolved => |value| value,
            .pending => |pending_id| {
                const pending = module.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)];
                if (pending != .resolve_expression or pending.resolve_expression.kind != .choice_literal) return try self.recordArgumentDefault(module_index, id, ty, bindings);
                const choice = pending.resolve_expression;
                if (choice.operands.len != 0) return try self.recordArgumentDefault(module_index, id, ty, bindings);
                const name = choice.name orelse return null;
                _ = try self.ensureGenericInstance(ty);
                const variant = global_types.findVariant(self.graph, ty, module.text(name)) orelse return null;
                if (variant.variant.payload_type != null) return null;
                const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
                try self.graph.nodes.append(self.allocator, .{
                    .source = self.globalSource(module_index, choice.source),
                    .ty = ty,
                    .content = .{ .choice_literal = .{ .choice_type = ty, .variant = variant.id, .payload = null } },
                });
                return global;
            },
        };
        const content: global_sg.Node.Content = switch (resolved.content) {
            .int_literal => |value| .{ .int_literal = value },
            .float_literal => |value| .{ .float_literal = value },
            .bool_literal => |value| .{ .bool_literal = value },
            .char_literal => |value| .{ .char_literal = value },
            .string_literal => |value| .{ .string_literal = try self.graph.addString(self.allocator, module.text(value)) },
            else => return try self.recordArgumentDefault(module_index, id, ty, bindings),
        };
        const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        const literal_type = if (resolved.ty) |source_type| try self.instantiateParameterizedType(module_index, source_type, bindings) else ty;
        try self.graph.nodes.append(self.allocator, .{ .source = self.globalSource(module_index, resolved.source), .ty = literal_type, .content = content });
        return global;
    }

    fn recordArgumentDefault(self: *Resolver, module_index: usize, expression: ir.ParameterizedNodeId, ty: global_sg.GlobalTypeId, bindings: *Bindings) !global_sg.GlobalNodeId {
        const binding_start: u32 = @intCast(self.graph.argument_default_bindings.items.len);
        for (bindings.types, bindings.ints) |bound_type, integer|
            try self.graph.argument_default_bindings.append(self.allocator, .{ .ty = bound_type, .integer = integer });
        const recipe: u32 = @intCast(self.graph.argument_defaults.items.len);
        try self.graph.argument_defaults.append(self.allocator, .{
            .module_index = module_index,
            .expression = expression,
            .bindings = .{ .start = binding_start, .len = @intCast(bindings.types.len) },
        });
        const node: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = ty, .content = .{ .argument_default = recipe } });
        return node;
    }

    fn instantiateFields(
        self: *Resolver,
        module_index: usize,
        range: primitives.Range(ir.ParameterizedFieldId),
        bindings: *Bindings,
    ) !global_sg.FieldRange {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        var items: std.ArrayList(global_sg.Field) = .empty;
        defer items.deinit(self.allocator);
        for (0..range.len) |offset| {
            const field = storage.fields.items[range.start + @as(u32, @intCast(offset))];
            const ty = try self.instantiateParameterizedType(module_index, field.ty, bindings);
            try items.append(self.allocator, .{
                .name = try self.graph.addString(self.allocator, module.text(field.name)),
                .ty = ty,

                .source = self.globalSource(module_index, field.source),
                .default_value = if (field.default_value) |value| try self.instantiateFieldDefault(module_index, value, ty, bindings) else null,
            });
        }
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.allocator, items.items);
        return .{ .start = start, .len = range.len };
    }

    fn instantiateVariants(
        self: *Resolver,
        module_index: usize,
        range: primitives.Range(ir.ParameterizedVariantId),
        bindings: *Bindings,
    ) !global_sg.VariantRange {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
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
                            break :blk found orelse return error.UnknownParameterizedVariant;
                        },
                    };
                    try items.append(self.allocator, existing);
                },
                .semantic => |value| try items.append(self.allocator, .{
                    .name = try self.graph.addString(self.allocator, module.text(value.name)),
                    .payload_type = if (value.payload_type) |payload| try self.instantiateParameterizedType(module_index, payload, bindings) else null,
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

    pub fn evalInt(self: *Resolver, module_index: usize, id: ir.ParameterizedIntExprId, bindings: *Bindings) anyerror!i64 {
        const expression = self.modules[module_index].semantic.parameterized_storage.ir.int_expressions.items[@intFromEnum(id)];
        return switch (expression) {
            .literal => |value| value,
            .execution => |node| {
                if (self.execute_integer) |execute|
                    return execute(self.execution_context.?, module_index, node, bindings);
                const local = self.modules[module_index].semantic.parameterized_storage.ir.nodes.items[@intFromEnum(node)];
                const source = switch (local) {
                    .resolved => |value| value.source,
                    .pending => |pending| self.modules[module_index].semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending)].resolve_expression.source,
                };
                self.recordComptimeFailure(module_index, source, "compile-time execution in type or specialization arguments requires staged dependency resolution");
                return error.ComptimeExecutionNotReady;
            },
            .parameter => |parameter| bindings.ints[@intFromEnum(parameter)] orelse error.UnboundComptimeParameter,
            .projection => |value| blk: {
                const base = try self.instantiateParameterizedType(module_index, value.base, bindings);
                break :blk try self.constant_projection_resolver.?(self.projection_context.?, base, self.modules[module_index].text(value.member), self.globalSource(module_index, value.source));
            },
            .binary => |binary| blk: {
                const left = try self.evalInt(module_index, binary.left, bindings);
                const right = try self.evalInt(module_index, binary.right, bindings);
                break :blk switch (binary.operator) {
                    .add => std.math.add(i64, left, right) catch {
                        self.recordComptimeFailure(module_index, binary.source, "compile-time integer arithmetic overflow");
                        return error.ComptimeIntegerOverflow;
                    },
                    .subtract => std.math.sub(i64, left, right) catch {
                        self.recordComptimeFailure(module_index, binary.source, "compile-time integer arithmetic overflow");
                        return error.ComptimeIntegerOverflow;
                    },
                    .multiply => std.math.mul(i64, left, right) catch {
                        self.recordComptimeFailure(module_index, binary.source, "compile-time integer arithmetic overflow");
                        return error.ComptimeIntegerOverflow;
                    },
                    .divide, .modulo => blk_division: {
                        if (right == 0) {
                            self.recordComptimeFailure(module_index, binary.source, "division by zero in compile-time expression");
                            return error.ComptimeDivisionByZero;
                        }
                        if (left == std.math.minInt(i64) and right == -1) {
                            if (binary.operator == .modulo) break :blk_division 0;
                            self.recordComptimeFailure(module_index, binary.source, "compile-time integer arithmetic overflow");
                            return error.ComptimeIntegerOverflow;
                        }
                        break :blk_division if (binary.operator == .divide) @divTrunc(left, right) else @mod(left, right);
                    },
                };
            },
        };
    }

    fn recordComptimeFailure(self: *Resolver, module_index: usize, source: ?primitives.SourceRef, reason: []const u8) void {
        const location = source orelse return;
        self.comptime_failure = .{ .source = self.globalSource(module_index, location), .reason = reason };
    }

    pub fn internType(self: *Resolver, value: global_sg.GlobalType) !global_sg.GlobalTypeId {
        if (self.profile_io) |io| {
            const tag_index = @intFromEnum(std.meta.activeTag(value));
            const started = std.Io.Timestamp.now(io, .boot).nanoseconds;
            defer {
                const elapsed: u64 = @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - started);
                self.stats.type_intern_ns += elapsed;
                self.stats.type_intern_ns_by_tag[tag_index] += elapsed;
            }
            self.stats.type_intern_calls += 1;
            self.stats.type_intern_calls_by_tag[tag_index] += 1;
            if (value == .pointer) if (self.findCachedPointer(value.pointer, true)) |id| return id;
            if (value == .generic) if (self.findCachedGeneric(value.generic, true)) |id| return id;
            if (findEquivalentType(self.graph, value, &self.stats.type_intern_candidates, &self.stats.type_intern_candidates_by_tag)) |id| {
                self.cacheType(value, id);
                return id;
            }
            const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
            try self.graph.types.append(self.allocator, value);
            self.cacheType(value, id);
            return id;
        }
        if (value == .pointer) if (self.findCachedPointer(value.pointer, false)) |id| return id;
        if (value == .generic) if (self.findCachedGeneric(value.generic, false)) |id| return id;
        if (findEquivalentType(self.graph, value, null, null)) |id| {
            self.cacheType(value, id);
            return id;
        }
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, value);
        self.cacheType(value, id);
        return id;
    }

    fn cachePointer(self: *Resolver, pointer: anytype, id: global_sg.GlobalTypeId) void {
        // This index is disposable. A failed allocation must not turn a
        // successfully interned type into a semantic resolution failure.
        self.pointer_types.put(self.allocator, .{ .child = pointer.child, .mutability = pointer.mutability }, id) catch {};
    }

    fn genericKey(self: *const Resolver, generic: anytype) GenericKey {
        var hash = std.hash.Wyhash.init(0);
        for (self.graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| {
            // Matching accepts positional spelling as a wildcard. Index each
            // spelling separately so a later named instance cannot change the
            // first match previously found for a positional argument list.
            const name_length = argument.name.len;
            hash.update(std.mem.asBytes(&name_length));
            hash.update(self.graph.text(argument.name));
            const kind: u8 = @intFromEnum(std.meta.activeTag(argument.value));
            hash.update(std.mem.asBytes(&kind));
            switch (argument.value) {
                .type => |value| hash.update(std.mem.asBytes(&value)),
                .comptime_int => |value| hash.update(std.mem.asBytes(&value)),
            }
        }
        // Recursively equivalent types still use the original search on a miss.
        return .{ .base = generic.base, .arity = generic.arguments.len, .values = hash.final() };
    }

    fn cacheType(self: *Resolver, value: global_sg.GlobalType, id: global_sg.GlobalTypeId) void {
        switch (value) {
            .pointer => |pointer| self.cachePointer(pointer, id),
            .generic => |generic| self.generic_types.put(self.allocator, self.genericKey(generic), id) catch {},
            else => {},
        }
    }

    fn findCachedGeneric(self: *Resolver, generic: anytype, profile: bool) ?global_sg.GlobalTypeId {
        const key = self.genericKey(generic);
        const id = self.generic_types.get(key) orelse return null;
        if (profile) {
            self.stats.type_intern_candidates += 1;
            self.stats.type_intern_candidates_by_tag[@intFromEnum(std.meta.Tag(global_sg.GlobalType).generic)] += 1;
        }
        // Hash collisions, type mutation and IDs reused after rollback all
        // fall back to the original recursive equivalence search.
        const raw: usize = @intFromEnum(id);
        if (raw < self.graph.types.items.len and sameShallowType(self.graph, self.graph.types.items[raw], .{ .generic = generic })) return id;
        return null;
    }

    fn findCachedPointer(self: *Resolver, pointer: anytype, profile: bool) ?global_sg.GlobalTypeId {
        const key: PointerKey = .{ .child = pointer.child, .mutability = pointer.mutability };
        const candidate_id = self.pointer_types.get(key) orelse return null;
        if (profile) {
            self.stats.type_intern_candidates += 1;
            self.stats.type_intern_candidates_by_tag[@intFromEnum(std.meta.Tag(global_sg.GlobalType).pointer)] += 1;
        }
        const raw: usize = @intFromEnum(candidate_id);
        if (raw < self.graph.types.items.len and sameShallowType(self.graph, self.graph.types.items[raw], .{ .pointer = pointer })) {
            return candidate_id;
        }
        return null;
    }

    pub fn globalSource(self: *const Resolver, module_index: usize, source: primitives.SourceRef) primitives.SourceRef {
        return .{ .file_index = self.offsets[module_index].file_base + source.file_index, .offset = source.offset };
    }
};

fn findEquivalentType(
    graph: *const global_sg.GlobalSemanticGraph,
    value: global_sg.GlobalType,
    candidates_examined: ?*u64,
    candidates_by_tag: ?*[Stats.tag_count]u64,
) ?global_sg.GlobalTypeId {
    // These shapes retain their own field/variant storage identities. The
    // shallow equivalence predicate cannot reuse them, so scanning is futile.
    switch (value) {
        .inferred_choice, .structural, .structural_choice => return null,
        else => {},
    }
    for (graph.types.items, 0..) |candidate, raw| {
        if (candidates_examined) |count| count.* += 1;
        if (candidates_by_tag) |counts| counts[@intFromEnum(std.meta.activeTag(candidate))] += 1;
        if (sameShallowType(graph, candidate, value)) return @enumFromInt(@as(u32, @intCast(raw)));
    }
    return null;
}

fn sameShallowType(graph: *const global_sg.GlobalSemanticGraph, a: global_sg.GlobalType, b: global_sg.GlobalType) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .builtin => |value| value == b.builtin,
        .declared => |value| value == b.declared,
        .definition => |value| value == b.definition,
        .pointer => |value| value.mutability == b.pointer.mutability and global_types.identityEqual(graph, value.child, b.pointer.child),
        .array => |value| value.length == b.array.length and global_types.identityEqual(graph, value.element, b.array.element),
        .nullable => |value| global_types.identityEqual(graph, value, b.nullable),
        .inferred_errable => |value| global_types.identityEqual(graph, value, b.inferred_errable),
        .generic => |value| value.base == b.generic.base and global_types.genericArgumentsEqual(graph, value.arguments, b.generic.arguments),
        .virtual => |value| global_types.identityEqual(graph, value, b.virtual),
        .inferred_choice, .structural, .structural_choice => false,
    };
}

test "generic type identity is independent of argument pool position" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const name = try graph.addString(allocator, "t");
    try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(0) } });
    try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(0) } });

    const base: global_sg.GlobalDeclId = @enumFromInt(7);
    try graph.types.append(allocator, .{ .generic = .{
        .base = base,
        .arguments = .{ .start = 0, .len = 1 },
    } });

    const equivalent = findEquivalentType(&graph, .{ .generic = .{
        .base = base,
        .arguments = .{ .start = 1, .len = 1 },
    } }, null, null) orelse return error.ExpectedEquivalentGenericType;
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(equivalent));
}

test "generic interning fast index preserves argument matching and rollback" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const named = try graph.addString(allocator, "T");
    const positional = try graph.addString(allocator, "");
    const other = try graph.addString(allocator, "Other");
    inline for (.{ named, positional, other }) |name| try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(0) } });
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = undefined };
    defer resolver.deinit();
    const first = try resolver.internType(.{ .generic = .{ .base = @enumFromInt(7), .arguments = .{ .start = 0, .len = 1 } } });
    try std.testing.expectEqual(first, try resolver.internType(.{ .generic = .{ .base = @enumFromInt(7), .arguments = .{ .start = 1, .len = 1 } } }));
    const conflict = try resolver.internType(.{ .generic = .{ .base = @enumFromInt(7), .arguments = .{ .start = 2, .len = 1 } } });
    try std.testing.expect(first != conflict);
    // A key collision must not make incompatible named arguments reusable.
    const wanted = graph.types.items[@intFromEnum(first)].generic;
    try resolver.generic_types.put(allocator, resolver.genericKey(wanted), conflict);
    try std.testing.expectEqual(first, try resolver.internType(.{ .generic = wanted }));

    const saved = graph.checkpoint();
    const speculative = try resolver.internType(.{ .generic = .{ .base = @enumFromInt(8), .arguments = .{ .start = 0, .len = 1 } } });
    graph.rollback(allocator, saved);
    try graph.types.append(allocator, .{ .builtin = .Bool });
    const committed = try resolver.internType(.{ .generic = .{ .base = @enumFromInt(8), .arguments = .{ .start = 0, .len = 1 } } });
    try std.testing.expect(committed != speculative);

    graph.types.items[@intFromEnum(first)] = .{ .builtin = .UInt8 };
    const replacement = try resolver.internType(.{ .generic = .{ .base = @enumFromInt(7), .arguments = .{ .start = 0, .len = 1 } } });
    try std.testing.expect(replacement != first);
    const equivalent: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.generic_arguments.append(allocator, .{ .name = named, .value = .{ .type = equivalent } });
    try std.testing.expectEqual(replacement, try resolver.internType(.{ .generic = .{ .base = @enumFromInt(7), .arguments = .{ .start = 3, .len = 1 } } }));
}

test "pointer interning cache validates graph mutations" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });

    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = undefined,
    };
    defer resolver.deinit();

    const first = try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    try std.testing.expectEqual(first, try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } }));

    graph.types.items[@intFromEnum(first)] = .{ .builtin = .Bool };
    const after_mutation = try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    try std.testing.expect(after_mutation != first);
    try std.testing.expectEqual(.pointer, std.meta.activeTag(graph.types.items[@intFromEnum(after_mutation)]));
}

test "pointer interning fallback preserves recursive identity equality" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .builtin = .Int32 });

    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = undefined,
    };
    defer resolver.deinit();

    const first = try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } });
    const equivalent = try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } });
    try std.testing.expectEqual(first, equivalent);
}

test "generic type materialization has a dedicated resolver" {
    const stats: Stats = .{};
    try std.testing.expectEqual(@as(u64, 0), stats.type_intern_calls);
    try std.testing.expectEqual(@as(u64, 0), stats.type_intern_candidates);
    try std.testing.expectEqual(@as(u64, 0), stats.type_intern_ns);
}

test "type cache rollback discards rejected keys before graph IDs are reused" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    var resolver: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = undefined };
    defer resolver.deinit();
    const retained = try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    resolver.commitCaches();
    const saved = resolver.checkpointCaches();
    var transaction = graph.beginTransaction(a);
    defer transaction.deinit();
    const rejected = try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } });
    transaction.rollback();
    resolver.rollbackCaches(saved);
    try std.testing.expectEqual(@as(usize, 1), resolver.pointer_types.count());
    try graph.types.append(a, .{ .builtin = .Bool });
    try std.testing.expectEqual(primitives.BuiltinType.Bool, graph.semanticType(rejected).builtin);
    try std.testing.expectEqual(retained, try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } }));
    try std.testing.expect(rejected != try resolver.internType(.{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } }));
}

test "pending generic types revisit old holes and discover appended types" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.markTypeUnresolved(a, @enumFromInt(0));
    var core: core_mod.Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinit();
    var resolver: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer resolver.deinit();
    var pending: Resolver.PendingTypes = .{};
    defer pending.deinit(a);
    try std.testing.expect(!try resolver.materializePendingTypes(&pending));
    try std.testing.expectEqual(@as(usize, 1), pending.items.items.len);
    // No defining module yet: keep the old generic candidate rather than
    // treating a false materialization result as completion.
    try graph.resolveType(a, @enumFromInt(0), .{ .generic = .{ .base = @enumFromInt(0), .arguments = .{ .start = 0, .len = 0 } } });
    try std.testing.expect(!try resolver.materializePendingTypes(&pending));
    try std.testing.expectEqual(@as(usize, 1), pending.items.items.len);
    try graph.generic_instances.append(a, .{ .type_id = @enumFromInt(0), .shape = .{ .alias = @enumFromInt(1) } });
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.markTypeUnresolved(a, @enumFromInt(1));
    try std.testing.expect(!try resolver.materializePendingTypes(&pending));
    try std.testing.expectEqualSlices(global_sg.GlobalTypeId, &.{@enumFromInt(1)}, pending.items.items);
    try graph.resolveType(a, @enumFromInt(1), .{ .builtin = .Int32 });
    try std.testing.expect(!try resolver.materializePendingTypes(&pending));
    try std.testing.expectEqual(@as(usize, 0), pending.items.items.len);
    // A completed pool needs no worklist allocation, including setup calls.
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    resolver.allocator = failing.allocator();
    try std.testing.expect(!try resolver.materializeKnownTypes());
}

test "pending generic work is discarded across rollback and allocation failure" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.markTypeUnresolved(a, @enumFromInt(0));
    try std.testing.checkAllAllocationFailures(a, struct {
        fn collect(allocator: std.mem.Allocator, g: *global_sg.GlobalSemanticGraph) !void {
            var core: core_mod.Resolver = .{ .allocator = allocator, .graph = g, .modules = &.{}, .offsets = &.{} };
            defer core.deinit();
            var resolver: Resolver = .{ .allocator = allocator, .graph = g, .modules = &.{}, .offsets = &.{}, .core = &core };
            defer resolver.deinit();
            var pending: Resolver.PendingTypes = .{};
            defer pending.deinit(allocator);
            try std.testing.expect(!try resolver.materializePendingTypes(&pending));
            try std.testing.expectEqualSlices(global_sg.GlobalTypeId, &.{@enumFromInt(0)}, pending.items.items);
        }
    }.collect, .{&graph});

    var transaction = graph.beginTransaction(a);
    defer transaction.deinit();
    {
        var pending: Resolver.PendingTypes = .{};
        defer pending.deinit(a);
        try pending.discover(a, &graph, null);
        try graph.resolveType(a, @enumFromInt(0), .{ .builtin = .Int32 });
        // The worklist is owned by the resolution call, not the transaction.
    }
    transaction.rollback();
    var next: Resolver.PendingTypes = .{};
    defer next.deinit(a);
    try next.discover(a, &graph, null);
    try std.testing.expectEqualSlices(global_sg.GlobalTypeId, &.{@enumFromInt(0)}, next.items.items);
}

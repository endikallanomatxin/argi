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
    instances: u32 = 0,
    calls: u32 = 0,
    nodes: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    nested_call_context: ?*anyopaque = null,
    nested_call_resolver: ?*const fn (*anyopaque, usize, module_entities.ExternalRef, global_sg.GlobalNodeId, primitives.SourceRef) anyerror!?global_sg.Node = null,
    stats: Stats = .{},

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_call => |value| resolution.Result.fromBool(try self.resolveModuleGenericCall(module_index, module, o, value)),
            .resolve_index => |value| resolution.Result.fromBool(try self.resolveGenericIndex(module_index, o, value)),
            else => .not_applicable,
        };
    }

    fn resolveGenericIndex(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const collection = globalizer.globalNode(o, value.value);
        const collection_ty = self.graph.nodes.items[@intFromEnum(collection)].ty orelse return false;
        const identity = switch (self.graph.types.items[@intFromEnum(collection_ty)]) {
            .generic => |generic| generic,
            else => return false,
        };
        const operator: @import("../primitives/callable.zig").OperatorKind = if (value.store_value == null) .get else .set;

        // A generic container operator uses the container's parameters. This
        // covers value indexing without rebuilding parameterized unification in the
        // ordinary-operation resolver; parameterized_storage with a different parameter
        // list are rejected by instantiation or by the final operand match.
        for (self.modules, 0..) |*candidate_module, candidate_module_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                if (parameterized.operator != operator or parameterized.parameters.len != identity.arguments.len) continue;
                if (!self.parameterizedIndexesBase(candidate_module_index, parameterized, identity.base)) continue;
                const declaration = globalizer.globalDecl(self.offsets[candidate_module_index], parameterized.declaration);
                _ = self.instantiate(declaration, identity.arguments) catch continue;
            }
        }

        const index = globalizer.globalNode(o, value.index);
        var operands: [3]global_sg.GlobalNodeId = undefined;
        operands[0] = collection;
        operands[1] = index;
        var count: usize = 2;
        if (value.store_value) |stored| {
            operands[2] = globalizer.globalNode(o, stored);
            count = 3;
        }
        var operand_types: [3]global_sg.GlobalTypeId = undefined;
        for (operands[0..count], 0..) |node, i|
            operand_types[i] = self.graph.nodes.items[@intFromEnum(node)].ty orelse return false;
        var function = self.core.resolveOperator(module_index, operator, operand_types[0..count]) catch null;
        if (function == null) {
            var addressed_function: ?global_sg.GlobalFunctionId = null;
            var addressed_type: ?global_sg.GlobalTypeId = null;
            for (self.graph.functions.items, 0..) |candidate, raw| {
                if (raw >= self.graph.function_operators.items.len or self.graph.function_operators.items[raw] != operator) continue;
                if (candidate.input.len != count) continue;
                const expected_self = self.graph.fields.items[candidate.input.start].ty;
                const child = switch (self.graph.types.items[@intFromEnum(expected_self)]) {
                    .pointer => |pointer| pointer.child,
                    else => continue,
                };
                if (!global_types.equal(self.graph, child, collection_ty)) continue;
                var matches = true;
                for (1..count) |i| {
                    const expected = self.graph.fields.items[candidate.input.start + @as(u32, @intCast(i))].ty;
                    if (!global_types.equal(self.graph, expected, operand_types[i])) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
                if (addressed_function != null) return false;
                addressed_function = @enumFromInt(@as(u32, @intCast(raw)));
                addressed_type = expected_self;
            }
            function = addressed_function orelse return false;
            const address: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
            try self.graph.nodes.append(self.allocator, .{
                .source = self.graph.nodes.items[@intFromEnum(collection)].source,
                .ty = addressed_type,
                .content = .{ .address_of = collection },
            });
            operands[0] = address;
        }
        const input = try self.core.makeCallInput(function.?, operands[0..count]);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(collection)].source,
            .ty = try self.core.functionOutputType(function.?),
            .content = .{ .function_call = .{ .callee = function.?, .input = input } },
        };
        self.stats.calls += 1;
        return true;
    }

    fn parameterizedIndexesBase(
        self: *Resolver,
        module_index: usize,
        parameterized: parameterized_storage.ParameterizedFunction,
        base: global_sg.GlobalDeclId,
    ) bool {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const input = switch (storage.types.items[@intFromEnum(parameterized.input)]) {
            .resolved => |ty| switch (ty) {
                .structural => |shape| shape,
                else => return false,
            },
            else => return false,
        };
        if (input.fields.len == 0) return false;
        const self_field = storage.fields.items[input.fields.start];
        const child = switch (storage.types.items[@intFromEnum(self_field.ty)]) {
            .resolved => |ty| switch (ty) {
                .pointer => |pointer| pointer.child,
                else => return false,
            },
            else => return false,
        };
        const parameterized_base = switch (storage.types.items[@intFromEnum(child)]) {
            .resolved => |ty| switch (ty) {
                .generic => |generic| generic.base,
                else => return false,
            },
            else => return false,
        };
        return (self.generics.resolveParameterizedDeclaration(module_index, parameterized_base) catch return false) == base;
    }

    fn resolveModuleGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        const local_args = reference.generic_arguments;
        const name = module.text(reference.name);
        const input = globalizer.globalNode(o, value.input);
        if (local_args != null and reference.module_path == null and std.mem.eql(u8, name, "cast")) {
            const args = try self.generics.relocateModuleArguments(module_index, local_args.?);
            const node = (try self.makeExplicitCast(args, input, self.sourceFor(module_index, reference.source))) orelse return false;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return true;
        }
        if (reference.module_path == null and std.mem.eql(u8, name, "size_of")) {
            const node = (try self.makeSizeOf(input, self.sourceFor(module_index, reference.source))) orelse return false;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return true;
        }
        const function = if (local_args) |args|
            self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input) catch return false
        else
            self.resolveImplicitGenericFunction(module_index, module, reference, input) catch return false;
        if (!try self.core.completeCallInputFields(self.graph.functions.items[@intFromEnum(function)].input, input)) return false;
        const output_ty = try self.core.functionOutputType(function);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(module_index, reference.source),
            .ty = if (value.expected_type) |ty| globalizer.globalType(o, ty) else output_ty,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.calls += 1;
        return true;
    }

    fn resolveExplicitGenericFunction(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        const name = module.text(reference.name);
        var best: ?global_sg.GlobalDeclId = null;
        var best_score: u32 = 0;
        var tied = false;
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
                if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, candidate_module.semantic.parameterized_storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                self.generics.bindGlobalArguments(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;
                const score = self.scoreParameterizedInput(candidate_index, parameterized.input, &bindings, input) orelse continue;
                if (best == null or score > best_score) {
                    best = declaration;
                    best_score = score;
                    tied = false;
                } else if (score == best_score and declaration != best.?) tied = true;
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        return self.instantiate(best orelse return error.NoMatchingGenericFunction, arguments);
    }

    fn resolveImplicitGenericFunction(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return error.MissingGenericInputType,
        };
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        var best: ?global_sg.GlobalDeclId = null;
        var best_arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = 0, .len = 0 };
        var best_score: u32 = 0;
        var tied = false;
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), module.text(reference.name))) continue;
                if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, candidate_module.semantic.parameterized_storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                const storage = &candidate_module.semantic.parameterized_storage.ir;
                const shape = switch (storage.types.items[@intFromEnum(parameterized.input)]) {
                    .resolved => |ty| switch (ty) {
                        .structural => |shape| shape,
                        else => continue,
                    },
                    else => continue,
                };
                var matches = true;
                for (storage.fields.items[shape.fields.start..][0..shape.fields.len], 0..) |field, position| {
                    for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                        const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                        if (if (positional) position != supplied_position else !std.mem.eql(u8, candidate_module.text(field.name), self.graph.text(value.name))) continue;
                        const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse {
                            matches = false;
                            break;
                        };
                        if (!try self.inferInputType(candidate_index, field.ty, actual, &bindings)) matches = false;
                        break;
                    }
                    if (!matches) break;
                }
                if (!matches) continue;
                var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;
                defer arguments.deinit(self.allocator);
                for (parameterized.parameters.start..parameterized.parameters.start + parameterized.parameters.len) |raw| {
                    const parameter = candidate_module.semantic.parameterized_storage.comptime_parameters.items[raw];
                    const argument: global_sg.GenericArgument.Value = switch (parameter.kind) {
                        .type => .{ .type = bindings.types[raw] orelse break },
                        .comptime_int => .{ .comptime_int = bindings.ints[raw] orelse break },
                    };
                    try arguments.append(self.allocator, .{ .name = try self.graph.addString(self.allocator, candidate_module.text(parameter.name)), .value = argument });
                }
                if (arguments.items.len != parameterized.parameters.len) continue;
                const range: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = @intCast(self.graph.generic_arguments.items.len), .len = @intCast(arguments.items.len) };
                try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);
                const score = self.scoreParameterizedInput(candidate_index, parameterized.input, &bindings, input) orelse continue;
                if (best == null or score > best_score) {
                    best = declaration;
                    best_arguments = range;
                    best_score = score;
                    tied = false;
                } else if (score == best_score and declaration != best.?) tied = true;
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        return self.instantiate(best orelse return error.NoMatchingGenericFunction, best_arguments);
    }

    fn scoreParameterizedInput(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, bindings: *generic_mod.Resolver.Bindings, input: global_sg.GlobalNodeId) ?u32 {
        // Signature probing must not create persistent generic identities on
        // each deferred retry, which would prevent the fixed point from closing.
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = self.generics.stats;
        defer {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            self.generics.stats = saved_stats;
        }
        const ty = self.generics.instantiateParameterizedType(module_index, pattern, bindings, null) catch return null;
        const fields = self.interfaceFields(ty) catch return null;
        return self.core.scoreCallInput(fields, input);
    }

    // Infer from named input fields before materializing a function. Missing
    // defaulted fields supply no evidence; repeated parameters must agree.
    fn inferInputType(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        actual: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) anyerror!bool {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        switch (storage.types.items[@intFromEnum(pattern)]) {
            .parameter => |parameter| {
                const slot = &bindings.types[@intFromEnum(parameter)];
                if (slot.*) |previous| return global_types.equal(self.graph, previous, actual);
                slot.* = actual;
                return true;
            },
            .resolved => |resolved| switch (resolved) {
                .pointer => |pointer| {
                    const value = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .pointer => |value| value,
                        else => return false,
                    };
                    if (pointer.mutability == .read_write and value.mutability != .read_write) return false;
                    if (try self.inferInputType(module_index, pointer.child, value.child, bindings)) return true;
                    const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings, null) catch return false;
                    return self.core.callTypesCompatible(actual, expected);
                },
                .structural => |shape| {
                    const fields = global_types.fields(self.graph, actual) orelse return false;
                    for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                        for (self.graph.fields.items[fields.start..][0..fields.len]) |value| {
                            if (!std.mem.eql(u8, module.text(field.name), self.graph.text(value.name))) continue;
                            if (!try self.inferInputType(module_index, field.ty, value.ty, bindings)) return false;
                            break;
                        }
                    }
                    return true;
                },
                .generic => |generic| {
                    const value = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .generic => |value| value,
                        else => return false,
                    };
                    if (try self.generics.resolveParameterizedDeclaration(module_index, generic.base) != value.base) return false;
                    if (generic.arguments.len != value.arguments.len) return false;
                    for (storage.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| {
                        var matched = false;
                        for (self.graph.generic_arguments.items[value.arguments.start..][0..value.arguments.len]) |concrete| {
                            if (!std.mem.eql(u8, module.text(argument.name), self.graph.text(concrete.name))) continue;
                            switch (argument.value) {
                                .type => |ty| {
                                    if (concrete.value != .type) return false;
                                    if (!try self.inferInputType(module_index, ty, concrete.value.type, bindings)) return false;
                                },
                                .comptime_int => return false,
                            }
                            matched = true;
                            break;
                        }
                        if (!matched) return false;
                    }
                    return true;
                },
                else => {},
            },
            else => {},
        }
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings, null) catch return false;
        return global_types.equal(self.graph, expected, actual);
    }

    fn makeExplicitCast(
        self: *Resolver,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !?global_sg.Node {
        var target_type: ?global_sg.GlobalTypeId = null;
        for (self.graph.generic_arguments.items[arguments.start..][0..arguments.len]) |argument| {
            if (!std.mem.eql(u8, self.graph.text(argument.name), "to")) continue;
            target_type = switch (argument.value) {
                .type => |ty| ty,
                .comptime_int => return error.CastTargetMustBeType,
            };
            break;
        }
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return null,
        };
        var cast_value: ?global_sg.GlobalNodeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (std.mem.eql(u8, self.graph.text(field.name), "value")) {
                cast_value = field.value;
                break;
            }
        }
        const ty = target_type orelse return error.CastTargetMissing;
        return .{
            .source = source,
            .ty = ty,
            .content = .{ .explicit_cast = .{
                .value = cast_value orelse return error.CastValueMissing,
                .target_type = ty,
            } },
        };
    }

    fn makeSizeOf(
        self: *Resolver,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !?global_sg.Node {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return null,
        };
        var measured_type: ?global_sg.GlobalTypeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), "type")) continue;
            measured_type = switch (self.graph.nodes.items[@intFromEnum(field.value)].content) {
                .type_literal => |ty| ty,
                else => return null,
            };
            break;
        }
        const size = global_types.sizeOf(self.graph, measured_type orelse return error.SizeOfTypeMissing) catch return null;
        return .{
            .source = source,
            .ty = try self.generics.internType(.{ .builtin = .UIntNative }),
            .content = .{ .int_literal = std.math.cast(i64, size) orelse return error.TypeSizeOverflow },
        };
    }

    pub fn instantiate(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !global_sg.GlobalFunctionId {
        if (self.findExisting(declaration, arguments)) |id| return id;
        // Candidate bodies can fail while their dependencies remain deferred.
        // Discard every appended pool entry so retries never reuse a partial
        // function or leave nested instances referring to abandoned nodes.
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        errdefer {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            self.stats = saved_stats;
            self.generics.stats = saved_generic_stats;
        }
        const located = self.findParameterized(declaration) orelse return error.GenericFunctionParameterizedNotFound;
        const module = &self.modules[located.module_index];
        const storage = &module.semantic.parameterized_storage;

        var substitutions = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer substitutions.deinit(self.allocator);
        try self.generics.bindGlobalArguments(located.module_index, located.parameterized.parameters, arguments, &substitutions);

        const input_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.input, &substitutions, null);
        const output_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.output, &substitutions, null);
        const input_fields = try self.interfaceFields(input_ty);
        const output_fields = try self.interfaceFields(output_ty);

        var context = try InstanceContext.init(self, located.module_index, located.parameterized, &substitutions);
        defer context.deinit();
        const input_bindings = try context.instantiateBindingRange(located.parameterized.input_bindings);
        const output_bindings = try context.instantiateBindingRange(located.parameterized.output_bindings);

        // Reserve the function and identity before its body. Recursive generic
        // calls can now discover this exact monomorphization while the body is
        // still being instantiated.
        const function_id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(self.graph.functions.items.len)));
        try self.graph.functions.append(self.allocator, .{
            .declaration = declaration,
            .input = input_fields,
            .output = output_fields,
            .body = null,
            .input_bindings = input_bindings,
            .output_bindings = output_bindings,
            .safety_primitive = located.parameterized.safety_primitive,
            .flags = .{
                .is_deinit = located.parameterized.is_deinit,
                .has_declared_body = located.parameterized.body != null,
                .is_generic_instantiation = true,
                .is_abstract_dispatch = located.parameterized.dispatch_kind == .abstract_contract,
            },
        });
        try self.graph.function_operators.append(self.allocator, located.parameterized.operator);
        try self.graph.generic_function_instances.append(self.allocator, .{
            .function = function_id,
            .parameterized_declaration = declaration,
            .arguments = arguments,
        });

        context.function = function_id;
        if (located.parameterized.body) |body| {
            const instantiated_body = try context.instantiateBlock(body);
            self.graph.functions.items[@intFromEnum(function_id)].body = instantiated_body;
        }
        self.stats.instances += 1;
        return function_id;
    }

    const LocatedParameterized = struct {
        module_index: usize,
        parameterized: parameterized_storage.ParameterizedFunction,
    };

    fn findParameterized(self: *Resolver, declaration: global_sg.GlobalDeclId) ?LocatedParameterized {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return null;
        const module_index: usize = @intFromEnum(owner);
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
            if (parameterized.declaration == local) return .{ .module_index = module_index, .parameterized = parameterized };
        }
        return null;
    }

    fn findExisting(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) ?global_sg.GlobalFunctionId {
        for (self.graph.generic_function_instances.items) |instance| {
            if (instance.parameterized_declaration != declaration) continue;
            if (argumentRangesEqual(self.graph, instance.arguments, arguments)) return instance.function;
        }
        return null;
    }

    fn interfaceFields(self: *Resolver, ty: global_sg.GlobalTypeId) !global_sg.FieldRange {
        if (global_types.fields(self.graph, ty)) |range| return range;
        const name = try self.graph.addString(self.allocator, "value");
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.append(self.allocator, .{
            .name = name,
            .ty = ty,
            .source = .{ .file_index = 0, .offset = 0 },
        });
        return .{ .start = start, .len = 1 };
    }

    fn sourceFor(self: *Resolver, module_index: usize, source: primitives.SourceRef) primitives.SourceRef {
        return .{ .file_index = self.offsets[module_index].file_base + source.file_index, .offset = source.offset };
    }

    const InstanceContext = struct {
        resolver: *Resolver,
        module_index: usize,
        parameterized: parameterized_storage.ParameterizedFunction,
        substitutions: *generic_mod.Resolver.Bindings,
        binding_map: []?global_sg.GlobalBindingId,
        node_map: []?global_sg.GlobalNodeId,
        block_map: []?global_sg.GlobalBlockId,
        function: ?global_sg.GlobalFunctionId = null,

        fn init(
            resolver: *Resolver,
            module_index: usize,
            parameterized: parameterized_storage.ParameterizedFunction,
            substitutions: *generic_mod.Resolver.Bindings,
        ) !InstanceContext {
            const storage = &resolver.modules[module_index].semantic.parameterized_storage.ir;
            const bindings = try resolver.allocator.alloc(?global_sg.GlobalBindingId, storage.bindings.items.len);
            errdefer resolver.allocator.free(bindings);
            const nodes = try resolver.allocator.alloc(?global_sg.GlobalNodeId, storage.nodes.items.len);
            errdefer resolver.allocator.free(nodes);
            const blocks = try resolver.allocator.alloc(?global_sg.GlobalBlockId, storage.blocks.items.len);
            @memset(bindings, null);
            @memset(nodes, null);
            @memset(blocks, null);
            return .{
                .resolver = resolver,
                .module_index = module_index,
                .parameterized = parameterized,
                .substitutions = substitutions,
                .binding_map = bindings,
                .node_map = nodes,
                .block_map = blocks,
            };
        }

        fn deinit(self: *InstanceContext) void {
            self.resolver.allocator.free(self.binding_map);
            self.resolver.allocator.free(self.node_map);
            self.resolver.allocator.free(self.block_map);
        }

        fn instantiateBindingRange(self: *InstanceContext, range: primitives.Range(ir.ParameterizedBindingId)) !global_sg.BindingRange {
            const start: u32 = @intCast(self.resolver.graph.binding_refs.items.len);
            for (0..range.len) |offset| {
                const local: ir.ParameterizedBindingId = @enumFromInt(range.start + @as(u32, @intCast(offset)));
                const global = try self.instantiateBinding(local);
                try self.resolver.graph.binding_refs.append(self.resolver.allocator, global);
            }
            return .{ .start = start, .len = range.len };
        }

        fn instantiateBinding(self: *InstanceContext, id: ir.ParameterizedBindingId) !global_sg.GlobalBindingId {
            if (self.binding_map[@intFromEnum(id)]) |existing| return existing;
            const module = &self.resolver.modules[self.module_index];
            const source = module.semantic.parameterized_storage.ir.bindings.items[@intFromEnum(id)];
            const global: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.bindings.items.len)));
            try self.resolver.graph.bindings.append(self.resolver.allocator, .{
                .name = try self.resolver.graph.addString(self.resolver.allocator, module.text(source.name)),
                .source = self.resolver.sourceFor(self.module_index, source.source),
                .ty = try self.resolver.generics.instantiateParameterizedType(self.module_index, source.ty, self.substitutions, null),
                .initialization = null,
                .mutability = source.mutability,
            });
            self.binding_map[@intFromEnum(id)] = global;
            if (source.initialization) |node| {
                const initialization = try self.instantiateNodeAs(node, source.ty);
                self.resolver.graph.bindings.items[@intFromEnum(global)].initialization = initialization;
                const binding = &self.resolver.graph.bindings.items[@intFromEnum(global)];
                if (global_types.isBuiltin(self.resolver.graph, binding.ty, .Any)) {
                    binding.ty = self.resolver.graph.nodes.items[@intFromEnum(initialization)].ty orelse binding.ty;
                }
            }
            return global;
        }

        fn instantiateBlock(self: *InstanceContext, id: ir.ParameterizedBlockId) anyerror!global_sg.GlobalBlockId {
            if (self.block_map[@intFromEnum(id)]) |existing| return existing;
            const local = self.resolver.modules[self.module_index].semantic.parameterized_storage.ir.blocks.items[@intFromEnum(id)];
            const global: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.blocks.items.len)));
            // Reserve to support nested/self-referential block graphs.
            try self.resolver.graph.blocks.append(self.resolver.allocator, .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = null });
            self.block_map[@intFromEnum(id)] = global;

            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            var nodes: std.ArrayList(global_sg.GlobalNodeId) = .empty;
            defer nodes.deinit(self.resolver.allocator);
            for (storage.node_refs.items[local.nodes.start..][0..local.nodes.len]) |node| {
                try nodes.append(self.resolver.allocator, try self.instantiateNode(node));
            }
            const start: u32 = @intCast(self.resolver.graph.node_refs.items.len);
            try self.resolver.graph.node_refs.appendSlice(self.resolver.allocator, nodes.items);
            const ret_val = if (local.ret_val) |node| try self.instantiateNode(node) else null;
            self.resolver.graph.blocks.items[@intFromEnum(global)] = .{
                .nodes = .{ .start = start, .len = local.nodes.len },
                .ret_val = ret_val,
            };
            return global;
        }

        fn instantiateNode(self: *InstanceContext, id: ir.ParameterizedNodeId) anyerror!global_sg.GlobalNodeId {
            if (self.node_map[@intFromEnum(id)]) |existing| return existing;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const local = storage.nodes.items[@intFromEnum(id)];
            const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
            // Reserve the slot first so recursive expression graphs remain stable.
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                .source = .{ .file_index = 0, .offset = 0 },
                .ty = null,
                .content = .break_statement,
            });
            self.node_map[@intFromEnum(id)] = global;
            const instantiated: global_sg.Node = switch (local) {
                .resolved => |node| try self.instantiateResolvedNode(node),
                .pending => |pending| try self.instantiatePendingNode(storage.pending.items[@intFromEnum(pending)]),
            };
            self.resolver.graph.nodes.items[@intFromEnum(global)] = instantiated;
            self.resolver.stats.nodes += 1;
            return global;
        }

        fn instantiateNodeAs(self: *InstanceContext, id: ir.ParameterizedNodeId, expected_parameterized: ir.ParameterizedTypeId) anyerror!global_sg.GlobalNodeId {
            const expected = try self.resolver.generics.instantiateParameterizedType(self.module_index, expected_parameterized, self.substitutions, null);
            return self.instantiateNodeWithExpected(id, expected);
        }

        fn instantiateNodeWithExpected(self: *InstanceContext, id: ir.ParameterizedNodeId, expected: global_sg.GlobalTypeId) anyerror!global_sg.GlobalNodeId {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const local = storage.nodes.items[@intFromEnum(id)];
            if (local == .pending) {
                const pending = storage.pending.items[@intFromEnum(local.pending)];
                if (pending == .resolve_expression and pending.resolve_expression.kind == .choice_literal) {
                    if (self.node_map[@intFromEnum(id)]) |existing| return existing;
                    const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
                    try self.resolver.graph.nodes.append(self.resolver.allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .break_statement });
                    self.node_map[@intFromEnum(id)] = global;
                    self.resolver.graph.nodes.items[@intFromEnum(global)] = try self.resolveChoiceLiteral(pending.resolve_expression, expected);
                    self.resolver.stats.nodes += 1;
                    return global;
                }
            } else if (local.resolved.content == .struct_value_literal) {
                return self.instantiateStructValueWithExpected(id, local.resolved, expected);
            }
            return self.instantiateNode(id);
        }

        fn instantiateStructValueWithExpected(self: *InstanceContext, id: ir.ParameterizedNodeId, node: ir.ResolvedNode, expected: global_sg.GlobalTypeId) !global_sg.GlobalNodeId {
            if (self.node_map[@intFromEnum(id)]) |existing| return existing;
            const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .break_statement });
            self.node_map[@intFromEnum(id)] = global;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const expected_fields = global_types.fields(self.resolver.graph, expected) orelse return error.ParameterizedStructExpectedNonStruct;
            const local_fields = node.content.struct_value_literal.fields;
            var values: std.ArrayList(global_sg.ValueField) = .empty;
            defer values.deinit(self.resolver.allocator);
            for (storage.value_fields.items[local_fields.start..][0..local_fields.len]) |field| {
                var expected_field: ?global_sg.Field = null;
                for (self.resolver.graph.fields.items[expected_fields.start..][0..expected_fields.len]) |candidate| {
                    if (std.mem.eql(u8, self.resolver.modules[self.module_index].text(field.name), self.resolver.graph.text(candidate.name))) {
                        expected_field = candidate;
                        break;
                    }
                }
                const field_type = expected_field orelse return error.UnknownParameterizedStructField;
                try values.append(self.resolver.allocator, .{
                    .name = field_type.name,
                    .value = try self.instantiateNodeWithExpected(field.value, field_type.ty),
                });
            }
            const start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, values.items);
            self.resolver.graph.nodes.items[@intFromEnum(global)] = .{
                .source = self.resolver.sourceFor(self.module_index, node.source),
                .ty = expected,
                .content = .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = local_fields.len }, .ty = expected } },
            };
            self.resolver.stats.nodes += 1;
            return global;
        }

        fn instantiateResolvedNode(self: *InstanceContext, node: ir.ResolvedNode) anyerror!global_sg.Node {
            if (node.content == .struct_value_literal) return self.instantiateStructValue(node);
            if (node.content == .binding_use or node.content == .binding_declaration) {
                const declaration = node.content == .binding_declaration;
                const binding = try self.instantiateBinding(if (declaration) node.content.binding_declaration else node.content.binding_use);
                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = self.resolver.graph.bindings.items[@intFromEnum(binding)].ty,
                    .content = if (declaration) .{ .binding_declaration = binding } else .{ .binding_use = binding },
                };
            }
            const ty = if (node.ty) |value| try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions, null) else null;
            return .{
                .source = self.resolver.sourceFor(self.module_index, node.source),
                .ty = ty,
                .content = switch (node.content) {
                    .binding_use => |binding| .{ .binding_use = try self.instantiateBinding(binding) },
                    .binding_declaration => |binding| .{ .binding_declaration = try self.instantiateBinding(binding) },
                    .assignment => |assignment| .{ .assignment = .{
                        .binding = try self.instantiateBinding(assignment.binding),
                        .value = try self.instantiateNodeAs(assignment.value, self.resolver.modules[self.module_index].semantic.parameterized_storage.ir.bindings.items[@intFromEnum(assignment.binding)].ty),
                    } },
                    .code_block => |block| .{ .code_block = try self.instantiateBlock(block) },
                    .int_literal => |value| .{ .int_literal = value },
                    .float_literal => |value| .{ .float_literal = value },
                    .char_literal => |value| .{ .char_literal = value },
                    .bool_literal => |value| .{ .bool_literal = value },
                    .string_literal => |value| .{ .string_literal = try self.copyString(value) },
                    .type_literal => |value| .{ .type_literal = try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions, null) },
                    .move_value => |value| .{ .move_value = try self.instantiateNode(value) },
                    .break_statement => .break_statement,
                    .continue_statement => .continue_statement,
                    else => return error.UnsupportedResolvedParameterizedNode,
                },
            };
        }

        fn instantiateStructValue(self: *InstanceContext, node: ir.ResolvedNode) !global_sg.Node {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const range = node.content.struct_value_literal.fields;
            var values: std.ArrayList(global_sg.ValueField) = .empty;
            defer values.deinit(self.resolver.allocator);
            var fields: std.ArrayList(global_sg.Field) = .empty;
            defer fields.deinit(self.resolver.allocator);
            var choice_context: ?global_sg.GlobalTypeId = null;
            for (storage.value_fields.items[range.start..][0..range.len]) |field| {
                if (!std.mem.eql(u8, self.resolver.modules[self.module_index].text(field.name), "value")) continue;
                const value = try self.instantiateNode(field.value);
                choice_context = self.resolver.graph.nodes.items[@intFromEnum(value)].ty;
                break;
            }
            for (storage.value_fields.items[range.start..][0..range.len]) |field| {
                const local = storage.nodes.items[@intFromEnum(field.value)];
                const contextual_choice = local == .pending and storage.pending.items[@intFromEnum(local.pending)] == .resolve_expression and
                    storage.pending.items[@intFromEnum(local.pending)].resolve_expression.kind == .choice_literal;
                const value = if (contextual_choice and choice_context != null)
                    try self.instantiateChoiceTag(field.value, choice_context.?)
                else
                    try self.instantiateNode(field.value);
                const name = try self.copyString(field.name);
                try values.append(self.resolver.allocator, .{ .name = name, .value = value });
                try fields.append(self.resolver.allocator, .{
                    .name = name,
                    .ty = self.resolver.graph.nodes.items[@intFromEnum(value)].ty orelse return error.MissingParameterizedValueType,
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                });
            }
            const field_start: u32 = @intCast(self.resolver.graph.fields.items.len);
            try self.resolver.graph.fields.appendSlice(self.resolver.allocator, fields.items);
            const ty: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.types.items.len)));
            try self.resolver.graph.types.append(self.resolver.allocator, .{ .structural = .{
                .fields = .{ .start = field_start, .len = @intCast(fields.items.len) },
            } });
            const start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, values.items);
            return .{ .source = self.resolver.sourceFor(self.module_index, node.source), .ty = ty, .content = .{
                .struct_value_literal = .{ .fields = .{ .start = start, .len = @intCast(values.items.len) }, .ty = ty },
            } };
        }

        fn instantiateChoiceTag(self: *InstanceContext, id: ir.ParameterizedNodeId, choice_type: global_sg.GlobalTypeId) !global_sg.GlobalNodeId {
            if (self.node_map[@intFromEnum(id)]) |existing| return existing;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const local = storage.nodes.items[@intFromEnum(id)];
            const pending = switch (local) {
                .pending => |pending_id| storage.pending.items[@intFromEnum(pending_id)],
                else => return error.ParameterizedChoiceTagExpected,
            };
            const expression = switch (pending) {
                .resolve_expression => |value| value,
                else => return error.ParameterizedChoiceTagExpected,
            };
            const name = self.resolver.modules[self.module_index].text(expression.name orelse return error.ParameterizedChoiceLiteralWithoutName);
            const variant = global_types.findVariant(self.resolver.graph, choice_type, name) orelse return error.UnknownParameterizedChoiceVariant;
            const ty = try self.resolver.generics.internType(.{ .builtin = .Int32 });
            const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                .source = self.resolver.sourceFor(self.module_index, expression.source),
                .ty = ty,
                .content = .{ .int_literal = variant.variant.value },
            });
            self.node_map[@intFromEnum(id)] = global;
            self.resolver.stats.nodes += 1;
            return global;
        }

        fn instantiatePendingNode(self: *InstanceContext, pending: ir.Pending) anyerror!global_sg.Node {
            return switch (pending) {
                .resolve_name => |value| self.resolveName(value),
                .resolve_call => |value| self.resolveLegacyCall(value),
                .resolve_field => |value| self.resolveParameterizedField(value.value, value.field_name, value.source),
                .resolve_expression => |value| self.resolveExpression(value),
                .resolve_copy, .resolve_deinit => error.ParameterizedOwnershipPending,
            };
        }

        fn resolveName(self: *InstanceContext, value: anytype) !global_sg.Node {
            const name = self.resolver.modules[self.module_index].text(value.name);
            if (self.findGlobalBinding(name)) |binding| {
                const record = self.resolver.graph.bindings.items[@intFromEnum(binding)];
                return .{ .source = self.resolver.sourceFor(self.module_index, value.source), .ty = record.ty, .content = .{ .binding_use = binding } };
            }
            return error.UnknownParameterizedName;
        }

        fn resolveLegacyCall(self: *InstanceContext, value: anytype) !global_sg.Node {
            const input = try self.instantiateNode(value.input);
            return self.makeNamedCall(value.name, null, .{ .start = 0, .len = 0 }, input, value.source);
        }

        fn resolveExpression(self: *InstanceContext, value: ir.PendingExpression) anyerror!global_sg.Node {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            var operands = std.array_list.Managed(global_sg.GlobalNodeId).init(self.resolver.allocator);
            defer operands.deinit();
            for (storage.node_refs.items[value.operands.start..][0..value.operands.len]) |operand|
                try operands.append(try self.instantiateNode(operand));

            return switch (value.kind) {
                .unknown_identifier => if (value.name) |name| self.resolveName(.{ .name = name, .source = value.source }) else error.UnknownParameterizedName,
                .generic_call => blk: {
                    const name = value.name orelse return error.GenericParameterizedCallWithoutName;
                    const args = try self.resolver.generics.instantiateParameterizedArguments(self.module_index, value.generic_arguments, self.substitutions, null);
                    const input = if (operands.items.len != 0) operands.items[0] else return error.GenericParameterizedCallWithoutInput;
                    break :blk try self.makeNamedCall(name, value.module_path, args, input, value.source);
                },
                .binary => self.resolveBinary(operands.items, value.source, value.detail),
                .comparison => self.resolveComparison(operands.items, value.source, value.detail),
                .logical => self.resolveLogical(operands.items, value.source, value.detail),
                .index => self.resolveIndex(operands.items, value.source, false),
                .index_store => self.resolveIndex(operands.items, value.source, true),
                .field_access => if (value.name) |name| self.resolveField(operands.items[0], name, value.source) else error.InvalidParameterizedFieldAccess,
                .choice_payload => if (value.name) |name| self.resolveChoicePayload(operands.items[0], name, value.source) else error.InvalidParameterizedChoicePayload,
                .return_statement => self.resolveReturn(operands.items, value.source),
                .if_statement => self.resolveIf(operands.items, value.source),
                .while_statement => self.resolveWhile(operands.items, value.source),
                .match => if (operands.items.len == 1) self.resolveMatch(value, operands.items[0]) else error.InvalidParameterizedMatch,
                .address_of => self.resolveAddress(operands.items, value.source, value.detail),
                .dereference => self.resolveDereference(operands.items, value.source),
                .pointer_store => self.resolvePointerStore(operands.items, value.source),
                .move_value => self.resolveMove(operands.items, value.source),
                .pipe => if (operands.items.len != 0) self.resolver.graph.nodes.items[@intFromEnum(operands.items[operands.items.len - 1])] else error.InvalidParameterizedPipe,
                .struct_value,
                .list_value,
                .choice_literal,
                .nullable_test,
                .unwrap_or,
                .unwrap_or_do,
                .error_propagation,
                .error_context,
                .for_each,
                .match_case,
                .defer_value,
                .keep_binding,
                .type_initializer,
                .explicit_cast,
                .other,
                => error.ParameterizedExpressionRequiresGlobalResolver,
            };
        }

        fn resolveChoiceLiteral(self: *InstanceContext, value: ir.PendingExpression, expected: global_sg.GlobalTypeId) !global_sg.Node {
            const name_range = value.name orelse return error.ParameterizedChoiceLiteralWithoutName;
            const name = self.resolver.modules[self.module_index].text(name_range);
            const variant = global_types.findVariant(self.resolver.graph, expected, name) orelse return error.UnknownParameterizedChoiceVariant;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const payload = if (value.operands.len == 0)
                null
            else if (value.operands.len == 1)
                if (variant.variant.payload_type) |payload_type|
                    try self.instantiateNodeWithExpected(storage.node_refs.items[value.operands.start], payload_type)
                else
                    try self.instantiateNode(storage.node_refs.items[value.operands.start])
            else
                return error.InvalidParameterizedChoicePayload;
            if ((variant.variant.payload_type == null) != (payload == null)) return error.ParameterizedChoicePayloadMismatch;
            if (payload) |node| {
                const actual = self.resolver.graph.nodes.items[@intFromEnum(node)].ty orelse return error.UntypedParameterizedChoicePayload;
                if (!global_types.equal(self.resolver.graph, actual, variant.variant.payload_type.?)) return error.ParameterizedChoicePayloadMismatch;
            }
            return .{
                .source = self.resolver.sourceFor(self.module_index, value.source),
                .ty = expected,
                .content = .{ .choice_literal = .{ .choice_type = expected, .variant = variant.id, .payload = payload } },
            };
        }

        fn resolveMatch(self: *InstanceContext, value: ir.PendingExpression, expression: global_sg.GlobalNodeId) !global_sg.Node {
            const choice_type = self.resolver.graph.nodes.items[@intFromEnum(expression)].ty orelse return error.UntypedParameterizedMatch;
            const variants = global_types.variants(self.resolver.graph, choice_type) orelse return error.ParameterizedMatchRequiresChoice;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            var cases: std.ArrayList(global_sg.SwitchCase) = .empty;
            defer cases.deinit(self.resolver.allocator);
            var seen: std.ArrayList(global_sg.GlobalVariantId) = .empty;
            defer seen.deinit(self.resolver.allocator);
            for (storage.match_cases.items[value.match_cases.start..][0..value.match_cases.len]) |case| {
                const name = self.resolver.modules[self.module_index].text(case.name);
                const variant = global_types.findVariant(self.resolver.graph, choice_type, name) orelse return error.UnknownParameterizedMatchVariant;
                for (seen.items) |previous| if (previous == variant.id) return error.DuplicateParameterizedMatchCase;
                try seen.append(self.resolver.allocator, variant.id);
                if (case.payload_binding) |local_binding| {
                    const payload = variant.variant.payload_type orelse return error.ParameterizedMatchPayloadOnPayloadlessVariant;
                    const binding = try self.instantiateBinding(local_binding);
                    self.resolver.graph.bindings.items[@intFromEnum(binding)].ty = try self.matchBindingType(payload, case.mode);
                }
                const body = try self.instantiateBlock(case.body);
                const tag: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
                const int_type = try self.resolver.generics.internType(.{ .builtin = .Int32 });
                try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                    .source = self.resolver.sourceFor(self.module_index, case.source),
                    .ty = int_type,
                    .content = .{ .int_literal = variant.variant.value },
                });
                try cases.append(self.resolver.allocator, .{ .value = tag, .variant = variant.id, .body = body });
            }
            const case_start: u32 = @intCast(self.resolver.graph.switch_cases.items.len);
            try self.resolver.graph.switch_cases.appendSlice(self.resolver.allocator, cases.items);
            const switch_id: global_sg.GlobalSwitchId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.switches.items.len)));
            try self.resolver.graph.switches.append(self.resolver.allocator, .{
                .expression = expression,
                .cases = .{ .start = case_start, .len = @intCast(cases.items.len) },
                .default_block = null,
                .exhaustive = cases.items.len == variants.len,
            });
            return .{
                .source = self.resolver.sourceFor(self.module_index, value.source),
                .ty = try self.resolver.generics.internType(.{ .builtin = .Void }),
                .content = .{ .switch_statement = switch_id },
            };
        }

        fn matchBindingType(self: *InstanceContext, payload: global_sg.GlobalTypeId, mode: primitives.MatchCaseMode) !global_sg.GlobalTypeId {
            return switch (mode) {
                .value, .move => payload,
                .borrow => self.resolver.generics.internType(.{ .pointer = .{ .child = payload, .mutability = .read_only } }),
                .mut_borrow => self.resolver.generics.internType(.{ .pointer = .{ .child = payload, .mutability = .read_write } }),
            };
        }

        fn makeNamedCall(
            self: *InstanceContext,
            name_range: primitives.StringRange,
            module_path: ?primitives.StringRange,
            arguments: primitives.Range(global_sg.GlobalGenericArgId),
            input: global_sg.GlobalNodeId,
            source: primitives.SourceRef,
        ) !global_sg.Node {
            const module = &self.resolver.modules[self.module_index];
            const name = module.text(name_range);
            if (module_path == null and std.mem.eql(u8, name, "cast"))
                return (try self.resolver.makeExplicitCast(arguments, input, self.resolver.sourceFor(self.module_index, source))) orelse error.CastInputMustBeStruct;
            if (module_path == null and std.mem.eql(u8, name, "size_of"))
                return (try self.resolver.makeSizeOf(input, self.resolver.sourceFor(self.module_index, source))) orelse error.SizeOfInputMustBeStruct;
            if (module_path == null and std.mem.eql(u8, name, "is"))
                return self.resolveChoiceTest(input, source);
            const input_literal = switch (self.resolver.graph.nodes.items[@intFromEnum(input)].content) {
                .struct_value_literal => |value| value,
                else => null,
            };
            if (input_literal) |literal| if (literal.fields.len == 0) {
                if (try self.resolveEmptyTypeInitializer(name, source)) |node| return node;
            };
            const reference: module_entities.ExternalRef = .{ .kind = .function, .module_path = module_path, .name = name_range, .source = source };
            const function = if (arguments.len != 0)
                try self.resolver.resolveExplicitGenericFunction(self.module_index, module, reference, arguments, input)
            else
                self.resolver.core.resolveFunctionByName(self.module_index, reference, input) catch
                    self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input) catch |err| {
                    if (self.resolver.nested_call_context) |context| {
                        if (self.resolver.nested_call_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
                    if (module_path == null and std.mem.eql(u8, name, "deinit") and
                        self.parameterized.safety_primitive == .trusted_opaque_drop)
                        return self.emptyValue(try self.resolver.generics.internType(.{ .builtin = .Void }), source);
                    return err;
                };
            if (!try self.resolver.core.completeCallInputFields(self.resolver.graph.functions.items[@intFromEnum(function)].input, input)) return error.IncompleteParameterizedCallInput;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = try self.resolver.core.functionOutputType(function),
                .content = .{ .function_call = .{ .callee = function, .input = input } },
            };
        }

        fn resolveChoiceTest(self: *InstanceContext, input: global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            const literal = self.resolver.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal;
            var value: ?global_sg.GlobalNodeId = null;
            var variant: ?global_sg.GlobalNodeId = null;
            for (self.resolver.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
                if (std.mem.eql(u8, self.resolver.graph.text(field.name), "value")) value = field.value;
                if (std.mem.eql(u8, self.resolver.graph.text(field.name), "variant")) variant = field.value;
            }
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = try self.resolver.generics.internType(.{ .builtin = .Bool }),
                .content = .{ .comparison = .{ .operator = .equal, .left = value orelse return error.ChoiceTestMissingValue, .right = variant orelse return error.ChoiceTestMissingVariant } },
            };
        }

        fn resolveEmptyTypeInitializer(self: *InstanceContext, name: []const u8, source: primitives.SourceRef) !?global_sg.Node {
            inline for (@typeInfo(primitives.BuiltinType).@"enum".fields) |field| {
                if (std.mem.eql(u8, name, field.name)) {
                    const ty = try self.resolver.generics.internType(.{ .builtin = @enumFromInt(field.value) });
                    return self.emptyValue(ty, source);
                }
            }
            for (self.resolver.graph.declarations.items, 0..) |declaration, raw| {
                if (declaration.kind != .type or !std.mem.eql(u8, self.resolver.graph.text(declaration.name), name)) continue;
                const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
                if (!self.resolver.core.declarationVisible(self.module_index, id, null)) continue;
                const ty = declaration.type_id orelse continue;
                const fields = global_types.fields(self.resolver.graph, ty) orelse continue;
                if (fields.len == 0) return self.emptyValue(ty, source);
            }
            return null;
        }

        fn emptyValue(self: *InstanceContext, ty: global_sg.GlobalTypeId, source: primitives.SourceRef) global_sg.Node {
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = ty,
                .content = .{ .struct_value_literal = .{
                    .fields = .{ .start = @intCast(self.resolver.graph.value_fields.items.len), .len = 0 },
                    .ty = ty,
                } },
            };
        }

        fn resolveBinary(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, detail: ir.PendingExpressionDetail) !global_sg.Node {
            if (operands.len != 2) return error.InvalidParameterizedBinary;
            const operator: primitives.BinaryOperator = switch (detail) {
                .binary => |value| value,
                else => return error.InvalidParameterizedBinary,
            };
            const ty = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = ty,
                .content = .{ .binary_operation = .{ .operator = operator, .left = operands[0], .right = operands[1] } },
            };
        }

        fn resolveComparison(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, detail: ir.PendingExpressionDetail) !global_sg.Node {
            if (operands.len != 2) return error.InvalidParameterizedComparison;
            const operator: primitives.ComparisonOperator = switch (detail) {
                .comparison => |value| value,
                else => return error.InvalidParameterizedComparison,
            };
            const bool_ty = try self.resolver.generics.internType(.{ .builtin = .Bool });
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = bool_ty,
                .content = .{ .comparison = .{ .operator = operator, .left = operands[0], .right = operands[1] } },
            };
        }

        fn resolveLogical(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, detail: ir.PendingExpressionDetail) !global_sg.Node {
            if (operands.len != 2) return error.InvalidParameterizedLogical;
            const operator: primitives.LogicalOperator = switch (detail) {
                .logical => |value| value,
                else => return error.InvalidParameterizedLogical,
            };
            const bool_ty = try self.resolver.generics.internType(.{ .builtin = .Bool });
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = bool_ty, .content = .{ .logical_operation = .{ .operator = operator, .left = operands[0], .right = operands[1] } } };
        }

        fn resolveParameterizedField(self: *InstanceContext, value: ir.ParameterizedNodeId, field_name: primitives.StringRange, source: primitives.SourceRef) !global_sg.Node {
            return self.resolveField(try self.instantiateNode(value), field_name, source);
        }

        fn resolveField(self: *InstanceContext, value: global_sg.GlobalNodeId, field_name: primitives.StringRange, source: primitives.SourceRef) !global_sg.Node {
            const ty = self.resolver.graph.nodes.items[@intFromEnum(value)].ty orelse return error.ParameterizedFieldOnUntypedValue;
            const name = self.resolver.modules[self.module_index].text(field_name);
            if (self.resolver.core.isUnpackedOutputField(value, name))
                return self.resolver.graph.nodes.items[@intFromEnum(value)];
            _ = try self.resolver.generics.ensureGenericInstance(ty);
            const hit = global_types.findField(self.resolver.graph, ty, name) orelse return error.UnknownParameterizedField;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = hit.field.ty,
                .content = .{ .struct_field_access = .{ .value = value, .field_name = try self.copyString(field_name), .field_index = hit.index } },
            };
        }

        fn resolveChoicePayload(self: *InstanceContext, value: global_sg.GlobalNodeId, variant_name: primitives.StringRange, source: primitives.SourceRef) !global_sg.Node {
            const choice_ty = self.resolver.graph.nodes.items[@intFromEnum(value)].ty orelse return error.ParameterizedChoicePayloadOnUntypedValue;
            _ = try self.resolver.generics.ensureGenericInstance(choice_ty);
            const name = self.resolver.modules[self.module_index].text(variant_name);
            const hit = global_types.findVariant(self.resolver.graph, choice_ty, name) orelse return error.UnknownParameterizedChoiceVariant;
            const payload_ty = hit.variant.payload_type orelse return error.ParameterizedChoiceVariantWithoutPayload;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = payload_ty,
                .content = .{ .choice_payload_access = .{
                    .value = value,
                    .variant = hit.id,
                    .payload_type = payload_ty,
                } },
            };
        }

        fn resolveMove(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 1) return error.InvalidParameterizedMove;
            const value = operands[0];
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = self.resolver.graph.nodes.items[@intFromEnum(value)].ty,
                .content = .{ .move_value = value },
            };
        }

        fn resolveIndex(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, store: bool) !global_sg.Node {
            if (operands.len < 2) return error.InvalidParameterizedIndex;
            const collection_ty = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.ParameterizedIndexUntyped;
            const element = global_types.arrayElement(self.resolver.graph, collection_ty) orelse return error.ParameterizedIndexRequiresDispatch;
            return if (store) .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = element,
                .content = .{ .array_store = .{ .array_ptr = operands[0], .index = operands[1], .value = operands[2], .element_type = element, .array_type = collection_ty } },
            } else .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = element,
                .content = .{ .array_index = .{ .array_ptr = operands[0], .index = operands[1], .element_type = element, .array_type = collection_ty } },
            };
        }

        fn resolveReturn(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            const void_ty = try self.resolver.generics.internType(.{ .builtin = .Void });
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = if (operands.len != 0) self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty else void_ty,
                .content = .{ .return_statement = .{ .expression = if (operands.len != 0) operands[0] else null, .cleanup = .{ .start = 0, .len = 0 } } },
            };
        }

        fn resolveIf(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len < 2) return error.InvalidParameterizedIf;
            const then_block = switch (self.resolver.graph.nodes.items[@intFromEnum(operands[1])].content) {
                .code_block => |block| block,
                else => return error.ParameterizedIfBlockExpected,
            };
            const else_block = if (operands.len > 2) switch (self.resolver.graph.nodes.items[@intFromEnum(operands[2])].content) {
                .code_block => |block| block,
                else => return error.ParameterizedIfBlockExpected,
            } else null;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = try self.resolver.generics.internType(.{ .builtin = .Void }),
                .content = .{ .if_statement = .{ .condition = operands[0], .then_block = then_block, .else_block = else_block } },
            };
        }

        fn resolveWhile(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 2) return error.InvalidParameterizedWhile;
            const body = switch (self.resolver.graph.nodes.items[@intFromEnum(operands[1])].content) {
                .code_block => |block| block,
                else => return error.ParameterizedWhileBlockExpected,
            };
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = try self.resolver.generics.internType(.{ .builtin = .Void }),
                .content = .{ .while_statement = .{ .condition = operands[0], .body = body } },
            };
        }

        fn resolveAddress(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, detail: ir.PendingExpressionDetail) !global_sg.Node {
            if (operands.len != 1) return error.InvalidParameterizedAddressOf;
            const child = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.ParameterizedAddressUntyped;
            const mutability: primitives.PointerMutability = switch (detail) {
                .pointer_mutability => |value| value,
                else => return error.InvalidParameterizedAddressOf,
            };
            const pointer = try self.resolver.generics.internType(.{ .pointer = .{ .child = child, .mutability = mutability } });
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = pointer, .content = .{ .address_of = operands[0] } };
        }

        fn resolveDereference(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 1) return error.InvalidParameterizedDereference;
            const pointer_ty = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.ParameterizedDereferenceUntyped;
            const child = switch (self.resolver.graph.types.items[@intFromEnum(pointer_ty)]) {
                .pointer => |pointer| pointer.child,
                else => return error.ParameterizedDereferenceNonPointer,
            };
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = child, .content = .{ .dereference = .{ .pointer = operands[0], .ty = child, .pointer_type = pointer_ty } } };
        }

        fn resolvePointerStore(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 2) return error.InvalidParameterizedPointerStore;
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = self.resolver.graph.nodes.items[@intFromEnum(operands[1])].ty, .content = .{ .pointer_assignment = .{ .pointer = operands[0], .value = operands[1] } } };
        }

        fn findGlobalBinding(self: *InstanceContext, name: []const u8) ?global_sg.GlobalBindingId {
            for (self.resolver.graph.bindings.items, 0..) |binding, raw| {
                if (std.mem.eql(u8, self.resolver.graph.text(binding.name), name)) return @enumFromInt(@as(u32, @intCast(raw)));
            }
            return null;
        }

        fn copyString(self: *InstanceContext, range: primitives.StringRange) !primitives.StringRange {
            return self.resolver.graph.addString(self.resolver.allocator, self.resolver.modules[self.module_index].text(range));
        }
    };
};

fn argumentRangesEqual(
    graph: *const global_sg.GlobalSemanticGraph,
    a: primitives.Range(global_sg.GlobalGenericArgId),
    b: primitives.Range(global_sg.GlobalGenericArgId),
) bool {
    if (a.len != b.len) return false;
    for (0..a.len) |offset| {
        const left = graph.generic_arguments.items[a.start + @as(u32, @intCast(offset))];
        const right = graph.generic_arguments.items[b.start + @as(u32, @intCast(offset))];
        if (!std.mem.eql(u8, graph.text(left.name), graph.text(right.name))) return false;
        switch (left.value) {
            .type => |left_ty| switch (right.value) {
                .type => |right_ty| if (left_ty != right_ty) return false,
                else => return false,
            },
            .comptime_int => |left_int| switch (right.value) {
                .comptime_int => |right_int| if (left_int != right_int) return false,
                else => return false,
            },
        }
    }
    return true;
}

test "generic function monomorphization uses stable GlobalFunctionId identity" {
    try std.testing.expect(@sizeOf(global_sg.GlobalFunctionId) == 4);
    try std.testing.expect(@sizeOf(global_sg.GenericFunctionInstance) <= 16);
}

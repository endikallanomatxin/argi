const implementation_arguments = @import("implementation_arguments.zig");
const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const primitives = @import("../primitives/schema.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const reach_context = @import("reach_context.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const generic_mod = @import("generics.zig");
const generic_functions_mod = @import("generic_functions.zig");
const types = @import("types.zig");
const contract_mod = @import("contracts.zig");
const initializer_contract = @import("initializer_contract.zig");
const standard_contracts = @import("standard_contracts.zig");
const c_abi = @import("c_abi.zig");
const module_linker = @import("module_linker.zig");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");

/// Resolves type calls through Init evidence or structural initialization.
pub const Resolver = struct {
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    diagnostics: ?*diagnostics_mod.Diagnostics = null,
    // GlobalSema wires these after creating the mutually recursive resolvers.
    // Constructor probes share their caches and services with normal calls.
    generics: ?*generic_mod.Resolver = null,
    generic_functions: ?*generic_functions_mod.Resolver = null,
    contracts: ?*contract_mod.Resolver = null,

    /// Resolve a constructor encountered while materializing a generic
    /// function body. Structural construction never bypasses a visible init.
    pub fn resolveNestedCall(
        context_ptr: *anyopaque,
        module_index: usize,
        reference: module_entities.ExternalRef,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
        reach: reach_context.Context,
        source: primitives.SourceRef,
    ) anyerror!?global_sg.Node {
        const self: *Resolver = @ptrCast(@alignCast(context_ptr));
        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return null,
            else => return err,
        };
        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
        const generics = self.generics.?;
        const parameterized = generics.isParameterizedTypeDeclaration(declaration_id);
        const ty = if (parameterized) blk: {
            if (arguments.len == 0) {
                const identity = standard_contracts.standardDeclaration(self.graph, "Init") orelse return null;
                const selection = try self.inferContractArguments(identity, null, declaration_id, input, reach, source) orelse return null;
                _ = try generics.ensureGenericInstance(selection.target);
                return self.contractInitializer(module_index, selection.target, input, reach, source);
            }
            if (generics.findTypeParameterized(declaration_id)) |located| {
                if (arguments.len < located.parameterized.parameters.len) {
                    const identity = standard_contracts.standardDeclaration(self.graph, "Init") orelse return null;
                    const selection = try self.inferConstructorArguments(identity, .{ .partial = .{ .family = declaration_id, .arguments = arguments } }, input, reach, source);
                    if (selection) |selected| return self.contractInitializer(module_index, selected.target, input, reach, source);
                }
            }
            const generic_ty = try generics.internType(.{ .generic = .{
                .base = declaration_id,
                .arguments = arguments,
            } });
            _ = generics.ensureGenericInstance(generic_ty) catch return null;
            break :blk generic_ty;
        } else blk: {
            if (arguments.len != 0) return null;
            break :blk declaration.type_id orelse return null;
        };

        if (try self.contractInitializer(module_index, ty, input, reach, source)) |call| return call;

        const fields = types.fields(self.graph, ty) orelse return null;
        switch (self.core.matchCallInput(fields, input)) {
            .applicable => {},
            .no_match, .deferred => return null,
        }
        if (!try self.core.completeCallInputFieldsWithReach(fields, input, reach)) return null;
        self.graph.nodes.items[@intFromEnum(input)].ty = ty;
        var node = self.graph.nodes.items[@intFromEnum(input)];
        node.source = source;
        self.core.stats.calls += 1;
        return node;
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_call => |value| try self.resolveCall(module_index, module, o, value),
            else => .not_applicable,
        };
    }

    fn callbackError(self: *Resolver, source: primitives.SourceRef, message: []const u8) !resolution.Result {
        if (self.diagnostics) |diagnostics| {
            var file_id: u32 = 0;
            const file = self.graph.files.items[source.file_index];
            const name = self.graph.text(file.path);
            const dir = self.graph.text(self.graph.modules.items[@intFromEnum(file.module)].dir);
            for (diagnostics.source_files, 0..) |candidate, index| {
                if (std.mem.eql(u8, std.fs.path.basename(candidate.path), name) and std.mem.eql(u8, std.fs.path.dirname(candidate.path) orelse ".", dir)) {
                    file_id = @intCast(index);
                    break;
                }
            }
            try diagnostics.add(.{ .file = @enumFromInt(file_id), .offset = source.offset }, .semantic, "{s}", .{message});
        }
        return error.Reported;
    }

    fn resolveCallbackConstructor(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype, declaration: global_sg.Declaration, ty: global_sg.GlobalTypeId, input: global_sg.GlobalNodeId) !resolution.Result {
        const target = globalizer.globalNode(o, value.node);
        const local_source = module.semantic.external_refs.items[@intFromEnum(value.callee)].source;
        const source: primitives.SourceRef = .{ .file_index = o.file_base + local_source.file_index, .offset = local_source.offset };
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |item| item,
            else => return .deferred,
        };
        if (literal.fields.len != 1) return self.callbackError(source, "CFunctionPointer construction requires '.function = name'");
        const field = self.graph.value_fields.items[literal.fields.start];
        if (!std.mem.eql(u8, self.graph.text(field.name), "function")) return self.callbackError(source, "CFunctionPointer construction requires '.function = name'");
        var selector = field.value;
        var reference: ?module_entities.ExternalRef = null;
        // Selection consumes source-name metadata, not a runtime value. Follow
        // the implicit copy wrapper so ordinary bindings keep their own rules.
        for (0..8) |_| {
            const raw = @intFromEnum(selector);
            if (raw < o.node_base or raw - o.node_base >= module.semantic.nodes.items.len) break;
            const pending = switch (module.semantic.nodes.items[raw - o.node_base]) {
                .pending => |id| module.semantic.pending_operations.items[@intFromEnum(id)],
                else => break,
            };
            switch (pending) {
                .resolve_copy => |copy| selector = globalizer.globalNode(o, copy.value),
                .resolve_name_use => |name| {
                    reference = .{ .kind = .function, .name = name.name, .module_path = name.module_path, .source = name.source };
                    break;
                },
                else => break,
            }
        }
        const name_ref = reference orelse return self.callbackError(source, "callback '.function' must name a concrete CFunction body");
        const filter = if (name_ref.module_path) |path|
            try module_linker.resolveImportPath(self.core.allocator, self.graph, self.modules, module_index, module.text(path))
        else
            null;
        const signature = self.graph.function(declaration.function_id orelse return .deferred);
        var selected: ?global_sg.GlobalFunctionId = null;
        for (try self.graph.functionsNamed(self.core.allocator, module.text(name_ref.name))) |id| {
            const candidate = self.graph.function(id);
            if (!candidate.flags.is_c_abi or !candidate.flags.has_declared_body or candidate.flags.is_once or candidate.flags.is_c_function_pointer) continue;
            if (!self.core.declarationVisible(module_index, candidate.declaration, filter)) continue;
            if (c_abi.physicalInputCount(candidate) != c_abi.physicalInputCount(signature) or candidate.output.len != signature.output.len) continue;
            var matches = true;
            for (0..c_abi.physicalInputCount(signature)) |i| {
                const expected = self.graph.fields.items[signature.input.start + i].ty;
                const actual = self.graph.fields.items[candidate.input.start + i].ty;
                if (self.graph.isTypeUnresolved(expected) or self.graph.isTypeUnresolved(actual)) return .deferred;
                if (!types.equal(self.graph, expected, actual)) matches = false;
            }
            for (0..signature.output.len) |i| {
                const expected = self.graph.fields.items[signature.output.start + i].ty;
                const actual = self.graph.fields.items[candidate.output.start + i].ty;
                if (self.graph.isTypeUnresolved(expected) or self.graph.isTypeUnresolved(actual)) return .deferred;
                if (!types.equal(self.graph, expected, actual)) matches = false;
            }
            if (!matches) continue;
            if (selected != null) return self.callbackError(source, "callback function selection is ambiguous for this C signature");
            selected = id;
        }
        const function = selected orelse return self.callbackError(source, "no visible concrete CFunction body matches the callback signature");
        const node: global_sg.Node = .{ .source = source, .ty = ty, .content = .{ .function_address = function } };
        self.graph.nodes.items[@intFromEnum(selector)] = node;
        self.graph.nodes.items[@intFromEnum(target)] = node;
        return .resolved;
    }

    /// Argument shapes only infer input participants. Associated results never
    /// select a constructor, and matching scores do not rank conformances.
    const ContractArguments = struct { target: global_sg.GlobalTypeId, args: global_sg.GlobalTypeId };

    fn inferContractArguments(self: *Resolver, declaration: global_sg.GlobalDeclId, target: ?global_sg.GlobalTypeId, family: ?global_sg.GlobalDeclId, input: global_sg.GlobalNodeId, reach: reach_context.Context, source: primitives.SourceRef) anyerror!?ContractArguments {
        const participant: implementation_arguments.Participant = if (target) |known| .{ .known = known } else .{ .partial = .{ .family = family.?, .arguments = .{ .start = 0, .len = 0 } } };
        return self.inferConstructorArguments(declaration, participant, input, reach, source);
    }

    fn inferConstructorArguments(self: *Resolver, declaration: global_sg.GlobalDeclId, participant: implementation_arguments.Participant, input: global_sg.GlobalNodeId, reach: reach_context.Context, source: primitives.SourceRef) anyerror!?ContractArguments {
        if (participant == .partial) {
            const partial = participant.partial;
            const generics = self.generics.?;
            const located = generics.findTypeParameterized(partial.family) orelse return null;
            var supplied = try generic_mod.Resolver.Bindings.init(self.core.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
            defer supplied.deinit(self.core.allocator);
            generics.bindGlobalArgumentsPartial(located.module_index, located.parameterized.parameters, partial.arguments, &supplied) catch |err| {
                const reason = switch (err) {
                    error.TooManyGenericArguments => "too many compile-time arguments in constructor",
                    error.UnknownGenericArgument => "unknown compile-time parameter in constructor",
                    error.DuplicateGenericArgument => "duplicate compile-time argument in constructor",
                    error.GenericArgumentKindMismatch => "compile-time constructor argument has the wrong kind (type or integer)",
                    else => return err,
                };
                try self.reportConstructorError(source, reason);
                return error.InvalidInitializerArguments;
            };
        }
        var resolver: implementation_arguments.Resolver = .{
            .graph = self.graph,
            .modules = self.modules,
            .core = self.core,
            .generics = self.generics.?,
            .functions = self.generic_functions.?,
            .contracts = self.contracts.?,
        };
        switch (try resolver.infer(declaration, &.{participant}, input, reach)) {
            .selected => |selection| {
                defer self.core.allocator.free(selection.participants);
                return .{ .target = selection.participants[0], .args = selection.participants[1] };
            },
            .none => return null,
            .deferred => return error.DeferredContractInitializer,
            .ambiguous => try self.reportConstructorError(source, "ambiguous Init argument shapes; qualify the contract with an explicit Args type"),
            .missing_reach => |field| {
                const message = try std.fmt.allocPrint(self.core.allocator, "Init argument '.{s}' requires a reachable value or an explicit argument", .{self.graph.text(field.name)});
                defer self.core.allocator.free(message);
                try self.reportConstructorError(source, message);
            },
            .incompatible_arguments => try self.reportConstructorError(source, "construction arguments do not match the selected Init.Args"),
        }
        return error.InvalidInitializerArguments;
    }

    fn contractInitializer(self: *Resolver, module_index: usize, ty: global_sg.GlobalTypeId, input: global_sg.GlobalNodeId, reach: reach_context.Context, source: primitives.SourceRef) !?global_sg.Node {
        const checkpoint = self.graph.checkpoint();
        const generic_functions = self.generic_functions.?;
        const side_effects = generic_functions.checkpointSideEffects();
        const original_input = self.graph.node(input);
        var committed = false;
        defer if (!committed) {
            self.graph.nodes.items[@intFromEnum(input)] = original_input;
            self.graph.rollback(checkpoint);
            generic_functions.rollbackSideEffects(side_effects);
        };
        const declaration = standard_contracts.standardDeclaration(self.graph, "Init") orelse return null;
        const contracts = self.contracts orelse return null;
        const selected_arguments = try self.inferContractArguments(declaration, ty, null, input, reach, source) orelse return null;
        const arguments_type = selected_arguments.args;
        const generics = self.generics.?;
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        try self.graph.generic_arguments.append(self.core.allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = ty } });
        try self.graph.generic_arguments.append(self.core.allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = arguments_type } });
        const contract_type = try generics.internType(.{ .generic = .{ .base = declaration, .arguments = .{ .start = start, .len = 2 } } });
        _ = try generics.ensureGenericInstance(arguments_type);
        var arguments_resolver: implementation_arguments.Resolver = .{ .graph = self.graph, .modules = self.modules, .core = self.core, .generics = generics, .functions = generic_functions, .contracts = contracts };
        switch (try arguments_resolver.complete(arguments_type, input, reach)) {
            .completed => {},
            .deferred => return error.DeferredContractInitializer,
            .incompatible_arguments => {
                try self.reportConstructorError(source, "construction arguments do not match the selected Init.Args");
                return error.InvalidInitializerArguments;
            },
            .incompatible_default => {
                try self.reportConstructorError(source, "default value is incompatible with its selected Init.Args field type");
                return error.InvalidInitializerArguments;
            },
        }
        const value_start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.append(self.core.allocator, .{ .name = try self.graph.addString(self.core.allocator, "args"), .value = input });
        const wrapped: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.core.allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = value_start, .len = 1 } } } });
        const call = try contracts.makeScopedOperationCall(module_index, contract_type, "init", wrapped, reach, source) orelse return error.DeferredContractInitializer;
        const result_type = call.ty orelse return error.DeferredContractInitializer;
        if (self.graph.isTypeUnresolved(result_type)) return error.DeferredContractInitializer;
        if (!types.resultMatchesTarget(self.graph, result_type, ty)) {
            try self.reportConstructorError(source, "Init.Result must be its participant type or one Errable containing that type");
            return error.InvalidInitializerResult;
        }
        committed = true;
        return call;
    }

    fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        if (value.callee_value != null) return .not_applicable;
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.generic_arguments != null or reference.computed_arguments != null)
            return self.resolveExplicitGenericCall(module_index, module, o, value, reference);

        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return .not_applicable,
            else => return err,
        };
        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
        const input = globalizer.globalNode(o, value.input);
        const type_generics = self.generics.?;
        if (type_generics.isParameterizedTypeDeclaration(declaration_id))
            return self.resolveImplicitGenericCall(module_index, module, o, value, declaration_id, input);
        const ty = declaration.type_id orelse return .deferred;
        if (declaration.struct_layout == .c_function_pointer)
            return self.resolveCallbackConstructor(module_index, module, o, value, declaration, ty, input);

        if (self.contractInitializer(module_index, ty, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function), self.graph.node(input).source) catch |err| {
            if (err == error.DeferredContractInitializer) return .deferred;
            return err;
        }) |call| {
            var selected = call;
            selected.source = .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset };
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = selected;
            self.core.stats.calls += 1;
            return .resolved;
        }

        return self.writeStructuralConstruction(module_index, o, value, reference, ty, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function));
    }

    fn resolveImplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
        declaration_id: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
    ) !resolution.Result {
        // Candidate inference interns temporary types and generic identities.
        // Keep the whole attempt transactional: if some dependency is still
        // unresolved, a later fixed-point round must start from the same graph.
        const generics = self.generics.?;
        const generic_functions = self.generic_functions.?;
        const checkpoint = self.graph.checkpoint();
        const side_effect_checkpoint = generic_functions.checkpointSideEffects();
        var committed = false;
        defer if (!committed) {
            self.graph.rollback(checkpoint);
            generic_functions.rollbackSideEffects(side_effect_checkpoint);
        };

        // Context can fully determine a generic constructor even when none of
        // the runtime arguments mention its type parameter (for example an
        // owning container whose element type appears only in `$&Container#`).
        if (value.expected_type) |local_expected| {
            const expected = globalizer.globalType(o, local_expected);
            if (!self.graph.isTypeUnresolved(expected)) switch (self.graph.types.items[@intFromEnum(expected)]) {
                .generic => |identity| if (identity.base == declaration_id) {
                    _ = generics.ensureGenericInstance(expected) catch return .deferred;
                    if (self.contractInitializer(module_index, expected, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function), self.graph.node(input).source) catch |err| {
                        if (err == error.DeferredContractInitializer) return .deferred;
                        return err;
                    }) |call| {
                        self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = call;
                        self.core.stats.calls += 1;
                        committed = true;
                        return .resolved;
                    }
                },
                else => {},
            };
        }

        if (standard_contracts.standardDeclaration(self.graph, "Init")) |identity| {
            const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);
            if (self.inferContractArguments(identity, null, declaration_id, input, reach, self.graph.node(input).source) catch |err| {
                if (err == error.DeferredContractInitializer) return .deferred;
                return err;
            }) |selection| {
                _ = try generics.ensureGenericInstance(selection.target);
                const call = self.contractInitializer(module_index, selection.target, input, reach, self.graph.node(input).source) catch |err| {
                    if (err == error.DeferredContractInitializer) return .deferred;
                    return err;
                };
                if (call) |node| {
                    self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
                    self.core.stats.calls += 1;
                    committed = true;
                    return .resolved;
                }
            }
        }

        return .deferred;
    }

    fn resolveExplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
        reference: module_entities.ExternalRef,
    ) !resolution.Result {
        // Generic construction can be retried by the global fixed point while
        // dependencies in the initializer body are still unresolved. Keep the
        // attempt transactional so failed retries do not accumulate generic
        // identities, instantiated fields, functions or value-field tails.
        const generic_functions = self.generic_functions.?;
        const checkpoint = self.graph.checkpoint();
        const side_effect_checkpoint = generic_functions.checkpointSideEffects();
        var committed = false;
        var failed = false;
        defer if (!committed) {
            const comptime_failure = self.generics.?.comptime_failure;
            const projection_failure = if (self.contracts) |contracts| contracts.participant_conformance_failure else null;
            self.graph.rollback(checkpoint);
            generic_functions.rollbackSideEffects(side_effect_checkpoint);
            if (failed) {
                self.generics.?.comptime_failure = comptime_failure;
                if (self.contracts) |contracts| contracts.participant_conformance_failure = projection_failure;
            }
        };
        errdefer failed = true;

        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return .not_applicable,
            else => return err,
        };
        const generics = self.generics.?;
        const arguments = (try generics.resolveCallArguments(module_index, reference)).?;
        if (generics.findTypeParameterized(declaration_id)) |located| {
            if (arguments.len < located.parameterized.parameters.len) {
                if (standard_contracts.standardDeclaration(self.graph, "Init")) |identity| {
                    const input = globalizer.globalNode(o, value.input);
                    const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);
                    const selection = self.inferConstructorArguments(identity, .{ .partial = .{ .family = declaration_id, .arguments = arguments } }, input, reach, self.graph.node(input).source) catch |err| {
                        if (err == error.DeferredContractInitializer) return .deferred;
                        return err;
                    };
                    if (selection) |selected| {
                        if (try self.contractInitializer(module_index, selected.target, input, reach, self.graph.node(input).source)) |call| {
                            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = call;
                            committed = true;
                            self.core.stats.calls += 1;
                            return .resolved;
                        }
                    }
                }
            }
        }
        const ty = try generics.internType(.{ .generic = .{
            .base = declaration_id,
            .arguments = arguments,
        } });
        _ = generics.ensureGenericInstance(ty) catch |err| switch (err) {
            error.InvalidAssociatedTypeProjection, error.InvalidArrayLength, error.ComptimeIntegerOverflow, error.ComptimeDivisionByZero => return err,
            else => return .deferred,
        };

        const input = globalizer.globalNode(o, value.input);
        if (self.contractInitializer(module_index, ty, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function), self.graph.node(input).source) catch |err| {
            if (err == error.DeferredContractInitializer) return .deferred;
            return err;
        }) |call| {
            var selected = call;
            selected.source = .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset };
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = selected;
            self.core.stats.calls += 1;
            committed = true;
            return .resolved;
        }

        const result = try self.writeStructuralConstruction(module_index, o, value, reference, ty, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function));
        committed = result == .resolved;
        return result;
    }

    fn reportConstructorError(self: *Resolver, source: primitives.SourceRef, message: []const u8) !void {
        if (self.diagnostics) |diagnostics| {
            var file_id: u32 = 0;
            if (source.file_index < self.graph.files.items.len) {
                const file = self.graph.files.items[source.file_index];
                const name = self.graph.text(file.path);
                const dir = self.graph.text(self.graph.modules.items[@intFromEnum(file.module)].dir);
                for (diagnostics.source_files, 0..) |candidate, index| {
                    if (std.mem.eql(u8, std.fs.path.basename(candidate.path), name) and
                        std.mem.eql(u8, std.fs.path.dirname(candidate.path) orelse ".", dir))
                    {
                        file_id = @intCast(index);
                        break;
                    }
                }
            }
            try diagnostics.add(.{ .file = @enumFromInt(file_id), .offset = source.offset }, .semantic, "{s}", .{message});
            return error.Reported;
        }
    }

    fn writeStructuralConstruction(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
        value: anytype,
        reference: module_entities.ExternalRef,
        ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        reach: reach_context.Context,
    ) !resolution.Result {
        const fields = types.fields(self.graph, ty) orelse return .deferred;
        self.core.contextualizeConstructorChoices(module_index, o, fields, input);
        switch (self.core.matchCallInput(fields, input)) {
            .applicable => {},
            .no_match, .deferred => return .deferred,
        }
        if (!try self.core.completeCallInputFieldsWithReach(fields, input, reach)) return .deferred;

        self.graph.nodes.items[@intFromEnum(input)].ty = ty;
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = self.graph.nodes.items[@intFromEnum(input)];
        self.graph.nodes.items[@intFromEnum(target)].source = .{
            .file_index = o.file_base + reference.source.file_index,
            .offset = reference.source.offset,
        };
        self.core.stats.calls += 1;
        return .resolved;
    }
};

test "declared type call materializes a struct value without visible init" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.init(allocator);
    defer fixture.deinit();

    try std.testing.expect((try fixture.resolve()).isResolved());
    const result = fixture.graph.nodes.items[1];
    try std.testing.expectEqual(fixture.declared_type, result.ty.?);
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    graph: global_sg.GlobalSemanticGraph,
    module: module_sg.ModuleSemanticGraph,
    offsets: [1]globalizer.Offsets,
    declared_type: global_sg.GlobalTypeId,

    fn init(allocator: std.mem.Allocator) !Fixture {
        var graph: global_sg.GlobalSemanticGraph = .{};
        errdefer graph.deinit(allocator);
        var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "app") };
        errdefer module.deinit(allocator);

        try module.strings.appendSlice(allocator, "Packet");
        try module.semantic.external_refs.append(allocator, .{
            .kind = .function,
            .module_path = null,
            .name = .{ .start = 0, .len = 6 },
            .source = .{ .file_index = 0, .offset = 17 },
        });

        const declaration_name = try graph.addString(allocator, "Packet");
        const module_dir = try graph.addString(allocator, "app");
        const declared_type: global_sg.GlobalTypeId = @enumFromInt(0);
        const input_type: global_sg.GlobalTypeId = @enumFromInt(1);
        try graph.declarations.append(allocator, .{
            .kind = .type,
            .name = declaration_name,
            .source = .{ .file_index = 0, .offset = 0 },
            .type_id = declared_type,
            .struct_fields = .{ .start = 0, .len = 0 },
        });
        try graph.types.append(allocator, .{ .declared = @as(global_sg.GlobalDeclId, @enumFromInt(0)) });
        try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } });

        try graph.modules.append(allocator, .{
            .dir = module_dir,
            .files = .{ .start = 0, .len = 0 },
            .declarations = .{ .start = 0, .len = 1 },
        });
        try graph.nodes.append(allocator, .{
            .source = .{ .file_index = 0, .offset = 18 },
            .ty = input_type,
            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = 0, .len = 0 },
            } },
        });
        try graph.nodes.append(allocator, .{
            .source = .{ .file_index = 0, .offset = 19 },
            .ty = input_type,
            .content = .{ .bool_literal = false },
        });

        return .{
            .allocator = allocator,
            .graph = graph,
            .module = module,
            .offsets = .{emptyOffsets()},
            .declared_type = declared_type,
        };
    }

    fn deinit(self: *Fixture) void {
        self.graph.deinit(self.allocator);
        self.module.deinit(self.allocator);
    }

    fn resolve(self: *Fixture) !resolution.Result {
        var core = core_mod.Resolver{
            .allocator = self.allocator,
            .graph = &self.graph,
            .modules = self.modules(),
            .offsets = &self.offsets,
        };
        var generics = generic_mod.Resolver{
            .allocator = self.allocator,
            .graph = &self.graph,
            .modules = self.modules(),
            .offsets = &self.offsets,
            .core = &core,
        };
        defer generics.deinit();
        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.allocator,
            .graph = &self.graph,
            .modules = self.modules(),
            .offsets = &self.offsets,
            .core = &core,
            .generics = &generics,
        };
        var resolver: Resolver = .{
            .graph = &self.graph,
            .modules = self.modules(),
            .offsets = &self.offsets,
            .core = &core,
            .generics = &generics,
            .generic_functions = &generic_functions,
        };
        const operation = module_entities.PendingOperation{ .resolve_call = .{
            .node = @enumFromInt(1),
            .callee = @enumFromInt(0),
            .input = @enumFromInt(0),
        } };
        return resolver.tryResolve(0, &self.module, self.offsets[0], operation);
    }

    fn modules(self: *Fixture) []const module_sg.ModuleSemanticGraph {
        return @as([*]const module_sg.ModuleSemanticGraph, @ptrCast(&self.module))[0..1];
    }
};

fn emptyOffsets() globalizer.Offsets {
    return .{
        .file_base = 0,
        .declaration_base = 0,
        .type_base = 0,
        .function_base = 0,
        .field_base = 0,
        .variant_base = 0,
        .generic_argument_base = 0,
        .binding_base = 0,
        .node_base = 0,
        .block_base = 0,
        .value_field_base = 0,
        .switch_case_base = 0,
        .switch_base = 0,
        .auto_deinit_field_base = 0,
        .auto_deinit_base = 0,
        .virtual_registry_base = 0,
        .virtualize_base = 0,
        .virtual_call_base = 0,
        .reach_segment_base = 0,
        .reach_alternative_base = 0,
        .reach_base = 0,
        .nullable_unwrap_base = 0,
        .testing_expect_error_base = 0,
        .error_propagation_base = 0,
        .error_context_base = 0,
        .node_ref_base = 0,
        .type_ref_base = 0,
        .binding_ref_base = 0,
        .function_ref_base = 0,
        .virtual_registry_ref_base = 0,
        .symbol_declaration_base = 0,
        .string_base = 0,
    };
}

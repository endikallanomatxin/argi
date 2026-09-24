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
const abstract_mod = @import("abstracts.zig");
const call_compatibility = @import("call_compatibility.zig");

/// Resolves call syntax whose callee is a declared type. A visible `init`
/// whose first input is `$&ConstructedType` owns construction; only types with
/// no such initializer may fall back to direct structural initialization.
pub const Resolver = struct {
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    abstracts: ?*abstract_mod.Resolver = null,

    const InitializerLookup = struct {
        function: ?global_sg.GlobalFunctionId = null,
        has_visible_initializer: bool = false,
    };

    const InitializerProbe = struct {
        owns_type: bool = false,
        score: ?u32 = null,
    };

    const InferredInitializerLookup = struct {
        function: ?global_sg.GlobalFunctionId = null,
        constructed_type: ?global_sg.GlobalTypeId = null,
        has_visible_initializer: bool = false,
    };

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
        var generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        defer generics.deinit();

        const parameterized = generics.isParameterizedTypeDeclaration(declaration_id);
        const ty = if (parameterized) blk: {
            if (arguments.len == 0) return null;
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

        if (parameterized) {
            var generic_functions = generic_functions_mod.Resolver{
                .allocator = self.core.allocator,
                .graph = self.graph,
                .modules = self.modules,
                .offsets = self.offsets,
                .core = self.core,
                .generics = &generics,
                .nested_call_context = self.abstracts,
                .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,
                .nested_constructor_context = self,
                .nested_constructor_resolver = Resolver.resolveNestedCall,
            };
            const initializer = try self.findGenericInitializer(
                &generics,
                &generic_functions,
                module_index,
                ty,
                input,
                reach,
            );
            if (initializer.function) |function_id| {
                const function = self.graph.functions.items[@intFromEnum(function_id)];
                const user_fields = global_sg.FieldRange{
                    .start = function.input.start + 1,
                    .len = function.input.len - 1,
                };
                if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, reach)) return null;
                self.core.stats.calls += 1;
                return .{
                    .source = source,
                    .ty = ty,
                    .content = .{ .type_initializer = .{
                        .type_decl = declaration_id,
                        .init_fn = function_id,
                        .args = input,
                    } },
                };
            }
            if (initializer.has_visible_initializer) return null;
        } else {
            const initializer = self.findInitializer(module_index, ty, input, reach);
            if (initializer.function) |function_id| {
                var selected = function_id;
                if (self.graph.functions.items[@intFromEnum(selected)].flags.is_abstract_dispatch) {
                    var generic_functions = generic_functions_mod.Resolver{
                        .allocator = self.core.allocator,
                        .graph = self.graph,
                        .modules = self.modules,
                        .offsets = self.offsets,
                        .core = self.core,
                        .generics = &generics,
                        .nested_call_context = self.abstracts,
                        .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,
                        .nested_constructor_context = self,
                        .nested_constructor_resolver = Resolver.resolveNestedCall,
                    };
                    selected = (try generic_functions.instantiateInitializer(
                        self.graph.functions.items[@intFromEnum(selected)].declaration,
                        ty,
                        input,
                        reach,
                    )) orelse return null;
                }
                const function = self.graph.functions.items[@intFromEnum(selected)];
                const user_fields = global_sg.FieldRange{
                    .start = function.input.start + 1,
                    .len = function.input.len - 1,
                };
                if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, reach)) return null;
                self.core.stats.calls += 1;
                return .{
                    .source = source,
                    .ty = ty,
                    .content = .{ .type_initializer = .{
                        .type_decl = declaration_id,
                        .init_fn = selected,
                        .args = input,
                    } },
                };
            }
            if (initializer.has_visible_initializer) return null;
        }

        const fields = types.fields(self.graph, ty) orelse return null;
        switch (self.core.matchCallInput(fields, input)) {
            .score => {},
            .no_match, .deferred => return null,
        }
        if (!try self.core.completeCallInputFields(fields, input)) return null;
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

    fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.generic_arguments) |arguments|
            return self.resolveExplicitGenericCall(module_index, module, o, value, reference, arguments);

        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return .not_applicable,
            else => return err,
        };
        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
        const input = globalizer.globalNode(o, value.input);
        var type_generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        defer type_generics.deinit();
        if (type_generics.isParameterizedTypeDeclaration(declaration_id))
            return self.resolveImplicitGenericCall(module_index, module, o, value, reference, declaration_id, input);
        const ty = declaration.type_id orelse return .deferred;

        const initializer = self.findInitializer(
            module_index,
            ty,
            input,
            reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
        );
        if (initializer.function) |function_id| {
            var selected = function_id;
            if (self.graph.functions.items[@intFromEnum(selected)].flags.is_abstract_dispatch) {
                var generics = generic_mod.Resolver{
                    .allocator = self.core.allocator,
                    .graph = self.graph,
                    .modules = self.modules,
                    .offsets = self.offsets,
                    .core = self.core,
                };
                defer generics.deinit();
                var generic_functions = generic_functions_mod.Resolver{
                    .allocator = self.core.allocator,
                    .graph = self.graph,
                    .modules = self.modules,
                    .offsets = self.offsets,
                    .core = self.core,
                    .generics = &generics,
                    .nested_call_context = self.abstracts,
                    .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,
                    .nested_constructor_context = self,
                    .nested_constructor_resolver = Resolver.resolveNestedCall,
                };
                selected = (try generic_functions.instantiateInitializer(
                    self.graph.functions.items[@intFromEnum(selected)].declaration,
                    ty,
                    input,
                    reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
                )) orelse return .deferred;
            }
            const function = self.graph.functions.items[@intFromEnum(selected)];
            const user_fields = global_sg.FieldRange{
                .start = function.input.start + 1,
                .len = function.input.len - 1,
            };
            if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function))) return .deferred;
            self.writeInitializer(o, value, reference, declaration_id, ty, selected, input);
            return .resolved;
        }

        // A visible initializer blocks field-wise construction even when the
        // provided arguments do not match it. That preserves the language's
        // encapsulation rule: private/invariant-bearing structs cannot bypass
        // their `init` merely because overload resolution failed.
        if (initializer.has_visible_initializer) return .deferred;

        return self.writeStructuralConstruction(o, value, reference, ty, input);
    }

    fn resolveImplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
        reference: module_entities.ExternalRef,
        declaration_id: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
    ) !resolution.Result {
        // Candidate inference interns temporary types and generic identities.
        // Keep the whole attempt transactional: if some dependency is still
        // unresolved, a later fixed-point round must start from the same graph.
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        const saved_function_count = self.graph.functions.items.len;
        const saved_declaration_count = self.graph.declarations.items.len;
        inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
            .@"struct" => @hasField(pool.type, "items"),
            else => false,
        }) {
            lengths[index] = @field(self.graph, pool.name).items.len;
        };
        var committed = false;
        defer if (!committed) {
            self.graph.discardIndexedTail(saved_function_count, saved_declaration_count);
            inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
                .@"struct" => @hasField(pool.type, "items"),
                else => false,
            }) {
                @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            };
        };

        var generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        defer generics.deinit();
        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
            .generics = &generics,
            .nested_call_context = self.abstracts,
            .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,
            .nested_constructor_context = self,
            .nested_constructor_resolver = Resolver.resolveNestedCall,
        };

        // Context can fully determine a generic constructor even when none of
        // the runtime arguments mention its type parameter (for example an
        // owning container whose element type appears only in `$&Container#`).
        if (value.expected_type) |local_expected| {
            const expected = globalizer.globalType(o, local_expected);
            if (!self.graph.isTypeUnresolved(expected)) switch (self.graph.types.items[@intFromEnum(expected)]) {
                .generic => |identity| if (identity.base == declaration_id) {
                    _ = generics.ensureGenericInstance(expected) catch return .deferred;
                    const initializer = try self.findGenericInitializer(
                        &generics,
                        &generic_functions,
                        module_index,
                        expected,
                        input,
                        reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
                    );
                    if (initializer.function) |function_id| {
                        const function = self.graph.functions.items[@intFromEnum(function_id)];
                        const user_fields = global_sg.FieldRange{
                            .start = function.input.start + 1,
                            .len = function.input.len - 1,
                        };
                        if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function))) return .deferred;
                        self.writeInitializer(o, value, reference, declaration_id, expected, function_id, input);
                        committed = true;
                        return .resolved;
                    }
                    if (initializer.has_visible_initializer) return .deferred;
                },
                else => {},
            };
        }

        const initializer = try self.findImplicitGenericInitializer(
            &generics,
            &generic_functions,
            module_index,
            declaration_id,
            input,
            reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
        );
        if (initializer.function) |function_id| {
            const ty = initializer.constructed_type.?;
            const function = self.graph.functions.items[@intFromEnum(function_id)];
            const user_fields = global_sg.FieldRange{
                .start = function.input.start + 1,
                .len = function.input.len - 1,
            };
            if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function))) return .deferred;
            self.writeInitializer(o, value, reference, declaration_id, ty, function_id, input);
            committed = true;
            return .resolved;
        }

        // Generic type construction without an initializer needs inference
        // from the parameterized type body itself. Do not guess that mapping
        // here; a visible initializer also owns construction even when the
        // supplied arguments are not yet sufficient to select an overload.
        if (initializer.has_visible_initializer) return .deferred;
        return .deferred;
    }

    fn resolveExplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
        reference: module_entities.ExternalRef,
        local_arguments: module_entities.GenericArgRange,
    ) !resolution.Result {
        // Generic construction can be retried by the global fixed point while
        // dependencies in the initializer body are still unresolved. Keep the
        // attempt transactional so failed retries do not accumulate generic
        // identities, instantiated fields, functions or value-field tails.
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        const saved_function_count = self.graph.functions.items.len;
        const saved_declaration_count = self.graph.declarations.items.len;
        inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
            .@"struct" => @hasField(pool.type, "items"),
            else => false,
        }) {
            lengths[index] = @field(self.graph, pool.name).items.len;
        };
        var committed = false;
        defer if (!committed) {
            self.graph.discardIndexedTail(saved_function_count, saved_declaration_count);
            inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
                .@"struct" => @hasField(pool.type, "items"),
                else => false,
            }) {
                @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            };
        };

        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return .not_applicable,
            else => return err,
        };
        var generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        defer generics.deinit();
        const arguments = try generics.relocateModuleArguments(module_index, local_arguments);
        const ty = try generics.internType(.{ .generic = .{
            .base = declaration_id,
            .arguments = arguments,
        } });
        _ = generics.ensureGenericInstance(ty) catch return .deferred;

        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
            .generics = &generics,
            .nested_call_context = self.abstracts,
            .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,
            .nested_constructor_context = self,
            .nested_constructor_resolver = Resolver.resolveNestedCall,
        };
        const input = globalizer.globalNode(o, value.input);
        const initializer = try self.findGenericInitializer(
            &generics,
            &generic_functions,
            module_index,
            ty,
            input,
            reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
        );
        if (initializer.function) |function_id| {
            const function = self.graph.functions.items[@intFromEnum(function_id)];
            const user_fields = global_sg.FieldRange{
                .start = function.input.start + 1,
                .len = function.input.len - 1,
            };
            if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function))) return .deferred;
            self.writeInitializer(o, value, reference, declaration_id, ty, function_id, input);
            committed = true;
            return .resolved;
        }
        if (initializer.has_visible_initializer) return .deferred;

        const result = try self.writeStructuralConstruction(o, value, reference, ty, input);
        committed = result == .resolved;
        return result;
    }

    fn writeInitializer(
        self: *Resolver,
        o: globalizer.Offsets,
        value: anytype,
        reference: module_entities.ExternalRef,
        declaration_id: global_sg.GlobalDeclId,
        ty: global_sg.GlobalTypeId,
        function_id: global_sg.GlobalFunctionId,
        input: global_sg.GlobalNodeId,
    ) void {
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = .{
                .file_index = o.file_base + reference.source.file_index,
                .offset = reference.source.offset,
            },
            .ty = ty,
            .content = .{ .type_initializer = .{
                .type_decl = declaration_id,
                .init_fn = function_id,
                .args = input,
            } },
        };
        self.core.stats.calls += 1;
    }

    fn writeStructuralConstruction(
        self: *Resolver,
        o: globalizer.Offsets,
        value: anytype,
        reference: module_entities.ExternalRef,
        ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
    ) !resolution.Result {
        const fields = types.fields(self.graph, ty) orelse return .deferred;
        switch (self.core.matchCallInput(fields, input)) {
            .score => {},
            .no_match, .deferred => return .deferred,
        }
        if (!try self.core.completeCallInputFields(fields, input)) return .deferred;

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

    fn findInitializer(
        self: *Resolver,
        module_index: usize,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: ?reach_context.Context,
    ) InitializerLookup {
        var result: InitializerLookup = .{};
        var best_score: u32 = 0;
        var tied = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.input.len == 0) continue;
            const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(declaration.name), "init")) continue;
            if (!self.core.declarationVisible(module_index, function.declaration, null)) continue;

            const destination = self.graph.fields.items[function.input.start];
            const pointer = switch (self.graph.types.items[@intFromEnum(destination.ty)]) {
                .pointer => |pointer_value| pointer_value,
                else => continue,
            };
            if (!types.equal(self.graph, pointer.child, constructed_ty)) continue;
            result.has_visible_initializer = true;

            const user_fields = global_sg.FieldRange{
                .start = function.input.start + 1,
                .len = function.input.len - 1,
            };
            const score_match = if (!function.flags.is_abstract_dispatch and context != null)
                self.core.matchCallInputWithReach(user_fields, input, context.?) catch .deferred
            else if (self.abstracts) |abstracts|
                call_compatibility.matchInput(.{ .core = self.core, .abstracts = abstracts }, user_fields, input)
            else
                self.core.matchCallInput(user_fields, input);
            var score = switch (score_match) {
                .score => |value| value,
                .no_match, .deferred => continue,
            };
            const owner = self.graph.moduleForDeclaration(function.declaration) orelse continue;
            if (@intFromEnum(owner) == module_index) score += 1;
            if (result.function == null or score > best_score) {
                result.function = @enumFromInt(@as(u32, @intCast(raw)));
                best_score = score;
                tied = false;
            } else if (score == best_score) {
                const selected = self.graph.functions.items[@intFromEnum(result.function.?)];
                if (selected.declaration == function.declaration and
                    selected.flags.is_abstract_dispatch != function.flags.is_abstract_dispatch)
                {
                    if (selected.flags.is_abstract_dispatch and !function.flags.is_abstract_dispatch)
                        result.function = @enumFromInt(@as(u32, @intCast(raw)));
                    tied = false;
                } else {
                    tied = true;
                }
            }
        }
        if (tied) result.function = null;
        return result;
    }

    fn findImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        module_index: usize,
        constructed_declaration: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !InferredInitializerLookup {
        var result: InferredInitializerLookup = .{};
        var best_declaration: ?global_sg.GlobalDeclId = null;
        var best_score: u32 = 0;
        var tied = false;

        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
                if (!std.mem.eql(u8, self.graph.text(declaration.name), "init")) continue;
                if (!self.core.declarationVisible(module_index, declaration_id, null)) continue;
                if (!self.parameterizedInitializerOwnsType(generics, candidate_index, parameterized, constructed_declaration)) continue;
                result.has_visible_initializer = true;

                const probe = try self.probeImplicitGenericInitializer(
                    generics,
                    generic_functions,
                    candidate_module,
                    candidate_index,
                    parameterized,
                    input,
                    context,
                );
                var score = probe.score orelse continue;
                const owner = self.graph.moduleForDeclaration(declaration_id) orelse continue;
                if (@intFromEnum(owner) == module_index) score += 1;
                if (best_declaration == null or score > best_score) {
                    best_declaration = declaration_id;
                    best_score = score;
                    tied = false;
                } else if (score == best_score and declaration_id != best_declaration.?) {
                    tied = true;
                }
            }
        }

        if (tied or best_declaration == null) return result;
        const materialized = try self.materializeImplicitGenericInitializer(
            generics,
            generic_functions,
            best_declaration.?,
            constructed_declaration,
            input,
            context,
        ) orelse return result;
        result.function = materialized.function;
        result.constructed_type = materialized.constructed_type;
        return result;
    }

    fn parameterizedInitializerOwnsType(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        candidate_index: usize,
        parameterized: anytype,
        constructed_declaration: global_sg.GlobalDeclId,
    ) bool {
        const storage = &self.modules[candidate_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(parameterized.input)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;
        const destination = storage.fields.items[shape.fields.start];
        const pointer = switch (storage.types.items[@intFromEnum(destination.ty)]) {
            .resolved => |ty| switch (ty) {
                .pointer => |value| value,
                else => return false,
            },
            else => return false,
        };
        const generic = switch (storage.types.items[@intFromEnum(pointer.child)]) {
            .resolved => |ty| switch (ty) {
                .generic => |value| value,
                else => return false,
            },
            else => return false,
        };
        const base = generics.resolveParameterizedDeclaration(candidate_index, generic.base) catch return false;
        return base == constructed_declaration;
    }

    fn probeImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_module: *const module_sg.ModuleSemanticGraph,
        candidate_index: usize,
        parameterized: anytype,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !InitializerProbe {
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        const saved_function_count = self.graph.functions.items.len;
        const saved_declaration_count = self.graph.declarations.items.len;
        inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
            .@"struct" => @hasField(pool.type, "items"),
            else => false,
        }) {
            lengths[index] = @field(self.graph, pool.name).items.len;
        };
        const saved_stats = generics.stats;
        defer {
            self.graph.discardIndexedTail(saved_function_count, saved_declaration_count);
            inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
                .@"struct" => @hasField(pool.type, "items"),
                else => false,
            }) {
                @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            };
            generics.stats = saved_stats;
        }

        var bindings = try generic_mod.Resolver.Bindings.init(
            self.core.allocator,
            candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
        );
        defer bindings.deinit(self.core.allocator);
        if (!try generic_functions.inferInitializerInputBindings(
            candidate_index,
            parameterized.input,
            input,
            context,
            &bindings,
        )) return .{ .owns_type = true };
        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch
            return .{ .owns_type = true };
        const fields = types.fields(self.graph, input_ty) orelse return .{ .owns_type = true };
        if (fields.len == 0) return .{ .owns_type = true };
        return .{
            .owns_type = true,
            .score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{
                .start = fields.start + 1,
                .len = fields.len - 1,
            }, input),
        };
    }

    fn materializeImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        declaration: global_sg.GlobalDeclId,
        constructed_declaration: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !?InferredInitializerLookup {
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (declaration_id != declaration) continue;
                if (!self.parameterizedInitializerOwnsType(generics, candidate_index, parameterized, constructed_declaration)) return null;

                var bindings = try generic_mod.Resolver.Bindings.init(
                    self.core.allocator,
                    candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
                );
                defer bindings.deinit(self.core.allocator);
                if (!try generic_functions.inferInitializerInputBindings(
                    candidate_index,
                    parameterized.input,
                    input,
                    context,
                    &bindings,
                )) return null;
                const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch return null;
                const fields = types.fields(self.graph, input_ty) orelse return null;
                if (fields.len == 0) return null;
                const destination = self.graph.fields.items[fields.start];
                const pointer = switch (self.graph.types.items[@intFromEnum(destination.ty)]) {
                    .pointer => |value| value,
                    else => return null,
                };
                const identity = switch (self.graph.types.items[@intFromEnum(pointer.child)]) {
                    .generic => |value| value,
                    else => return null,
                };
                if (identity.base != constructed_declaration) return null;
                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch return null;
                const function = generic_functions.instantiate(declaration, arguments) catch return null;
                return .{
                    .function = function,
                    .constructed_type = pointer.child,
                    .has_visible_initializer = true,
                };
            }
        }
        return null;
    }

    fn findGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        module_index: usize,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !InitializerLookup {
        var result: InitializerLookup = .{};
        var best_declaration: ?global_sg.GlobalDeclId = null;
        var best_score: u32 = 0;
        var tied = false;

        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
                if (!std.mem.eql(u8, self.graph.text(declaration.name), "init")) continue;
                if (!self.core.declarationVisible(module_index, declaration_id, null)) continue;

                const probe = try self.probeGenericInitializer(
                    generics,
                    generic_functions,
                    candidate_module,
                    candidate_index,
                    parameterized,
                    constructed_ty,
                    input,
                    context,
                );
                if (!probe.owns_type) continue;
                result.has_visible_initializer = true;
                var score = probe.score orelse continue;
                const owner = self.graph.moduleForDeclaration(declaration_id) orelse continue;
                if (@intFromEnum(owner) == module_index) score += 1;
                if (best_declaration == null or score > best_score) {
                    best_declaration = declaration_id;
                    best_score = score;
                    tied = false;
                } else if (score == best_score and declaration_id != best_declaration.?) {
                    tied = true;
                }
            }
        }

        if (tied or best_declaration == null) return result;
        result.function = try self.materializeGenericInitializer(
            generic_functions,
            best_declaration.?,
            constructed_ty,
            input,
            context,
        );
        return result;
    }

    fn probeGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_module: *const module_sg.ModuleSemanticGraph,
        candidate_index: usize,
        parameterized: anytype,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !InitializerProbe {
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        const saved_function_count = self.graph.functions.items.len;
        const saved_declaration_count = self.graph.declarations.items.len;
        inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
            .@"struct" => @hasField(pool.type, "items"),
            else => false,
        }) {
            lengths[index] = @field(self.graph, pool.name).items.len;
        };
        const saved_stats = generics.stats;
        defer {
            self.graph.discardIndexedTail(saved_function_count, saved_declaration_count);
            inline for (pools, 0..) |pool, index| if (comptime switch (@typeInfo(pool.type)) {
                .@"struct" => @hasField(pool.type, "items"),
                else => false,
            }) {
                @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            };
            generics.stats = saved_stats;
        }

        var bindings = try generic_mod.Resolver.Bindings.init(
            self.core.allocator,
            candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
        );
        defer bindings.deinit(self.core.allocator);
        if (!try self.populateInitializerBindings(
            generic_functions,
            candidate_index,
            parameterized,
            constructed_ty,
            input,
            context,
            &bindings,
        )) return .{};
        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch return .{};
        const fields = types.fields(self.graph, input_ty) orelse return .{};
        if (fields.len == 0) return .{};
        return .{
            .owns_type = true,
            .score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{
                .start = fields.start + 1,
                .len = fields.len - 1,
            }, input),
        };
    }

    fn materializeGenericInitializer(
        self: *Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        declaration: global_sg.GlobalDeclId,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !?global_sg.GlobalFunctionId {
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (declaration_id != declaration) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(
                    self.core.allocator,
                    candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
                );
                defer bindings.deinit(self.core.allocator);
                if (!try self.populateInitializerBindings(
                    generic_functions,
                    candidate_index,
                    parameterized,
                    constructed_ty,
                    input,
                    context,
                    &bindings,
                )) return null;
                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch return null;
                return generic_functions.instantiate(declaration, arguments) catch return null;
            }
        }
        return null;
    }

    fn populateInitializerBindings(
        self: *Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_index: usize,
        parameterized: anytype,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        _ = self;
        return generic_functions.inferInitializerBindings(
            candidate_index,
            parameterized.input,
            constructed_ty,
            input,
            context,
            bindings,
        );
    }

    fn scoreInitializerInput(
        self: *Resolver,
        candidate_index: usize,
        pattern: @import("../module/parameterized/ir.zig").ParameterizedTypeId,
        user_fields: global_sg.FieldRange,
        input: global_sg.GlobalNodeId,
    ) !?u32 {
        const storage = &self.modules[candidate_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return null,
            },
            else => return null,
        };
        if (shape.fields.len == 0 or user_fields.len != shape.fields.len - 1) return null;
        const copied = try self.core.allocator.dupe(global_sg.Field, self.graph.fields.items[user_fields.start..][0..user_fields.len]);
        defer self.core.allocator.free(copied);
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.core.allocator, copied);
        for (storage.fields.items[shape.fields.start + 1 ..][0 .. shape.fields.len - 1], 0..) |field, offset| {
            if (field.default_value != null)
                self.graph.fields.items[start + @as(u32, @intCast(offset))].default_value = @enumFromInt(0);
        }
        return self.core.scoreCallInput(.{ .start = start, .len = user_fields.len }, input);
    }
};

test "declared type call materializes a struct value without visible init" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.init(allocator, false);
    defer fixture.deinit();

    try std.testing.expect((try fixture.resolve()).isResolved());
    const result = fixture.graph.nodes.items[1];
    try std.testing.expectEqual(fixture.declared_type, result.ty.?);
}

test "declared type call dispatches through visible init" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.init(allocator, true);
    defer fixture.deinit();

    try std.testing.expect((try fixture.resolve()).isResolved());
    const result = fixture.graph.nodes.items[1];
    try std.testing.expectEqual(fixture.declared_type, result.ty.?);
    try std.testing.expectEqual(@as(global_sg.GlobalDeclId, @enumFromInt(0)), result.content.type_initializer.type_decl);
    try std.testing.expectEqual(@as(global_sg.GlobalFunctionId, @enumFromInt(0)), result.content.type_initializer.init_fn);
    try std.testing.expectEqual(@as(global_sg.GlobalNodeId, @enumFromInt(0)), result.content.type_initializer.args);
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    graph: global_sg.GlobalSemanticGraph,
    module: module_sg.ModuleSemanticGraph,
    offsets: [1]globalizer.Offsets,
    declared_type: global_sg.GlobalTypeId,

    fn init(allocator: std.mem.Allocator, with_initializer: bool) !Fixture {
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

        if (with_initializer) {
            const pointer_type: global_sg.GlobalTypeId = @enumFromInt(2);
            try graph.types.append(allocator, .{ .pointer = .{ .child = declared_type, .mutability = .read_write } });
            const p_name = try graph.addString(allocator, "p");
            try graph.fields.append(allocator, .{
                .name = p_name,
                .ty = pointer_type,
                .source = .{ .file_index = 0, .offset = 3 },
            });
            const init_name = try graph.addString(allocator, "init");
            try graph.declarations.append(allocator, .{
                .kind = .function,
                .name = init_name,
                .source = .{ .file_index = 0, .offset = 2 },
                .function_id = @enumFromInt(0),
            });
            try graph.functions.append(allocator, .{
                .declaration = @enumFromInt(1),
                .input = .{ .start = 0, .len = 1 },
                .output = .{ .start = 1, .len = 0 },
            });
        }

        try graph.modules.append(allocator, .{
            .dir = module_dir,
            .files = .{ .start = 0, .len = 0 },
            .declarations = .{ .start = 0, .len = if (with_initializer) 2 else 1 },
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
        var resolver: Resolver = .{
            .graph = &self.graph,
            .modules = self.modules(),
            .offsets = &self.offsets,
            .core = &core,
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

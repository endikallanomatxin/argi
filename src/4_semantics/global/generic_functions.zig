const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const parameterized_storage = @import("../module/parameterized/storage.zig");
const ir = @import("../module/parameterized/ir.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const reach_context_mod = @import("reach_context.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const generic_mod = @import("generics.zig");
const abstract_mod = @import("abstracts.zig");
const call_compatibility = @import("call_compatibility.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    instances: u32 = 0,
    calls: u32 = 0,
    nodes: u32 = 0,
};

const ReachInferenceContext = reach_context_mod.Context;

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    nested_call_context: ?*abstract_mod.Resolver = null,
    nested_call_resolver: ?*const fn (*abstract_mod.Resolver, usize, module_entities.ExternalRef, global_sg.GlobalNodeId, primitives.SourceRef) anyerror!?global_sg.Node = null,
    nested_constructor_context: ?*anyopaque = null,
    nested_constructor_resolver: ?*const fn (*anyopaque, usize, module_entities.ExternalRef, primitives.Range(global_sg.GlobalGenericArgId), global_sg.GlobalNodeId, ReachInferenceContext, primitives.SourceRef) anyerror!?global_sg.Node = null,
    ownership_context: ?*anyopaque = null,
    register_defer: ?*const fn (*anyopaque, global_sg.GlobalNodeId, global_sg.GlobalNodeId) anyerror!void = null,
    stats: Stats = .{},

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_call => |value| try self.resolveModuleGenericCall(module_index, module, o, value),
            .resolve_index => |value| try self.resolveGenericIndex(module_index, module, o, value),
            else => .not_applicable,
        };
    }

    const ResolvedIndexOperator = struct {
        function: global_sg.GlobalFunctionId,
        addressed_receiver_type: ?global_sg.GlobalTypeId = null,
    };

    fn resolveGenericIndex(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const collection = globalizer.globalNode(o, value.value);
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
        for (operands[0..count], 0..) |node, offset| {
            const ty = self.graph.nodes.items[@intFromEnum(node)].ty orelse return .deferred;
            if (self.graph.isTypeUnresolved(ty)) return .deferred;
            operand_types[offset] = ty;
        }

        const reach = ReachInferenceContext.fromModule(
            module,
            o,
            value.visible_bindings,
            value.owner_function,
        );
        const input = try self.makePositionalInput(operands[0..count]);

        // Parameterized operators use the same inference ingredients as
        // parameterized calls: explicit operands first, then omitted #reach
        // defaults, then constraints. The receiver is the one index-specific
        // detail: index syntax may implicitly take its address.
        var instantiated = false;
        for (self.modules, 0..) |*candidate_module, candidate_module_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                if (parameterized.dispatch_kind == .abstract_contract) continue;
                if (parameterized.operator != value.operator) continue;
                const declaration = globalizer.globalDecl(
                    self.offsets[candidate_module_index],
                    parameterized.declaration,
                );
                if (!self.core.declarationVisible(module_index, declaration, null)) continue;

                var bindings = try generic_mod.Resolver.Bindings.init(
                    self.allocator,
                    candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
                );
                defer bindings.deinit(self.allocator);

                if (!try self.inferIndexCandidate(
                    candidate_module_index,
                    parameterized,
                    operands[0..count],
                    operand_types[0..count],
                    input,
                    reach,
                    &bindings,
                )) continue;

                const arguments = self.appendBoundArguments(
                    candidate_module_index,
                    parameterized.parameters,
                    &bindings,
                ) catch |err| switch (err) {
                    error.MissingGenericArgument => continue,
                    else => return err,
                };
                _ = self.instantiate(declaration, arguments) catch continue;
                instantiated = true;
            }
        }
        if (!instantiated) return .not_applicable;

        const selected = self.resolveInstantiatedIndexOperator(
            module_index,
            value.operator,
            operand_types[0],
            operands[0..count],
            operand_types[0..count],
        ) orelse return .deferred;

        if (selected.addressed_receiver_type) |receiver_ty| {
            const address: global_sg.GlobalNodeId = @enumFromInt(
                @as(u32, @intCast(self.graph.nodes.items.len)),
            );
            try self.graph.nodes.append(self.allocator, .{
                .source = self.graph.nodes.items[@intFromEnum(collection)].source,
                .ty = receiver_ty,
                .content = .{ .address_of = collection },
            });
            const literal = self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal;
            self.graph.value_fields.items[literal.fields.start].value = address;
        }

        const function = self.graph.functions.items[@intFromEnum(selected.function)];
        if (!try self.core.completeCallInputFieldsWithReach(function.input, input, reach))
            return .deferred;

        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(collection)].source,
            .ty = try self.core.functionOutputType(selected.function),
            .content = .{ .function_call = .{
                .callee = selected.function,
                .input = input,
            } },
        };
        self.stats.calls += 1;
        return .resolved;
    }

    fn makePositionalInput(
        self: *Resolver,
        nodes: []const global_sg.GlobalNodeId,
    ) !global_sg.GlobalNodeId {
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        const empty_name = try self.graph.addString(self.allocator, "");
        for (nodes) |node|
            try self.graph.value_fields.append(self.allocator, .{
                .name = empty_name,
                .value = node,
            });

        const id: global_sg.GlobalNodeId = @enumFromInt(
            @as(u32, @intCast(self.graph.nodes.items.len)),
        );
        try self.graph.nodes.append(self.allocator, .{
            .source = self.graph.nodes.items[@intFromEnum(nodes[0])].source,
            .ty = null,
            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = start, .len = @intCast(nodes.len) },
                .dispatch_prefix_positional_count = @intCast(nodes.len),
            } },
        });
        return id;
    }

    fn inferIndexCandidate(
        self: *Resolver,
        candidate_module_index: usize,
        parameterized: parameterized_storage.ParameterizedFunction,
        operands: []const global_sg.GlobalNodeId,
        operand_types: []const global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        reach: ReachInferenceContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const storage = &self.modules[candidate_module_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(parameterized.input)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len < operands.len) return false;

        for (operands, 0..) |operand, offset| {
            const field = storage.fields.items[shape.fields.start + @as(u32, @intCast(offset))];
            const pattern = field.ty;

            if (offset == 0) {
                if (!try self.inferInputTypeWithImplicitAddress(
                    candidate_module_index,
                    pattern,
                    operand_types[offset],
                    bindings,
                )) return false;
                continue;
            }

            {
                if (self.generics.instantiateParameterizedType(
                    candidate_module_index,
                    pattern,
                    bindings,
                    null,
                )) |expected| {
                    if (self.core.contextualLiteralFits(operand, expected)) continue;
                } else |_| {}
            }

            if (!try self.inferInputType(
                candidate_module_index,
                pattern,
                operand_types[offset],
                bindings,
            )) return false;
        }

        if (!try self.inferBindingsFromReachDefaults(
            candidate_module_index,
            parameterized.input,
            input,
            bindings,
            reach,
        )) return false;

        return self.inferAndValidateConstraints(
            candidate_module_index,
            parameterized.parameters,
            bindings,
        );
    }

    fn resolveInstantiatedIndexOperator(
        self: *Resolver,
        module_index: usize,
        operator: @import("../primitives/callable.zig").OperatorKind,
        collection_ty: global_sg.GlobalTypeId,
        operand_nodes: []const global_sg.GlobalNodeId,
        operand_types: []const global_sg.GlobalTypeId,
    ) ?ResolvedIndexOperator {
        var chosen: ?ResolvedIndexOperator = null;

        for (self.graph.functions.items, 0..) |candidate, raw| {
            if (raw >= self.graph.function_operators.items.len or
                self.graph.function_operators.items[raw] != operator) continue;
            if (!self.core.declarationVisible(module_index, candidate.declaration, null)) continue;
            if (candidate.input.len < operand_types.len) continue;

            var defaults_available = true;
            for (operand_types.len..candidate.input.len) |offset| {
                if (self.graph.fields.items[candidate.input.start + @as(u32, @intCast(offset))].default_value == null) {
                    defaults_available = false;
                    break;
                }
            }
            if (!defaults_available) continue;

            const expected_receiver = self.graph.fields.items[candidate.input.start].ty;
            var addressed_receiver_type: ?global_sg.GlobalTypeId = null;
            if (!global_types.equal(self.graph, expected_receiver, collection_ty) and
                !self.core.callTypesCompatible(collection_ty, expected_receiver))
            {
                const pointer = switch (self.graph.types.items[@intFromEnum(expected_receiver)]) {
                    .pointer => |value| value,
                    else => continue,
                };
                if (!global_types.equal(self.graph, pointer.child, collection_ty) and
                    !self.core.callTypesCompatible(collection_ty, pointer.child)) continue;
                addressed_receiver_type = expected_receiver;
            }

            var matches = true;
            for (1..operand_types.len) |offset| {
                const expected = self.graph.fields.items[
                    candidate.input.start + @as(u32, @intCast(offset))
                ].ty;
                if (!global_types.equal(self.graph, expected, operand_types[offset]) and
                    !self.core.callTypesCompatible(operand_types[offset], expected) and
                    !self.core.contextualLiteralFits(operand_nodes[offset], expected))
                {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            if (chosen != null) return null;
            chosen = .{
                .function = @enumFromInt(@as(u32, @intCast(raw))),
                .addressed_receiver_type = addressed_receiver_type,
            };
        }
        return chosen;
    }

    fn resolveModuleGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        const local_args = reference.generic_arguments;
        const name = module.text(reference.name);
        const input = globalizer.globalNode(o, value.input);
        if (local_args != null and reference.module_path == null and std.mem.eql(u8, name, "cast")) {
            const args = try self.generics.relocateModuleArguments(module_index, local_args.?);
            const node = (try self.makeExplicitCast(args, input, self.sourceFor(module_index, reference.source))) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, name, "size_of")) {
            const node = (try self.makeSizeOf(input, self.sourceFor(module_index, reference.source))) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return .resolved;
        }
        const reach: ReachInferenceContext = ReachInferenceContext.fromModule(module, o, value.visible_bindings, value.owner_function);
        const function = if (local_args) |args|
            self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input, reach) catch |err| switch (err) {
                error.NoMatchingGenericFunction => return .not_applicable,
                error.DeferredGenericFunction => return .deferred,
                error.AmbiguousGenericFunction => return .invalid,
                else => return .deferred,
            }
        else
            self.resolveImplicitGenericFunction(module_index, module, reference, input, reach) catch |err| switch (err) {
                error.NoMatchingGenericFunction => return .not_applicable,
                error.DeferredGenericFunction => return .deferred,
                error.AmbiguousGenericFunction => return .invalid,
                error.ConflictingGenericArgument => return err,
                else => return .deferred,
            };
        const completed = try self.core.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function)].input, input, reach);
        if (std.mem.eql(u8, name, "exercise")) std.debug.print("[exercise] completed={}\n", .{completed});
        if (!completed) return .deferred;
        const output_ty = try self.core.functionOutputType(function);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(module_index, reference.source),
            .ty = if (value.expected_type) |ty| globalizer.globalType(o, ty) else output_ty,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.calls += 1;
        return .resolved;
    }

    fn resolveExplicitGenericFunction(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
        reach_context: ?ReachInferenceContext,
    ) !global_sg.GlobalFunctionId {
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        const name = module.text(reference.name);
        var best: ?global_sg.GlobalDeclId = null;
        var best_arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = 0, .len = 0 };
        var best_score: u32 = 0;
        var best_specificity: ParameterizedSpecificity = .{};
        var tied = false;
        var saw_deferred = false;
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
                if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, candidate_module.semantic.parameterized_storage.comptime_parameters.items.len);
                defer bindings.deinit(self.allocator);
                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;
                const input_inferred = self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings) catch |err| switch (err) {
                    error.ConflictingGenericArgument => continue,
                    else => return err,
                };
                if (!input_inferred) continue;
                if (reach_context) |context|
                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
                if (!try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings)) continue;
                const complete_arguments = self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| switch (err) {
                    error.MissingGenericArgument => continue,
                    else => return err,
                };
                const score = switch (self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input)) {
                    .no_match => continue,
                    .deferred => {
                        saw_deferred = true;
                        continue;
                    },
                    .score => |score| score,
                };
                const specificity = self.parameterizedInputSpecificity(candidate_index, parameterized.input, input);
                const ordering: CandidateOrdering = if (best == null) .better else compareCandidates(specificity, score, best_specificity, best_score);
                switch (ordering) {
                    .better => {
                        best = declaration;
                        best_arguments = complete_arguments;
                        best_score = score;
                        best_specificity = specificity;
                        tied = false;
                    },
                    .worse => {},
                    .tie => if (declaration != best.?) {
                        tied = true;
                    },
                }
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        const declaration = best orelse return if (saw_deferred) error.DeferredGenericFunction else error.NoMatchingGenericFunction;
        return self.instantiate(declaration, best_arguments);
    }

    pub fn inferBindingsFromInput(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        // Once prior arguments have determined a field's concrete type,
        // a contextual literal is compatibility information, not new generic
        // evidence (e.g. Int32 literal 0 passed to UIntNative).
        return self.inferBindingsFromInputFields(module_index, pattern, input, bindings, 0, true);
    }

    fn inferBindingsFromInputFields(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
        field_offset: u32,
        allow_contextual_concrete: bool,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (field_offset > shape.fields.len) return false;

        const fields = storage.fields.items[shape.fields.start + field_offset ..][0 .. shape.fields.len - field_offset];
        for (fields, 0..) |field, expected_position| {
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional)
                    expected_position != supplied_position
                else
                    !std.mem.eql(u8, module.text(field.name), self.graph.text(value.name))) continue;

                if (allow_contextual_concrete) {
                    if (self.generics.instantiateParameterizedType(module_index, field.ty, bindings, null)) |expected| {
                        if (self.core.contextualLiteralFits(value.value, expected)) break;
                    } else |_| {}
                }

                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse return false;
                if (!try self.inferInputType(module_index, field.ty, actual, bindings)) return false;
                break;
            }
        }
        return true;
    }

    fn inferBindingsFromReachDefaults(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
        context: ReachInferenceContext,
    ) !bool {
        return self.inferBindingsFromReachDefaultFields(module_index, pattern, input, bindings, context, 0);
    }

    fn inferBindingsFromReachDefaultFields(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
        context: ReachInferenceContext,
        field_offset: u32,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return true,
        };
        const candidate_module = &self.modules[module_index];
        const storage = &candidate_module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return true,
            },
            else => return true,
        };
        if (field_offset > shape.fields.len) return false;

        const fields = storage.fields.items[shape.fields.start + field_offset ..][0 .. shape.fields.len - field_offset];
        for (fields, 0..) |field, expected_position| {
            var supplied = false;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional)
                    expected_position == supplied_position
                else
                    std.mem.eql(u8, candidate_module.text(field.name), self.graph.text(value.name)))
                {
                    supplied = true;
                    break;
                }
            }
            if (supplied) continue;

            const default_id = field.default_value orelse continue;
            const default_node = switch (storage.nodes.items[@intFromEnum(default_id)]) {
                .resolved => |node| node,
                .pending => continue,
            };
            const reach_id = switch (default_node.content) {
                .reach_directive => |reach| reach,
                else => continue,
            };
            const reach = storage.reaches.items[@intFromEnum(reach_id)];

            var inferred = false;
            for (storage.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
                if (alternative.segments.len == 0) continue;
                const segments = storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
                const root_name = candidate_module.text(segments[0]);
                var scope_index = context.bindingCount();
                while (scope_index > 0) {
                    scope_index -= 1;
                    const binding_id = context.bindingAt(scope_index);
                    if (self.graph.isBindingTypeUnresolved(binding_id)) continue;
                    const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                    if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                    var current_ty = binding.ty;
                    var valid = !self.graph.isTypeUnresolved(current_ty);
                    for (segments[1..]) |segment| {
                        if (!valid) break;
                        const step = self.core.reachedField(current_ty, candidate_module.text(segment)) orelse {
                            valid = false;
                            break;
                        };
                        current_ty = step.hit.field.storage_type orelse step.hit.field.ty;
                        if (self.graph.isTypeUnresolved(current_ty)) valid = false;
                    }
                    if (!valid) continue;
                    const matched = self.inferInputTypeWithImplicitAddress(
                        module_index,
                        field.ty,
                        current_ty,
                        bindings,
                    ) catch |err| switch (err) {
                        error.ConflictingGenericArgument => return false,
                        else => continue,
                    };
                    if (matched) {
                        inferred = true;
                        break;
                    }
                }
                if (inferred) break;
            }
        }
        return true;
    }

    pub fn inferInitializerInputBindings(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        context: ReachInferenceContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        if (!try self.inferBindingsFromInputFields(
            module_index,
            pattern,
            input,
            bindings,
            1,
            true,
        )) return false;

        return self.inferBindingsFromReachDefaultFields(
            module_index,
            pattern,
            input,
            bindings,
            context,
            1,
        );
    }

    pub fn inferInitializerBindings(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        destination_type: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: ReachInferenceContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;

        const destination_pointer = try self.generics.internType(.{ .pointer = .{
            .child = destination_type,
            .mutability = .read_write,
        } });
        if (!try self.inferInputType(
            module_index,
            storage.fields.items[shape.fields.start].ty,
            destination_pointer,
            bindings,
        )) return false;

        return self.inferInitializerInputBindings(
            module_index,
            pattern,
            input,
            context,
            bindings,
        );
    }

    fn inferAndValidateConstraints(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const abstracts = self.nested_call_context orelse return true;
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
                };
            }

            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                const constraint_id = parameter.constraint orelse continue;
                if (parameter.kind != .type) continue;
                const concrete = bindings.types[raw] orelse continue;
                const constraint_ok = try abstracts.inferConstraintBindings(module_index, constraint_id, concrete, bindings);

                if (!constraint_ok) return false;
            }

            var after: usize = 0;
            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                after += switch (parameter.kind) {
                    .type => @intFromBool(bindings.types[raw] != null),
                    .comptime_int => @intFromBool(bindings.ints[raw] != null),
                };
            }
            made_progress = after > before;
        }

        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            const constraint_id = parameter.constraint orelse continue;
            if (parameter.kind != .type) return false;
            const concrete = bindings.types[raw] orelse return false;
            const constraint_ok = try abstracts.inferConstraintBindings(module_index, constraint_id, concrete, bindings);

            if (!constraint_ok) return false;
        }
        return true;
    }

    pub fn appendBoundArguments(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *const generic_mod.Resolver.Bindings,
    ) !primitives.Range(global_sg.GlobalGenericArgId) {
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            const value: global_sg.GenericArgument.Value = switch (parameter.kind) {
                .type => .{ .type = bindings.types[raw] orelse return error.MissingGenericArgument },
                .comptime_int => .{ .comptime_int = bindings.ints[raw] orelse return error.MissingGenericArgument },
            };
            try self.graph.generic_arguments.append(self.allocator, .{
                .name = try self.graph.addString(self.allocator, self.modules[module_index].text(parameter.name)),
                .value = value,
            });
        }
        return .{ .start = start, .len = parameters.len };
    }

    fn resolveImplicitGenericFunction(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        reach_context: ?ReachInferenceContext,
    ) !global_sg.GlobalFunctionId {
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        return self.resolveImplicitGenericFunctionFiltered(
            current_module,
            module.text(reference.name),
            module_filter,
            input,
            reach_context,
            null,
        );
    }

    /// Compiler-generated calls participate in exactly the same generic
    /// inference and declaration-specificity ordering as source calls.
    pub fn resolveImplicitGenericFunctionByName(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input: global_sg.GlobalNodeId,
        reach: ?ReachInferenceContext,
    ) !global_sg.GlobalFunctionId {
        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input, reach, null);
    }

    pub fn hasVisibleParameterizedFunctionName(
        self: *const Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
    ) bool {
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
                if (self.core.declarationVisible(current_module, declaration, module_filter)) return true;
            }
        }
        return false;
    }

    fn resolveImplicitGenericFunctionFiltered(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input: global_sg.GlobalNodeId,
        reach_context: ?ReachInferenceContext,
        ambiguity_candidates: ?*std.ArrayList(global_sg.GlobalDeclId),
    ) !global_sg.GlobalFunctionId {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return error.MissingGenericInputType,
        };
        var best: ?global_sg.GlobalDeclId = null;
        var best_arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = 0, .len = 0 };
        var best_score: u32 = 0;
        var best_specificity: ParameterizedSpecificity = .{};
        var tied = false;
        var saw_deferred = false;
        var conflicting_candidates: usize = 0;
        var candidate_count: usize = 0;
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
                if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
                candidate_count += 1;
                const trace_exercise = std.mem.eql(u8, name, "exercise");
                if (trace_exercise) {
                    std.debug.print("[exercise] candidate module={d} params={d} visible={d}\n", .{
                        candidate_index,
                        parameterized.parameters.len,
                        if (reach_context) |context| context.bindingCount() else 0,
                    });
                    if (reach_context) |context| {
                        var trace_index: usize = 0;
                        while (trace_index < context.bindingCount()) : (trace_index += 1) {
                            const trace_binding = self.graph.bindings.items[@intFromEnum(context.bindingAt(trace_index))];
                            std.debug.print("[exercise] visible[{d}]={s} unresolved={} ty={d}\n", .{
                                trace_index,
                                self.graph.text(trace_binding.name),
                                self.graph.isBindingTypeUnresolved(context.bindingAt(trace_index)),
                                @intFromEnum(trace_binding.ty),
                            });
                        }
                    }
                }
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
                var candidate_deferred = false;
                for (storage.fields.items[shape.fields.start..][0..shape.fields.len], 0..) |field, position| {
                    for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                        const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                        if (if (positional) position != supplied_position else !std.mem.eql(u8, candidate_module.text(field.name), self.graph.text(value.name))) continue;
                        const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse {
                            candidate_deferred = true;
                            matches = false;
                            break;
                        };
                        _ = self.inferInputType(candidate_index, field.ty, actual, &bindings) catch |err| {
                            if (err == error.ConflictingGenericArgument) {
                                conflicting_candidates += 1;
                                matches = false;
                                break;
                            }
                            candidate_deferred = true;
                            matches = false;
                            break;
                        };
                        break;
                    }
                    if (!matches) break;
                }
                if (!matches) {
                    if (candidate_deferred) saw_deferred = true;
                    continue;
                }
                if (reach_context) |context| {
                    const reach_ok = try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context);
                    if (trace_exercise) {
                        std.debug.print("[exercise] reach_ok={}\n", .{reach_ok});
                        for (parameterized.parameters.start..parameterized.parameters.start + parameterized.parameters.len) |raw| {
                            const parameter = candidate_module.semantic.parameterized_storage.comptime_parameters.items[raw];
                            std.debug.print("[exercise] param {s} type={any}\n", .{
                                candidate_module.text(parameter.name),
                                bindings.types[raw],
                            });
                        }
                    }
                    if (!reach_ok) continue;
                }
                const constraints_ok = try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings);
                if (trace_exercise) std.debug.print("[exercise] constraints_ok={}\n", .{constraints_ok});
                if (!constraints_ok) continue;
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
                if (trace_exercise) std.debug.print("[exercise] arguments={d}/{d}\n", .{ arguments.items.len, parameterized.parameters.len });
                if (arguments.items.len != parameterized.parameters.len) continue;
                const range: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = @intCast(self.graph.generic_arguments.items.len), .len = @intCast(arguments.items.len) };
                try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);
                const input_match = self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input);
                if (trace_exercise) std.debug.print("[exercise] input_match={s}\n", .{@tagName(input_match)});
                const score = switch (input_match) {
                    .no_match => continue,
                    .deferred => {
                        saw_deferred = true;
                        continue;
                    },
                    .score => |score| score,
                };
                const specificity = self.parameterizedInputSpecificity(candidate_index, parameterized.input, input);
                const ordering: CandidateOrdering = if (best == null) .better else compareCandidates(specificity, score, best_specificity, best_score);
                switch (ordering) {
                    .better => {
                        best = declaration;
                        best_arguments = range;
                        best_score = score;
                        best_specificity = specificity;
                        tied = false;
                        if (ambiguity_candidates) |candidates| {
                            candidates.clearRetainingCapacity();
                            try candidates.append(self.allocator, declaration);
                        }
                    },
                    .worse => {},
                    .tie => if (declaration != best.?) {
                        tied = true;
                        if (ambiguity_candidates) |candidates|
                            try candidates.append(self.allocator, declaration);
                    },
                }
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        const declaration = best orelse return if (saw_deferred) error.DeferredGenericFunction else if (candidate_count == 1 and conflicting_candidates == 1) error.ConflictingGenericArgument else error.NoMatchingGenericFunction;
        if (std.mem.eql(u8, name, "exercise")) std.debug.print("[exercise] selected declaration={d}\n", .{@intFromEnum(declaration)});
        const instantiated = self.instantiate(declaration, best_arguments) catch |err| {
            if (std.mem.eql(u8, name, "exercise")) std.debug.print("[exercise] instantiate_error={s}\n", .{@errorName(err)});
            return err;
        };
        if (std.mem.eql(u8, name, "exercise")) std.debug.print("[exercise] instantiated function={d}\n", .{@intFromEnum(instantiated)});
        return instantiated;
    }

    /// Re-run implicit generic selection transactionally for diagnostics and
    /// report the declaration identities tied at the best rank. This keeps
    /// diagnostics coupled to the real inference/specificity algorithm rather
    /// than maintaining an approximate second overload matcher.
    pub fn collectImplicitGenericAmbiguity(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        candidates: *std.ArrayList(global_sg.GlobalDeclId),
    ) !bool {
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index|
            lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        const saved_core_stats = self.core.stats;
        defer {
            inline for (pools, 0..) |pool, index|
                @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            self.stats = saved_stats;
            self.generics.stats = saved_generic_stats;
            self.core.stats = saved_core_stats;
        }

        candidates.clearRetainingCapacity();
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        _ = self.resolveImplicitGenericFunctionFiltered(
            current_module,
            module.text(reference.name),
            module_filter,
            input,
            null,
            candidates,
        ) catch |err| return switch (err) {
            error.AmbiguousGenericFunction => true,
            else => false,
        };
        return false;
    }

    const ParameterizedSpecificity = struct {
        /// Exact nominal/builtin leaves. Exactness also satisfies the weaker
        /// "bounded" dimension so a concrete type dominates an abstract bound.
        exact: u32 = 0,
        bounded: u32 = 0,
        /// Fixed type constructors such as pointer/array/structural shape.
        structure: u32 = 0,

        fn add(self: *ParameterizedSpecificity, other: ParameterizedSpecificity) void {
            self.exact += other.exact;
            self.bounded += other.bounded;
            self.structure += other.structure;
        }
    };

    const SpecificityOrdering = enum { less, equal, greater, incomparable };
    const CandidateOrdering = enum { better, worse, tie };

    fn compareSpecificity(left: ParameterizedSpecificity, right: ParameterizedSpecificity) SpecificityOrdering {
        if (left.exact == right.exact and left.bounded == right.bounded and left.structure == right.structure) return .equal;
        const left_at_least = left.exact >= right.exact and left.bounded >= right.bounded and left.structure >= right.structure;
        const right_at_least = right.exact >= left.exact and right.bounded >= left.bounded and right.structure >= left.structure;
        if (left_at_least) return .greater;
        if (right_at_least) return .less;
        return .incomparable;
    }

    fn compareCandidates(
        candidate_specificity: ParameterizedSpecificity,
        candidate_score: u32,
        best_specificity: ParameterizedSpecificity,
        best_score: u32,
    ) CandidateOrdering {
        return switch (compareSpecificity(candidate_specificity, best_specificity)) {
            .greater => .better,
            .less => .worse,
            // Compatibility remains a useful discriminator when declarations
            // impose the same restrictions, or restrictions on orthogonal
            // dimensions. Equal quality in the latter case is ambiguous.
            .equal, .incomparable => if (candidate_score > best_score)
                .better
            else if (candidate_score < best_score)
                .worse
            else
                .tie,
        };
    }

    fn exactSpecificity() ParameterizedSpecificity {
        return .{ .exact = 1, .bounded = 1 };
    }

    fn parameterizedInputSpecificity(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
    ) ParameterizedSpecificity {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return self.parameterizedTypeSpecificity(module_index, pattern),
        };
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return self.parameterizedTypeSpecificity(module_index, pattern),
            },
            else => return self.parameterizedTypeSpecificity(module_index, pattern),
        };

        var specificity: ParameterizedSpecificity = .{};
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |supplied, supplied_position| {
            const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(supplied.name).len == 0;
            var matched: ?ir.ParameterizedTypeId = null;
            if (positional) {
                if (supplied_position < shape.fields.len) {
                    matched = storage.fields.items[shape.fields.start + @as(u32, @intCast(supplied_position))].ty;
                }
            } else {
                for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                    if (!std.mem.eql(u8, self.modules[module_index].text(field.name), self.graph.text(supplied.name))) continue;
                    matched = field.ty;
                    break;
                }
            }
            if (matched) |field_type| specificity.add(self.parameterizedTypeSpecificity(module_index, field_type));
        }
        return specificity;
    }

    fn parameterizedTypeSpecificity(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
    ) ParameterizedSpecificity {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        return switch (storage.types.items[@intFromEnum(pattern)]) {
            .parameter => |parameter| if (module.semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter)].constraint != null)
                .{ .bounded = 1 }
            else
                .{},
            .abstract_self => .{ .bounded = 1 },
            .concrete, .external => exactSpecificity(),
            .array => |array| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedIntSpecificity(module_index, array.length));
                result.add(self.parameterizedTypeSpecificity(module_index, array.element));
                break :blk result;
            },
            .choice_union => |value| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedTypeSpecificity(module_index, value.left));
                result.add(self.parameterizedTypeSpecificity(module_index, value.right));
                break :blk result;
            },
            .resolved => |resolved| self.resolvedPatternSpecificity(module_index, resolved),
        };
    }

    fn parameterizedIntSpecificity(
        self: *Resolver,
        module_index: usize,
        expression: ir.ParameterizedIntExprId,
    ) ParameterizedSpecificity {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        return switch (storage.int_expressions.items[@intFromEnum(expression)]) {
            .literal => exactSpecificity(),
            .parameter => .{},
            .binary => |binary| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedIntSpecificity(module_index, binary.left));
                result.add(self.parameterizedIntSpecificity(module_index, binary.right));
                break :blk result;
            },
        };
    }

    fn resolvedPatternSpecificity(
        self: *Resolver,
        module_index: usize,
        resolved: ir.ResolvedType,
    ) ParameterizedSpecificity {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        return switch (resolved) {
            .builtin => |builtin| if (builtin == .Any) .{} else exactSpecificity(),
            .declared => exactSpecificity(),
            .pointer => |pointer| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedTypeSpecificity(module_index, pointer.child));
                break :blk result;
            },
            .array => |array| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(exactSpecificity());
                result.add(self.parameterizedTypeSpecificity(module_index, array.element));
                break :blk result;
            },
            .nullable, .inferred_errable, .virtual => |child| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                result.add(self.parameterizedTypeSpecificity(module_index, child));
                break :blk result;
            },
            .generic => |generic| blk: {
                var result = exactSpecificity();
                result.structure += 1;
                for (storage.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| switch (argument.value) {
                    .type => |ty| result.add(self.parameterizedTypeSpecificity(module_index, ty)),
                    .comptime_int => |value| result.add(self.parameterizedIntSpecificity(module_index, value)),
                };
                break :blk result;
            },
            .structural => |shape| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                    result.structure += 1;
                    result.add(self.parameterizedTypeSpecificity(module_index, field.ty));
                }
                break :blk result;
            },
            .structural_choice => |shape| blk: {
                var result: ParameterizedSpecificity = .{ .structure = 1 };
                for (storage.variants.items[shape.variants.start..][0..shape.variants.len]) |variant| {
                    result.structure += 1;
                    if (variant == .semantic) if (variant.semantic.payload_type) |payload|
                        result.add(self.parameterizedTypeSpecificity(module_index, payload));
                }
                break :blk result;
            },
            .inferred_choice => .{ .structure = 1 },
        };
    }

    fn matchParameterizedInput(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, bindings: *generic_mod.Resolver.Bindings, input: global_sg.GlobalNodeId) core_mod.Resolver.CallInputMatch {
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = self.generics.stats;
        defer {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            self.generics.stats = saved_stats;
        }
        const ty = self.generics.instantiateParameterizedType(module_index, pattern, bindings, null) catch return .deferred;
        const fields = self.interfaceFields(ty) catch return .deferred;
        const matching_fields = self.materializeDefaultPresenceForMatch(module_index, pattern, fields) catch return .deferred;
        if (self.nested_call_context) |abstracts| {
            return call_compatibility.matchInput(.{ .core = self.core, .abstracts = abstracts }, matching_fields, input);
        }
        return self.core.matchCallInput(matching_fields, input);
    }

    /// Dispatch only needs to know whether an omitted field has a default. Its
    /// concrete node is instantiated after selecting the generic declaration.
    fn materializeDefaultPresenceForMatch(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        fields: global_sg.FieldRange,
    ) !global_sg.FieldRange {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |shape| shape,
                else => return fields,
            },
            else => return fields,
        };
        if (shape.fields.len != fields.len) return fields;
        var has_defaults = false;
        for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |field|
            if (field.default_value != null) {
                has_defaults = true;
                break;
            };
        if (!has_defaults) return fields;

        const copied = try self.allocator.dupe(global_sg.Field, self.graph.fields.items[fields.start..][0..fields.len]);
        defer self.allocator.free(copied);
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.allocator, copied);
        for (storage.fields.items[shape.fields.start..][0..shape.fields.len], 0..) |field, offset| {
            if (field.default_value == null) continue;
            const global_field = &self.graph.fields.items[start + @as(u32, @intCast(offset))];
            const marker: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
            try self.graph.nodes.append(self.allocator, .{
                .source = global_field.source,
                .ty = global_field.ty,
                .content = .break_statement,
            });
            global_field.default_value = marker;
        }
        return .{ .start = start, .len = fields.len };
    }

    /// Reach defaults and index receivers may synthesize an address when a
    /// value is supplied for a reference parameter. Generic inference runs
    /// before that address node exists, so infer from the pointee pattern in
    /// that case and use ordinary inference for real pointer arguments.
    fn inferInputTypeWithImplicitAddress(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        actual: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) anyerror!bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .pointer => |pointer| switch (self.graph.types.items[@intFromEnum(actual)]) {
                    .pointer => {},
                    else => return self.inferInputType(
                        module_index,
                        pointer.child,
                        actual,
                        bindings,
                    ),
                },
                else => {},
            },
            else => {},
        }
        return self.inferInputType(module_index, pattern, actual, bindings);
    }

    pub fn inferInputType(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        actual: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) anyerror!bool {
        const actual_raw: usize = @intFromEnum(actual);
        if (actual_raw >= self.graph.types.items.len or self.graph.isTypeUnresolved(actual)) return false;
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        switch (storage.types.items[@intFromEnum(pattern)]) {
            .parameter => |parameter| {
                const comptime_parameter = module.semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter)];
                // A contract declaration can appear as an intermediate input
                // type while a caller is still unspecialized. Only an
                // implementer's type may bind its constrained parameter.
                if (comptime_parameter.constraint != null) switch (self.graph.types.items[@intFromEnum(actual)]) {
                    .declared => |declaration| if (self.graph.declarations.items[@intFromEnum(declaration)].kind == .abstract_type) return false,
                    else => {},
                };
                const slot = &bindings.types[@intFromEnum(parameter)];
                if (slot.*) |previous| {
                    if (!global_types.equal(self.graph, previous, actual)) return error.ConflictingGenericArgument;
                    return true;
                }
                slot.* = actual;
                return true;
            },
            .array => |array| {
                const value = switch (self.graph.types.items[@intFromEnum(actual)]) {
                    .array => |value| value,
                    else => return false,
                };
                if (!try self.inferIntExpression(module_index, array.length, @intCast(value.length), bindings)) return false;
                return self.inferInputType(module_index, array.element, value.element, bindings);
            },
            .resolved => |resolved| switch (resolved) {
                .nullable => |child| {
                    const value = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .nullable => |value| value,
                        else => return false,
                    };
                    return self.inferInputType(module_index, child, value, bindings);
                },
                .inferred_errable => |child| {
                    const value = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .inferred_errable => |value| value,
                        else => return false,
                    };
                    return self.inferInputType(module_index, child, value, bindings);
                },
                .pointer => |pointer| {
                    const value = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .pointer => |value| value,
                        else => return false,
                    };
                    if (pointer.mutability == .read_write and value.mutability != .read_write) return false;
                    if (try self.inferInputType(module_index, pointer.child, value.child, bindings)) return true;
                    const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings, null) catch return false;
                    if (self.core.callTypesCompatible(actual, expected)) return true;
                    if (self.nested_call_context) |abstracts| {
                        return (call_compatibility.Abstract{ .core = self.core, .abstracts = abstracts }).compatible(actual, expected);
                    }
                    return false;
                },
                .structural => |shape| {
                    const fields = global_types.fields(self.graph, actual) orelse return false;
                    for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                        var matched = false;
                        for (self.graph.fields.items[fields.start..][0..fields.len]) |value| {
                            if (!std.mem.eql(u8, module.text(field.name), self.graph.text(value.name))) continue;
                            if (!try self.inferInputType(module_index, field.ty, value.ty, bindings)) return false;
                            matched = true;
                            break;
                        }
                        if (!matched) return false;
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
                                .comptime_int => |expression| {
                                    if (concrete.value != .comptime_int) return false;
                                    if (!try self.inferIntExpression(module_index, expression, concrete.value.comptime_int, bindings)) return false;
                                },
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

    fn inferIntExpression(
        self: *Resolver,
        module_index: usize,
        expression: ir.ParameterizedIntExprId,
        actual: i64,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        return switch (storage.int_expressions.items[@intFromEnum(expression)]) {
            .literal => |value| value == actual,
            .parameter => |parameter| blk: {
                const slot = &bindings.ints[@intFromEnum(parameter)];
                if (slot.*) |previous| {
                    if (previous != actual) return error.ConflictingGenericArgument;
                } else slot.* = actual;
                break :blk true;
            },
            // Composite expressions are constraints rather than invertible
            // bindings. Once their operands have been inferred elsewhere the
            // regular evaluator validates the dependent value.
            .binary => (self.generics.evalInt(module_index, expression, bindings) catch return false) == actual,
        };
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

    /// Materialize a constructor initializer through the same generic
    /// inference used by every other generic call. Field 0 is the compiler
    /// supplied destination; source arguments and #reach defaults start at 1.
    pub fn instantiateInitializer(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        destination_type: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: ReachInferenceContext,
    ) !?global_sg.GlobalFunctionId {
        const located = self.findParameterized(declaration) orelse return null;
        const module = &self.modules[located.module_index];
        var bindings = try generic_mod.Resolver.Bindings.init(
            self.allocator,
            module.semantic.parameterized_storage.comptime_parameters.items.len,
        );
        defer bindings.deinit(self.allocator);
        if (!try self.inferInitializerBindings(
            located.module_index,
            located.parameterized.input,
            destination_type,
            input,
            context,
            &bindings,
        )) return null;
        if (!try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &bindings))
            return null;
        const arguments = self.appendBoundArguments(
            located.module_index,
            located.parameterized.parameters,
            &bindings,
        ) catch return null;
        return try self.instantiate(declaration, arguments);
    }

    pub fn instantiate(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !global_sg.GlobalFunctionId {
        if (self.findExisting(declaration, arguments)) |id| return id;
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
        if (!try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &substitutions))
            return error.GenericAbstractConstraintNotSatisfied;

        const input_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.input, &substitutions, null);
        const output_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.output, &substitutions, null);
        const input_shape = try self.interfaceFields(input_ty);
        const output_shape = try self.interfaceFields(output_ty);

        var context = try InstanceContext.init(self, located.module_index, located.parameterized, &substitutions);
        defer context.deinit();
        const input_bindings = try context.instantiateBindingRange(located.parameterized.input_bindings);
        const output_bindings = try context.instantiateBindingRange(located.parameterized.output_bindings);
        const input_fields = try self.materializeInterfaceDefaults(input_shape, input_bindings);
        const output_fields = try self.materializeInterfaceDefaults(output_shape, output_bindings);

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
                // A contract template has no runtime ABI; its inferred
                // instance does, once every abstract parameter is concrete.
                .is_abstract_dispatch = false,
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
            if (global_types.genericArgumentsEqual(self.graph, instance.arguments, arguments)) return instance.function;
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

    /// Function interface fields are owned by the concrete instance. Generic
    /// structural types can be interned and shared, so their canonical fields
    /// must not be mutated when defaults become concrete nodes.
    fn materializeInterfaceDefaults(
        self: *Resolver,
        shape: global_sg.FieldRange,
        bindings: global_sg.BindingRange,
    ) !global_sg.FieldRange {
        const fields = try self.allocator.dupe(global_sg.Field, self.graph.fields.items[shape.start..][0..shape.len]);
        defer self.allocator.free(fields);
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.allocator, fields);
        const count = @min(shape.len, bindings.len);
        for (0..count) |offset| {
            const binding_id = self.graph.binding_refs.items[bindings.start + @as(u32, @intCast(offset))];
            self.graph.fields.items[start + @as(u32, @intCast(offset))].default_value =
                self.graph.bindings.items[@intFromEnum(binding_id)].initialization;
        }
        return .{ .start = start, .len = shape.len };
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
            const storage = &module.semantic.parameterized_storage.ir;
            const source = storage.bindings.items[@intFromEnum(id)];
            const source_ty = storage.bindingType(id);
            const global: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.bindings.items.len)));
            try self.resolver.graph.bindings.append(self.resolver.allocator, .{
                .name = try self.resolver.graph.addString(self.resolver.allocator, module.text(source.name)),
                .source = self.resolver.sourceFor(self.module_index, source.source),
                .ty = if (source_ty) |ty|
                    try self.resolver.generics.instantiateParameterizedType(self.module_index, ty, self.substitutions, null)
                else
                    @enumFromInt(0),
                .initialization = null,
                .mutability = source.mutability,
            });
            self.binding_map[@intFromEnum(id)] = global;
            if (source_ty == null) try self.resolver.graph.markBindingTypeUnresolved(self.resolver.allocator, global);
            if (source.initialization) |node| {
                const initialization = if (source_ty) |ty|
                    try self.instantiateNodeAs(node, ty)
                else
                    try self.instantiateNode(node);
                self.resolver.graph.bindings.items[@intFromEnum(global)].initialization = initialization;
                if (source_ty == null) {
                    if (self.resolver.graph.nodes.items[@intFromEnum(initialization)].ty) |inferred| {
                        if (!self.resolver.graph.isTypeUnresolved(inferred)) {
                            self.resolver.graph.bindings.items[@intFromEnum(global)].ty = inferred;
                            _ = self.resolver.graph.reconcileBindingTypeResolution();
                        }
                    }
                }
            }
            return global;
        }

        fn instantiateBlock(self: *InstanceContext, id: ir.ParameterizedBlockId) anyerror!global_sg.GlobalBlockId {
            if (self.block_map[@intFromEnum(id)]) |existing| return existing;
            const local = self.resolver.modules[self.module_index].semantic.parameterized_storage.ir.blocks.items[@intFromEnum(id)];
            const global: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.blocks.items.len)));
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
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                .source = .{ .file_index = 0, .offset = 0 },
                .ty = null,
                .content = .break_statement,
            });
            self.node_map[@intFromEnum(id)] = global;
            if (local == .pending) {
                const pending = storage.pending.items[@intFromEnum(local.pending)];
                if (pending == .resolve_expression and pending.resolve_expression.kind == .defer_value) {
                    const expression = pending.resolve_expression;
                    if (expression.operands.len != 1) return error.InvalidParameterizedDefer;
                    const deferred_value = try self.instantiateNode(storage.node_refs.items[expression.operands.start]);
                    const context = self.resolver.ownership_context orelse return error.ParameterizedDeferWithoutOwnershipResolver;
                    const register = self.resolver.register_defer orelse return error.ParameterizedDeferWithoutOwnershipResolver;
                    try register(context, global, deferred_value);
                    self.resolver.stats.nodes += 1;
                    return global;
                }
            }
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
            } else if (local.resolved.content == .string_literal or local.resolved.content == .int_literal) {
                const global = try self.instantiateNode(id);
                const current = self.resolver.graph.nodes.items[@intFromEnum(global)].ty;
                if (current == null or !global_types.equal(self.resolver.graph, current.?, expected))
                    _ = self.resolver.core.coerceContextualValue(global, expected);
                return global;
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
                .content = .{ .struct_value_literal = .{
                    .fields = .{ .start = start, .len = local_fields.len },
                    .dispatch_prefix_positional_count = node.content.struct_value_literal.dispatch_prefix_positional_count,
                } },
            };
            self.resolver.stats.nodes += 1;
            return global;
        }

        fn instantiateResolvedNode(self: *InstanceContext, node: ir.ResolvedNode) anyerror!global_sg.Node {
            if (node.content == .struct_value_literal) return self.instantiateStructValue(node);
            if (node.content == .code_block) {
                const block = try self.instantiateBlock(node.content.code_block);
                const body = self.resolver.graph.blocks.items[@intFromEnum(block)];
                const ty: ?global_sg.GlobalTypeId = if (body.ret_val) |ret_val|
                    self.resolver.graph.nodes.items[@intFromEnum(ret_val)].ty
                else
                    try self.resolver.generics.internType(.{ .builtin = .Void });
                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = ty,
                    .content = .{ .code_block = block },
                };
            }
            if (node.content == .binding_use or node.content == .binding_declaration) {
                const declaration = node.content == .binding_declaration;
                const binding = try self.instantiateBinding(if (declaration) node.content.binding_declaration else node.content.binding_use);
                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = if (self.resolver.graph.isBindingTypeUnresolved(binding)) null else self.resolver.graph.bindings.items[@intFromEnum(binding)].ty,
                    .content = if (declaration) .{ .binding_declaration = binding } else .{ .binding_use = binding },
                };
            }
            const ty = if (node.ty) |value|
                try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions, null)
            else if (node.content == .string_literal)
                self.resolver.core.defaultStringLiteralType()
            else
                null;
            return .{
                .source = self.resolver.sourceFor(self.module_index, node.source),
                .ty = ty,
                .content = switch (node.content) {
                    .binding_use => |binding| .{ .binding_use = try self.instantiateBinding(binding) },
                    .binding_declaration => |binding| .{ .binding_declaration = try self.instantiateBinding(binding) },
                    .reach_directive => |reach| .{ .reach_directive = try self.instantiateReach(reach) },
                    .assignment => |assignment| .{ .assignment = .{
                        .binding = try self.instantiateBinding(assignment.binding),
                        .value = if (self.resolver.modules[self.module_index].semantic.parameterized_storage.ir.bindingType(assignment.binding)) |binding_ty|
                            try self.instantiateNodeAs(assignment.value, binding_ty)
                        else
                            try self.instantiateNode(assignment.value),
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

        fn instantiateReach(self: *InstanceContext, id: ir.ParameterizedReachId) !global_sg.GlobalReachId {
            const module = &self.resolver.modules[self.module_index];
            const storage = &module.semantic.parameterized_storage.ir;
            const local = storage.reaches.items[@intFromEnum(id)];
            const alternatives_start: u32 = @intCast(self.resolver.graph.reach_alternatives.items.len);
            for (storage.reach_alternatives.items[local.alternatives.start..][0..local.alternatives.len]) |alternative| {
                const segments_start: u32 = @intCast(self.resolver.graph.reach_segments.items.len);
                for (storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len]) |segment|
                    try self.resolver.graph.reach_segments.append(
                        self.resolver.allocator,
                        try self.resolver.graph.addString(self.resolver.allocator, module.text(segment)),
                    );
                try self.resolver.graph.reach_alternatives.append(self.resolver.allocator, .{
                    .segments = .{ .start = segments_start, .len = alternative.segments.len },
                });
            }
            const global: global_sg.GlobalReachId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.reaches.items.len)));
            try self.resolver.graph.reaches.append(self.resolver.allocator, .{
                .alternatives = .{ .start = alternatives_start, .len = local.alternatives.len },
            });
            return global;
        }

        fn instantiateStructValue(self: *InstanceContext, node: ir.ResolvedNode) !global_sg.Node {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const literal = node.content.struct_value_literal;
            const range = literal.fields;
            var values: std.ArrayList(global_sg.ValueField) = .empty;
            defer values.deinit(self.resolver.allocator);
            var fields: std.ArrayList(global_sg.Field) = .empty;
            defer fields.deinit(self.resolver.allocator);
            var complete_type = true;
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
                if (self.resolver.graph.nodes.items[@intFromEnum(value)].ty) |field_ty| {
                    try fields.append(self.resolver.allocator, .{
                        .name = name,
                        .ty = field_ty,
                        .source = self.resolver.sourceFor(self.module_index, node.source),
                    });
                } else {
                    complete_type = false;
                }
            }
            var ty: ?global_sg.GlobalTypeId = null;
            if (complete_type) {
                const field_start: u32 = @intCast(self.resolver.graph.fields.items.len);
                try self.resolver.graph.fields.appendSlice(self.resolver.allocator, fields.items);
                const structural: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.types.items.len)));
                try self.resolver.graph.types.append(self.resolver.allocator, .{ .structural = .{
                    .fields = .{ .start = field_start, .len = @intCast(fields.items.len) },
                } });
                ty = structural;
            }
            const start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, values.items);
            return .{ .source = self.resolver.sourceFor(self.module_index, node.source), .ty = ty, .content = .{
                .struct_value_literal = .{
                    .fields = .{ .start = start, .len = @intCast(values.items.len) },
                    .dispatch_prefix_positional_count = literal.dispatch_prefix_positional_count,
                },
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
                .comptime_parameter => self.resolveComptimeParameter(value),
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
                .nullable_test => self.resolveNullableTest(operands.items, value.source),
                .return_statement => self.resolveReturn(operands.items, value.source),
                .if_statement => self.resolveIf(operands.items, value.source),
                .while_statement => self.resolveWhile(operands.items, value.source),
                .match => if (operands.items.len == 1) self.resolveMatch(value, operands.items[0]) else error.InvalidParameterizedMatch,
                .address_of => self.resolveAddress(operands.items, value.source, value.detail),
                .dereference => self.resolveDereference(operands.items, value.source),
                .pointer_store => self.resolvePointerStore(operands.items, value.source),
                .move_value => self.resolveMove(operands.items, value.source),
                .error_propagation => self.resolveErrorPropagation(operands.items, value.source),
                .pipe => if (operands.items.len != 0) self.resolver.graph.nodes.items[@intFromEnum(operands.items[operands.items.len - 1])] else error.InvalidParameterizedPipe,
                .struct_value,
                .list_value,
                .choice_literal,
                .unwrap_or,
                .unwrap_or_do,
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

        fn resolveErrorPropagation(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 1) return error.InvalidParameterizedErrorPropagation;
            const errable = operands[0];
            const errable_ty = self.resolver.graph.node(errable).ty orelse return error.UntypedParameterizedErrorPropagation;
            const ok = global_types.findVariant(self.resolver.graph, errable_ty, "ok") orelse return error.InvalidParameterizedErrorPropagation;
            const err = global_types.findVariant(self.resolver.graph, errable_ty, "error") orelse return error.InvalidParameterizedErrorPropagation;
            const void_ty = try self.resolver.generics.internType(.{ .builtin = .Void });
            const ok_payload = ok.variant.payload_type orelse void_ty;
            const error_payload = err.variant.payload_type orelse void_ty;
            const function_id = self.function orelse return error.ParameterizedErrorPropagationOutsideFunction;
            const function = self.resolver.graph.functions.items[@intFromEnum(function_id)];
            if (function.output.len != 1) return error.InvalidParameterizedErrorPropagation;
            const propagated_ty = global_types.effectiveFieldType(self.resolver.graph.fields.items[function.output.start]);
            const propagated_error = global_types.findVariant(self.resolver.graph, propagated_ty, "error") orelse return error.InvalidParameterizedErrorPropagation;
            const propagated_error_payload = propagated_error.variant.payload_type orelse error_payload;
            if (!global_types.equal(self.resolver.graph, error_payload, propagated_error_payload)) return error.IncompatibleParameterizedErrorPayload;
            const ok_fields = global_types.fields(self.resolver.graph, ok_payload);
            const result_ty = if (ok_fields) |fields|
                if (fields.len == 1) global_types.effectiveFieldType(self.resolver.graph.fields.items[fields.start]) else ok_payload
            else
                ok_payload;
            const id: global_sg.GlobalErrorPropagationId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.error_propagations.items.len)));
            const empty = try self.resolver.graph.addString(self.resolver.allocator, "");
            try self.resolver.graph.error_propagations.append(self.resolver.allocator, .{
                .errable_value = errable,
                .cleanup_nodes = .{ .start = @intCast(self.resolver.graph.node_refs.items.len), .len = 0 },
                .ok_variant = ok.id,
                .ok_value_field_index = if (ok_fields) |fields| if (fields.len == 1) 0 else null else null,
                .error_variant = err.id,
                .propagated_errable_type = propagated_ty,
                .propagated_error_variant = propagated_error.id,
                .ok_payload_type = ok_payload,
                .error_payload_type = error_payload,
                .propagated_error_payload_type = propagated_error_payload,
                .diagnostic_line = 0,
                .diagnostic_column = 0,
                .diagnostic_source_line = empty,
            });
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = result_ty,
                .content = .{ .error_propagation = id },
            };
        }

        fn resolveNullableTest(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 1) return error.InvalidParameterizedNullableTest;
            const value = operands[0];
            const choice_ty = self.resolver.graph.node(value).ty orelse return error.UntypedParameterizedNullableTest;
            const some = global_types.findVariant(self.resolver.graph, choice_ty, "some") orelse return error.InvalidParameterizedNullableTest;
            const int_ty = try self.resolver.generics.internType(.{ .builtin = .Int32 });
            const bool_ty = try self.resolver.generics.internType(.{ .builtin = .Bool });
            const global_source = self.resolver.sourceFor(self.module_index, source);
            const tag: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                .source = global_source,
                .ty = int_ty,
                .content = .{ .int_literal = some.variant.value },
            });
            return .{
                .source = global_source,
                .ty = bool_ty,
                .content = .{ .comparison = .{ .operator = .equal, .left = value, .right = tag } },
            };
        }

        fn resolveComptimeParameter(self: *InstanceContext, value: ir.PendingExpression) !global_sg.Node {
            const parameter: ir.ComptimeParameterId = switch (value.detail) {
                .comptime_parameter => |id| id,
                else => return error.InvalidParameterizedComptimeParameter,
            };
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage;
            const definition = storage.comptime_parameters.items[@intFromEnum(parameter)];
            if (definition.kind != .comptime_int) return error.InvalidParameterizedComptimeParameter;
            const number = self.substitutions.ints[@intFromEnum(parameter)] orelse return error.UnboundComptimeParameter;
            const ty = if (definition.value_type) |parameterized_type|
                try self.resolver.generics.instantiateParameterizedType(self.module_index, parameterized_type, self.substitutions, null)
            else
                try self.resolver.generics.internType(.{ .builtin = .Int32 });
            return .{
                .source = self.resolver.sourceFor(self.module_index, value.source),
                .ty = ty,
                .content = .{ .int_literal = number },
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
                if (!global_types.equal(self.resolver.graph, actual, variant.variant.payload_type.?) and
                    !self.matchesPendingNullable(actual, variant.variant.payload_type.?)) return error.ParameterizedChoicePayloadMismatch;
            }
            return .{
                .source = self.resolver.sourceFor(self.module_index, value.source),
                .ty = expected,
                .content = .{ .choice_literal = .{ .choice_type = expected, .variant = variant.id, .payload = payload } },
            };
        }

        fn matchesPendingNullable(self: *InstanceContext, actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {
            // A nested generic call can return a materialized ?T while this
            // instance has just interned the corresponding nullable sugar.
            // The fixed-point pass materializes `expected` after instantiation.
            const child = switch (self.resolver.graph.types.items[@intFromEnum(expected)]) {
                .nullable => |value| value,
                else => return false,
            };
            const variants = global_types.variants(self.resolver.graph, actual) orelse return false;
            if (variants.len != 2) return false;
            const none = global_types.findVariant(self.resolver.graph, actual, "none") orelse return false;
            if (none.variant.payload_type != null) return false;
            const some = global_types.findVariant(self.resolver.graph, actual, "some") orelse return false;
            const payload = some.variant.payload_type orelse return false;
            const fields = global_types.fields(self.resolver.graph, payload) orelse return false;
            if (fields.len != 1) return false;
            const field = self.resolver.graph.fields.items[fields.start];
            return std.mem.eql(u8, self.resolver.graph.text(field.name), "value") and
                global_types.equal(self.resolver.graph, field.ty, child);
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
                const payload_binding = if (case.payload_binding) |local_binding| blk: {
                    const payload = variant.variant.payload_type orelse return error.ParameterizedMatchPayloadOnPayloadlessVariant;
                    const binding = try self.instantiateBinding(local_binding);
                    self.resolver.graph.bindings.items[@intFromEnum(binding)].ty = try self.matchBindingType(payload, case.mode);
                    _ = self.resolver.graph.reconcileBindingTypeResolution();
                    break :blk binding;
                } else null;
                const body = try self.instantiateBlock(case.body);
                const tag: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
                const int_type = try self.resolver.generics.internType(.{ .builtin = .Int32 });
                try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                    .source = self.resolver.sourceFor(self.module_index, case.source),
                    .ty = int_type,
                    .content = .{ .int_literal = variant.variant.value },
                });
                try cases.append(self.resolver.allocator, .{
                    .value = tag,
                    .variant = variant.id,
                    .body = body,
                    .payload_binding = payload_binding,
                    .payload_mode = case.mode,
                });
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

        fn resolveConstrainedStaticCall(
            self: *InstanceContext,
            reference: module_entities.ExternalRef,
            input: global_sg.GlobalNodeId,
            source: primitives.SourceRef,
        ) !?global_sg.Node {
            const abstracts = self.resolver.nested_call_context orelse return null;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage;
            for (0..self.parameterized.parameters.len) |offset| {
                const raw = self.parameterized.parameters.start + @as(u32, @intCast(offset));
                const parameter = storage.comptime_parameters.items[raw];
                const constraint_id = parameter.constraint orelse continue;
                const concrete = self.substitutions.types[raw] orelse continue;
                const constraint = storage.abstract_constraints.items[@intFromEnum(constraint_id)];
                if (try abstracts.resolveStaticRequirementCall(
                    self.module_index,
                    constraint.abstract_ref,
                    concrete,
                    reference,
                    input,
                    self.resolver.sourceFor(self.module_index, source),
                )) |node| return node;
            }
            return null;
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
            // Calls in an instantiated body can reach the instance's concrete
            // input bindings, including parameters inferred from generic args.
            const input_bindings = self.resolver.graph.functions.items[@intFromEnum(self.function.?)].input_bindings;
            const visible = try self.resolver.allocator.dupe(global_sg.GlobalBindingId, self.resolver.graph.binding_refs.items[input_bindings.start..][0..input_bindings.len]);
            defer self.resolver.allocator.free(visible);
            const nested_reach = ReachInferenceContext.fromGlobal(visible, self.function);
            const function = if (arguments.len != 0)
                self.resolver.resolveExplicitGenericFunction(
                    self.module_index,
                    module,
                    reference,
                    arguments,
                    input,
                    nested_reach,
                ) catch |err| switch (err) {
                    error.NoMatchingGenericFunction => {
                        if (self.resolver.nested_constructor_context) |context| {
                            if (self.resolver.nested_constructor_resolver) |resolve| {
                                if (try resolve(
                                    context,
                                    self.module_index,
                                    reference,
                                    arguments,
                                    input,
                                    nested_reach,
                                    self.resolver.sourceFor(self.module_index, source),
                                )) |node| return node;
                            }
                        }
                        return err;
                    },
                    else => return err,
                }
            else blk: {
                const ordinary = if (module_path == null)
                    try self.resolver.core.matchUnqualifiedFunctionByNameWithReach(self.module_index, name, input, nested_reach)
                else
                    try self.resolver.core.matchFunctionByName(self.module_index, reference, input);
                if (ordinary == .function) break :blk ordinary.function;
                break :blk self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, nested_reach) catch |err| {
                    if (self.resolver.nested_constructor_context) |context| {
                        if (self.resolver.nested_constructor_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, arguments, input, nested_reach, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
                    if (arguments.len == 0) {
                        if (try self.resolveConstrainedStaticCall(reference, input, source)) |node| return node;
                    }
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
            };
            if (!try self.resolver.core.completeCallInputFieldsWithReach(
                self.resolver.graph.functions.items[@intFromEnum(function)].input,
                input,
                nested_reach,
            )) return error.IncompleteParameterizedCallInput;
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

test "generic function monomorphization uses stable GlobalFunctionId identity" {
    try std.testing.expect(@sizeOf(global_sg.GlobalFunctionId) == 4);
    try std.testing.expect(@sizeOf(global_sg.GenericFunctionInstance) <= 16);
}

test "generic inference binds comptime integer expressions" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "generic_int") };
    defer module.deinit(allocator);
    try module.semantic.parameterized_storage.comptime_parameters.append(allocator, .{
        .name = try @import("../primitives/strings.zig").append(&module.strings, allocator, "n"),
        .kind = .comptime_int,
    });
    try module.semantic.parameterized_storage.ir.int_expressions.append(allocator, .{ .parameter = @enumFromInt(0) });
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var core: core_mod.Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &modules, .offsets = &.{} };
    var generics: generic_mod.Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &modules, .offsets = &.{}, .core = &core };
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &modules, .offsets = &.{}, .core = &core, .generics = &generics };
    var bindings = try generic_mod.Resolver.Bindings.init(allocator, 1);
    defer bindings.deinit(allocator);

    try std.testing.expect(try resolver.inferIntExpression(0, @enumFromInt(0), 7, &bindings));
    try std.testing.expectEqual(@as(?i64, 7), bindings.ints[0]);
    try std.testing.expectError(error.ConflictingGenericArgument, resolver.inferIntExpression(0, @enumFromInt(0), 8, &bindings));
}

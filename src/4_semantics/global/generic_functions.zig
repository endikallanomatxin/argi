const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const parameterized_storage = @import("../module/parameterized/storage.zig");
const ir = @import("../module/parameterized/ir.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const reach_context_mod = @import("reach_context.zig");
const errors_mod = @import("errors.zig");
const control_mod = @import("control.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const generic_mod = @import("generics.zig");
const contract_mod = @import("contracts.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");
const implementation_arguments = @import("implementation_arguments.zig");
const standard_contracts = @import("standard_contracts.zig");

pub const Stats = struct {
    instances: u32 = 0,
    calls: u32 = 0,
    nodes: u32 = 0,
};

pub const SelectionProfile = struct {
    implicit_calls: u64 = 0,
    implicit_candidates: u64 = 0,
    implicit_prefilter_inference_ns: u64 = 0,
    implicit_constraints_ns: u64 = 0,
    implicit_applicability_ns: u64 = 0,
    implicit_argument_materialization_ns: u64 = 0,
    implicit_final_instantiation_ns: u64 = 0,
    explicit_calls: u64 = 0,
    explicit_candidates: u64 = 0,
    explicit_candidates_reaching_argument_materialization: u64 = 0,
    explicit_candidates_matching: u64 = 0,
    explicit_argument_materializations_discarded: u64 = 0,
    explicit_prefilter_inference_ns: u64 = 0,
    explicit_constraints_ns: u64 = 0,
    explicit_applicability_ns: u64 = 0,
    explicit_argument_materialization_ns: u64 = 0,
    explicit_final_instantiation_ns: u64 = 0,
};

const ReachInferenceContext = reach_context_mod.Context;

pub const ConstraintFailure = struct {
    function: global_sg.GlobalDeclId,
    contract_decl: global_sg.GlobalDeclId,
    actual: global_sg.GlobalTypeId,
    parameter_name: []const u8,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    nested_call_context: ?*contract_mod.Resolver = null,
    nested_call_resolver: ?*const fn (*contract_mod.Resolver, usize, module_entities.ExternalRef, global_sg.GlobalNodeId, primitives.SourceRef, ReachInferenceContext) anyerror!?global_sg.Node = null,
    nested_constructor_context: ?*anyopaque = null,
    nested_constructor_resolver: ?*const fn (*anyopaque, usize, module_entities.ExternalRef, primitives.Range(global_sg.GlobalGenericArgId), global_sg.GlobalNodeId, ReachInferenceContext, primitives.SourceRef) anyerror!?global_sg.Node = null,
    ownership_context: ?*anyopaque = null,
    register_defer: ?*const fn (*anyopaque, global_sg.GlobalNodeId, global_sg.GlobalNodeId) anyerror!void = null,
    ownership_checkpoint: ?*const fn (*anyopaque) [2]usize = null,
    rollback_ownership: ?*const fn (*anyopaque, [2]usize) void = null,
    constraint_diagnostics: ?*std.ArrayList(ConstraintFailure) = null,
    failed_constraint: ?struct {
        contract_decl: global_sg.GlobalDeclId,
        actual: global_sg.GlobalTypeId,
        parameter_name: []const u8,
    } = null,
    stats: Stats = .{},
    profile_io: ?std.Io = null,
    selection_profile: SelectionProfile = .{},
    profile_constraints_ns: i96 = 0,
    profile_source_selection_ns: i96 = 0,
    profile_source_completion_ns: i96 = 0,
    profile_instantiate_ns: i96 = 0,
    profile_instantiate_calls: u64 = 0,
    profile_instantiate_existing: u64 = 0,
    profile_instantiate_lookup_ns: i96 = 0,
    profile_instantiate_body_ns: i96 = 0,
    profile_instance_context_init_ns: i96 = 0,

    pub const SideEffectCheckpoint = struct {
        ownership: ?[2]usize = null,
        reached_calls: usize = 0,
        reached_signatures: usize = 0,
        contracts: ?contract_mod.Resolver.ResolutionCheckpoint = null,
        comptime_failure: ?generic_mod.ComptimeFailure = null,
    };

    pub fn checkpointSideEffects(self: *const Resolver) SideEffectCheckpoint {
        var saved: SideEffectCheckpoint = .{ .comptime_failure = self.generics.comptime_failure, .reached_calls = self.core.reached_calls.items.len, .reached_signatures = self.core.reached_signature_changes.items.len };
        if (self.ownership_context) |context| {
            if (self.ownership_checkpoint) |checkpoint|
                saved.ownership = checkpoint(context);
        }
        if (self.nested_call_context) |contracts|
            saved.contracts = contracts.checkpointResolution();
        return saved;
    }

    pub fn rollbackSideEffects(self: *Resolver, saved: SideEffectCheckpoint) void {
        self.generics.comptime_failure = saved.comptime_failure;
        self.core.rollbackReachedCalls(saved.reached_calls);
        self.core.rollback_reached_signatures(saved.reached_signatures);
        if (saved.contracts) |checkpoint|
            if (self.nested_call_context) |contracts|
                contracts.rollbackResolution(checkpoint);
        if (saved.ownership) |checkpoint| {
            const context = self.ownership_context orelse return;
            const rollback = self.rollback_ownership orelse return;
            rollback(context, checkpoint);
        }
    }

    fn profileTimestamp(self: *const Resolver) i96 {
        if (self.profile_io) |io| return std.Io.Timestamp.now(io, .boot).nanoseconds;
        return 0;
    }

    fn addProfileTime(self: *Resolver, start: i96, elapsed: *u64) void {
        if (self.profile_io != null) elapsed.* += @intCast(self.profileTimestamp() - start);
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_call => |value| try self.resolveModuleGenericCall(module_index, module, o, value),
            else => .not_applicable,
        };
    }

    /// Operator sugar selects scoped evidence from an operand record. Reached
    /// capability fields participate in inference before materializing the call.
    pub fn resolveContractArithmetic(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const identity = standard_contracts.arithmeticOperation(value.operator);
        const reach = ReachInferenceContext.fromModule(module, o, value.visible_bindings, value.owner_function);
        const assumed = if (value.assumed_arguments) |local| globalizer.globalNode(o, local) else null;
        const operands = [_]global_sg.GlobalNodeId{ globalizer.globalNode(o, value.left), globalizer.globalNode(o, value.right) };
        self.core.contextualizeArithmeticPair(&operands);
        const call = try self.makeContractOperator(module_index, identity.contract, identity.operation, &operands, reach, assumed) orelse return .deferred;
        self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = self.lowerSelectedScalarArithmetic(call, value.operator, &operands);
        return .resolved;
    }

    /// Trusted scalar implementations preserve constant-expression lowering,
    /// after scoped evidence has selected the operation. Other implementations
    /// remain ordinary calls, even when their participants are scalar types.
    const ScalarPrimitive = union(enum) { arithmetic: primitives.BinaryOperator, equality };

    fn isSelectedScalarPrimitive(self: *Resolver, call: global_sg.Node, operation: ScalarPrimitive) bool {
        if (call.content != .function_call or call.content.function_call.contract_operation == null) return false;
        const declaration = self.graph.declaration(self.graph.function(call.content.function_call.callee).declaration);
        const function = self.graph.function(call.content.function_call.callee);
        const file = self.graph.files.items[declaration.source.file_index];
        const module = self.graph.modules.items[@intFromEnum(file.module)];
        if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(self.graph.text(file.path)), "scalar_arithmetic.rg")) return false;
        // Prove the exact primitive body before eliding the call. Adding checks,
        // capabilities or other effects in core must retain the ordinary call.
        if (function.input.len != 1 or function.output.len != 1 or function.input_bindings.len != 1 or function.output_bindings.len != 1) return false;
        const body = self.graph.blocks.items[@intFromEnum(function.body orelse return false)];
        if (body.nodes.len != 1) return false;
        const statement = self.graph.node(self.graph.node_refs.items[body.nodes.start]);
        if (statement.content != .assignment or statement.content.assignment.binding != self.graph.binding_refs.items[function.output_bindings.start]) return false;
        const expression = self.graph.node(statement.content.assignment.value);
        const primitive_operands: [2]global_sg.GlobalNodeId = switch (operation) {
            .arithmetic => |operator| if (expression.content == .binary_operation and expression.content.binary_operation.operator == operator)
                .{ expression.content.binary_operation.left, expression.content.binary_operation.right }
            else
                return false,
            .equality => if (expression.content == .comparison and expression.content.comparison.operator == .equal)
                .{ expression.content.comparison.left, expression.content.comparison.right }
            else
                return false,
        };
        for (primitive_operands, 0..) |operand, position| {
            const projection = self.graph.node(operand).content;
            if (projection != .struct_field_access or projection.struct_field_access.field_index != position) return false;
            const record = self.graph.node(projection.struct_field_access.value).content;
            if (record != .binding_use or record.binding_use != self.graph.binding_refs.items[function.input_bindings.start]) return false;
        }
        return true;
    }

    fn lowerSelectedScalarArithmetic(self: *Resolver, call: global_sg.Node, operator: primitives.BinaryOperator, operands: []const global_sg.GlobalNodeId) global_sg.Node {
        if (!self.isSelectedScalarPrimitive(call, .{ .arithmetic = operator })) return call;
        const left = self.graph.node(operands[0]).ty orelse return call;
        const right = self.graph.node(operands[1]).ty orelse return call;
        if (!self.core.isScalarArithmeticRepresentation(left, right) or !global_types.equal(self.graph, call.ty.?, left)) return call;
        return .{ .source = call.source, .ty = call.ty, .content = .{ .binary_operation = .{ .operator = operator, .left = operands[0], .right = operands[1] } } };
    }

    fn lowerSelectedScalarEquality(self: *Resolver, call: global_sg.Node, operands: []const global_sg.GlobalNodeId) global_sg.Node {
        if (!self.isSelectedScalarPrimitive(call, .equality)) return call;
        const left = self.graph.node(operands[0]).ty orelse return call;
        const right = self.graph.node(operands[1]).ty orelse return call;
        if (!self.core.isBuiltinComparable(left, right)) return call;
        return .{ .source = call.source, .ty = call.ty, .content = .{ .comparison = .{ .operator = .equal, .left = operands[0], .right = operands[1] } } };
    }

    fn makeContractOperator(self: *Resolver, module_index: usize, contract_name: []const u8, operation_name: []const u8, operands: []const global_sg.GlobalNodeId, reach: ReachInferenceContext, assumed: ?global_sg.GlobalNodeId) anyerror!?global_sg.Node {
        for (operands) |operand| {
            const ty = self.graph.node(operand).ty orelse return null;
            if (self.graph.isTypeUnresolved(ty)) return null;
        }
        const declaration = standard_contracts.standardDeclaration(self.graph, contract_name) orelse return null;
        const contracts = self.nested_call_context orelse return null;
        const checkpoint = self.graph.checkpoint();
        const side_effects = self.checkpointSideEffects();
        var committed = false;
        var failure: ?contract_mod.ParticipantConformanceFailure = null;
        defer if (!committed) {
            self.graph.rollback(checkpoint);
            self.rollbackSideEffects(side_effects);
            if (failure) |value| contracts.participant_conformance_failure = value;
        };
        const input = try self.makePositionalInput(operands);
        // Operand transfer is explicit. No distinguished receiver is borrowed
        // automatically, and Args completion handles all auxiliary capabilities.
        self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.dispatch_prefix_positional_count = 0;
        if (reach == .global) self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.assumed_fields = reach.global.assumed_fields;
        if (assumed) |node| self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.assumed_fields = self.graph.node(node).content.struct_value_literal.assumed_fields;
        var resolver: implementation_arguments.Resolver = .{ .graph = self.graph, .modules = self.modules, .core = self.core, .generics = self.generics, .functions = self, .contracts = contracts };
        const selected = switch (try resolver.infer(declaration, &.{ .inferred, .inferred }, input, reach)) {
            .selected => |selection| selection,
            .ambiguous => {
                failure = .{ .source = self.graph.node(operands[0]).source, .contract_name = contract_name, .operation = operation_name, .reason = standard_contracts.operatorMessage(contract_name, "ambiguous ", " argument shapes; qualify the contract with an explicit Args type") };
                return error.InvalidContractOperator;
            },
            .missing_reach => {
                failure = .{ .source = self.graph.node(operands[0]).source, .contract_name = contract_name, .operation = operation_name, .reason = standard_contracts.operatorMessage(contract_name, "", ".Args requires a reachable capability or an explicitly qualified operation call") };
                return error.InvalidContractOperator;
            },
            else => return null,
        };
        defer self.allocator.free(selected.participants);
        const args_type = selected.participants[2];
        _ = try self.generics.ensureGenericInstance(args_type);
        switch (try resolver.complete(args_type, input, reach)) {
            .completed => {},
            .incompatible_default => {
                failure = .{ .source = self.graph.node(operands[0]).source, .contract_name = contract_name, .operation = operation_name, .reason = "default value is incompatible with its selected operator Args field type" };
                return error.InvalidContractOperator;
            },
            else => return null,
        }
        const arguments_start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (selected.participants) |participant| try self.graph.generic_arguments.append(self.allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = participant } });
        const contract = try self.generics.internType(.{ .generic = .{ .base = declaration, .arguments = .{ .start = arguments_start, .len = 3 } } });
        const wrapped = try self.makePositionalInput(&.{input});
        const call = try contracts.makeScopedOperationCall(module_index, contract, operation_name, wrapped, reach, self.graph.node(operands[0]).source) orelse return null;
        if (call.ty == null or self.graph.isTypeUnresolved(call.ty.?)) return null;
        committed = true;
        self.stats.calls += 1;
        return call;
    }

    pub fn resolveContractEquality(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        if (value.operator != .equal and value.operator != .not_equal) return .not_applicable;
        const reach = ReachInferenceContext.fromModule(module, o, value.visible_bindings, value.owner_function);
        const assumed = if (value.assumed_arguments) |local| globalizer.globalNode(o, local) else null;
        const operands = [_]global_sg.GlobalNodeId{ globalizer.globalNode(o, value.left), globalizer.globalNode(o, value.right) };
        self.core.contextualizeArithmeticPair(&operands);
        const call = try self.makeContractOperator(module_index, "Equal", "equal", &operands, reach, assumed) orelse return .deferred;
        self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = try self.equalityResult(self.lowerSelectedScalarEquality(call, &operands), value.operator);
        return .resolved;
    }

    fn equalityResult(self: *Resolver, call: global_sg.Node, operator: primitives.ComparisonOperator) !global_sg.Node {
        if (operator == .equal) return call;
        const value: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, call);
        const false_id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        const boolean = try self.generics.internType(.{ .builtin = .Bool });
        try self.graph.nodes.append(self.allocator, .{ .source = call.source, .ty = boolean, .content = .{ .bool_literal = false } });
        return .{ .source = call.source, .ty = boolean, .content = .{ .comparison = .{ .operator = .equal, .left = value, .right = false_id } } };
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

    fn resolveModuleGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        const arguments = try self.generics.resolveCallArguments(module_index, reference);
        const name = module.text(reference.name);
        const input = globalizer.globalNode(o, value.input);
        if (reference.module_path == null and arguments == null and primitives.integerRange(primitives.builtinTypeNamedForTarget(name, self.graph.target.stdTarget()) orelse .Void, self.graph.target.stdTarget()) != null) {
            const literal = self.graph.node(input).content;
            if (literal == .struct_value_literal and literal.struct_value_literal.fields.len == 1) {
                const field = self.graph.value_fields.items[literal.struct_value_literal.fields.start];
                if (std.mem.eql(u8, self.graph.text(field.name), "value")) {
                    self.generics.comptime_failure = .{ .source = self.sourceFor(module_index, reference.source), .reason = "numeric type-call conversions are unsupported; use convert#(.to: Target)(.value = source)" };
                    return error.InvalidNumericTypeCall;
                }
            }
        }
        if (reference.module_path == null and std.mem.eql(u8, name, "_zeroed")) {
            const node = (try self.core.makeZeroed(input, self.sourceFor(module_index, reference.source))) orelse return .deferred;
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
        if (reference.module_path == null and std.mem.eql(u8, name, "alignment_of")) {
            const node = (try self.makeAlignmentOf(input, self.sourceFor(module_index, reference.source))) orelse return .deferred;
            self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] = node;
            self.stats.calls += 1;
            return .resolved;
        }
        const reach: ReachInferenceContext = ReachInferenceContext.fromModule(module, o, value.visible_bindings, value.owner_function);
        const function = blk: {
            const started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            defer {
                if (self.profile_io) |io| self.profile_source_selection_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - started;
            }
            break :blk if (arguments) |args|
                self.resolveExplicitGenericFunction(module_index, module, reference, args, input, reach) catch |err| switch (err) {
                    error.NoMatchingGenericFunction => return .not_applicable,
                    error.DeferredGenericFunction => return .deferred,
                    error.AmbiguousGenericFunction => return .invalid,
                    error.InvalidGenericCallArguments, error.InvalidNumericTypeCall, error.InvalidAssociatedTypeProjection, error.InvalidArrayLength, error.ComptimeIntegerOverflow, error.ComptimeDivisionByZero => return err,
                    else => return .deferred,
                }
            else
                self.resolveImplicitGenericFunction(module_index, module, reference, input, reach) catch |err| switch (err) {
                    error.NoMatchingGenericFunction => return .not_applicable,
                    error.DeferredGenericFunction => return .deferred,
                    error.AmbiguousGenericFunction => return .invalid,
                    error.InvalidGenericCallArguments, error.InvalidNumericTypeCall, error.InvalidAssociatedTypeProjection, error.InvalidArrayLength, error.ComptimeIntegerOverflow, error.ComptimeDivisionByZero => return err,
                    error.ConflictingGenericArgument => return err,
                    else => return .deferred,
                };
        };
        const completion_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        const completed = try self.core.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function)].input, input, reach);
        if (self.profile_io) |io| self.profile_source_completion_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - completion_started;
        if (!completed)
            return .deferred;
        const output_ty = try self.core.functionOutputType(function);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(module_index, reference.source),
            .ty = output_ty,
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
        if (self.profile_io != null) self.selection_profile.explicit_calls += 1;
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        const name = module.text(reference.name);
        var best: ?global_sg.GlobalDeclId = null;
        var best_arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = 0, .len = 0 };
        var tied = false;
        var saw_deferred = false;
        var argument_failure: ?anyerror = null;
        var saw_valid_arguments = false;
        const function_candidates = try self.graph.parameterizedFunctionsNamed(self.allocator, self.modules, name);
        for (function_candidates) |candidate| {
            if (self.profile_io != null) self.selection_profile.explicit_candidates += 1;
            var phase_start = self.profileTimestamp();
            var prefilter_active = true;
            var applicability_start: i96 = 0;
            var applicability_active = false;
            defer {
                if (prefilter_active) self.addProfileTime(phase_start, &self.selection_profile.explicit_prefilter_inference_ns);
                if (applicability_active) self.addProfileTime(applicability_start, &self.selection_profile.explicit_applicability_ns);
            }
            const candidate_index: usize = candidate.module_index;
            const candidate_module = &self.modules[candidate_index];
            const parameterized = candidate_module.semantic.parameterized_storage.parameterized_functions.items[candidate.function_index];
            const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
            if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, candidate_module.semantic.parameterized_storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch |err| {
                if (err == error.OutOfMemory) return err;
                argument_failure = err;
                continue;
            };
            saw_valid_arguments = true;
            const input_inferred = self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings) catch |err| switch (err) {
                error.ConflictingGenericArgument => continue,
                else => return err,
            };
            if (!input_inferred) continue;
            if (reach_context) |context|
                if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
            self.addProfileTime(phase_start, &self.selection_profile.explicit_prefilter_inference_ns);
            prefilter_active = false;
            phase_start = self.profileTimestamp();
            const constraints_ok = try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings);
            self.addProfileTime(phase_start, &self.selection_profile.explicit_constraints_ns);
            if (!constraints_ok) {
                try self.recordConstraintFailure(candidate_index, declaration, parameterized.input, &bindings, input);
                continue;
            }
            phase_start = self.profileTimestamp();
            if (self.profile_io != null)
                self.selection_profile.explicit_candidates_reaching_argument_materialization += 1;
            const complete_arguments = self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| switch (err) {
                error.MissingGenericArgument => continue,
                else => return err,
            };
            self.addProfileTime(phase_start, &self.selection_profile.explicit_argument_materialization_ns);
            phase_start = self.profileTimestamp();
            applicability_start = phase_start;
            applicability_active = true;
            switch (self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input)) {
                .no_match => {
                    if (self.profile_io != null) self.selection_profile.explicit_argument_materializations_discarded += 1;
                    continue;
                },
                .deferred => {
                    saw_deferred = true;
                    if (self.profile_io != null) self.selection_profile.explicit_argument_materializations_discarded += 1;
                    continue;
                },
                .score => {},
            }
            if (self.profile_io != null) self.selection_profile.explicit_candidates_matching += 1;
            self.addProfileTime(applicability_start, &self.selection_profile.explicit_applicability_ns);
            applicability_active = false;
            if (best == null) {
                best = declaration;
                best_arguments = complete_arguments;
            } else if (declaration != best.?) {
                tied = true;
                if (self.profile_io != null) self.selection_profile.explicit_argument_materializations_discarded += 1;
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        if (saw_deferred) return error.DeferredGenericFunction;
        const declaration = best orelse {
            if (argument_failure) |failure| if (!saw_deferred and !saw_valid_arguments) {
                const reason = switch (failure) {
                    error.UnknownGenericArgument => "unknown compile-time argument",
                    error.DuplicateGenericArgument => "duplicate compile-time argument",
                    error.TooManyGenericArguments => "too many compile-time arguments",
                    error.GenericArgumentKindMismatch => "compile-time argument kind does not match its parameter",
                    else => return failure,
                };
                self.generics.comptime_failure = .{
                    .source = self.sourceFor(current_module, reference.source),
                    .reason = try std.fmt.allocPrint(self.allocator, "{s} in call to '{s}'", .{ reason, name }),
                };
                return error.InvalidGenericCallArguments;
            };
            return if (saw_deferred) error.DeferredGenericFunction else error.NoMatchingGenericFunction;
        };
        const instantiate_start = self.profileTimestamp();
        const result = try self.instantiate(declaration, best_arguments);
        self.addProfileTime(instantiate_start, &self.selection_profile.explicit_final_instantiation_ns);
        return result;
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
            const value = self.core.callArgumentNamed(literal, expected_position, module.text(field.name)) orelse continue;
            // Reject unrelated nominal references before instantiating their
            // constraints; an inapplicable identity must not emit type diagnostics.
            if (self.graph.node(value).ty) |actual|
                if (self.definiteNominalReferenceMismatch(module_index, field.ty, actual)) return false;
            if (allow_contextual_concrete) {
                if (self.contextualParameterizedLiteralFits(module_index, field.ty, bindings, value)) continue;
            }
            const actual = self.graph.node(value).ty orelse return false;
            if (!try self.inferInputType(module_index, field.ty, actual, bindings)) return false;
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
            if (self.core.callArgumentNamed(literal, expected_position, candidate_module.text(field.name)) != null) continue;

            const default_id = field.default_value orelse continue;
            // A supplied input wins. Missing inputs may bind a direct parameter
            // from a default whose type is known without executing its body.
            if (storage.types.items[@intFromEnum(field.ty)] == .parameter) {
                const parameter = storage.types.items[@intFromEnum(field.ty)].parameter;
                if (bindings.types[@intFromEnum(parameter)] == null) {
                    if (try self.knownDefaultType(module_index, default_id, bindings)) |ty|
                        bindings.types[@intFromEnum(parameter)] = ty;
                }
            }
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
                        current_ty = step.hit.field.ty;
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

    /// Read a fixed declaration signature, never expected result context or a
    /// speculative default body. Overloaded/default-dependent calls stay deferred.
    fn knownDefaultType(self: *Resolver, module_index: usize, node_id: ir.ParameterizedNodeId, bindings: *generic_mod.Resolver.Bindings) !?global_sg.GlobalTypeId {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        switch (storage.nodes.items[@intFromEnum(node_id)]) {
            .resolved => |node| {
                if (node.content == .reach_directive) return null;
                const ty = node.ty orelse return null;
                return self.generics.instantiateParameterizedType(module_index, ty, bindings) catch |err| switch (err) {
                    error.OutOfMemory => return err,
                    else => null,
                };
            },
            .pending => |pending_id| {
                const pending = storage.pending.items[@intFromEnum(pending_id)];
                if (pending != .resolve_expression) return null;
                const expression = pending.resolve_expression;
                if (expression.kind != .generic_call or expression.module_path != null or expression.contract_type != null or expression.generic_arguments.len != 0 or expression.operands.len != 1) return null;
                const input_id = storage.node_refs.items[expression.operands.start];
                const input = storage.nodes.items[@intFromEnum(input_id)];
                if (input != .resolved or input.resolved.content != .struct_value_literal or input.resolved.content.struct_value_literal.fields.len != 0) return null;
                const name = module.text(expression.name orelse return null);
                var selected: ?global_sg.GlobalTypeId = null;
                for (try self.graph.functionsNamed(self.allocator, name)) |function_id| {
                    const function = self.graph.function(function_id);
                    if (@intFromEnum(self.graph.moduleForDeclaration(function.declaration).?) != module_index) continue;
                    if (selected != null or function.flags.is_generic_instantiation or function.flags.is_once or function.input.len != 0 or function.output.len != 1) return null;
                    const ty = self.graph.fields.items[function.output.start].ty;
                    if (self.graph.isTypeUnresolved(ty)) return null;
                    selected = ty;
                }
                return selected;
            },
        }
    }

    pub fn inferArgumentRecordBindings(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        context: ReachInferenceContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        if (!try self.inferBindingsFromInputFields(module_index, pattern, input, bindings, 0, true)) return false;
        return self.inferBindingsFromReachDefaultFields(module_index, pattern, input, bindings, context, 0);
    }

    fn inferAndValidateConstraints(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        self.failed_constraint = null;
        const contracts = self.nested_call_context orelse return true;
        const storage = &self.modules[module_index].semantic.parameterized_storage;

        var made_progress = true;
        while (made_progress) {
            made_progress = false;
            var failed = false;
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
                const constraint_ok = try contracts.inferConstraintBindings(module_index, constraint_id, concrete, bindings);

                if (!constraint_ok) {
                    if (self.constraint_diagnostics != null and
                        try contracts.constraintArgumentsKnown(module_index, constraint_id, bindings)) self.failed_constraint = .{
                        .contract_decl = try contracts.constraintDeclaration(module_index, constraint_id),
                        .actual = concrete,
                        .parameter_name = self.modules[module_index].text(parameter.name),
                    };
                    failed = true;
                }
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
            if (!made_progress and failed) return false;
        }

        // Every bound constraint was checked in the last no-progress round.
        // This pass only needs to reject constraints left without a binding.
        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            if (parameter.constraint == null) continue;
            if (parameter.kind != .type) return false;
            if (bindings.types[raw] == null) return false;
        }
        self.failed_constraint = null;
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

    pub fn resolveOperationIdentity(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef) !?global_sg.Node {
        return self.resolveOperationIdentityFiltered(module_index, name, input, reach, source, null);
    }

    pub fn resolveOperationIdentityFiltered(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef, module_filter: ?global_sg.GlobalModuleId) !?global_sg.Node {
        const contracts = self.nested_call_context orelse return null;
        var candidates = try contracts.operationCandidatesFiltered(module_index, name, input, reach, module_filter);
        defer candidates.deinit(self.allocator);
        if (candidates.failure) |failure| {
            contracts.participant_conformance_failure = failure;
            return error.InvalidContractConformance;
        }
        const ordinary = try self.core.matchFunctionNamedWithReach(module_index, name, module_filter, input, reach);
        if (candidates.items.items.len == 0) {
            if (ordinary == .function) {
                const generic = try self.implicitOrdinaryApplicableFiltered(module_index, name, input, reach, module_filter);
                if (generic == .ambiguous or (generic == .applicable and generic.applicable != self.graph.functions.items[@intFromEnum(ordinary.function)].declaration)) {
                    contracts.participant_conformance_failure = .{ .source = source, .contract_name = name, .operation = name, .reason = "multiple applicable operation identities; qualify the function explicitly" };
                    return error.AmbiguousOperationIdentity;
                }
                if (generic == .deferred) return error.DeferredOperationIdentity;
            }
            return null;
        }
        const generic = try self.implicitOrdinaryApplicableFiltered(module_index, name, input, reach, module_filter);
        if (candidates.items.items.len > 1 or ordinary == .function or ordinary == .ambiguous or generic == .applicable or generic == .ambiguous) {
            contracts.participant_conformance_failure = .{ .source = source, .contract_name = name, .operation = name, .reason = "multiple applicable operation identities; qualify the contract operation explicitly" };
            return error.AmbiguousOperationIdentity;
        }
        if (candidates.deferred or ordinary == .deferred or generic == .deferred) return error.DeferredOperationIdentity;
        return contracts.callOperationCandidate(module_index, candidates.items.items[0], name, input, reach, source);
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

    const ImplicitGenericSelection = struct {
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    };

    fn resolveImplicitGenericFunctionFiltered(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input: global_sg.GlobalNodeId,
        reach: ?ReachInferenceContext,
        ambiguity_candidates: ?*std.ArrayList(global_sg.GlobalDeclId),
    ) !global_sg.GlobalFunctionId {
        const selected = try self.selectImplicitGenericFunctionFiltered(current_module, name, module_filter, input, reach, ambiguity_candidates);
        const started = self.profileTimestamp();
        const result = try self.instantiate(selected.declaration, selected.arguments);
        self.addProfileTime(started, &self.selection_profile.implicit_final_instantiation_ns);
        return result;
    }

    pub const OrdinaryApplicability = union(enum) {
        applicable: global_sg.GlobalDeclId,
        ambiguous,
        missing,
        deferred,
    };

    /// Identity lookup checks generic applicability without instantiating a body.
    /// The same selector supplies the arguments used by ordinary resolution.
    pub fn implicitOrdinaryApplicable(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext) !OrdinaryApplicability {
        return self.implicitOrdinaryApplicableFiltered(module_index, name, input, reach, null);
    }

    fn implicitOrdinaryApplicableFiltered(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, module_filter: ?global_sg.GlobalModuleId) !OrdinaryApplicability {
        const checkpoint = self.graph.checkpoint();
        const side_effects = self.checkpointSideEffects();
        const failed = self.failed_constraint;
        const argument_failure = self.generics.argument_failure;
        defer {
            self.graph.rollback(checkpoint);
            self.rollbackSideEffects(side_effects);
            self.failed_constraint = failed;
            self.generics.argument_failure = argument_failure;
        }
        const selected = self.selectImplicitGenericFunctionFiltered(module_index, name, module_filter, input, reach, null) catch |err| {
            return switch (err) {
                error.OutOfMemory => err,
                error.DeferredGenericFunction => .deferred,
                error.AmbiguousGenericFunction => .ambiguous,
                else => .missing,
            };
        };
        return .{ .applicable = selected.declaration };
    }

    fn selectImplicitGenericFunctionFiltered(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input: global_sg.GlobalNodeId,
        reach_context: ?ReachInferenceContext,
        ambiguity_candidates: ?*std.ArrayList(global_sg.GlobalDeclId),
    ) !ImplicitGenericSelection {
        if (self.profile_io != null) self.selection_profile.implicit_calls += 1;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return error.MissingGenericInputType,
        };
        var best: ?global_sg.GlobalDeclId = null;
        var best_arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = 0, .len = 0 };
        var tied = false;
        var saw_deferred = false;
        var conflicting_candidates: usize = 0;
        var candidate_count: usize = 0;
        // Candidate inference is synchronous. Reuse its scratch bindings
        // across candidates, resetting them before each independent match.
        var binding_types: std.ArrayList(?global_sg.GlobalTypeId) = .empty;
        defer binding_types.deinit(self.allocator);
        var binding_ints: std.ArrayList(?i64) = .empty;
        defer binding_ints.deinit(self.allocator);
        const function_candidates = try self.graph.parameterizedFunctionsNamed(self.allocator, self.modules, name);
        for (function_candidates) |candidate| {
            if (self.profile_io != null) self.selection_profile.implicit_candidates += 1;
            var phase_start = self.profileTimestamp();
            var prefilter_active = true;
            var applicability_start: i96 = 0;
            var applicability_active = false;
            defer {
                if (prefilter_active) self.addProfileTime(phase_start, &self.selection_profile.implicit_prefilter_inference_ns);
                if (applicability_active) self.addProfileTime(applicability_start, &self.selection_profile.implicit_applicability_ns);
            }
            const candidate_index: usize = candidate.module_index;
            const candidate_module = &self.modules[candidate_index];
            const parameterized = candidate_module.semantic.parameterized_storage.parameterized_functions.items[candidate.function_index];
            const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
            if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
            candidate_count += 1;
            const parameter_count = candidate_module.semantic.parameterized_storage.comptime_parameters.items.len;
            try binding_types.resize(self.allocator, parameter_count);
            try binding_ints.resize(self.allocator, parameter_count);
            @memset(binding_types.items, null);
            @memset(binding_ints.items, null);
            var bindings: generic_mod.Resolver.Bindings = .{
                .types = binding_types.items,
                .ints = binding_ints.items,
            };
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
                if (self.core.callArgumentNamed(literal, position, candidate_module.text(field.name))) |supplied| {
                    if (self.graph.node(supplied).ty) |actual| {
                        if (self.definiteNominalReferenceMismatch(candidate_index, field.ty, actual)) {
                            matches = false;
                            break;
                        }
                    }
                    // Earlier typed inputs may determine a generic scalar.
                    // A literal then supplies context-compatible data, rather
                    // than conflicting evidence from its default numeric type.
                    if (self.contextualParameterizedLiteralFits(candidate_index, field.ty, &bindings, supplied)) continue;
                    const actual = self.graph.node(supplied).ty orelse {
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
                }
                if (!matches) break;
            }
            if (!matches) {
                if (candidate_deferred) saw_deferred = true;
                continue;
            }
            if (reach_context) |context|
                if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
            self.addProfileTime(phase_start, &self.selection_profile.implicit_prefilter_inference_ns);
            prefilter_active = false;
            const constraints_start = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            const constraints_ok = try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings);
            if (self.profile_io) |io| {
                const elapsed: u64 = @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - constraints_start);
                self.profile_constraints_ns += elapsed;
                self.selection_profile.implicit_constraints_ns += elapsed;
            }
            if (!constraints_ok) {
                try self.recordConstraintFailure(candidate_index, declaration, parameterized.input, &bindings, input);
                continue;
            }
            var arguments_complete = true;
            for (parameterized.parameters.start..parameterized.parameters.start + parameterized.parameters.len) |raw| {
                const parameter = candidate_module.semantic.parameterized_storage.comptime_parameters.items[raw];
                if (switch (parameter.kind) {
                    .type => bindings.types[raw] == null,
                    .comptime_int => bindings.ints[raw] == null,
                }) {
                    arguments_complete = false;
                    break;
                }
            }
            if (!arguments_complete) continue;
            phase_start = self.profileTimestamp();
            applicability_start = phase_start;
            applicability_active = true;
            switch (self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input)) {
                .no_match => continue,
                .deferred => {
                    saw_deferred = true;
                    continue;
                },
                .score => {},
            }
            self.addProfileTime(applicability_start, &self.selection_profile.implicit_applicability_ns);
            applicability_active = false;
            if (best == null) {
                phase_start = self.profileTimestamp();
                // Only one applicable identity needs durable arguments.
                // Failed and deferred probes leave no argument tail.
                var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;
                defer arguments.deinit(self.allocator);
                for (parameterized.parameters.start..parameterized.parameters.start + parameterized.parameters.len) |raw| {
                    const parameter = candidate_module.semantic.parameterized_storage.comptime_parameters.items[raw];
                    const argument: global_sg.GenericArgument.Value = switch (parameter.kind) {
                        .type => .{ .type = bindings.types[raw].? },
                        .comptime_int => .{ .comptime_int = bindings.ints[raw].? },
                    };
                    try arguments.append(self.allocator, .{ .name = try self.graph.addString(self.allocator, candidate_module.text(parameter.name)), .value = argument });
                }
                const range: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = @intCast(self.graph.generic_arguments.items.len), .len = @intCast(arguments.items.len) };
                try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);
                self.addProfileTime(phase_start, &self.selection_profile.implicit_argument_materialization_ns);
                best = declaration;
                best_arguments = range;
                if (ambiguity_candidates) |candidates| {
                    candidates.clearRetainingCapacity();
                    try candidates.append(self.allocator, declaration);
                }
            } else if (declaration != best.?) {
                tied = true;
                if (ambiguity_candidates) |candidates|
                    try candidates.append(self.allocator, declaration);
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        if (saw_deferred) return error.DeferredGenericFunction;
        const declaration = best orelse return if (saw_deferred) error.DeferredGenericFunction else if (candidate_count == 1 and conflicting_candidates == 1) error.ConflictingGenericArgument else error.NoMatchingGenericFunction;
        return .{ .declaration = declaration, .arguments = best_arguments };
    }

    fn contextualParameterizedLiteralFits(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        bindings: *generic_mod.Resolver.Bindings,
        value: global_sg.GlobalNodeId,
    ) bool {
        // Context probes can materialize constrained nominal types even before
        // the actual argument is resolved. Keep those types speculative: the
        // final constraint pass must see only selected or source-written types.
        const checkpoint = self.graph.checkpoint();
        const side_effect_checkpoint = self.checkpointSideEffects();
        const saved_stats = self.generics.stats;
        defer {
            self.graph.rollback(checkpoint);
            self.rollbackSideEffects(side_effect_checkpoint);
            self.generics.stats = saved_stats;
        }
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch return false;
        return self.core.contextualLiteralFits(value, expected);
    }

    fn definiteNominalReferenceMismatch(
        self: *const Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        actual: global_sg.GlobalTypeId,
    ) bool {
        if (self.graph.isTypeUnresolved(actual)) return false;
        const actual_pointer = switch (self.graph.types.items[@intFromEnum(actual)]) {
            .pointer => |pointer| pointer,
            else => return false,
        };
        if (self.graph.isTypeUnresolved(actual_pointer.child)) return false;
        const actual_base = switch (self.graph.types.items[@intFromEnum(actual_pointer.child)]) {
            .declared => |declaration| declaration,
            .generic => |generic| generic.base,
            else => return false,
        };

        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const expected_pointer = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .pointer => |pointer| pointer,
                else => return false,
            },
            else => return false,
        };
        const expected_ref = switch (storage.types.items[@intFromEnum(expected_pointer.child)]) {
            .resolved => |ty| switch (ty) {
                .declared => |declaration| declaration,
                .generic => |generic| generic.base,
                else => return false,
            },
            else => return false,
        };
        const expected_base = self.generics.resolveParameterizedDeclaration(module_index, expected_ref) catch return false;
        // A different concrete nominal base cannot be supplied by reach or
        // pointer compatibility. Contract participants keep the full matcher.
        return self.graph.declarations.items[@intFromEnum(expected_base)].kind == .type and actual_base != expected_base;
    }

    fn recordConstraintFailure(
        self: *Resolver,
        module_index: usize,
        declaration: global_sg.GlobalDeclId,
        pattern: ir.ParameterizedTypeId,
        bindings: *generic_mod.Resolver.Bindings,
        input: global_sg.GlobalNodeId,
    ) !void {
        const failures = self.constraint_diagnostics orelse return;
        const failure = self.failed_constraint orelse return;
        // A bound can fail on a candidate whose other arguments do not fit.
        // Only explain constraints for otherwise compatible signatures, using
        // the same matcher as function applicability rather than a second rule set.
        switch (self.matchParameterizedInput(module_index, pattern, bindings, input)) {
            .score => {},
            else => return,
        }
        try failures.append(self.allocator, .{
            .function = declaration,
            .contract_decl = failure.contract_decl,
            .actual = failure.actual,
            .parameter_name = failure.parameter_name,
        });
    }

    /// Diagnostic probes use normal selection and roll back its graph and
    /// ownership effects. Rejected bounds must not escape a speculative probe
    /// or become an error when another visible identity actually accepts the call.
    pub fn collectGenericConstraintFailures(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        reach: ReachInferenceContext,
        failures: *std.ArrayList(ConstraintFailure),
        actual_name: *std.array_list.Managed(u8),
        append_type_name: *const fn (*std.array_list.Managed(u8), *const global_sg.GlobalSemanticGraph, global_sg.GlobalTypeId) anyerror!void,
    ) !void {
        const checkpoint = self.graph.checkpoint();
        const side_effect_checkpoint = self.checkpointSideEffects();
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        const saved_core_stats = self.core.stats;
        const saved_diagnostics = self.constraint_diagnostics;
        const saved_failure = self.failed_constraint;
        defer {
            self.graph.rollback(checkpoint);
            self.rollbackSideEffects(side_effect_checkpoint);
            self.stats = saved_stats;
            self.generics.stats = saved_generic_stats;
            self.core.stats = saved_core_stats;
            self.constraint_diagnostics = saved_diagnostics;
            self.failed_constraint = saved_failure;
        }
        failures.clearRetainingCapacity();
        self.constraint_diagnostics = failures;
        // TODO: Preserve selected-body instantiation failures separately from
        // selection failures, so rejected bounds do not hide a nested error.
        const selected = selection: {
            if (try self.generics.resolveCallArguments(current_module, reference)) |relocated| {
                _ = self.resolveExplicitGenericFunction(current_module, module, reference, relocated, input, reach) catch break :selection false;
            } else {
                _ = self.resolveImplicitGenericFunction(current_module, module, reference, input, reach) catch break :selection false;
            }
            break :selection true;
        };
        if (selected) {
            // A successful selection is not a constraint error even if other
            // candidates failed their bounds.
            failures.clearRetainingCapacity();
        } else if (failures.items.len != 0) {
            // Associated-parameter inference may create temporary types. Render
            // their name before rollback rather than expose their IDs afterward.
            try append_type_name(actual_name, self.graph, failures.items[0].actual);
        }
    }

    /// Re-run implicit generic selection transactionally for diagnostics and
    /// report the declaration identities tied at the best rank. This keeps
    /// diagnostics coupled to the real inference/specificity algorithm rather
    /// than maintaining an approximate second applicability matcher.
    pub fn collectImplicitGenericAmbiguity(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        candidates: *std.ArrayList(global_sg.GlobalDeclId),
    ) !bool {
        const checkpoint = self.graph.checkpoint();
        const side_effect_checkpoint = self.checkpointSideEffects();
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        const saved_core_stats = self.core.stats;
        defer {
            self.graph.rollback(checkpoint);
            self.rollbackSideEffects(side_effect_checkpoint);
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

    fn matchParameterizedInput(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, bindings: *generic_mod.Resolver.Bindings, input: global_sg.GlobalNodeId) core_mod.Resolver.CallInputMatch {
        const checkpoint = self.graph.checkpoint();
        const side_effect_checkpoint = self.checkpointSideEffects();
        const saved_stats = self.generics.stats;
        defer {
            self.graph.rollback(checkpoint);
            self.rollbackSideEffects(side_effect_checkpoint);
            self.generics.stats = saved_stats;
        }
        const ty = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch return .deferred;
        const fields = self.interfaceFields(ty) catch return .deferred;
        const matching_fields = self.materializeDefaultPresenceForMatch(module_index, pattern, fields) catch return .deferred;
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
                    .declared => |declaration| if (self.graph.declarations.items[@intFromEnum(declaration)].kind == .contract_type) return false,
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
                    if (self.definiteNominalReferenceMismatch(module_index, pattern, actual)) return false;
                    const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch return false;
                    if (self.core.callTypesCompatible(actual, expected)) return true;
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
                    const declaration = try self.generics.resolveParameterizedDeclaration(module_index, generic.base);
                    if (declaration != value.base) return false;
                    const located = self.generics.findTypeParameterized(declaration) orelse return false;
                    if (generic.arguments.len != located.parameterized.parameters.len or value.arguments.len != generic.arguments.len) return false;
                    const owner = &self.modules[located.module_index];
                    // Bind by declaration parameter order, regardless of the
                    // participant's positional or reordered named spelling.
                    for (0..located.parameterized.parameters.len) |position| {
                        const parameter = owner.semantic.parameterized_storage.comptime_parameters.items[located.parameterized.parameters.start + position];
                        const name = owner.text(parameter.name);
                        const argument = self.generics.findPatternArgument(module_index, generic.arguments, position, name) orelse return false;
                        const concrete = self.generics.findGlobalArgument(name, value.arguments, position) orelse return false;
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
                    }
                    return true;
                },
                else => {},
            },
            else => {},
        }
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch return false;
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
            .binary, .projection => (self.generics.evalInt(module_index, expression, bindings) catch return false) == actual,
        };
    }

    /// Materialize a pointer representation inside a recognized bundled
    /// primitive. The primitive's transfer rule supplies the validity facts.
    fn makeTrustedReferenceFromAddress(
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
                .comptime_int => return error.ReferenceTargetMustBeType,
            };
            break;
        }
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return null,
        };
        var cast_value: ?global_sg.GlobalNodeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (std.mem.eql(u8, self.graph.text(field.name), "address")) {
                cast_value = field.value;
                break;
            }
        }
        const ty = target_type orelse return error.ReferenceTargetMissing;
        if (self.graph.types.items[@intFromEnum(ty)] != .pointer) return error.ReferenceTargetMustBePointer;
        return .{
            .source = source,
            .ty = ty,
            .content = .{ .explicit_cast = .{
                .value = cast_value orelse return error.ReferenceAddressMissing,
                .target_type = ty,
            } },
        };
    }

    /// A reference can be observed as an address without carrying its
    /// validity dependency into the integer. The reverse operation needs a
    /// trusted root-establishment primitive instead of a type conversion.
    fn makeAddressConversion(
        self: *Resolver,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !?global_sg.Node {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        if (literal.fields.len != 1) return null;
        const field = self.graph.value_fields.items[literal.fields.start];
        if (!std.mem.eql(u8, self.graph.text(field.name), "value")) return null;
        const value_type = self.graph.nodes.items[@intFromEnum(field.value)].ty orelse return null;
        if (self.graph.isTypeUnresolved(value_type)) return null;
        const target = try self.core.builtin(.UIntNative);
        if (self.graph.types.items[@intFromEnum(value_type)] != .pointer and
            !global_types.equal(self.graph, value_type, target)) return null;
        return .{
            .source = source,
            .ty = target,
            .content = .{ .explicit_cast = .{ .value = field.value, .target_type = target } },
        };
    }

    /// These operations are representation primitives used by trusted core
    /// bodies after standard Convert evidence has selected the implementation.
    fn makeIntegerConversionPrimitive(
        self: *Resolver,
        name: []const u8,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !global_sg.Node {
        var from: ?global_sg.GlobalTypeId = null;
        var to: ?global_sg.GlobalTypeId = null;
        for (self.graph.generic_arguments.items[arguments.start..][0..arguments.len]) |argument| {
            if (argument.value != .type) return error.InvalidIntegerConversion;
            if (std.mem.eql(u8, self.graph.text(argument.name), "from")) from = argument.value.type;
            if (std.mem.eql(u8, self.graph.text(argument.name), "to")) to = argument.value.type;
        }
        const target = to orelse return error.InvalidIntegerConversion;
        const target_kind = switch (self.graph.resolvedSemanticType(target) orelse return error.InvalidIntegerConversion) {
            .builtin => |kind| kind,
            else => return error.InvalidIntegerConversion,
        };
        const target_range = primitives.integerRange(target_kind, self.graph.target.stdTarget()) orelse return error.InvalidIntegerConversion;
        if (std.mem.eql(u8, name, "__integer_conversion")) {
            const literal = self.graph.node(input).content.struct_value_literal;
            if (literal.fields.len != 1) return error.InvalidIntegerConversion;
            const value = self.graph.value_fields.items[literal.fields.start].value;
            const original = self.graph.node(value).ty orelse return error.InvalidIntegerConversion;
            const kind = switch (self.graph.resolvedSemanticType(original) orelse return error.InvalidIntegerConversion) {
                .builtin => |kind| kind,
                else => return error.InvalidIntegerConversion,
            };
            _ = primitives.integerRange(kind, self.graph.target.stdTarget()) orelse return error.InvalidIntegerConversion;
            return .{ .source = source, .ty = target, .content = .{ .explicit_cast = .{ .value = value, .target_type = target } } };
        }
        const original = from orelse return error.InvalidIntegerConversion;
        const original_kind = switch (self.graph.resolvedSemanticType(original) orelse return error.InvalidIntegerConversion) {
            .builtin => |kind| kind,
            else => return error.InvalidIntegerConversion,
        };
        const original_range = primitives.integerRange(original_kind, self.graph.target.stdTarget()) orelse return error.InvalidIntegerConversion;
        const bound = if (std.mem.eql(u8, name, "__integer_conversion_lower_bound"))
            @max(original_range.minimum, target_range.minimum)
        else
            @min(original_range.maximum, target_range.maximum);
        return .{ .source = source, .ty = original, .content = .{ .int_literal = bound } };
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

    fn makeAlignmentOf(
        self: *Resolver,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !?global_sg.Node {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
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
        const alignment = global_types.alignmentOf(self.graph, measured_type orelse return error.AlignmentOfTypeMissing) catch return null;
        return .{
            .source = source,
            .ty = try self.generics.internType(.{ .builtin = .UIntNative }),
            .content = .{ .int_literal = std.math.cast(i64, alignment) orelse return error.TypeAlignmentOverflow },
        };
    }

    /// Alias identity is fixed by its declaration. Infer its ordinary generic
    /// arguments from the selected requirement's inputs, never its result type
    /// and never a search through same-named functions.
    pub fn instantiateOperationAlias(context: *anyopaque, declaration: global_sg.GlobalDeclId, input: global_sg.GlobalTypeId) anyerror!global_sg.GlobalFunctionId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        const located = self.findParameterized(declaration) orelse return error.GenericFunctionParameterizedNotFound;
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        if (!try self.inferInputType(located.module_index, located.parameterized.input, input, &bindings)) return error.OperationAliasInputMismatch;
        if (!try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &bindings)) return error.OperationAliasConstraintMismatch;
        const arguments = self.appendBoundArguments(located.module_index, located.parameterized.parameters, &bindings) catch |err| {
            if (err == error.MissingGenericArgument) return error.OperationAliasMissingParameter;
            return err;
        };
        return self.instantiate(declaration, arguments);
    }

    pub fn instantiateReferencedFunction(context: *anyopaque, declaration: global_sg.GlobalDeclId, arguments: primitives.Range(global_sg.GlobalGenericArgId)) anyerror!global_sg.GlobalFunctionId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        return self.instantiate(declaration, arguments);
    }

    pub fn instantiate(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !global_sg.GlobalFunctionId {
        const profile_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        defer if (self.profile_io) |io| {
            self.profile_instantiate_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - profile_started;
            self.profile_instantiate_calls += 1;
        };
        const lookup_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        const existing = self.findExisting(declaration, arguments);
        if (self.profile_io) |io| self.profile_instantiate_lookup_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - lookup_started;
        if (existing) |id| {
            if (self.profile_io != null) self.profile_instantiate_existing += 1;
            return id;
        }
        const checkpoint = self.graph.checkpoint();
        const side_effect_checkpoint = self.checkpointSideEffects();
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        errdefer {
            const comptime_failure = self.generics.comptime_failure;
            const projection_failure = if (self.nested_call_context) |contracts| contracts.participant_conformance_failure else null;
            self.graph.rollback(checkpoint);
            self.rollbackSideEffects(side_effect_checkpoint);
            self.generics.comptime_failure = comptime_failure;
            // A selected instantiation must keep its projection diagnostic;
            // speculative signature probes restore theirs through checkpoints.
            if (self.nested_call_context) |contracts| if (projection_failure) |failure| {
                if (failure.is_projection or failure.operation != null) contracts.participant_conformance_failure = failure;
            };
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
            return error.GenericContractConstraintNotSatisfied;

        const input_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.input, &substitutions);
        const output_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.output, &substitutions);
        const input_shape = try self.interfaceFields(input_ty);
        const output_shape = try self.interfaceFields(output_ty);
        var inferred_errors = false;
        for (self.graph.fields.items[output_shape.start..][0..output_shape.len]) |field| {
            inferred_errors = inferred_errors or self.graph.types.items[@intFromEnum(field.ty)] == .inferred_errable;
        }

        const context_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        var context = try InstanceContext.init(self, located.module_index, located.parameterized, &substitutions);
        if (self.profile_io) |io| self.profile_instance_context_init_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - context_started;
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
                .has_declared_body = located.parameterized.body != null,
                .is_generic_instantiation = true,
                .uses_inferred_error_reasons = inferred_errors,
                // A contract template has no runtime ABI; its inferred
                // instance does, once every generic parameter is concrete.
            },
        });
        try self.graph.generic_function_instances.append(self.allocator, .{
            .function = function_id,
            .parameterized_declaration = declaration,
            .arguments = arguments,
        });

        context.function = function_id;
        if (located.parameterized.body) |body| {
            const body_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            const instantiated_body = try context.instantiateBlock(body);
            if (self.profile_io) |io| self.profile_instantiate_body_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - body_started;
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
                    try self.resolver.generics.instantiateParameterizedType(self.module_index, ty, self.substitutions)
                else
                    @enumFromInt(0),
                .initialization = null,
                .deferred_initialization = source.deferred_initialization,
                .mutability = source.mutability,
            });
            self.binding_map[@intFromEnum(id)] = global;
            if (source.cleanup_arguments) |node| {
                const arguments = try self.instantiateNode(node);
                self.resolver.graph.bindings.items[@intFromEnum(global)].cleanup_arguments = arguments;
            }
            if (source_ty == null) try self.resolver.graph.markBindingTypeUnresolved(self.resolver.allocator, global);
            if (source.initialization) |node| {
                const initialization = if (source_ty != null)
                    try self.instantiateNodeWithExpected(node, self.resolver.graph.bindings.items[@intFromEnum(global)].ty)
                else
                    try self.instantiateNode(node);
                self.resolver.graph.bindings.items[@intFromEnum(global)].initialization = initialization;
                if (source_ty == null) {
                    if (self.resolver.graph.nodes.items[@intFromEnum(initialization)].ty) |inferred| {
                        if (!self.resolver.graph.isTypeUnresolved(inferred)) {
                            try self.resolver.graph.resolveBindingType(global, inferred);
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
            const expected = try self.resolver.generics.instantiateParameterizedType(self.module_index, expected_parameterized, self.substitutions);
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
                    // Resolving payloads can grow the node pool. Compute the
                    // value before taking the destination slot's address.
                    const resolved = try self.resolveChoiceLiteral(pending.resolve_expression, expected);
                    self.resolver.graph.nodes.items[@intFromEnum(global)] = resolved;
                    self.resolver.stats.nodes += 1;
                    return global;
                }
            } else if (local.resolved.content == .struct_value_literal) {
                return self.instantiateStructValueWithExpected(id, local.resolved, expected);
            } else if (local.resolved.content == .string_literal or local.resolved.content == .int_literal) {
                const global = try self.instantiateNode(id);
                const current = self.resolver.graph.nodes.items[@intFromEnum(global)].ty;
                if (current == null or !global_types.equal(self.resolver.graph, current.?, expected))
                    self.resolver.core.contextualizeStoredValue(global, expected);
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
            // TODO: Support reporting value_sequence arguments to concrete
            // callees during contract-operation specialization. Even bare !!!
            // can currently make that enclosing specialization fail.
            if (node.content == .code_block or node.content == .value_sequence) {
                const is_sequence = node.content == .value_sequence;
                const block = try self.instantiateBlock(if (is_sequence) node.content.value_sequence else node.content.code_block);
                const body = self.resolver.graph.blocks.items[@intFromEnum(block)];
                const ty: ?global_sg.GlobalTypeId = if (body.ret_val) |ret_val|
                    self.resolver.graph.nodes.items[@intFromEnum(ret_val)].ty
                else
                    try self.resolver.generics.internType(.{ .builtin = .Void });
                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = ty,
                    .content = if (is_sequence) .{ .value_sequence = block } else .{ .code_block = block },
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
                try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions)
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
                    .value_sequence => |block| .{ .value_sequence = try self.instantiateBlock(block) },
                    .int_literal => |value| .{ .int_literal = value },
                    .float_literal => |value| .{ .float_literal = value },
                    .char_literal => |value| .{ .char_literal = value },
                    .bool_literal => |value| .{ .bool_literal = value },
                    .string_literal => |value| .{ .string_literal = try self.copyString(value) },
                    .type_literal => |value| .{ .type_literal = try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions) },
                    .move_value => |value| .{ .move_value = try self.instantiateNode(value) },
                    .break_statement => .break_statement,
                    .continue_statement => .continue_statement,
                    .abort_statement => .abort_statement,
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
            var assumed: std.ArrayList(global_sg.ValueField) = .empty;
            defer assumed.deinit(self.resolver.allocator);
            for (storage.value_fields.items[literal.assumed_fields.start..][0..literal.assumed_fields.len]) |field| {
                try assumed.append(self.resolver.allocator, .{
                    .name = try self.copyString(field.name),
                    .value = try self.instantiateNode(field.value),
                });
            }
            const assumed_start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, assumed.items);
            const start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, values.items);
            return .{ .source = self.resolver.sourceFor(self.module_index, node.source), .ty = ty, .content = .{
                .struct_value_literal = .{
                    .fields = .{ .start = start, .len = @intCast(values.items.len) },
                    .dispatch_prefix_positional_count = literal.dispatch_prefix_positional_count,
                    .assumed_fields = .{ .start = assumed_start, .len = @intCast(assumed.items.len) },
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
                .resolve_call => |value| self.resolveCall(value),
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

        fn resolveCall(self: *InstanceContext, value: anytype) !global_sg.Node {
            try self.contextualizeOrdinaryChoiceArguments(value.name, value.input);
            const input = try self.instantiateNode(value.input);
            return self.makeNamedCall(value.name, null, .{ .start = 0, .len = 0 }, input, value.source, null);
        }

        // A unique concrete ordinary identity supplies argument context before
        // input instantiation. Never use overload ranking or cached generic
        // specializations to decide the type of an untyped choice literal.
        fn contextualizeOrdinaryChoiceArguments(self: *InstanceContext, name_id: primitives.StringRange, input_id: ir.ParameterizedNodeId) !void {
            const name = self.resolver.modules[self.module_index].text(name_id);
            var selected: ?global_sg.GlobalFunctionId = null;
            for (try self.resolver.graph.functionsNamed(self.resolver.allocator, name)) |function_id| {
                const function = self.resolver.graph.function(function_id);
                if (function.flags.is_generic_instantiation or function.flags.is_c_function_pointer) continue;
                if (!self.resolver.core.declarationVisible(self.module_index, function.declaration, null)) continue;
                if (selected != null) return;
                selected = function_id;
            }
            const function_id = selected orelse return;
            if (self.resolver.hasVisibleParameterizedFunctionName(self.module_index, name, null)) return;
            const input_fields = self.resolver.graph.function(function_id).input;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const input = storage.nodes.items[@intFromEnum(input_id)];
            if (input != .resolved or input.resolved.content != .struct_value_literal) return;
            const fields = input.resolved.content.struct_value_literal.fields;
            for (storage.value_fields.items[fields.start..][0..fields.len], 0..) |field, position| {
                const local = storage.nodes.items[@intFromEnum(field.value)];
                if (local != .pending) continue;
                const pending = storage.pending.items[@intFromEnum(local.pending)];
                if (pending != .resolve_expression or pending.resolve_expression.kind != .choice_literal) continue;
                const field_name = self.resolver.modules[self.module_index].text(field.name);
                for (self.resolver.graph.fields.items[input_fields.start..][0..input_fields.len], 0..) |expected, offset| {
                    const matches = if (field_name.len == 0) position == offset else std.mem.eql(u8, field_name, self.resolver.graph.text(expected.name));
                    if (!matches) continue;
                    if (!self.resolver.graph.isTypeUnresolved(expected.ty))
                        _ = try self.instantiateNodeWithExpected(field.value, expected.ty);
                    break;
                }
            }
        }

        fn resolveExpression(self: *InstanceContext, value: ir.PendingExpression) anyerror!global_sg.Node {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            if (value.kind == .generic_call and value.module_path == null and value.contract_type == null and value.generic_arguments.len == 0 and value.operands.len == 1)
                if (value.name) |name|
                    try self.contextualizeOrdinaryChoiceArguments(name, storage.node_refs.items[value.operands.start]);
            var operands = std.array_list.Managed(global_sg.GlobalNodeId).init(self.resolver.allocator);
            defer operands.deinit();
            for (storage.node_refs.items[value.operands.start..][0..value.operands.len]) |operand|
                try operands.append(try self.instantiateNode(operand));

            return switch (value.kind) {
                .unknown_identifier => if (value.name) |name| self.resolveName(.{ .name = name, .source = value.source }) else error.UnknownParameterizedName,
                .comptime_parameter => self.resolveComptimeParameter(value),
                .generic_call => blk: {
                    const name = value.name orelse return error.GenericParameterizedCallWithoutName;
                    const args = try self.resolver.generics.instantiateParameterizedArguments(self.module_index, value.generic_arguments, self.substitutions);
                    const input = if (operands.items.len != 0) operands.items[0] else return error.GenericParameterizedCallWithoutInput;
                    if (value.contract_type) |contract| {
                        const base = try self.resolver.generics.instantiateParameterizedType(self.module_index, contract, self.substitutions);
                        var context = try self.operatorContext(value.assumed_arguments);
                        defer self.resolver.allocator.free(context.global.visible_bindings);
                        if (self.resolver.graph.node(input).content == .struct_value_literal)
                            context.global.assumed_fields = self.resolver.graph.node(input).content.struct_value_literal.assumed_fields;
                        const contracts = self.resolver.nested_call_context orelse return error.InvalidContractOperation;
                        break :blk try contracts.makeScopedOperationCall(self.module_index, base, self.resolver.modules[self.module_index].text(name), input, context, self.resolver.sourceFor(self.module_index, value.source)) orelse error.InvalidContractOperation;
                    }
                    break :blk try self.makeNamedCall(name, value.module_path, args, input, value.source, if (value.expected_type) |ty|
                        try self.resolver.generics.instantiateParameterizedType(self.module_index, ty, self.substitutions)
                    else
                        null);
                },
                .binary => self.resolveBinary(operands.items, value.source, value.detail, value.assumed_arguments),
                .comparison => self.resolveComparison(operands.items, value.source, value.detail, value.assumed_arguments),
                .logical => self.resolveLogical(operands.items, value.source, value.detail),
                .index => self.resolveIndex(operands.items, value.source, false),
                .index_store => self.resolveIndex(operands.items, value.source, true),
                .field_access => if (value.name) |name| self.resolveField(operands.items[0], name, value.source) else error.InvalidParameterizedFieldAccess,
                .choice_payload => blk: {
                    if (value.requires_errable) {
                        const ty = self.resolver.graph.node(operands.items[0]).ty orelse return error.GenericHandleRequiresErrable;
                        if (!global_types.isErrable(self.resolver.graph, ty)) return error.GenericHandleRequiresErrable;
                    }
                    break :blk if (value.name) |name| self.resolveChoicePayload(operands.items[0], name, value.source) else error.InvalidParameterizedChoicePayload;
                },
                .nullable_test => self.resolveNullableTest(operands.items, value.source),
                .return_statement => self.resolveReturn(operands.items, value.source),
                .if_statement => self.resolveIf(operands.items, value.source),
                .while_statement => self.resolveWhile(operands.items, value.source),
                .for_each => self.resolveForEach(value, operands.items),
                .match => if (operands.items.len == 1) self.resolveMatch(value, operands.items[0]) else error.InvalidParameterizedMatch,
                .address_of => self.resolveAddress(operands.items, value.source, value.detail),
                .dereference => self.resolveDereference(operands.items, value.source),
                .pointer_store => self.resolvePointerStore(operands.items, value.source),
                .move_value => self.resolveMove(operands.items, value.source),
                .error_propagation, .error_context => self.resolveErrorPropagation(operands.items, value.source),
                .pipe => if (operands.items.len != 0) self.resolver.graph.nodes.items[@intFromEnum(operands.items[operands.items.len - 1])] else error.InvalidParameterizedPipe,
                .struct_value,
                .list_value,
                .choice_literal,
                .unwrap_or,
                .unwrap_or_do,
                .match_case,
                .defer_value,
                .explicit_cast,
                .other,
                => error.ParameterizedExpressionRequiresGlobalResolver,
            };
        }

        fn resolveErrorPropagation(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 1 and operands.len != 2) return error.InvalidParameterizedErrorPropagation;
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
            const propagated_ty = (self.resolver.graph.fields.items[function.output.start]).ty;
            const propagated_error = global_types.findVariant(self.resolver.graph, propagated_ty, "error") orelse return error.InvalidParameterizedErrorPropagation;
            const propagated_error_payload = propagated_error.variant.payload_type orelse error_payload;
            var errors: errors_mod.Resolver = .{ .allocator = self.resolver.allocator, .graph = self.resolver.graph, .modules = self.resolver.modules, .offsets = self.resolver.offsets, .core = self.resolver.core };
            if (!errors.errorPayloadCanPropagate(error_payload, propagated_error_payload)) return error.IncompatibleParameterizedErrorPayload;
            try errors.absorbErrorPayloadReasons(error_payload, propagated_error_payload);
            const ok_fields = if (self.resolver.graph.types.items[@intFromEnum(ok_payload)] == .structural) global_types.fields(self.resolver.graph, ok_payload) else null;
            const result_ty = if (ok_fields) |fields|
                if (fields.len == 1) (self.resolver.graph.fields.items[fields.start]).ty else ok_payload
            else
                ok_payload;
            const id: global_sg.GlobalErrorPropagationId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.error_propagations.items.len)));
            const empty = try self.resolver.graph.addString(self.resolver.allocator, "");
            if (operands.len == 2) {
                const context_ty = self.resolver.graph.node(operands[1]).ty orelse return error.InvalidErrorContextType;
                if (!errors.validContextType(context_ty)) return error.InvalidErrorContextType;
                const context_id: global_sg.GlobalErrorContextId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.error_contexts.items.len)));
                try self.resolver.graph.error_contexts.append(self.resolver.allocator, .{
                    .errable_value = errable,
                    .context = operands[1],
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
                return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = result_ty, .content = .{ .error_context = context_id } };
            }
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
                try self.resolver.generics.instantiateParameterizedType(self.module_index, parameterized_type, self.substitutions)
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
            _ = try self.resolver.generics.ensureGenericInstance(expected);
            // Defaults can need their inferred Errable shape while the generic
            // instance is being built, before the ordinary fixed-point pass.
            if (self.resolver.graph.types.items[@intFromEnum(expected)] == .inferred_errable) {
                const child = self.resolver.graph.types.items[@intFromEnum(expected)].inferred_errable;
                var control = control_mod.Resolver{
                    .allocator = self.resolver.allocator,
                    .graph = self.resolver.graph,
                    .modules = self.resolver.modules,
                    .offsets = self.resolver.offsets,
                };
                try control.materializeInferredErrable(expected, child);
            }
            const variant = global_types.findVariant(self.resolver.graph, expected, name) orelse return error.UnknownParameterizedChoiceVariant;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const payload = if (value.operands.len == 0)
                null
            else if (value.operands.len == 1)
                if (variant.variant.payload_type) |payload_type|
                    try self.instantiateNodeWithExpected(self.normalizeChoicePayloadNode(storage.node_refs.items[value.operands.start], payload_type), payload_type)
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

        fn normalizeChoicePayloadNode(self: *InstanceContext, id: ir.ParameterizedNodeId, expected: global_sg.GlobalTypeId) ir.ParameterizedNodeId {
            // Choice constructor arguments are lowered as an aggregate. Match
            // the direct resolver's scalar payload normalization before typing.
            if (global_types.fields(self.resolver.graph, expected) != null) return id;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const node = storage.nodes.items[@intFromEnum(id)];
            if (node != .resolved or node.resolved.content != .struct_value_literal) return id;
            const literal = node.resolved.content.struct_value_literal;
            if (literal.fields.len != 1) return id;
            const field = storage.value_fields.items[literal.fields.start];
            if (literal.dispatch_prefix_positional_count != 1 and
                !std.mem.eql(u8, self.resolver.modules[self.module_index].text(field.name), "value")) return id;
            return field.value;
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
                    try self.resolver.graph.resolveBindingType(binding, try self.matchBindingType(payload, case.mode));
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

        fn makeNamedCall(
            self: *InstanceContext,
            name_range: primitives.StringRange,
            module_path: ?primitives.StringRange,
            arguments: primitives.Range(global_sg.GlobalGenericArgId),
            input: global_sg.GlobalNodeId,
            source: primitives.SourceRef,
            expected: ?global_sg.GlobalTypeId,
        ) !global_sg.Node {
            const module = &self.resolver.modules[self.module_index];
            const name = module.text(name_range);
            if (module_path == null and std.mem.eql(u8, name, "__scalar_equal")) {
                const declaration = self.resolver.graph.declaration(globalizer.globalDecl(self.resolver.offsets[self.module_index], self.parameterized.declaration));
                const path = self.resolver.graph.text(self.resolver.graph.files.items[declaration.source.file_index].path);
                if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(path), "scalar_arithmetic.rg")) return error.NoMatchingGenericFunction;
                const literal = self.resolver.graph.node(input).content.struct_value_literal;
                if (literal.fields.len != 2) return error.InvalidScalarEqualityPrimitive;
                const left = self.resolver.core.callArgumentNamed(literal, 0, "left") orelse return error.InvalidScalarEqualityPrimitive;
                const right = self.resolver.core.callArgumentNamed(literal, 1, "right") orelse return error.InvalidScalarEqualityPrimitive;
                const left_type = self.resolver.graph.node(left).ty orelse return error.InvalidScalarEqualityPrimitive;
                const right_type = self.resolver.graph.node(right).ty orelse return error.InvalidScalarEqualityPrimitive;
                if (!self.resolver.core.isBuiltinComparable(left_type, right_type)) return error.InvalidScalarEqualityPrimitive;
                return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = try self.resolver.generics.internType(.{ .builtin = .Bool }), .content = .{ .comparison = .{ .operator = .equal, .left = left, .right = right } } };
            }
            if (module_path == null) if (standard_contracts.scalarArithmeticPrimitive(name)) |operator| {
                const declaration = self.resolver.graph.declaration(globalizer.globalDecl(self.resolver.offsets[self.module_index], self.parameterized.declaration));
                const path = self.resolver.graph.text(self.resolver.graph.files.items[declaration.source.file_index].path);
                if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(path), "scalar_arithmetic.rg")) return error.NoMatchingGenericFunction;
                const literal = self.resolver.graph.node(input).content.struct_value_literal;
                if (literal.fields.len != 2) return error.InvalidScalarArithmeticPrimitive;
                const left = self.resolver.core.callArgumentNamed(literal, 0, "left") orelse return error.InvalidScalarArithmeticPrimitive;
                const right = self.resolver.core.callArgumentNamed(literal, 1, "right") orelse return error.InvalidScalarArithmeticPrimitive;
                const left_type = self.resolver.graph.node(left).ty orelse return error.InvalidScalarArithmeticPrimitive;
                const right_type = self.resolver.graph.node(right).ty orelse return error.InvalidScalarArithmeticPrimitive;
                if (!self.resolver.core.isScalarArithmeticRepresentation(left_type, right_type)) return error.InvalidScalarArithmeticPrimitive;
                return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = left_type, .content = .{ .binary_operation = .{ .operator = operator, .left = left, .right = right } } };
            };
            if (module_path == null and (std.mem.eql(u8, name, "__integer_conversion") or
                std.mem.eql(u8, name, "__integer_conversion_lower_bound") or
                std.mem.eql(u8, name, "__integer_conversion_upper_bound")))
            {
                const declaration = self.resolver.graph.declaration(globalizer.globalDecl(self.resolver.offsets[self.module_index], self.parameterized.declaration));
                const path = self.resolver.graph.text(self.resolver.graph.files.items[declaration.source.file_index].path);
                if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(path), "integer_conversion.rg")) return error.NoMatchingGenericFunction;
                return self.resolver.makeIntegerConversionPrimitive(name, arguments, input, self.resolver.sourceFor(self.module_index, source));
            }
            if (module_path == null and std.mem.eql(u8, name, "__reference_address")) {
                const declaration = self.resolver.graph.declaration(globalizer.globalDecl(self.resolver.offsets[self.module_index], self.parameterized.declaration));
                const path = self.resolver.graph.text(self.resolver.graph.files.items[declaration.source.file_index].path);
                if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(path), "reference_conversion.rg")) return error.NoMatchingGenericFunction;
                return (try self.resolver.makeAddressConversion(input, self.resolver.sourceFor(self.module_index, source))) orelse error.InvalidAddressConversion;
            }
            if (module_path == null and std.mem.eql(u8, name, "__trusted_reference_from_address")) {
                // The hook has no global declaration and cannot be selected by
                // ordinary lookup. Only these concrete primitive bodies use it.
                switch (self.parameterized.safety_primitive) {
                    .establish_inherited_reference, .establish_allocation_slot, .reference_offset, .mutable_reference_offset, .reinterpret_reference, .mutable_reinterpret_reference, .read_reference => {},
                    else => return error.NoMatchingGenericFunction,
                }
                return (try self.resolver.makeTrustedReferenceFromAddress(arguments, input, self.resolver.sourceFor(self.module_index, source))) orelse error.ReferenceAddressInputMustBeStruct;
            }
            if (module_path == null and std.mem.eql(u8, name, "_zeroed"))
                return (try self.resolver.core.makeZeroed(input, self.resolver.sourceFor(self.module_index, source))) orelse error.DeferredGenericFunction;
            if (module_path == null and std.mem.eql(u8, name, "size_of"))
                return (try self.resolver.makeSizeOf(input, self.resolver.sourceFor(self.module_index, source))) orelse error.SizeOfInputMustBeStruct;
            if (module_path == null and std.mem.eql(u8, name, "alignment_of"))
                return (try self.resolver.makeAlignmentOf(input, self.resolver.sourceFor(self.module_index, source))) orelse error.AlignmentOfInputMustBeStruct;
            if (module_path == null and std.mem.eql(u8, name, "is"))
                return self.resolveChoiceTest(input, source);
            if (module_path == null and std.mem.eql(u8, name, "to_virtual")) {
                if (self.resolver.nested_call_context) |contracts| {
                    const reference: module_entities.ExternalRef = .{ .kind = .function, .module_path = null, .name = name_range, .source = source };
                    if (try contracts.makeVirtualizeWithArguments(self.module_index, reference, input, arguments, expected)) |node| {
                        return node;
                    }
                }
                return error.DeferredGenericFunction;
            }
            const input_literal = switch (self.resolver.graph.nodes.items[@intFromEnum(input)].content) {
                .struct_value_literal => |value| value,
                else => null,
            };
            if (input_literal) |literal| if (literal.fields.len == 0) {
                if (try self.resolveEmptyTypeInitializer(name, source)) |node| {
                    return node;
                }
            };
            if (module_path == null and arguments.len == 0 and primitives.integerRange(primitives.builtinTypeNamedForTarget(name, self.resolver.graph.target.stdTarget()) orelse .Void, self.resolver.graph.target.stdTarget()) != null) {
                self.resolver.generics.comptime_failure = .{ .source = self.resolver.sourceFor(self.module_index, source), .reason = "numeric type-call conversions are unsupported; use convert#(.to: Target)(.value = source)" };
                return error.InvalidNumericTypeCall;
            }
            const reference: module_entities.ExternalRef = .{ .kind = .function, .module_path = module_path, .name = name_range, .source = source };
            // Calls in an instantiated body can reach the instance's concrete
            // input bindings, including parameters inferred from generic args.
            // Default expressions can be materialized before a function body
            // exists. They have no body-local input bindings to expose.
            const input_bindings = if (self.function) |owner|
                self.resolver.graph.function(owner).input_bindings
            else
                global_sg.BindingRange{ .start = 0, .len = 0 };
            const visible = try self.resolver.allocator.dupe(global_sg.GlobalBindingId, self.resolver.graph.binding_refs.items[input_bindings.start..][0..input_bindings.len]);
            defer self.resolver.allocator.free(visible);
            const nested_reach = ReachInferenceContext.fromGlobal(visible, self.function);
            if (arguments.len == 0) {
                const operation_module = if (module_path) |path| try self.resolver.core.findModuleForQualifier(self.module_index, module.text(path)) else null;
                if (try self.resolver.resolveOperationIdentityFiltered(self.module_index, name, input, nested_reach, self.resolver.sourceFor(self.module_index, source), operation_module)) |operation| return operation;
            }
            const function = blk: {
                break :blk if (arguments.len != 0)
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
                                    )) |node| {
                                        try self.resolver.core.trackResolvedReachedCall(node, nested_reach);
                                        return node;
                                    }
                                }
                            }
                            return err;
                        },
                        else => return err,
                    }
                else ordinary_lookup: {
                    const ordinary = if (module_path == null)
                        try self.resolver.core.matchUnqualifiedFunctionByNameWithReach(self.module_index, name, input, nested_reach)
                    else
                        try self.resolver.core.matchFunctionByName(self.module_index, reference, input);
                    if (ordinary == .function) break :ordinary_lookup ordinary.function;
                    break :ordinary_lookup self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, nested_reach) catch |err| {
                        if (self.resolver.nested_constructor_context) |context| {
                            if (self.resolver.nested_constructor_resolver) |resolve| {
                                if (try resolve(context, self.module_index, reference, arguments, input, nested_reach, self.resolver.sourceFor(self.module_index, source))) |node| {
                                    try self.resolver.core.trackResolvedReachedCall(node, nested_reach);
                                    return node;
                                }
                            }
                        }
                        if (self.resolver.nested_call_context) |context| {
                            if (self.resolver.nested_call_resolver) |resolve| {
                                if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source), nested_reach)) |node| {
                                    try self.resolver.core.trackResolvedReachedCall(node, nested_reach);
                                    return node;
                                }
                            }
                        }
                        if (module_path == null and std.mem.eql(u8, name, "deinit") and
                            self.parameterized.safety_primitive == .trusted_opaque_drop)
                            return self.emptyValue(try self.resolver.generics.internType(.{ .builtin = .Void }), source);
                        return err;
                    };
                };
            };
            if (!try self.resolver.core.completeCallInputFieldsWithReach(
                self.resolver.graph.functions.items[@intFromEnum(function)].input,
                input,
                nested_reach,
            )) return error.IncompleteParameterizedCallInput;
            try self.resolver.core.trackReachedCall(function, input, nested_reach, false);
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
            if (primitives.builtinTypeNamedForTarget(name, self.resolver.graph.target.stdTarget())) |builtin_type| {
                const ty = try self.resolver.generics.internType(.{ .builtin = builtin_type });
                // Builtin constructors produce scalar values, even when their
                // call arguments were represented by an empty aggregate.
                const content: @TypeOf(@as(global_sg.Node, undefined).content) = switch (builtin_type) {
                    .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64, .UIntNative => .{ .int_literal = 0 },
                    .Float16, .Float32, .Float64 => .{ .float_literal = 0 },
                    .Bool => .{ .bool_literal = false },
                    .Char => .{ .char_literal = 0 },
                    .Void => return self.emptyValue(ty, source),
                    else => return null,
                };
                return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = ty, .content = content };
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

        fn resolveBinary(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, _: primitives.SourceRef, detail: ir.PendingExpressionDetail, assumed: ?ir.ParameterizedNodeId) !global_sg.Node {
            if (operands.len != 2) return error.InvalidParameterizedBinary;
            const operator: primitives.BinaryOperator = switch (detail) {
                .binary => |value| value,
                else => return error.InvalidParameterizedBinary,
            };
            self.resolver.core.contextualizeArithmeticPair(operands);
            const identity = standard_contracts.arithmeticOperation(operator);
            const reach = try self.operatorContext(assumed);
            defer self.resolver.allocator.free(reach.global.visible_bindings);
            const call = try self.resolver.makeContractOperator(self.module_index, identity.contract, identity.operation, operands, reach, null) orelse return error.UnresolvedContractArithmetic;
            return self.resolver.lowerSelectedScalarArithmetic(call, operator, operands);
        }

        fn resolveComparison(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, detail: ir.PendingExpressionDetail, assumed: ?ir.ParameterizedNodeId) !global_sg.Node {
            if (operands.len != 2) return error.InvalidParameterizedComparison;
            const operator: primitives.ComparisonOperator = switch (detail) {
                .comparison => |value| value,
                else => return error.InvalidParameterizedComparison,
            };
            var left_ty = self.resolver.graph.node(operands[0]).ty orelse return error.UntypedParameterizedComparison;
            var right_ty = self.resolver.graph.node(operands[1]).ty orelse return error.UntypedParameterizedComparison;
            self.resolver.core.contextualizeArithmeticPair(operands);
            left_ty = self.resolver.graph.node(operands[0]).ty.?;
            right_ty = self.resolver.graph.node(operands[1]).ty.?;
            const bool_ty = try self.resolver.generics.internType(.{ .builtin = .Bool });
            if ((operator == .equal or operator == .not_equal) and !self.resolver.core.isForeignEqualityRepresentation(left_ty, right_ty)) {
                const reach = try self.operatorContext(assumed);
                defer self.resolver.allocator.free(reach.global.visible_bindings);
                if (try self.resolver.makeContractOperator(self.module_index, "Equal", "equal", operands, reach, null)) |call| return self.resolver.equalityResult(self.resolver.lowerSelectedScalarEquality(call, operands), operator);
            }
            // Tag tests retain comparison nodes. Unsupported aggregate nodes
            // remain typed for the final semantizing diagnostic, so speculative
            // speculative instantiation never emits errors for discarded candidates.
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

        fn operatorContext(self: *InstanceContext, assumed: ?ir.ParameterizedNodeId) !ReachInferenceContext {
            var context = ReachInferenceContext.fromGlobal(&.{}, self.function);
            if (assumed) |local| {
                const input = try self.instantiateNode(local);
                context.global.assumed_fields = self.resolver.graph.node(input).content.struct_value_literal.assumed_fields;
            }
            if (self.function) |function| {
                const bindings = self.resolver.graph.functions.items[@intFromEnum(function)].input_bindings;
                context.global.visible_bindings = try self.resolver.allocator.dupe(global_sg.GlobalBindingId, self.resolver.graph.binding_refs.items[bindings.start..][0..bindings.len]);
            }
            return context;
        }

        fn resolveIndex(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, store: bool) !global_sg.Node {
            if (operands.len != (if (store) @as(usize, 3) else 2)) return error.InvalidParameterizedIndex;
            const collection_ty = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.ParameterizedIndexUntyped;
            if (global_types.arrayElement(self.resolver.graph, collection_ty)) |element| {
                // Store operands take the array element's context before
                // codegen, so a narrow element never receives a default-width
                // literal store that overwrites adjacent elements.
                if (store) self.resolver.core.contextualizeStoredValue(operands[2], element);
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

            return error.ParameterizedIndexRequiresArray;
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

        fn resolveForEach(self: *InstanceContext, value: ir.PendingExpression, operands: []const global_sg.GlobalNodeId) !global_sg.Node {
            if (operands.len != 1 or value.detail != .for_each) return error.InvalidParameterizedFor;
            const detail = value.detail.for_each;
            const binding = try self.instantiateBinding(detail.binding);
            const graph = self.resolver.graph;
            const source = self.resolver.sourceFor(self.module_index, value.source);
            const void_ty = try self.resolver.generics.internType(.{ .builtin = .Void });
            const target: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(graph.nodes.items.len)));
            try graph.nodes.append(self.resolver.allocator, .{ .source = source, .ty = void_ty, .content = .break_statement });
            const empty: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(graph.blocks.items.len)));
            try graph.blocks.append(self.resolver.allocator, .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = null });
            var control = control_mod.Resolver{
                .allocator = self.resolver.allocator,
                .graph = graph,
                .modules = self.resolver.modules,
                .offsets = self.resolver.offsets,
                .core = self.resolver.core,
                .generic_functions = self.resolver,
                .contracts = self.resolver.nested_call_context,
            };
            // Resolve the iterator protocol before specializing the body: its
            // next output establishes the previously unknown item type. Both
            // concrete and generic loops use the same ownership wrapper.
            const operation: module_entities.PendingOperation = .{ .resolve_for_each = .{
                .node = @enumFromInt(@intFromEnum(target)),
                .binding = @enumFromInt(@intFromEnum(binding)),
                .iterable = @enumFromInt(@intFromEnum(operands[0])),
                .body = @enumFromInt(@intFromEnum(empty)),
                .mode = detail.mode,
                .source = source,
            } };
            switch (try control.resolveForEach(self.module_index, std.mem.zeroes(globalizer.Offsets), operation.resolve_for_each)) {
                .resolved => {},
                .deferred => return error.DeferredGenericFunction,
                else => return error.InvalidParameterizedForProtocol,
            }
            const loop = switch (graph.node(target).content) {
                .for_statement => target,
                .code_block => |wrapper| blk: {
                    // The wrapper retains any computed collection and the
                    // iterator before its final loop node.
                    const nodes = graph.blocks.items[@intFromEnum(wrapper)].nodes;
                    break :blk graph.node_refs.items[nodes.start + nodes.len - 1];
                },
                else => return error.InvalidParameterizedFor,
            };
            const body_id = graph.node(loop).content.for_statement.body;
            const prefix = graph.blocks.items[@intFromEnum(body_id)].nodes;
            const declaration = graph.node_refs.items[prefix.start];
            const assignment = graph.node_refs.items[prefix.start + 1];
            const actual = try self.instantiateBlock(detail.body);
            const actual_body = graph.blocks.items[@intFromEnum(actual)];
            const nodes = try self.resolver.allocator.dupe(global_sg.GlobalNodeId, graph.node_refs.items[actual_body.nodes.start..][0..actual_body.nodes.len]);
            defer self.resolver.allocator.free(nodes);
            const start: u32 = @intCast(graph.node_refs.items.len);
            try graph.node_refs.appendSlice(self.resolver.allocator, &.{ declaration, assignment });
            try graph.node_refs.appendSlice(self.resolver.allocator, nodes);
            graph.blocks.items[@intFromEnum(body_id)] = .{ .nodes = .{ .start = start, .len = @intCast(nodes.len + 2) }, .ret_val = actual_body.ret_val };
            return graph.node(target);
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
            const child = switch (self.resolver.graph.node(operands[0]).content) {
                .assignment => |assignment| blk: {
                    if (self.resolver.graph.isBindingTypeUnresolved(assignment.binding)) return error.ParameterizedAddressUntyped;
                    const ty = self.resolver.graph.binding(assignment.binding).ty;
                    self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty = ty;
                    break :blk ty;
                },
                else => self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.ParameterizedAddressUntyped,
            };
            const mutability: primitives.PointerMutability = switch (detail) {
                .pointer_mutability, .pipe_pointer_mutability => |value| value,
                else => return error.InvalidParameterizedAddressOf,
            };
            if (detail == .pipe_pointer_mutability and self.resolver.graph.types.items[@intFromEnum(child)] == .pointer)
                return self.resolver.graph.node(operands[0]);
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

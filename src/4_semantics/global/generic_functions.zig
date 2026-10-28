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
const instantiation_map = @import("instantiation_map.zig");
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

/// A diagnostic result owns its rendered name, independent of speculative IDs.
/// The caller releases actual_name with the resolver's allocator.
pub const ConstraintFailure = struct {
    function: global_sg.GlobalDeclId,
    contract_decl: global_sg.GlobalFamilyDefinitionId,
    actual_name: []const u8,
    parameter_name: []const u8,
};

pub const Resolver = struct {
    active_instance: ?*InstanceContext = null,
    capture_lookup_context: ?*anyopaque = null,
    capture_lookup: ?*const fn (*anyopaque, usize, ?global_sg.GlobalFunctionId, []const u8) ?global_sg.GlobalBindingId = null,
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
    ownership_checkpoint: ?*const fn (*anyopaque) @import("ownership.zig").Resolver.ParameterizedCheckpoint = null,
    rollback_ownership: ?*const fn (*anyopaque, @import("ownership.zig").Resolver.ParameterizedCheckpoint) void = null,
    constraint_diagnostic: ?*?ConstraintFailure = null,
    reach_diagnostics: ?*std.array_list.Managed(u8) = null,
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
    publishing_signature: bool = false,

    pub const SideEffectCheckpoint = struct {
        execution_requests: ?usize = null,
        ownership: ?@import("ownership.zig").Resolver.ParameterizedCheckpoint = null,
        reached_calls: usize = 0,
        type_caches: [2]usize,
        capture_nodes: usize,
        capture_bindings: usize,
        contracts: ?contract_mod.Resolver.ResolutionCheckpoint = null,
        comptime_failure: ?generic_mod.ComptimeFailure = null,
    };

    /// A speculative resolution owns graph tails and the effects they refer to.
    /// Destroying the scope rolls both back unless selection commits them.
    pub const Speculation = struct {
        resolver: *Resolver,
        graph: global_sg.GlobalSemanticGraph.Transaction,
        effects: SideEffectCheckpoint,
        active: bool = true,
        retain_execution: bool = false,

        pub fn commit(self: *Speculation) void {
            self.graph.commit();
            self.active = false;
        }

        // A suspended selection still needs its integer dependencies. Keep
        // their stable recipes while discarding the incomplete graph/evidence.
        pub fn retainPendingExecution(self: *Speculation) void {
            self.retain_execution = true;
        }

        pub fn rollback(self: *Speculation) void {
            if (!self.active) return;
            self.graph.rollback();
            var effects = self.effects;
            if (self.retain_execution) effects.execution_requests = null;
            self.resolver.rollbackSideEffects(effects);
            self.active = false;
        }

        pub fn deinit(self: *Speculation) void {
            self.rollback();
        }
    };

    pub fn beginSpeculation(self: *Resolver) Speculation {
        return .{ .resolver = self, .graph = self.graph.beginTransaction(self.allocator), .effects = self.checkpointSideEffects() };
    }

    pub fn checkpointSideEffects(self: *const Resolver) SideEffectCheckpoint {
        var saved: SideEffectCheckpoint = .{ .comptime_failure = self.generics.comptime_failure, .reached_calls = self.core.reached_calls.items.len, .type_caches = self.generics.checkpointCaches(), .capture_nodes = self.graph.nodes.items.len, .capture_bindings = self.graph.bindings.items.len };
        if (self.generics.checkpoint_execution) |checkpoint|
            saved.execution_requests = checkpoint(self.generics.execution_context.?);
        if (self.ownership_context) |context| {
            if (self.ownership_checkpoint) |checkpoint|
                saved.ownership = checkpoint(context);
        }
        if (self.nested_call_context) |contracts|
            saved.contracts = contracts.checkpointResolution();
        return saved;
    }

    pub fn rollbackSideEffects(self: *Resolver, saved: SideEffectCheckpoint) void {
        // Nested entry instantiation can forward a selected capture through
        // live outer contexts. Their maps must not retain provisional IDs.
        var instance = self.active_instance;
        while (instance) |context| : (instance = context.active_parent) {
            while (context.entry_captures.items.len != 0 and
                @intFromEnum(context.entry_captures.items[context.entry_captures.items.len - 1].binding) >= saved.capture_bindings)
                _ = context.entry_captures.pop();
            context.node_map.discardValuesFrom(@enumFromInt(saved.capture_nodes));
            context.binding_map.discardValuesFrom(@enumFromInt(saved.capture_bindings));
        }
        if (saved.execution_requests) |count| {
            if (self.generics.rollback_execution) |rollback|
                rollback(self.generics.execution_context.?, count);
        }
        self.generics.comptime_failure = saved.comptime_failure;
        self.generics.rollbackCaches(saved.type_caches);
        self.core.rollbackReachedCalls(saved.reached_calls);
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
            .resolve_function_signature => |value| self.resolveRetainedSignature(module_index, module, o, value.function, value.template_index),
            else => .not_applicable,
        };
    }

    fn resolveRetainedSignature(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, offsets: globalizer.Offsets, local_function: module_entities.ModuleFunctionId, template_index: u32) !resolution.Result {
        var speculation = self.beginSpeculation();
        defer speculation.deinit();
        const template = module.semantic.parameterized_storage.parameterized_functions.items[template_index];
        const function_id = globalizer.globalFunction(offsets, local_function);
        var function = self.graph.function(function_id);
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        const input = self.generics.instantiateParameterizedType(module_index, template.input, &bindings) catch |err| switch (err) {
            error.ComptimeExecutionPending => {
                speculation.retainPendingExecution();
                return .deferred;
            },
            else => return err,
        };
        const output = self.generics.instantiateParameterizedType(module_index, template.output, &bindings) catch |err| switch (err) {
            error.ComptimeExecutionPending => {
                speculation.retainPendingExecution();
                return .deferred;
            },
            else => return err,
        };
        const input_fields = global_types.fields(self.graph, input) orelse return self.unresolvedSignature(input);
        const output_fields = global_types.fields(self.graph, output) orelse return self.unresolvedSignature(output);
        var context = InstanceContext.init(self, module_index, template, &bindings);
        defer context.deinit();
        context.function = function_id;
        const inputs = try context.instantiateSignatureBindings(template.input_bindings, input_fields, .constant);
        const outputs = try context.instantiateSignatureBindings(template.output_bindings, output_fields, .variable);
        function.input_type = input;
        function.output_type = output;
        function.input = input_fields;
        function.output = try self.outputFieldsWithInitializers(output_fields, outputs);
        function.input_bindings = inputs;
        function.output_bindings = outputs;
        function.flags.uses_inferred_error_reasons = false;
        for (self.graph.fields.items[function.output.start..][0..function.output.len]) |field|
            if (self.graph.semanticType(field.ty) == .inferred_errable) {
                function.flags.uses_inferred_error_reasons = true;
            };
        try self.graph.setFunction(self.allocator, function_id, function);
        speculation.commit();
        return .resolved;
    }

    fn unresolvedSignature(self: *Resolver, ty: global_sg.GlobalTypeId) resolution.Result {
        const represented = global_types.representation(self.graph, ty) orelse return .deferred;
        if (represented == .generic and global_types.genericInstance(self.graph, ty) == null) return .deferred;
        return .invalid;
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
        try self.core.contextualizeArithmeticPair(&operands);
        const call = try self.makeContractOperator(module_index, identity.contract, identity.operation, &operands, reach, assumed) orelse return .deferred;
        try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), self.lowerSelectedScalarArithmetic(call, value.operator, &operands));
        return .resolved;
    }

    /// Trusted scalar implementations preserve constant-expression lowering,
    /// after scoped evidence has selected the operation. Other implementations
    /// remain ordinary calls, even when their participants are scalar types.
    const ScalarPrimitive = union(enum) { arithmetic: primitives.BinaryOperator, comparison: primitives.ComparisonOperator };

    fn isSelectedScalarPrimitive(self: *Resolver, call: global_sg.Node, operation: ScalarPrimitive) bool {
        if (call.content != .function_call or self.graph.callOperation(call.content.function_call) == null) return false;
        // Retain calls carrying safety promises until their selected body is
        // proved. Primitive elision must not hide that operation's use.
        const selection = self.graph.callOperation(call.content.function_call).?;
        for (self.graph.contract_safety_conformances.items) |proof|
            if (std.meta.eql(proof.selection, selection) and proof.method == call.content.function_call.callee) return false;
        const declaration = self.graph.declaration(self.graph.function(call.content.function_call.callee).declaration);
        const function = self.graph.function(call.content.function_call.callee);
        const file = self.graph.files.items[declaration.source.file_index];
        const module = self.graph.modules.items[@intFromEnum(file.module)];
        if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(self.graph.text(file.path)), "scalar_arithmetic.rg")) return false;
        // Prove the exact primitive body before eliding the call. Adding checks,
        // capabilities or other effects in core must retain the ordinary call.
        if (function.input.len != 2 or function.output.len != 1 or function.input_bindings.len != 2 or function.output_bindings.len != 1) return false;
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
            .comparison => |operator| if (expression.content == .comparison and expression.content.comparison.operator == operator)
                .{ expression.content.comparison.left, expression.content.comparison.right }
            else
                return false,
        };
        for (primitive_operands, 0..) |operand, position| {
            const projection = self.graph.node(operand).content;
            if (projection != .binding_use or projection.binding_use != self.graph.binding_refs.items[function.input_bindings.start + position]) return false;
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

    fn lowerSelectedScalarComparison(self: *Resolver, call: global_sg.Node, operator: primitives.ComparisonOperator, operands: []const global_sg.GlobalNodeId) global_sg.Node {
        if (!self.isSelectedScalarPrimitive(call, .{ .comparison = operator })) return call;
        const left = self.graph.node(operands[0]).ty orelse return call;
        const right = self.graph.node(operands[1]).ty orelse return call;
        if (!self.core.isDirectComparison(operator, left, right)) return call;
        return .{ .source = call.source, .ty = call.ty, .content = .{ .comparison = .{ .operator = operator, .left = operands[0], .right = operands[1] } } };
    }

    fn makeComparisonCall(self: *Resolver, module_index: usize, operator: primitives.ComparisonOperator, operands: []const global_sg.GlobalNodeId, reach: ReachInferenceContext, assumed: ?global_sg.GlobalNodeId) anyerror!?global_sg.Node {
        // A bare variant tests the discriminant; it is not a call to Equal
        // between two choice values. Parameterized lowering canonicalizes the
        // value first and represents the tested tag as an integer literal.
        if (operator == .equal or operator == .not_equal) {
            const left_type = self.graph.node(operands[0]).ty;
            if (left_type != null and global_types.variants(self.graph, left_type.?) != null and
                self.graph.node(operands[1]).content == .int_literal) return null;
        }
        const identity = standard_contracts.comparisonOperation(operator);
        return self.makeContractOperator(module_index, identity.contract, identity.operation, operands, reach, assumed);
    }

    fn makeContractOperator(self: *Resolver, module_index: usize, contract_name: []const u8, operation_name: []const u8, operands: []const global_sg.GlobalNodeId, reach: ReachInferenceContext, assumed: ?global_sg.GlobalNodeId) anyerror!?global_sg.Node {
        const declaration = standard_contracts.standardDefinition(self.graph, contract_name) orelse return null;
        const contracts = self.nested_call_context orelse return null;
        for (operands) |operand| {
            const ty = self.graph.node(operand).ty orelse return null;
            if (self.graph.isTypeUnresolved(ty)) return null;
        }
        var speculation = self.beginSpeculation();
        var failure: ?contract_mod.ParticipantConformanceFailure = null;
        defer if (speculation.active) {
            speculation.deinit();
            if (failure) |value| contracts.participant_conformance_failure = value;
        };
        errdefer |err| {
            if (err == error.ComptimeExecutionPending) speculation.retainPendingExecution();
        }
        const participants = [_]global_sg.GlobalTypeId{ self.graph.node(operands[0]).ty.?, self.graph.node(operands[1]).ty.? };
        // Missing operator evidence uses the ordinary operator diagnostic (and
        // the explicit pointer-arithmetic diagnostic), not a qualified-call error.
        const comparison = std.mem.eql(u8, contract_name, "Equal") or std.mem.eql(u8, contract_name, "CompareRelations");
        if (!comparison and try contracts.selectConformance(declaration, &participants, null, 0, null) == null) return null;
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (operands) |operand| try self.graph.generic_arguments.append(self.allocator, .{
            .name = .{ .start = 0, .len = 0 },
            .value = .{ .type = self.graph.node(operand).ty.? },
        });
        const contract = try self.generics.internType(.{ .generic = .{ .base = declaration, .arguments = .{ .start = start, .len = 2 } } });
        const input = try self.makePositionalInput(operands);
        var completed_input = self.graph.node(input);
        if (reach == .global) completed_input.content.struct_value_literal.assumed_fields = reach.global.assumed_fields;
        if (assumed) |node| completed_input.content.struct_value_literal.assumed_fields = self.graph.node(node).content.struct_value_literal.assumed_fields;
        try self.graph.setNode(self.allocator, input, completed_input);
        const call = contracts.makeScopedOperationCall(module_index, contract, operation_name, input, reach, self.graph.node(operands[0]).source) catch |err| {
            failure = contracts.participant_conformance_failure;
            if (failure) |*value| {
                value.input = null;
                value.output = null;
            }
            return @as(anyerror!?global_sg.Node, err);
        } orelse {
            failure = contracts.participant_conformance_failure;
            if (failure) |*value| {
                value.input = null;
                value.output = null;
            }
            return null;
        };
        if (call.ty == null or self.graph.isTypeUnresolved(call.ty.?)) return null;
        speculation.commit();
        self.stats.calls += 1;
        return call;
    }

    pub fn resolveContractComparison(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const reach = ReachInferenceContext.fromModule(module, o, value.visible_bindings, value.owner_function);
        const assumed = if (value.assumed_arguments) |local| globalizer.globalNode(o, local) else null;
        const operands = [_]global_sg.GlobalNodeId{ globalizer.globalNode(o, value.left), globalizer.globalNode(o, value.right) };
        try self.core.contextualizeArithmeticPair(&operands);
        const call = try self.makeComparisonCall(module_index, value.operator, &operands, reach, assumed) orelse return .deferred;
        try self.patchComparisonResult(globalizer.globalNode(o, value.node), self.lowerSelectedScalarComparison(call, if (value.operator == .not_equal) .equal else value.operator, &operands), value.operator);
        return .resolved;
    }

    fn patchComparisonResult(self: *Resolver, target: global_sg.GlobalNodeId, call: global_sg.Node, operator: primitives.ComparisonOperator) !void {
        // Negation appends nodes and can relocate the node buffer. Resolve it
        // before taking the destination element's address.
        const result = try self.comparisonResult(call, operator);
        try self.graph.setNode(self.allocator, target, result);
    }

    fn comparisonResult(self: *Resolver, call: global_sg.Node, operator: primitives.ComparisonOperator) !global_sg.Node {
        if (operator != .not_equal) return call;
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

    pub fn makeDefinitionCall(self: *Resolver, module_index: usize, reference: module_entities.ExternalRef, definition: global_sg.DefinitionValue, arguments: primitives.Range(global_sg.GlobalGenericArgId), input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef) !global_sg.Node {
        const family = self.graph.familyDefinition(definition.origin);
        if (family.kind == .function and family.template_index == null) {
            if (arguments.len != 0 or definition.captures.len != 0) return error.TooManyGenericArguments;
            const function = self.graph.declaration(self.graph.familyDeclaration(definition.origin)).function_id orelse return error.DeferredGenericFunction;
            return self.makeConcreteFunctionCall(function, input, reach, source);
        }
        if (self.core.callInputHasPendingTypes(input)) return error.DeferredGenericFunction;
        const input_value = self.graph.node(input).content;
        if (input_value == .struct_value_literal) {
            const fields = input_value.struct_value_literal.fields;
            for (self.graph.value_fields.items[fields.start..][0..fields.len]) |field| {
                const node = self.graph.node(field.value);
                const ty = node.ty orelse switch (node.content) {
                    // Aggregate literals receive their nominal identity from
                    // the selected signature rather than establishing it here.
                    .struct_value_literal, .list_literal => continue,
                    else => return error.DeferredGenericFunction,
                };
                if (self.graph.isTypeUnresolved(ty)) return error.DeferredGenericFunction;
            }
        }
        const selected = (if (arguments.len != 0)
            self.selectExplicitGenericFunction(module_index, &self.modules[module_index], reference, arguments, input, reach, true, definition)
        else
            self.selectImplicitGenericFunctionFiltered(module_index, self.graph.familyDefinitionName(definition.origin), null, input, reach, null, definition)) catch |err| switch (err) {
            error.NoMatchingGenericFunction, error.ConflictingGenericArgument => {
                self.generics.comptime_failure = .{ .source = source, .reason = "arguments do not match this specialized function definition, including its required reachable capabilities" };
                return error.InvalidGenericCallArguments;
            },
            else => return err,
        };
        const function = try self.instantiate(selected.declaration, selected.arguments);
        return self.makeConcreteFunctionCall(function, input, reach, source);
    }

    pub fn resolveDefinitionCall(self: *Resolver, module_index: usize, module: *const module_sg.ModuleSemanticGraph, offsets: globalizer.Offsets, call: anytype, definition: global_sg.DefinitionValue) !resolution.Result {
        const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
        const arguments = try self.generics.resolveCallArguments(module_index, reference) orelse primitives.Range(global_sg.GlobalGenericArgId){ .start = 0, .len = 0 };
        const node = self.makeDefinitionCall(module_index, reference, definition, arguments, globalizer.globalNode(offsets, call.input), ReachInferenceContext.fromModule(module, offsets, call.visible_bindings, call.owner_function), self.sourceFor(module_index, reference.source)) catch |err| switch (err) {
            error.DeferredGenericFunction => return .deferred,
            else => return err,
        };
        try self.graph.setNode(self.allocator, globalizer.globalNode(offsets, call.node), node);
        return .resolved;
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
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, name, "size_of")) {
            const node = (try self.makeSizeOf(input, self.sourceFor(module_index, reference.source))) orelse return .deferred;
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
            self.stats.calls += 1;
            return .resolved;
        }
        if (reference.module_path == null and std.mem.eql(u8, name, "alignment_of")) {
            const node = (try self.makeAlignmentOf(input, self.sourceFor(module_index, reference.source))) orelse return .deferred;
            try self.graph.setNode(self.allocator, globalizer.globalNode(o, value.node), node);
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
                    error.ComptimeExecutionPending => return error.ComptimeExecutionPending,
                    error.AmbiguousGenericFunction => return .invalid,
                    error.InvalidGenericCallArguments, error.InvalidNumericTypeCall, error.InvalidAssociatedTypeProjection, error.InvalidArrayLength, error.ComptimeIntegerOverflow, error.ComptimeDivisionByZero, error.UnknownParameterizedName, error.UncontextualizedRecordValue => return err,
                    else => return .deferred,
                }
            else
                self.resolveImplicitGenericFunction(module_index, module, reference, input, reach) catch |err| switch (err) {
                    error.NoMatchingGenericFunction => return .not_applicable,
                    error.DeferredGenericFunction => return .deferred,
                    error.ComptimeExecutionPending => return error.ComptimeExecutionPending,
                    error.AmbiguousGenericFunction => return .invalid,
                    error.InvalidGenericCallArguments, error.InvalidNumericTypeCall, error.InvalidAssociatedTypeProjection, error.InvalidArrayLength, error.ComptimeIntegerOverflow, error.ComptimeDivisionByZero, error.UnknownParameterizedName, error.UncontextualizedRecordValue => return err,
                    error.ConflictingGenericArgument => return err,
                    else => return .deferred,
                };
        };
        const completion_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        const completed = try self.core.completeRecordFieldsWithContext(self.graph.functions.items[@intFromEnum(function)].input, input, reach);
        if (self.profile_io) |io| self.profile_source_completion_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - completion_started;
        if (!completed)
            return .deferred;
        const output_ty = try self.core.functionOutputType(function);
        const target = globalizer.globalNode(o, value.node);
        try self.graph.setNode(self.allocator, target, .{
            .source = self.sourceFor(module_index, reference.source),
            .ty = output_ty,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        });
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
        const selected = try self.selectExplicitGenericFunction(current_module, module, reference, arguments, input, reach_context, true, null);
        const instantiate_start = self.profileTimestamp();
        const result = try self.instantiate(selected.declaration, selected.arguments);
        self.addProfileTime(instantiate_start, &self.selection_profile.explicit_final_instantiation_ns);
        return result;
    }

    fn selectExplicitGenericFunction(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        input: global_sg.GlobalNodeId,
        reach_context: ?ReachInferenceContext,
        report_argument_failure: bool,
        definition_override: ?global_sg.DefinitionValue,
    ) !ImplicitGenericSelection {
        if (self.profile_io != null) self.selection_profile.explicit_calls += 1;
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        const selected_definition = definition_override orelse try self.core.resolveDefinitionAlias(current_module, reference);
        const name = if (selected_definition) |value| self.graph.familyDefinitionName(value.origin) else module.text(reference.name);
        var selected: ?global_sg.GlobalDeclId = null;
        var selected_arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = 0, .len = 0 };
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
            if (selected_definition) |id| {
                if (self.graph.familyForDeclaration(declaration) != id.origin) continue;
            } else if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
            var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, candidate_module.semantic.parameterized_storage.comptime_parameters.items.len);
            defer bindings.deinit(self.allocator);
            const remaining = if (selected_definition) |definition|
                try self.generics.bindDefinitionCaptures(candidate_index, parameterized.parameters, definition, &bindings)
            else
                parameterized.parameters;
            self.generics.bindGlobalArgumentsPartial(candidate_index, remaining, arguments, &bindings) catch |err| {
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
            const constraint_check = try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings);
            self.addProfileTime(phase_start, &self.selection_profile.explicit_constraints_ns);
            if (constraint_check == .rejected) {
                try self.recordConstraintFailure(candidate_index, declaration, parameterized.input, &bindings, input, constraint_check.rejected);
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
            switch (try self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input)) {
                .no_match => {
                    if (self.profile_io != null) self.selection_profile.explicit_argument_materializations_discarded += 1;
                    continue;
                },
                .deferred => {
                    saw_deferred = true;
                    if (self.profile_io != null) self.selection_profile.explicit_argument_materializations_discarded += 1;
                    continue;
                },
                .applicable => {},
            }
            if (self.profile_io != null) self.selection_profile.explicit_candidates_matching += 1;
            self.addProfileTime(applicability_start, &self.selection_profile.explicit_applicability_ns);
            applicability_active = false;
            if (selected == null) {
                selected = declaration;
                selected_arguments = complete_arguments;
            } else if (declaration != selected.?) {
                tied = true;
                if (self.profile_io != null) self.selection_profile.explicit_argument_materializations_discarded += 1;
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        if (saw_deferred) return error.DeferredGenericFunction;
        const declaration = selected orelse {
            if (argument_failure) |failure| if (!saw_deferred and !saw_valid_arguments) {
                const reason = switch (failure) {
                    error.UnknownGenericArgument => "unknown compile-time argument",
                    error.DuplicateGenericArgument => "duplicate compile-time argument",
                    error.TooManyGenericArguments => "too many compile-time arguments",
                    error.GenericArgumentKindMismatch => "compile-time argument kind does not match its parameter",
                    error.DefinitionParameterSignatureMismatch => "type-family argument does not match its parameter signature",
                    else => return failure,
                };
                if (!report_argument_failure) return error.InvalidGenericCallArguments;
                self.generics.comptime_failure = .{
                    .source = self.sourceFor(current_module, reference.source),
                    .reason = reason,
                    .call_name = module.text(reference.name),
                };
                return error.InvalidGenericCallArguments;
            };
            return if (saw_deferred) error.DeferredGenericFunction else error.NoMatchingGenericFunction;
        };
        return .{ .declaration = declaration, .arguments = selected_arguments };
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

    fn inferNamedSignature(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, input: global_sg.GlobalNodeId, bindings: *generic_mod.Resolver.Bindings, field_offset: u32, reach: ?ReachInferenceContext) anyerror!bool {
        const caller = &self.modules[module_index];
        const expression = caller.semantic.parameterized_storage.ir.representation(pattern);
        if (expression != .resolved or expression.resolved != .generic)
            return self.matchClosedSignatureInput(module_index, pattern, input, bindings, field_offset);
        return self.inferFamilyApplication(module_index, expression.resolved.generic, .{ .fields = input }, bindings, field_offset, reach);
    }

    const FamilyInput = union(enum) {
        fields: global_sg.GlobalNodeId,
        value_type: global_sg.GlobalTypeId,
        signature_type: global_sg.GlobalTypeId,
        callable: struct { input: global_sg.GlobalNodeId, arguments: primitives.Range(global_sg.GlobalGenericArgId) },
    };

    fn inferFamilyApplication(self: *Resolver, module_index: usize, application: @FieldType(ir.ResolvedType, "generic"), input: FamilyInput, bindings: *generic_mod.Resolver.Bindings, field_offset: u32, reach: ?ReachInferenceContext) anyerror!bool {
        const definition = try self.generics.resolveParameterizedDefinitionValue(module_index, application.base, bindings);
        const ApplicationDefinition = struct { module_index: usize, parameters: primitives.Range(ir.ComptimeParameterId), shape: ir.ParameterizedTypeId };
        const located: ApplicationDefinition = if (input == .callable) callable: {
            const function = self.findParameterized(self.graph.familyDeclaration(definition.origin)) orelse return false;
            break :callable .{ .module_index = function.module_index, .parameters = function.parameterized.parameters, .shape = function.parameterized.input };
        } else family: {
            const ty = self.generics.findTypeParameterized(definition.origin) orelse return false;
            break :family .{ .module_index = ty.module_index, .parameters = ty.parameterized.parameters, .shape = ty.parameterized.body };
        };
        const module = &self.modules[located.module_index];
        var local = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
        defer local.deinit(self.allocator);
        const parameters = try self.generics.bindDefinitionCaptures(located.module_index, located.parameters, definition, &local);
        // Transfer known arguments into the definition's lexical parameter IDs.
        for (0..parameters.len) |offset| {
            const raw = parameters.start + offset;
            const parameter = module.semantic.parameterized_storage.comptime_parameters.items[raw];
            const argument = self.generics.findPatternArgument(module_index, application.arguments, offset, module.text(parameter.name)) orelse continue;
            switch (argument.value) {
                .projection => |projection| {
                    const value = self.generics.instantiateArgumentProjection(module_index, projection, bindings) catch |err| switch (err) {
                        error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => continue,
                        else => return err,
                    };
                    switch (value) {
                        .definition => |v| local.definitions[raw] = v,
                        .type => |v| local.types[raw] = v,
                        .comptime_int => |v| local.ints[raw] = v,
                    }
                },
                .definition => |definition_value| local.definitions[raw] = self.generics.instantiateDefinitionValue(module_index, definition_value, bindings) catch |err| switch (err) {
                    error.UnboundDefinitionParameter => null,
                    else => return err,
                },
                .type => |ty| local.types[raw] = self.generics.instantiateParameterizedType(module_index, ty, bindings) catch |err| switch (err) {
                    error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => null,
                    else => return err,
                },
                .comptime_int => |integer| local.ints[raw] = self.generics.evalInt(module_index, integer, bindings) catch |err| switch (err) {
                    error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => null,
                    else => return err,
                },
            }
        }
        if (input == .callable) {
            if (application.arguments.len > parameters.len) return false;
            const remaining: primitives.Range(ir.ComptimeParameterId) = .{
                .start = parameters.start + application.arguments.len,
                .len = parameters.len - application.arguments.len,
            };
            self.generics.bindGlobalArgumentsPartial(located.module_index, remaining, input.callable.arguments, &local) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return false,
            };
        }
        switch (input) {
            .callable => |call| {
                if (!try self.inferBindingsFromInputFields(located.module_index, located.shape, call.input, &local, field_offset, true)) return false;
                if (reach) |context|
                    if (!try self.inferBindingsFromReachDefaultFields(located.module_index, located.shape, call.input, &local, context, field_offset)) return false;
            },
            .fields => |node| {
                if (!try self.inferBindingsFromInputFields(located.module_index, located.shape, node, &local, field_offset, true)) return false;
                if (reach) |context|
                    if (!try self.inferBindingsFromReachDefaultFields(located.module_index, located.shape, node, &local, context, field_offset)) return false;
            },
            .value_type => |actual| if (!try self.inferInputType(located.module_index, located.shape, actual, &local)) return false,
            .signature_type => |required| if (!try self.inferSignatureBindings(located.module_index, located.shape, required, &local)) return false,
        }
        try self.generics.applyParameterDefaults(located.module_index, parameters, &local);
        // Captures are fixed lexical evidence. Traversing the family body may
        // check them, but cannot infer a different environment from call inputs.
        for (0..definition.captures.len) |offset| {
            const raw = located.parameters.start + offset;
            const captured = self.graph.generic_arguments.items[definition.captures.start + offset].value;
            switch (captured) {
                .definition => |value| {
                    const actual = local.definitions[raw] orelse return false;
                    if (value.origin != actual.origin or !global_types.genericArgumentsEqual(self.graph, value.captures, actual.captures)) return false;
                },
                .type => |ty| if (local.types[raw] == null or !global_types.equal(self.graph, local.types[raw].?, ty)) return false,
                .comptime_int => |integer| if (local.ints[raw] != integer) return false,
            }
        }
        // Return only evidence inferred from inputs/defaults. Result types never
        // determine these bindings, and no nominal identity is changed.
        for (0..parameters.len) |offset| {
            const raw = parameters.start + offset;
            const parameter = module.semantic.parameterized_storage.comptime_parameters.items[raw];
            const argument = self.generics.findPatternArgument(module_index, application.arguments, offset, module.text(parameter.name)) orelse continue;
            switch (argument.value) {
                .projection => |projection| {
                    const value = try self.generics.instantiateArgumentProjection(module_index, projection, bindings);
                    const actual: global_sg.GenericArgument.Value = switch (parameter.kind) {
                        .definition => .{ .definition = local.definitions[raw] orelse return false },
                        .type => .{ .type = local.types[raw] orelse return false },
                        .comptime_int => .{ .comptime_int = local.ints[raw] orelse return false },
                    };
                    if (!global_types.genericArgumentValuesEqual(self.graph, value, actual)) return false;
                },
                .definition => |definition_value| if (local.definitions[raw]) |actual| {
                    if (!try self.generics.inferDefinitionValue(module_index, definition_value, actual, bindings)) return false;
                },
                .type => |ty| if (local.types[raw]) |actual| {
                    if (!try self.inferInputType(module_index, ty, actual, bindings)) return false;
                },
                .comptime_int => |integer| if (local.ints[raw]) |actual| {
                    if (!try self.inferIntExpression(module_index, integer, actual, bindings)) return false;
                },
            }
        }
        return true;
    }

    fn matchClosedSignatureInput(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, input: global_sg.GlobalNodeId, bindings: *generic_mod.Resolver.Bindings, field_offset: u32) !bool {
        const ty = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch |err| switch (err) {
            error.UnboundGenericTypeParameter, error.UnboundComptimeParameter, error.ComptimeExecutionPending => return false,
            else => return err,
        };
        const fields = global_types.fields(self.graph, ty) orelse return false;
        if (field_offset > fields.len) return false;
        return self.core.matchCallInput(.{ .start = fields.start + field_offset, .len = fields.len - field_offset }, input) == .applicable;
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
        const shape = switch (storage.representation(pattern)) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return self.inferNamedSignature(module_index, pattern, input, bindings, field_offset, null),
            },
            else => return self.inferNamedSignature(module_index, pattern, input, bindings, field_offset, null),
        };
        if (field_offset > shape.fields.len) return false;

        const fields = storage.fields.items[shape.fields.start + field_offset ..][0 .. shape.fields.len - field_offset];
        for (fields, 0..) |field, expected_position| {
            const value = self.core.recordFieldValue(literal, expected_position, module.text(field.name)) orelse continue;
            // Reject unrelated nominal references before instantiating their
            // constraints; an inapplicable identity must not emit type diagnostics.
            if (self.graph.node(value).ty) |actual|
                if (self.definiteNominalReferenceMismatch(module_index, field.ty, actual)) return false;
            if (allow_contextual_concrete) {
                if (try self.contextualParameterizedLiteralFits(module_index, field.ty, bindings, value)) continue;
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
        const shape = switch (storage.representation(pattern)) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return self.inferNamedSignature(module_index, pattern, input, bindings, field_offset, context),
            },
            else => return self.inferNamedSignature(module_index, pattern, input, bindings, field_offset, context),
        };
        if (field_offset > shape.fields.len) return false;

        const fields = storage.fields.items[shape.fields.start + field_offset ..][0 .. shape.fields.len - field_offset];
        for (fields, 0..) |field, expected_position| {
            if (self.core.recordFieldValue(literal, expected_position, candidate_module.text(field.name)) != null) continue;

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
            if (!inferred) if (self.reach_diagnostics) |message| {
                // Render while the speculative candidate is alive; retain no
                // inferred type or graph-tail identity in the diagnostic.
                try message.print("\n  .{s} uses reach ", .{candidate_module.text(field.name)});
                for (storage.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len], 0..) |alternative, index| {
                    if (index != 0) try message.appendSlice(" or ");
                    for (storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len], 0..) |segment, part| {
                        if (part != 0) try message.append('.');
                        try message.appendSlice(candidate_module.text(segment));
                    }
                }
            };
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
                    if (selected != null or function.flags.is_once or function.input.len != 0 or function.output.len != 1) return null;
                    const ty = self.graph.fields.items[function.output.start].ty;
                    if (self.graph.isTypeUnresolved(ty)) return null;
                    selected = ty;
                }
                return selected;
            },
        }
    }

    fn bindKnownOperationAssociations(self: *Resolver, module_index: usize, parameters: primitives.Range(ir.ComptimeParameterId), arguments: primitives.Range(ir.ParameterizedGenericArgId), bindings: *generic_mod.Resolver.Bindings) !bool {
        if (parameters.len == 0) return true;
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage;
        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            const argument = self.generics.findPatternArgument(module_index, arguments, raw - parameters.start, module.text(parameter.name)) orelse return false;
            // Facts learned from operation inputs may bind a declared associated
            // pattern (e.g. Args = Packet#(T)); never use an expected output.
            const compatible = switch (argument.value) {
                .type => |pattern| if (bindings.types[raw]) |actual| try self.inferInputType(module_index, pattern, actual, bindings) else true,
                .comptime_int => |pattern| if (bindings.ints[raw]) |actual| try self.inferIntExpression(module_index, pattern, actual, bindings) else true,
                .definition => |pattern| if (bindings.definitions[raw]) |actual| try self.generics.inferDefinitionValue(module_index, pattern, actual, bindings) else true,
                .projection => true,
            };
            if (!compatible) return false;
            // Keep unrelated associated projections deferred until their own
            // implementation parameters are known; they are not dispatch inputs.
            const value = self.generics.instantiateArgumentValue(module_index, argument.value, bindings) catch |err| switch (err) {
                error.UnboundGenericTypeParameter, error.UnboundComptimeParameter, error.UnboundDefinitionParameter => continue,
                else => return err,
            };
            switch (parameter.kind) {
                .type => if (bindings.types[raw]) |old| {
                    if (value != .type or !global_types.equal(self.graph, old, value.type)) return false;
                },
                .comptime_int => if (bindings.ints[raw]) |old| {
                    if (value != .comptime_int or old != value.comptime_int) return false;
                },
                .definition => if (bindings.definitions[raw]) |old| {
                    if (value != .definition or old.origin != value.definition.origin or !global_types.genericArgumentsEqual(self.graph, old.captures, value.definition.captures)) return false;
                },
            }
            const start: u32 = @intCast(self.graph.generic_arguments.items.len);
            try self.graph.generic_arguments.append(self.allocator, .{ .name = try self.graph.addString(self.allocator, module.text(parameter.name)), .value = value });
            try self.generics.bindGlobalArgumentsPartial(module_index, parameters, .{ .start = start, .len = 1 }, bindings);
        }
        return true;
    }

    /// Inline operations capture implementation parameters by position. Infer
    /// in the callable's own parameter pool, then transfer the captured prefix
    /// back to the conformance; equal parameter names do not establish identity.
    pub fn inferImplementationInput(
        self: *Resolver,
        module_index: usize,
        operation: parameterized_storage.ContractOperation,
        captures: primitives.Range(ir.ComptimeParameterId),
        input: global_sg.GlobalNodeId,
        context: ReachInferenceContext,
        bindings: *generic_mod.Resolver.Bindings,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        associated: primitives.Range(ir.ParameterizedGenericArgId),
    ) !?global_sg.GlobalTypeId {
        const contracts = self.nested_call_context orelse return error.MissingOperationInstantiator;
        // Reject already-disproved candidates before materializing associated
        // types or named signatures that rely on those same constraints.
        const capture_storage = &self.modules[module_index].semantic.parameterized_storage;
        for (captures.start..captures.start + captures.len) |raw| {
            const parameter = capture_storage.comptime_parameters.items[raw];
            const constraint = parameter.constraint orelse continue;
            const actual = bindings.types[raw] orelse continue;
            if (try contracts.constraintArgumentsKnown(module_index, constraint, bindings)) {
                if (!try contracts.inferConstraintBindings(module_index, constraint, actual, bindings)) return null;
            }
        }
        if (!try self.bindKnownOperationAssociations(module_index, operation.associated_parameters, associated, bindings)) return null;
        if (operation.function == .expression) {
            const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
            const expression = storage.nodes.items[@intFromEnum(operation.function.expression)];
            if (expression == .pending) {
                const pending = storage.pending.items[@intFromEnum(expression.pending)];
                if (pending == .resolve_expression and pending.resolve_expression.kind == .entity_application) {
                    const application = storage.types.items[@intFromEnum(pending.resolve_expression.detail.entity_application)];
                    if (application == .resolved and application.resolved == .generic) {
                        if (!try self.inferFamilyApplication(module_index, application.resolved.generic, .{ .callable = .{ .input = input, .arguments = arguments } }, bindings, 0, context)) return null;
                    }
                }
            }
        }
        // Input inference may complete implementation parameters. Reapply their
        // associated definitions and reject inferred facts that contradict them.
        if (!try self.bindKnownOperationAssociations(module_index, operation.associated_parameters, associated, bindings)) return null;
        const target = try contracts.resolveFunctionTarget(module_index, operation.function, bindings);
        const definition = target.value(self.graph) orelse return error.DeferredGenericFunction;
        const declaration = self.graph.familyDeclaration(definition.origin);
        const located = self.findParameterized(declaration) orelse {
            if (arguments.len != 0) return null;
            const function_id = self.graph.declaration(declaration).function_id orelse return null;
            return self.graph.function(function_id).input_type;
        };
        const function = located.parameterized;
        const capture_count = if (operation.instantiate_associated) captures.len else 0;
        if (operation.instantiate_associated and (located.module_index != module_index or function.captured_parameter_count < capture_count)) return null;
        var inferred = try generic_mod.Resolver.Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);
        defer inferred.deinit(self.allocator);
        if (!operation.instantiate_associated) _ = try self.generics.bindDefinitionCaptures(located.module_index, function.parameters, definition, &inferred);
        for (0..capture_count) |index| {
            const from = captures.start + index;
            const to = function.parameters.start + index;
            inferred.types[to] = bindings.types[from];
            inferred.ints[to] = bindings.ints[from];
            inferred.definitions[to] = bindings.definitions[from];
        }
        const own_parameters: primitives.Range(ir.ComptimeParameterId) = .{
            .start = function.parameters.start + @max(function.captured_parameter_count, definition.captures.len),
            .len = function.parameters.len - @max(function.captured_parameter_count, definition.captures.len),
        };
        self.generics.bindGlobalArgumentsPartial(located.module_index, own_parameters, arguments, &inferred) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return null,
        };
        if (!try self.inferBindingsFromInput(located.module_index, function.input, input, &inferred)) return null;
        if (!try self.inferBindingsFromReachDefaults(located.module_index, function.input, input, &inferred, context)) return null;
        const implementation_parameters: primitives.Range(ir.ComptimeParameterId) = .{ .start = function.parameters.start, .len = capture_count };
        if ((try self.inferAndValidateConstraints(located.module_index, implementation_parameters, &inferred)) != .satisfied or
            !self.parametersBound(located.module_index, implementation_parameters, &inferred)) return null;
        for (0..capture_count) |index| {
            const from = function.parameters.start + index;
            const to = captures.start + index;
            bindings.types[to] = inferred.types[from];
            bindings.ints[to] = inferred.ints[from];
            bindings.definitions[to] = inferred.definitions[from];
        }
        if (operation.instantiate_associated) {
            const values = try self.generics.instantiateParameterizedArguments(module_index, associated, bindings);
            self.generics.bindGlobalArgumentsPartial(located.module_index, .{
                .start = function.parameters.start + capture_count,
                .len = function.captured_parameter_count - capture_count,
            }, values, &inferred) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return null,
            };
        }
        if ((try self.inferAndValidateConstraints(located.module_index, own_parameters, &inferred)) != .satisfied or
            !self.parametersBound(located.module_index, own_parameters, &inferred)) return null;
        const signature = self.generics.instantiateParameterizedType(located.module_index, function.input, &inferred) catch |err| switch (err) {
            error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => return null,
            else => return err,
        };
        return signature;
    }

    /// Probe an implementation-owned interface through ordinary input inference.
    /// Bodies stay deferred, and all graph/call/default effects are rolled back.
    pub fn probeImplementationOperation(function_context: *anyopaque, module_index: usize, declaration: global_sg.GlobalFamilyDefinitionId, participant_count: u32, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, arguments: primitives.Range(global_sg.GlobalGenericArgId), deferred: *bool, failure: *?contract_mod.ParticipantConformanceFailure) anyerror!?contract_mod.Resolver.OperationCandidate {
        const self: *Resolver = @ptrCast(@alignCast(function_context));
        const contracts = self.nested_call_context orelse return error.MissingOperationInstantiator;
        const boundary: @import("type_recipe.zig").Recipe.Boundary = .{
            .types = self.graph.types.items.len,
            .declarations = self.graph.declarations.items.len,
            .nodes = self.graph.nodes.items.len,
            .type_definitions = self.graph.type_definitions.items.len,
            .family_definitions = self.graph.family_definitions.items.len,
        };
        var scope = self.beginSpeculation();
        defer scope.deinit();
        const saved_publication = self.publishing_signature;
        self.publishing_signature = true;
        defer self.publishing_signature = saved_publication;
        const prefix = try self.allocator.alloc(implementation_arguments.Participant, participant_count);
        defer self.allocator.free(prefix);
        @memset(prefix, .inferred);
        var resolver: implementation_arguments.Resolver = .{ .graph = self.graph, .modules = self.modules, .core = self.core, .generics = self.generics, .functions = self, .contracts = contracts };
        const result = resolver.inferOperationWithArguments(declaration, prefix, name, input, reach, arguments) catch |err| switch (err) {
            error.ComptimeExecutionPending => {
                scope.retainPendingExecution();
                deferred.* = true;
                return null;
            },
            else => return err,
        };
        const selected = switch (result) {
            .selected => |value| value,
            .ambiguous => return .{ .declaration = declaration, .participants = .ambiguous },
            .deferred => {
                deferred.* = true;
                return null;
            },
            else => return null,
        };
        var retained = false;
        defer if (!retained) self.allocator.free(selected.participants);
        const start: u32 = @intCast(self.graph.generic_arguments.items.len);
        for (selected.participants) |participant| try self.graph.generic_arguments.append(self.allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = participant } });
        const contract = try self.generics.internType(.{ .generic = .{ .base = declaration, .arguments = .{ .start = start, .len = participant_count } } });
        _ = contracts.makeSpecializedScopedOperationCall(module_index, contract, name, arguments, input, reach, self.graph.node(input).source) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ComptimeExecutionPending => {
                scope.retainPendingExecution();
                deferred.* = true;
                return null;
            },
            else => {
                if (contracts.participant_conformance_failure) |diagnostic| {
                    var retained_failure = diagnostic;
                    retained_failure.input = null;
                    retained_failure.output = null;
                    const owner = @intFromEnum(self.graph.moduleForDeclaration(self.graph.familyDeclaration(declaration)).?);
                    const local = @intFromEnum(self.graph.familyDeclaration(declaration)) - self.offsets[owner].declaration_base;
                    retained_failure.contract_name = self.modules[owner].text(self.modules[owner].declarations.items[local].name);
                    retained_failure.operation = name;
                    failure.* = retained_failure;
                }
                return null;
            },
        } orelse return null;
        const candidate = try contracts.captureOperationCandidate(declaration, selected.participants, false, boundary);
        retained = true;
        return candidate;
    }

    // Return the explanation with its decision. Recursive probes and later
    // candidates must not overwrite another check's diagnostic state.
    const ConstraintCheck = union(enum) {
        const Failure = struct {
            contract_decl: global_sg.GlobalFamilyDefinitionId,
            actual: global_sg.GlobalTypeId,
            parameter_name: []const u8,
        };
        satisfied,
        rejected: ?Failure,
    };

    fn inferAndValidateConstraints(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *generic_mod.Resolver.Bindings,
    ) !ConstraintCheck {
        self.generics.applyParameterDefaults(module_index, parameters, bindings) catch |err| switch (err) {
            error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => return .{ .rejected = null },
            else => return err,
        };
        var failure: ?ConstraintCheck.Failure = null;
        const contracts = self.nested_call_context orelse return .satisfied;
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
                    .definition => @intFromBool(bindings.definitions[raw] != null),
                };
            }

            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                const constraint_id = parameter.constraint orelse continue;
                if (parameter.kind != .type) continue;
                const concrete = bindings.types[raw] orelse continue;
                const constraint_ok = try contracts.inferConstraintBindings(module_index, constraint_id, concrete, bindings);

                if (!constraint_ok) {
                    if (self.constraint_diagnostic != null and
                        try contracts.constraintArgumentsKnown(module_index, constraint_id, bindings)) failure = .{
                        .contract_decl = try contracts.constraintDefinition(module_index, constraint_id),
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
                    .definition => @intFromBool(bindings.definitions[raw] != null),
                };
            }
            made_progress = after > before;
            if (!made_progress and failed) return .{ .rejected = failure };
        }

        // Every bound constraint was checked in the last no-progress round.
        // This pass only needs to reject constraints left without a binding.
        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            if (parameter.constraint == null) continue;
            if (parameter.kind != .type) return .{ .rejected = null };
            if (bindings.types[raw] == null) return .{ .rejected = null };
        }
        return .satisfied;
    }

    fn parametersBound(
        self: *const Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *const generic_mod.Resolver.Bindings,
    ) bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            if (switch (parameter.kind) {
                .type => bindings.types[raw] == null,
                .comptime_int => bindings.ints[raw] == null,
                .definition => bindings.definitions[raw] == null,
            }) return false;
        }
        return true;
    }

    pub fn appendBoundArguments(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *const generic_mod.Resolver.Bindings,
    ) !primitives.Range(global_sg.GlobalGenericArgId) {
        return self.generics.appendBoundArguments(module_index, parameters, bindings);
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
        const selected_definition = try self.core.resolveDefinitionAlias(current_module, reference);
        return self.resolveImplicitGenericFunctionFiltered(
            current_module,
            if (selected_definition) |value| self.graph.familyDefinitionName(value.origin) else module.text(reference.name),
            module_filter,
            input,
            reach_context,
            null,
            selected_definition,
        );
    }

    pub fn resolveOperationIdentity(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef) !?global_sg.Node {
        return self.resolveOperationIdentityFiltered(module_index, name, input, reach, source, null);
    }

    pub fn resolveOperationIdentityFiltered(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef, module_filter: ?global_sg.GlobalModuleId) !?global_sg.Node {
        return self.resolveSpecializedOperationIdentityFiltered(module_index, name, input, reach, source, module_filter, .{ .start = 0, .len = 0 }, null);
    }

    pub fn resolveSpecializedOperationIdentityFiltered(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef, module_filter: ?global_sg.GlobalModuleId, arguments: primitives.Range(global_sg.GlobalGenericArgId), reference: ?module_entities.ExternalRef) !?global_sg.Node {
        const contracts = self.nested_call_context orelse return null;
        var candidates = try contracts.specializedOperationCandidatesFiltered(module_index, name, input, reach, module_filter, arguments);
        defer candidates.deinit(self.allocator);
        const ordinary: core_mod.Resolver.FunctionMatch = if (arguments.len == 0) try self.core.matchFunctionNamedWithReach(module_index, name, module_filter, input, reach) else .no_match;
        if (candidates.items.items.len == 0) {
            if (candidates.deferred) return error.DeferredOperationIdentity;
            if (ordinary == .function or candidates.failure != null) {
                const generic = if (arguments.len == 0) try self.implicitOrdinaryApplicableFiltered(module_index, name, input, reach, module_filter) else try self.explicitOrdinaryApplicable(module_index, reference.?, arguments, input, reach);
                if (generic == .ambiguous or (ordinary == .function and generic == .applicable and generic.applicable != self.graph.functions.items[@intFromEnum(ordinary.function)].declaration)) {
                    contracts.participant_conformance_failure = .{ .source = source, .contract_name = name, .operation = name, .reason = "multiple applicable operation identities; qualify the function explicitly" };
                    return error.AmbiguousOperationIdentity;
                }
                if (generic == .deferred) return error.DeferredOperationIdentity;
                if (ordinary == .no_match and generic == .missing) {
                    if (candidates.failure) |failure| {
                        contracts.participant_conformance_failure = failure;
                        return error.InvalidContractConformance;
                    }
                }
            }
            return null;
        }
        const generic = if (arguments.len == 0) try self.implicitOrdinaryApplicableFiltered(module_index, name, input, reach, module_filter) else try self.explicitOrdinaryApplicable(module_index, reference.?, arguments, input, reach);
        if (candidates.items.items.len > 1 or ordinary == .function or ordinary == .ambiguous or generic == .applicable or generic == .ambiguous) {
            contracts.participant_conformance_failure = .{ .source = source, .contract_name = name, .operation = name, .reason = "multiple applicable operation identities; qualify the contract operation explicitly" };
            return error.AmbiguousOperationIdentity;
        }
        if (candidates.deferred or ordinary == .deferred or generic == .deferred) return error.DeferredOperationIdentity;
        return contracts.callSpecializedOperationCandidate(module_index, candidates.items.items[0], name, input, reach, source, arguments);
    }

    pub fn hasVisibleParameterizedFunctionName(
        self: *const Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
    ) bool {
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                if (parameterized.concrete_function != null) continue;
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
        selected_definition: ?global_sg.DefinitionValue,
    ) !global_sg.GlobalFunctionId {
        const selected = try self.selectImplicitGenericFunctionFiltered(current_module, name, module_filter, input, reach, ambiguity_candidates, selected_definition);
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

    fn explicitOrdinaryApplicable(self: *Resolver, module_index: usize, reference: module_entities.ExternalRef, arguments: primitives.Range(global_sg.GlobalGenericArgId), input: global_sg.GlobalNodeId, reach: ReachInferenceContext) !OrdinaryApplicability {
        var speculation = self.beginSpeculation();
        const argument_failure = self.generics.argument_failure;
        defer {
            speculation.deinit();
            self.generics.argument_failure = argument_failure;
        }
        const selected = self.selectExplicitGenericFunction(module_index, &self.modules[module_index], reference, arguments, input, reach, false, null) catch |err| return switch (err) {
            error.ComptimeExecutionPending => pending: {
                speculation.retainPendingExecution();
                break :pending .deferred;
            },
            error.OutOfMemory => err,
            error.DeferredGenericFunction => .deferred,
            error.AmbiguousGenericFunction => .ambiguous,
            else => .missing,
        };
        return .{ .applicable = selected.declaration };
    }

    fn implicitOrdinaryApplicableFiltered(self: *Resolver, module_index: usize, name: []const u8, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, module_filter: ?global_sg.GlobalModuleId) !OrdinaryApplicability {
        var speculation = self.beginSpeculation();
        const argument_failure = self.generics.argument_failure;
        defer {
            speculation.deinit();
            self.generics.argument_failure = argument_failure;
        }
        const selected = self.selectImplicitGenericFunctionFiltered(module_index, name, module_filter, input, reach, null, null) catch |err| {
            return switch (err) {
                error.ComptimeExecutionPending => blk: {
                    speculation.retainPendingExecution();
                    break :blk .deferred;
                },
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
        selected_definition: ?global_sg.DefinitionValue,
    ) !ImplicitGenericSelection {
        if (self.profile_io != null) self.selection_profile.implicit_calls += 1;
        _ = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return error.MissingGenericInputType,
        };
        var selected: ?global_sg.GlobalDeclId = null;
        var selected_arguments: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = 0, .len = 0 };
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
        var binding_definitions: std.ArrayList(?global_sg.DefinitionValue) = .empty;
        defer binding_definitions.deinit(self.allocator);
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
            if (selected_definition) |id| {
                if (self.graph.familyForDeclaration(declaration) != id.origin) continue;
            } else if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
            candidate_count += 1;
            const parameter_count = candidate_module.semantic.parameterized_storage.comptime_parameters.items.len;
            try binding_types.resize(self.allocator, parameter_count);
            try binding_ints.resize(self.allocator, parameter_count);
            try binding_definitions.resize(self.allocator, parameter_count);
            @memset(binding_types.items, null);
            @memset(binding_ints.items, null);
            @memset(binding_definitions.items, null);
            var bindings: generic_mod.Resolver.Bindings = .{
                .types = binding_types.items,
                .ints = binding_ints.items,
                .definitions = binding_definitions.items,
            };
            if (selected_definition) |definition| _ = try self.generics.bindDefinitionCaptures(candidate_index, parameterized.parameters, definition, &bindings);
            var candidate_deferred = false;
            const matches = self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings) catch |err| matches: {
                if (err == error.ConflictingGenericArgument) {
                    conflicting_candidates += 1;
                } else candidate_deferred = true;
                break :matches false;
            };
            if (!matches) {
                if (candidate_deferred) saw_deferred = true;
                continue;
            }
            if (reach_context) |context|
                if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
            self.addProfileTime(phase_start, &self.selection_profile.implicit_prefilter_inference_ns);
            prefilter_active = false;
            const constraints_start = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            const constraint_check = try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings);
            if (self.profile_io) |io| {
                const elapsed: u64 = @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - constraints_start);
                self.profile_constraints_ns += elapsed;
                self.selection_profile.implicit_constraints_ns += elapsed;
            }
            if (constraint_check == .rejected) {
                try self.recordConstraintFailure(candidate_index, declaration, parameterized.input, &bindings, input, constraint_check.rejected);
                continue;
            }
            if (!self.parametersBound(candidate_index, parameterized.parameters, &bindings)) continue;
            phase_start = self.profileTimestamp();
            applicability_start = phase_start;
            applicability_active = true;
            switch (try self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input)) {
                .no_match => continue,
                .deferred => {
                    saw_deferred = true;
                    continue;
                },
                .applicable => {},
            }
            self.addProfileTime(applicability_start, &self.selection_profile.implicit_applicability_ns);
            applicability_active = false;
            if (selected == null) {
                phase_start = self.profileTimestamp();
                // Only one applicable identity needs durable arguments.
                // Failed and deferred probes leave no argument tail.
                const range = try self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings);
                self.addProfileTime(phase_start, &self.selection_profile.implicit_argument_materialization_ns);
                selected = declaration;
                selected_arguments = range;
                if (ambiguity_candidates) |candidates| {
                    candidates.clearRetainingCapacity();
                    try candidates.append(self.allocator, declaration);
                }
            } else if (declaration != selected.?) {
                tied = true;
                if (ambiguity_candidates) |candidates|
                    try candidates.append(self.allocator, declaration);
            }
        }
        if (tied) return error.AmbiguousGenericFunction;
        if (saw_deferred) return error.DeferredGenericFunction;
        const declaration = selected orelse return if (saw_deferred) error.DeferredGenericFunction else if (candidate_count == 1 and conflicting_candidates == 1) error.ConflictingGenericArgument else error.NoMatchingGenericFunction;
        return .{ .declaration = declaration, .arguments = selected_arguments };
    }

    fn contextualParameterizedLiteralFits(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        bindings: *generic_mod.Resolver.Bindings,
        value: global_sg.GlobalNodeId,
    ) anyerror!bool {
        // Context probes can materialize constrained nominal types even before
        // the actual argument is resolved. Keep those types speculative: the
        // final constraint pass must see only selected or source-written types.
        var speculation = self.beginSpeculation();
        const saved_stats = self.generics.stats;
        defer {
            speculation.deinit();
            self.generics.stats = saved_stats;
        }
        errdefer |err| {
            if (err == error.ComptimeExecutionPending) speculation.retainPendingExecution();
        }
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch |err| switch (err) {
            error.ComptimeExecutionPending => return error.ComptimeExecutionPending,
            else => return false,
        };
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
        const Base = union(enum) { nominal: global_sg.GlobalTypeDefinitionId, family: global_sg.GlobalFamilyDefinitionId };
        const actual_base: Base = switch (self.graph.semanticType(actual_pointer.child)) {
            .nominal => |definition| .{ .nominal = definition },
            .generic => |generic| .{ .family = generic.base },
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
        const expected_base: Base = switch (storage.types.items[@intFromEnum(expected_pointer.child)]) {
            .resolved => |ty| switch (ty) {
                .nominal => |definition| .{ .nominal = globalizer.globalTypeDefinition(self.offsets[module_index], definition) },
                .generic => |generic| .{ .family = self.generics.resolveParameterizedFamily(module_index, generic.base) catch return false },
                else => return false,
            },
            else => return false,
        };
        // Contract participants require conformance matching. Concrete nominal
        // definitions and type families can be rejected by identity alone.
        if (expected_base == .family and self.graph.familyDefinition(expected_base.family).kind == .contract) return false;
        if (expected_base == .family) {
            const located = self.generics.findTypeParameterized(expected_base.family) orelse return false;
            const owner = &self.modules[located.module_index];
            if (owner.semantic.parameterized_storage.ir.types.items[@intFromEnum(located.parameterized.body)] != .definition) return false;
        }
        return !std.meta.eql(actual_base, expected_base);
    }

    fn recordConstraintFailure(
        self: *Resolver,
        module_index: usize,
        declaration: global_sg.GlobalDeclId,
        pattern: ir.ParameterizedTypeId,
        bindings: *generic_mod.Resolver.Bindings,
        input: global_sg.GlobalNodeId,
        rejected: ?ConstraintCheck.Failure,
    ) !void {
        const diagnostic = self.constraint_diagnostic orelse return;
        if (diagnostic.* != null) return;
        const failure = rejected orelse return;
        // A bound can fail on a candidate whose other arguments do not fit.
        // Only explain constraints for otherwise compatible signatures, using
        // the same matcher as function applicability rather than a second rule set.
        switch (try self.matchParameterizedInput(module_index, pattern, bindings, input)) {
            .applicable => {},
            else => return,
        }
        var name = std.array_list.Managed(u8).init(self.allocator);
        defer name.deinit();
        // Associated-parameter inference can create temporary types. Capture the
        // first explanation now, before later candidate work or rollback.
        try @import("type_names.zig").appendTypeName(&name, self.graph, failure.actual);
        const text = try name.toOwnedSlice();
        diagnostic.* = .{
            .function = declaration,
            .contract_decl = failure.contract_decl,
            .actual_name = text,
            .parameter_name = failure.parameter_name,
        };
    }

    /// Diagnostic probes use normal selection and roll back its graph and
    /// ownership effects. Bounds and unavailable reach defaults are explanations
    /// only; discard them when another visible identity accepts the call.
    pub fn probeGenericCallFailure(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        reach: ReachInferenceContext,
        missing_reach: *std.array_list.Managed(u8),
    ) !?ConstraintFailure {
        var speculation = self.beginSpeculation();
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        const saved_core_stats = self.core.stats;
        const saved_diagnostics = self.constraint_diagnostic;
        const saved_reach_diagnostics = self.reach_diagnostics;
        defer {
            speculation.deinit();
            self.stats = saved_stats;
            self.generics.stats = saved_generic_stats;
            self.core.stats = saved_core_stats;
            self.constraint_diagnostic = saved_diagnostics;
            self.reach_diagnostics = saved_reach_diagnostics;
        }
        var failure: ?ConstraintFailure = null;
        errdefer if (failure) |value| self.allocator.free(value.actual_name);
        self.constraint_diagnostic = &failure;
        missing_reach.clearRetainingCapacity();
        self.reach_diagnostics = missing_reach;
        // TODO: Preserve selected-body instantiation failures separately from
        // selection failures, so rejected bounds do not hide a nested error.
        const selected = selection: {
            if (try self.generics.resolveCallArguments(current_module, reference)) |relocated| {
                _ = self.resolveExplicitGenericFunction(current_module, module, reference, relocated, input, reach) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    break :selection false;
                };
            } else {
                _ = self.resolveImplicitGenericFunction(current_module, module, reference, input, reach) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    break :selection false;
                };
            }
            break :selection true;
        };
        if (selected) {
            // A successful selection is not a constraint error even if other
            // candidates failed their bounds.
            if (failure) |value| self.allocator.free(value.actual_name);
            missing_reach.clearRetainingCapacity();
            return null;
        }
        return failure;
    }

    /// Re-run implicit generic selection transactionally for diagnostics and
    /// report every applicable declaration identity. This keeps
    /// diagnostics coupled to actual inference and applicability rather
    /// than maintaining an approximate second applicability matcher.
    pub fn collectImplicitGenericAmbiguity(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        candidates: *std.ArrayList(global_sg.GlobalDeclId),
    ) !bool {
        var speculation = self.beginSpeculation();
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        const saved_core_stats = self.core.stats;
        defer {
            speculation.deinit();
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
            null,
        ) catch |err| return switch (err) {
            error.AmbiguousGenericFunction => true,
            else => false,
        };
        return false;
    }

    fn matchParameterizedInput(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, bindings: *generic_mod.Resolver.Bindings, input: global_sg.GlobalNodeId) !core_mod.Resolver.RecordMatch {
        var speculation = self.beginSpeculation();
        const saved_stats = self.generics.stats;
        defer {
            speculation.deinit();
            self.generics.stats = saved_stats;
        }
        const ty = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch |err| return switch (err) {
            error.OutOfMemory => err,
            error.ComptimeExecutionPending => pending: {
                speculation.retainPendingExecution();
                break :pending .deferred;
            },
            error.DeferredGenericFunction,
            error.UnresolvedAssociatedType,
            error.UnboundGenericTypeParameter,
            error.UnboundComptimeParameter,
            error.UnboundDefinitionParameter,
            => .deferred,
            // A failed candidate is not unfinished work. Speculation restores
            // its diagnostics before another operation identity is considered.
            else => .no_match,
        };
        const fields = global_types.fields(self.graph, ty) orelse return if (self.unresolvedSignature(ty) == .deferred) .deferred else .no_match;
        return self.core.matchCallInput(fields, input);
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
            .definition => {
                const arguments = self.generics.definitionArguments(module_index, pattern, actual) orelse return false;
                for (0..arguments.pattern.len) |position| {
                    const wanted = storage.generic_arguments.items[arguments.pattern.start + position];
                    const given = self.graph.generic_arguments.items[arguments.actual.start + position];
                    switch (wanted.value) {
                        .projection => |projection| if (!global_types.genericArgumentValuesEqual(self.graph, try self.generics.instantiateArgumentProjection(module_index, projection, bindings), given.value)) return false,
                        .definition => |definition| {
                            if (given.value != .definition) return false;
                            if (!try self.generics.inferDefinitionValue(module_index, definition, given.value.definition, bindings)) return false;
                        },
                        .type => |ty| {
                            if (given.value != .type or !try self.inferInputType(module_index, ty, given.value.type, bindings)) return false;
                        },
                        .comptime_int => |integer| {
                            if (given.value != .comptime_int or !try self.inferIntExpression(module_index, integer, given.value.comptime_int, bindings)) return false;
                        },
                    }
                }
                return true;
            },
            .parameter => |parameter| {
                const comptime_parameter = module.semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter)];
                // A contract declaration can appear as an intermediate input
                // type while a caller is still unspecialized. Only an
                // implementer's type may bind its constrained parameter.
                if (comptime_parameter.constraint != null) switch (self.graph.types.items[@intFromEnum(actual)]) {
                    .definition => |declaration| if (self.graph.familyDefinition(declaration).kind == .contract) return false,
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
                    const value = global_types.nullableChild(self.graph, actual) orelse return false;
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
                    const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch |err| switch (err) {
                        error.ComptimeExecutionPending => return error.ComptimeExecutionPending,
                        else => return false,
                    };
                    if (self.core.valueTypesCompatible(actual, expected)) return true;
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
                    const definition = try self.generics.resolveParameterizedDefinitionValue(module_index, generic.base, bindings);
                    const declaration = definition.origin;
                    const located = self.generics.findTypeParameterized(declaration) orelse return false;
                    const owner = &self.modules[located.module_index];
                    const body = owner.semantic.parameterized_storage.ir.types.items[@intFromEnum(located.parameterized.body)];
                    if (body != .definition)
                        return self.inferFamilyApplication(module_index, generic, .{ .value_type = actual }, bindings, 0, null);
                    const value = switch (self.graph.types.items[@intFromEnum(actual)]) {
                        .generic => |value| value,
                        else => return false,
                    };
                    if (declaration != value.base) return false;
                    if (definition.captures.len > located.parameterized.parameters.len or
                        generic.arguments.len != located.parameterized.parameters.len - definition.captures.len or
                        value.arguments.len != located.parameterized.parameters.len) return false;
                    const actual_captures = primitives.Range(global_sg.GlobalGenericArgId){ .start = value.arguments.start, .len = definition.captures.len };
                    if (!global_types.genericArgumentsEqual(self.graph, definition.captures, actual_captures)) return false;
                    // Bind by declaration parameter order, regardless of the
                    // participant's positional or reordered named spelling.
                    for (definition.captures.len..located.parameterized.parameters.len) |position| {
                        const parameter = owner.semantic.parameterized_storage.comptime_parameters.items[located.parameterized.parameters.start + position];
                        const name = owner.text(parameter.name);
                        const argument = self.generics.findPatternArgument(module_index, generic.arguments, position - definition.captures.len, name) orelse return false;
                        const concrete = self.generics.findGlobalArgument(name, value.arguments, position) orelse return false;
                        switch (argument.value) {
                            .projection => |projection| if (!global_types.genericArgumentValuesEqual(self.graph, try self.generics.instantiateArgumentProjection(module_index, projection, bindings), concrete.value)) return false,
                            .definition => |definition_value| {
                                if (concrete.value != .definition or !try self.generics.inferDefinitionValue(module_index, definition_value, concrete.value.definition, bindings)) return false;
                            },
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
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch |err| switch (err) {
            error.ComptimeExecutionPending => return error.ComptimeExecutionPending,
            else => return false,
        };
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
            .binary, .projection, .execution => (self.generics.evalInt(module_index, expression, bindings) catch |err| switch (err) {
                error.ComptimeExecutionPending => return error.ComptimeExecutionPending,
                else => return false,
            }) == actual,
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
                .comptime_int, .definition => return error.ReferenceTargetMustBeType,
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
        const target_kind = switch (global_types.representation(self.graph, target) orelse return error.InvalidIntegerConversion) {
            .builtin => |kind| kind,
            else => return error.InvalidIntegerConversion,
        };
        const target_range = primitives.integerRange(target_kind, self.graph.target.stdTarget()) orelse return error.InvalidIntegerConversion;
        if (std.mem.eql(u8, name, "__integer_conversion")) {
            const literal = self.graph.node(input).content.struct_value_literal;
            if (literal.fields.len != 1) return error.InvalidIntegerConversion;
            const value = self.graph.value_fields.items[literal.fields.start].value;
            const original = self.graph.node(value).ty orelse return error.InvalidIntegerConversion;
            const kind = switch (global_types.representation(self.graph, original) orelse return error.InvalidIntegerConversion) {
                .builtin => |kind| kind,
                else => return error.InvalidIntegerConversion,
            };
            _ = primitives.integerRange(kind, self.graph.target.stdTarget()) orelse return error.InvalidIntegerConversion;
            return .{ .source = source, .ty = target, .content = .{ .explicit_cast = .{ .value = value, .target_type = target } } };
        }
        const original = from orelse return error.InvalidIntegerConversion;
        const original_kind = switch (global_types.representation(self.graph, original) orelse return error.InvalidIntegerConversion) {
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
        const size = global_types.sizeOf(self.graph, measured_type orelse return error.SizeOfTypeMissing) catch |err| switch (err) {
            error.UnmaterializedGlobalType, error.UnmaterializedGenericType => return error.ComptimeExecutionPending,
            else => return null,
        };
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
        const alignment = global_types.alignmentOf(self.graph, measured_type orelse return error.AlignmentOfTypeMissing) catch |err| switch (err) {
            error.UnmaterializedGlobalType, error.UnmaterializedGenericType => return error.ComptimeExecutionPending,
            else => return null,
        };
        return .{
            .source = source,
            .ty = try self.generics.internType(.{ .builtin = .UIntNative }),
            .content = .{ .int_literal = std.math.cast(i64, alignment) orelse return error.TypeAlignmentOverflow },
        };
    }

    /// Preserve the aliased function definition. Infer callable parameters
    /// from the selected requirement's inputs, never its result type or a
    /// search through same-named functions. This does not
    /// equate the two domain record types or convert a record value: ordinary
    /// call construction contextualizes the argument literal to the callee.
    fn inferSignatureBindings(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, required: global_sg.GlobalTypeId, bindings: *generic_mod.Resolver.Bindings) !bool {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const representation = storage.representation(pattern);
        if (representation == .resolved and representation.resolved == .generic)
            return self.inferFamilyApplication(module_index, representation.resolved.generic, .{ .signature_type = required }, bindings, 0, null) catch |err| switch (err) {
                error.ConflictingGenericArgument => false,
                else => return err,
            };
        if (representation != .resolved or representation.resolved != .structural) {
            const actual = self.generics.instantiateParameterizedType(module_index, pattern, bindings) catch |err| switch (err) {
                error.UnboundGenericTypeParameter, error.UnboundComptimeParameter => return false,
                else => return err,
            };
            return global_types.operationInputsCompatible(self.graph, global_types.fields(self.graph, required) orelse return false, global_types.fields(self.graph, actual) orelse return false);
        }
        const fields = representation.resolved.structural.fields;
        const inputs = global_types.fields(self.graph, required) orelse return false;
        if (fields.len < inputs.len) return false;
        for (0..inputs.len) |position| {
            const wanted = storage.fields.items[fields.start + position];
            const given = self.graph.fields.items[inputs.start + position];
            if (!std.mem.eql(u8, module.text(wanted.name), self.graph.text(given.name))) return false;
            if (!(self.inferInputType(module_index, wanted.ty, given.ty, bindings) catch |err| switch (err) {
                error.ConflictingGenericArgument => return false,
                else => return err,
            })) return false;
        }
        for (inputs.len..fields.len) |position|
            if (storage.fields.items[fields.start + position].default_value == null) return false;
        return true;
    }

    pub fn callImplementationOperation(context: *anyopaque, module_index: usize, declaration: global_sg.GlobalDeclId, captures: primitives.Range(global_sg.GlobalGenericArgId), arguments: primitives.Range(global_sg.GlobalGenericArgId), input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef) anyerror!global_sg.Node {
        const self: *Resolver = @ptrCast(@alignCast(context));
        if (self.findParameterized(declaration) != null) {
            const family = self.graph.familyForDeclaration(declaration) orelse return error.GenericFunctionParameterizedNotFound;
            const reference = module_entities.ExternalRef{ .kind = .function, .module_path = null, .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = source.file_index - self.offsets[module_index].file_base, .offset = source.offset } };
            return self.makeDefinitionCall(module_index, reference, .{ .origin = family, .captures = captures }, arguments, input, reach, source);
        }
        if (arguments.len != 0) return error.TooManyGenericArguments;
        const function = self.graph.declaration(declaration).function_id orelse return error.DeferredGenericFunction;
        return self.makeConcreteFunctionCall(function, input, reach, source);
    }

    fn makeConcreteFunctionCall(self: *Resolver, function: global_sg.GlobalFunctionId, input: global_sg.GlobalNodeId, reach: ReachInferenceContext, source: primitives.SourceRef) !global_sg.Node {
        if (self.core.functionSignaturePending(function)) return error.DeferredGenericFunction;
        const signature = self.graph.function(function);
        if (self.core.callInputHasPendingTypes(input)) return error.DeferredGenericFunction;
        switch (try self.core.matchCallInputWithReach(signature.input, input, reach)) {
            .deferred => return error.DeferredGenericFunction,
            .no_match => {
                self.generics.comptime_failure = .{ .source = source, .reason = "arguments do not match the selected function definition, including its required reachable capabilities" };
                return error.InvalidGenericCallArguments;
            },
            .applicable => {},
        }
        if (!try self.core.completeRecordFieldsWithContext(signature.input, input, reach)) return error.DeferredGenericFunction;
        try self.core.trackReachedCall(function, input, reach, false);
        return .{ .source = source, .ty = try self.core.functionOutputType(function), .content = .{ .function_call = .{ .callee = function, .input = input } } };
    }

    pub fn inferOperationParameters(context: *anyopaque, module_index: usize, requirement: @import("../module/parameterized/storage.zig").ContractRequirement, input: global_sg.GlobalNodeId, bindings: *generic_mod.Resolver.Bindings, reach: ReachInferenceContext) anyerror!bool {
        const signature = requirement.signature orelse return false;
        const self: *Resolver = @ptrCast(@alignCast(context));
        if (!try self.inferBindingsFromInput(module_index, signature.input, input, bindings)) return false;
        if (!try self.inferBindingsFromReachDefaults(module_index, signature.input, input, bindings, reach)) return false;
        if ((try self.inferAndValidateConstraints(module_index, requirement.parameters, bindings)) != .satisfied) return false;
        return self.parametersBound(module_index, requirement.parameters, bindings);
    }

    pub fn instantiateGenericOperation(context: *anyopaque, declaration: global_sg.GlobalDeclId, captures: primitives.Range(global_sg.GlobalGenericArgId), input: global_sg.GlobalTypeId, output: global_sg.GlobalTypeId, contextual: bool) anyerror!global_sg.GlobalFunctionId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        const located = self.findParameterized(declaration) orelse return error.GenericFunctionParameterizedNotFound;
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        try self.generics.bindGlobalArgumentsPartial(located.module_index, .{ .start = located.parameterized.parameters.start, .len = captures.len }, captures, &bindings);
        if (!try self.inferSignatureBindings(located.module_index, located.parameterized.input, input, &bindings)) return error.OperationAliasInputMismatch;
        if ((try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &bindings)) != .satisfied) return error.OperationAliasConstraintMismatch;
        const arguments = try self.appendBoundArguments(located.module_index, located.parameterized.parameters, &bindings);
        const saved_publication = self.publishing_signature;
        self.publishing_signature = true;
        defer self.publishing_signature = saved_publication;
        return self.instantiateWithSignature(declaration, arguments, if (contextual) .{ .input = input, .output = output } else null);
    }

    pub fn instantiateOperationValue(context: *anyopaque, module_index: usize, node: ir.ParameterizedNodeId, bindings: *generic_mod.Resolver.Bindings) anyerror!global_sg.GlobalNodeId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        return self.instantiateComptimeExpression(module_index, node, bindings);
    }

    pub fn instantiateOperationAlias(context: *anyopaque, definition: global_sg.DefinitionValue, input: global_sg.GlobalTypeId) anyerror!global_sg.GlobalFunctionId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        const declaration = self.graph.familyDeclaration(definition.origin);
        const saved_publication = self.publishing_signature;
        self.publishing_signature = true;
        defer self.publishing_signature = saved_publication;
        const located = self.findParameterized(declaration) orelse return error.GenericFunctionParameterizedNotFound;
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        _ = try self.generics.bindDefinitionCaptures(located.module_index, located.parameterized.parameters, definition, &bindings);
        if (!try self.inferSignatureBindings(located.module_index, located.parameterized.input, input, &bindings)) return error.OperationAliasInputMismatch;
        if ((try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &bindings)) != .satisfied) return error.OperationAliasConstraintMismatch;
        const arguments = self.appendBoundArguments(located.module_index, located.parameterized.parameters, &bindings) catch |err| {
            if (err == error.MissingGenericArgument) return error.OperationAliasMissingParameter;
            return err;
        };
        return self.instantiate(declaration, arguments);
    }

    pub fn instantiateReferencedFunction(context: *anyopaque, declaration: global_sg.GlobalDeclId, arguments: primitives.Range(global_sg.GlobalGenericArgId), input: global_sg.GlobalTypeId, output: global_sg.GlobalTypeId) anyerror!global_sg.GlobalFunctionId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        const saved_publication = self.publishing_signature;
        self.publishing_signature = true;
        defer self.publishing_signature = saved_publication;
        return self.instantiateWithSignature(declaration, arguments, .{ .input = input, .output = output });
    }

    pub fn instantiate(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !global_sg.GlobalFunctionId {
        return self.instantiateWithSignature(declaration, arguments, null);
    }

    fn contextualSignatureType(self: *Resolver, module_index: usize, pattern: ir.ParameterizedTypeId, expected: global_sg.GlobalTypeId, direction: enum { input, output }, allow_optional_inputs: bool, bindings: *generic_mod.Resolver.Bindings) anyerror!global_sg.GlobalTypeId {
        const mismatch = if (direction == .input) error.ContextualSignatureMismatch else error.ContextualOutputSignatureMismatch;
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const expression = storage.types.items[@intFromEnum(pattern)];
        if (expression == .definition) {
            const shape = storage.representation(pattern);
            if (shape != .resolved or shape.resolved != .structural) return mismatch;
            const fields = global_types.fields(self.graph, expected) orelse return mismatch;
            const written = shape.resolved.structural.fields;
            if (written.len < fields.len or (written.len != fields.len and !allow_optional_inputs)) return mismatch;
            const contextual = try self.allocator.alloc(global_sg.GlobalTypeId, fields.len);
            defer self.allocator.free(contextual);
            for (0..fields.len) |offset| {
                const field = storage.fields.items[written.start + offset];
                const required = self.graph.fields.items[fields.start + offset];
                if (!std.mem.eql(u8, module.text(field.name), self.graph.text(required.name))) return mismatch;
                contextual[offset] = try self.contextualSignatureType(module_index, field.ty, required.ty, direction, false, bindings);
            }
            if (written.len == fields.len) return expected;
            for (fields.len..written.len) |offset|
                if (storage.fields.items[written.start + offset].default_value == null) return mismatch;
            return self.generics.instantiateRecordDefinition(module_index, pattern, bindings, contextual);
        }
        const actual = try self.generics.instantiateParameterizedType(module_index, pattern, bindings);
        if (!global_types.equal(self.graph, actual, expected)) return mismatch;
        return expected;
    }

    const ExpectedSignature = struct { input: global_sg.GlobalTypeId, output: global_sg.GlobalTypeId };

    fn instantiateWithSignature(self: *Resolver, declaration: global_sg.GlobalDeclId, arguments: primitives.Range(global_sg.GlobalGenericArgId), expected: ?ExpectedSignature) anyerror!global_sg.GlobalFunctionId {
        const profile_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        defer if (self.profile_io) |io| {
            self.profile_instantiate_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - profile_started;
            self.profile_instantiate_calls += 1;
        };
        const lookup_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        const existing = self.findExisting(declaration, arguments);
        if (self.profile_io) |io| self.profile_instantiate_lookup_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - lookup_started;
        if (existing) |id| {
            if (expected) |signature| {
                const function = self.graph.function(id);
                const required = global_types.fields(self.graph, signature.input) orelse return error.ContextualSignatureMismatch;
                if (!global_types.operationInputsCompatible(self.graph, required, function.input)) return error.ContextualSignatureMismatch;
                if (function.output_type == null or !global_types.equal(self.graph, function.output_type.?, signature.output)) return error.ContextualOutputSignatureMismatch;
            }
            if (self.profile_io != null) self.profile_instantiate_existing += 1;
            return id;
        }
        var speculation = self.beginSpeculation();
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        errdefer |err| {
            if (err == error.ComptimeExecutionPending) speculation.retainPendingExecution();
            const comptime_failure = self.generics.comptime_failure;
            const projection_failure = if (self.nested_call_context) |contracts| contracts.participant_conformance_failure else null;
            speculation.deinit();
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
        if ((try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &substitutions)) != .satisfied)
            return error.GenericContractConstraintNotSatisfied;

        if (located.parameterized.safety_primitive == .allocation_metadata_layout or located.parameterized.safety_primitive == .prepare_allocation_metadata) {
            if (arguments.len != 1) return error.InvalidAllocationMetadataPrimitive;
            const participant = self.graph.generic_arguments.items[arguments.start].value;
            if (participant != .type) return error.InvalidAllocationMetadataPrimitive;
            const contracts = self.nested_call_context orelse return error.MissingOwnershipDispatch;
            try contracts.prepareStorageCleanupEvidence(participant.type);
        }

        const input_ty = if (expected) |signature| try self.contextualSignatureType(located.module_index, located.parameterized.input, signature.input, .input, true, &substitutions) else try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.input, &substitutions);
        const output_ty = if (expected) |signature| try self.contextualSignatureType(located.module_index, located.parameterized.output, signature.output, .output, false, &substitutions) else try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.output, &substitutions);
        const signature_source = self.graph.declaration(declaration).source;
        const input_shape = try self.requireRecordSignature(input_ty, signature_source, .input);
        const output_shape = try self.requireRecordSignature(output_ty, signature_source, .output);
        var inferred_errors = false;
        for (self.graph.fields.items[output_shape.start..][0..output_shape.len]) |field| {
            inferred_errors = inferred_errors or self.graph.types.items[@intFromEnum(field.ty)] == .inferred_errable;
        }

        const context_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        var context = InstanceContext.init(self, located.module_index, located.parameterized, &substitutions);
        if (self.profile_io) |io| self.profile_instance_context_init_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - context_started;
        defer context.deinit();
        context.expected_signature = expected;
        const input_bindings = try context.instantiateSignatureBindings(located.parameterized.input_bindings, input_shape, .constant);
        const output_bindings = try context.instantiateSignatureBindings(located.parameterized.output_bindings, output_shape, .variable);
        const input_fields = input_shape;
        const output_fields = try self.outputFieldsWithInitializers(output_shape, output_bindings);

        const function_id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(self.graph.functions.items.len)));
        try self.graph.functions.append(self.allocator, .{
            .declaration = declaration,
            .input = input_fields,
            .output = output_fields,
            .input_type = input_ty,
            .output_type = output_ty,
            .body = null,
            .input_bindings = input_bindings,
            .output_bindings = output_bindings,
            .safety_primitive = located.parameterized.safety_primitive,
            .flags = .{
                .has_declared_body = located.parameterized.body != null,
                .is_once = located.parameterized.is_once,
                .is_generic_instantiation = true,
                .is_comptime_entry = located.parameterized.is_comptime_entry,
                .is_comptime_host_entry = located.parameterized.is_comptime_host_entry,
                .uses_inferred_error_reasons = inferred_errors,
                // A contract template has no runtime ABI; its inferred
                // instance does, once every generic parameter is concrete.
            },
        });
        try self.graph.generic_function_instances.append(self.allocator, .{
            .function = function_id,
            .parameterized_definition = self.graph.familyForDeclaration(declaration).?,
            .arguments = arguments,
        });

        context.function = function_id;
        // Scalar representations are proved from their exact trusted bodies
        // during operator selection, including module constant initializers.
        // They are selected specializations, not eagerly registered families.
        const declaration_file = self.graph.files.items[self.graph.declaration(declaration).source.file_index];
        const scalar_primitive = module.is_bundled_core and std.mem.eql(u8, std.fs.path.basename(self.graph.text(declaration_file.path)), "scalar_arithmetic.rg");
        if (!self.publishing_signature or scalar_primitive or located.parameterized.is_comptime_entry) if (located.parameterized.body) |body| {
            const body_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
            const instantiated_body = try context.instantiateBlock(body);
            if (self.profile_io) |io| self.profile_instantiate_body_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - body_started;
            try context.publishEntryCaptures();
            try self.graph.completeFunctionBody(self.allocator, function_id, instantiated_body, &.{});
        };
        self.stats.instances += 1;
        speculation.commit();
        return function_id;
    }

    /// Conformance registration publishes interfaces without lowering bodies.
    /// Reachability and exhaustive semantizing complete those same identities.
    pub fn materializePublishedBodies(self: *Resolver, reachable: ?*const @import("reachability.zig").FunctionSet) !bool {
        var changed = false;
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.published_bodies) else null;
        defer if (measurement) |m| m.finish(changed);
        // Copy each instance before lowering: nested specialization can grow
        // the instance and function pools. Newly published bodies join a later pass.
        const count = self.graph.generic_function_instances.items.len;
        for (0..count) |index| {
            const instance = self.graph.generic_function_instances.items[index];
            const function = self.graph.function(instance.function);
            if (function.body != null or !function.flags.has_declared_body) continue;
            if (reachable) |set| if (!set.contains(instance.function)) continue;
            const located = self.findParameterizedFamily(instance.parameterized_definition) orelse return error.GenericFunctionParameterizedNotFound;
            const storage = &self.modules[located.module_index].semantic.parameterized_storage;
            var substitutions = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
            defer substitutions.deinit(self.allocator);
            try self.generics.bindGlobalArguments(located.module_index, located.parameterized.parameters, instance.arguments, &substitutions);
            if (try self.materializeRetainedBody(located, instance.function, &substitutions)) changed = true;
        }
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const local = parameterized.concrete_function orelse continue;
                const function_id = globalizer.globalFunction(self.offsets[module_index], local);
                const function = self.graph.function(function_id);
                if (self.core.functionSignaturePending(function_id)) continue;
                if (function.body != null or !function.flags.has_declared_body) continue;
                if (reachable) |set| if (!set.contains(function_id)) continue;
                var substitutions = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
                defer substitutions.deinit(self.allocator);
                if (try self.materializeRetainedBody(.{ .module_index = module_index, .parameterized = parameterized }, function_id, &substitutions)) changed = true;
            }
        }
        return changed;
    }

    fn materializeRetainedBody(self: *Resolver, located: LocatedParameterized, function_id: global_sg.GlobalFunctionId, substitutions: *generic_mod.Resolver.Bindings) !bool {
        const body = located.parameterized.body orelse return false;
        const function = self.graph.function(function_id);
        inline for (.{ function.input, function.output }) |fields| {
            for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
                if (self.graph.isTypeUnresolved(field.ty)) return false;
        }
        var speculation = self.beginSpeculation();
        defer speculation.deinit();
        errdefer {
            const failure = self.generics.comptime_failure;
            const projection = if (self.nested_call_context) |contracts| contracts.participant_conformance_failure else null;
            speculation.rollback();
            self.generics.comptime_failure = failure;
            if (self.nested_call_context) |contracts| if (projection) |retained| {
                if (retained.is_projection or retained.operation != null) contracts.participant_conformance_failure = retained;
            };
        }
        var context = InstanceContext.init(self, located.module_index, located.parameterized, substitutions);
        defer context.deinit();
        context.function = function_id;
        inline for (.{ "input_bindings", "output_bindings" }) |name| {
            const local = @field(located.parameterized, name);
            const global = @field(function, name);
            for (0..local.len) |offset| try context.binding_map.put(self.allocator, local.start + offset, self.graph.binding_refs.items[global.start + offset]);
        }
        // The signature keeps its published identities, including capabilities
        // completed while resolving this body. Stage only new output defaults;
        // incomplete work must not leave initializers pointing into rolled-back IR.
        var defaults: std.ArrayList(global_sg.GlobalSemanticGraph.BindingInitialization) = .empty;
        defer defaults.deinit(self.allocator);
        if (located.parameterized.concrete_function != null) {
            const storage = &self.modules[located.module_index].semantic.parameterized_storage.ir;
            const outputs = located.parameterized.output_bindings;
            for (0..outputs.len) |offset| {
                const local: ir.ParameterizedBindingId = @enumFromInt(outputs.start + @as(u32, @intCast(offset)));
                const initialization = storage.bindings.items[@intFromEnum(local)].initialization orelse continue;
                const binding = self.graph.binding_refs.items[function.output_bindings.start + offset];
                const value = context.instantiateNodeWithExpected(initialization, self.graph.binding(binding).ty) catch |err| {
                    if (err == error.ComptimeExecutionPending) {
                        speculation.retainPendingExecution();
                        return false;
                    }
                    return err;
                };
                try defaults.append(self.allocator, .{ .binding = binding, .value = value });
            }
        }
        const saved_publication = self.publishing_signature;
        self.publishing_signature = false;
        defer self.publishing_signature = saved_publication;
        const body_started = if (self.profile_io) |io| std.Io.Timestamp.now(io, .boot).nanoseconds else 0;
        defer if (self.profile_io) |io| {
            self.profile_instantiate_body_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - body_started;
        };
        const instantiated = context.instantiateBlock(body) catch |err| {
            if (err == error.ComptimeExecutionPending) {
                speculation.retainPendingExecution();
                return false;
            }
            if (err == error.UnresolvedCompileTimeCaptureType) return false;
            if (err == error.OutOfMemory or err == error.Reported) return err;
            if (self.nested_call_context) |contracts| if (contracts.participant_conformance_failure != null) return err;
            if (self.generics.comptime_failure == null) self.generics.comptime_failure = .{
                .source = self.graph.declaration(function.declaration).source,
                .reason = "cannot materialize function body",
                .materialization_error = err,
            };
            return err;
        };
        try context.publishEntryCaptures();
        try self.graph.completeFunctionBody(self.allocator, function_id, instantiated, defaults.items);
        speculation.commit();
        return true;
    }

    const LocatedParameterized = struct {
        module_index: usize,
        parameterized: parameterized_storage.ParameterizedFunction,
    };

    fn findParameterized(self: *Resolver, declaration: global_sg.GlobalDeclId) ?LocatedParameterized {
        return self.findParameterizedFamily(self.graph.familyForDeclaration(declaration) orelse return null);
    }

    fn findParameterizedFamily(self: *Resolver, definition: global_sg.GlobalFamilyDefinitionId) ?LocatedParameterized {
        const family = self.graph.familyDefinition(definition);
        if (family.kind != .function) return null;
        const module_index = @intFromEnum(self.graph.moduleForFamilyDefinition(definition) orelse return null);
        const index = family.template_index orelse return null;
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        if (index >= storage.parameterized_functions.items.len) return null;
        return .{ .module_index = module_index, .parameterized = storage.parameterized_functions.items[index] };
    }

    fn findExisting(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) ?global_sg.GlobalFunctionId {
        for (self.graph.generic_function_instances.items) |instance| {
            if (instance.parameterized_definition != self.graph.familyForDeclaration(declaration)) continue;
            if (global_types.genericArgumentsEqual(self.graph, instance.arguments, arguments)) return instance.function;
        }
        return null;
    }

    fn requireRecordSignature(self: *Resolver, ty: global_sg.GlobalTypeId, source: primitives.SourceRef, comptime direction: enum { input, output }) !global_sg.FieldRange {
        if (global_types.fields(self.graph, ty)) |fields| return fields;
        if (self.unresolvedSignature(ty) == .deferred) return error.DeferredGenericFunction;
        self.generics.comptime_failure = .{
            .source = source,
            .reason = "function " ++ @tagName(direction) ++ " signature must be a record type",
        };
        return error.InvalidGenericCallArguments;
    }

    /// Inputs reuse their type's fields and unevaluated default recipes. Output
    /// bindings can instead hold concrete entry initializers; retain a separate
    /// range only when those differ from the stable result type's defaults.
    fn outputFieldsWithInitializers(self: *Resolver, shape: global_sg.FieldRange, bindings: global_sg.BindingRange) !global_sg.FieldRange {
        if (shape.len != bindings.len) return error.ContextualOutputSignatureMismatch;
        var changed = false;
        for (0..shape.len) |offset| {
            const binding = self.graph.binding_refs.items[bindings.start + offset];
            if (self.graph.fields.items[shape.start + offset].default_value != self.graph.binding(binding).initialization) {
                changed = true;
                break;
            }
        }
        if (!changed) return shape;
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.ensureUnusedCapacity(self.allocator, shape.len);
        for (0..shape.len) |offset| {
            var field = self.graph.fields.items[shape.start + offset];
            const binding = self.graph.binding_refs.items[bindings.start + offset];
            field.default_value = self.graph.binding(binding).initialization;
            self.graph.fields.appendAssumeCapacity(field);
        }
        return .{ .start = start, .len = shape.len };
    }

    fn sourceFor(self: *Resolver, module_index: usize, source: primitives.SourceRef) primitives.SourceRef {
        return .{ .file_index = self.offsets[module_index].file_base + source.file_index, .offset = source.offset };
    }

    pub fn checkpointDefaultEffects(context: *anyopaque) SideEffectCheckpoint {
        const self: *Resolver = @ptrCast(@alignCast(context));
        return self.checkpointSideEffects();
    }

    pub fn rollbackDefaultEffects(context: *anyopaque, saved: SideEffectCheckpoint) void {
        const self: *Resolver = @ptrCast(@alignCast(context));
        self.rollbackSideEffects(saved);
    }

    pub fn instantiateCapturedExpression(context: *anyopaque, recipe_id: u32, reach: ReachInferenceContext) anyerror!global_sg.GlobalNodeId {
        const self: *Resolver = @ptrCast(@alignCast(context));
        const recipe = self.graph.captured_expressions.items[recipe_id];
        var substitutions = try generic_mod.Resolver.Bindings.init(self.allocator, recipe.bindings.len);
        defer substitutions.deinit(self.allocator);
        for (self.graph.captured_expression_bindings.items[recipe.bindings.start..][0..recipe.bindings.len], 0..) |binding, index| {
            substitutions.types[index] = binding.ty;
            substitutions.ints[index] = binding.integer;
            substitutions.definitions[index] = binding.definition;
        }
        var instance = InstanceContext.init(self, recipe.module_index, .{
            .declaration = @enumFromInt(0),
            .parameters = .{ .start = 0, .len = 0 },
            .input = @enumFromInt(0),
            .output = @enumFromInt(0),
            .body = null,
        }, &substitutions);
        defer instance.deinit();
        instance.function = reach.ownerFunction();
        instance.callsite_reach = reach;
        const expression = try instance.instantiateNode(recipe.expression);
        for (instance.callsite_temporaries.items) |declaration| {
            try self.graph.argument_default_temporaries.append(self.allocator, .{ .expression = expression, .declaration = declaration });
        }
        return expression;
    }

    // Compile-time requests reuse ordinary expression instantiation without a
    // fabricated function identity. The scheduler owns publication/rollback.
    pub fn instantiateComptimeExpression(self: *Resolver, module_index: usize, node: ir.ParameterizedNodeId, bindings: *generic_mod.Resolver.Bindings) !global_sg.GlobalNodeId {
        var instance = InstanceContext.init(self, module_index, .{
            .declaration = @enumFromInt(0),
            .parameters = .{ .start = 0, .len = 0 },
            .input = @enumFromInt(0),
            .output = @enumFromInt(0),
            .body = null,
        }, bindings);
        defer instance.deinit();
        return instance.instantiateNode(node);
    }

    const InstanceContext = struct {
        active_parent: ?*InstanceContext = null,
        expected_signature: ?ExpectedSignature = null,
        resolver: *Resolver,
        module_index: usize,
        parameterized: parameterized_storage.ParameterizedFunction,
        substitutions: *generic_mod.Resolver.Bindings,
        binding_map: instantiation_map.Map(global_sg.GlobalBindingId),
        node_map: instantiation_map.Map(global_sg.GlobalNodeId),
        block_map: instantiation_map.Map(global_sg.GlobalBlockId),
        function: ?global_sg.GlobalFunctionId = null,
        callsite_reach: ?ReachInferenceContext = null,
        callsite_temporaries: std.ArrayList(global_sg.GlobalNodeId) = .empty,
        conditional_bindings: std.ArrayList(struct { local: ir.ParameterizedBindingId, global: global_sg.GlobalBindingId }) = .empty,
        entry_captures: std.ArrayList(struct { field: global_sg.Field, binding: global_sg.GlobalBindingId }) = .empty,

        fn init(
            resolver: *Resolver,
            module_index: usize,
            parameterized: parameterized_storage.ParameterizedFunction,
            substitutions: *generic_mod.Resolver.Bindings,
        ) InstanceContext {
            const storage = &resolver.modules[module_index].semantic.parameterized_storage.ir;
            return .{
                .resolver = resolver,
                .module_index = module_index,
                .parameterized = parameterized,
                .substitutions = substitutions,
                .binding_map = .init(storage.bindings.items.len),
                .node_map = .init(storage.nodes.items.len),
                .block_map = .init(storage.blocks.items.len),
            };
        }

        fn deinit(self: *InstanceContext) void {
            self.entry_captures.deinit(self.resolver.allocator);
            self.callsite_temporaries.deinit(self.resolver.allocator);
            self.conditional_bindings.deinit(self.resolver.allocator);
            self.binding_map.deinit(self.resolver.allocator);
            self.node_map.deinit(self.resolver.allocator);
            self.block_map.deinit(self.resolver.allocator);
        }

        fn instantiateSignatureBindings(self: *InstanceContext, range: primitives.Range(ir.ParameterizedBindingId), fields: global_sg.FieldRange, mutability: primitives.Mutability) !global_sg.BindingRange {
            if (mutability != .constant and (range.len != 0 or fields.len == 0)) return self.instantiateBindingRange(range);
            // Input defaults belong to the signature as recipes. Evaluating
            // their template initializers here would allocate storage in the
            // callee and lose the caller's reached capabilities. Named input
            // types use this same path without duplicate local declarations.
            const bindings = try self.resolver.allocator.alloc(global_sg.GlobalBindingId, fields.len);
            defer self.resolver.allocator.free(bindings);
            for (0..fields.len) |offset| {
                const field = self.resolver.graph.fields.items[fields.start + offset];
                bindings[offset] = @enumFromInt(@as(u32, @intCast(self.resolver.graph.bindings.items.len)));
                try self.resolver.graph.bindings.append(self.resolver.allocator, .{
                    .name = field.name,
                    .source = field.source,
                    .ty = field.ty,
                    .initialization = field.default_value,
                    .mutability = mutability,
                });
                if (offset < range.len) try self.binding_map.put(self.resolver.allocator, range.start + @as(u32, @intCast(offset)), bindings[offset]);
            }
            const start: u32 = @intCast(self.resolver.graph.binding_refs.items.len);
            try self.resolver.graph.binding_refs.appendSlice(self.resolver.allocator, bindings);
            return .{ .start = start, .len = fields.len };
        }

        fn instantiateBindingRange(self: *InstanceContext, range: primitives.Range(ir.ParameterizedBindingId)) !global_sg.BindingRange {
            // Defaults can instantiate other functions and append their binding
            // ranges. Publish this interface only after those dependencies.
            const bindings = try self.resolver.allocator.alloc(global_sg.GlobalBindingId, range.len);
            defer self.resolver.allocator.free(bindings);
            for (bindings, 0..) |*binding, offset| {
                const local: ir.ParameterizedBindingId = @enumFromInt(range.start + @as(u32, @intCast(offset)));
                binding.* = try self.instantiateBinding(local);
            }
            const start: u32 = @intCast(self.resolver.graph.binding_refs.items.len);
            try self.resolver.graph.binding_refs.appendSlice(self.resolver.allocator, bindings);
            return .{ .start = start, .len = range.len };
        }

        fn expectedBindingType(self: *InstanceContext, id: ir.ParameterizedBindingId) !?global_sg.GlobalTypeId {
            const signature = self.expected_signature orelse return null;
            const raw = @intFromEnum(id);
            inline for (.{ "input", "output" }) |direction| {
                const range = @field(self.parameterized, direction ++ "_bindings");
                if (raw >= range.start and raw - range.start < range.len) {
                    const fields = global_types.fields(self.resolver.graph, @field(signature, direction)) orelse return error.ContextualSignatureMismatch;
                    const offset = raw - range.start;
                    if (offset >= fields.len) return null;
                    return self.resolver.graph.fields.items[fields.start + offset].ty;
                }
            }
            return null;
        }

        fn instantiateBinding(self: *InstanceContext, id: ir.ParameterizedBindingId) !global_sg.GlobalBindingId {
            if (self.binding_map.get(@intFromEnum(id))) |existing| return existing;
            const module = &self.resolver.modules[self.module_index];
            const storage = &module.semantic.parameterized_storage.ir;
            const source = storage.bindings.items[@intFromEnum(id)];
            const source_ty = storage.bindingType(id);
            const global: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.bindings.items.len)));
            try self.resolver.graph.bindings.append(self.resolver.allocator, .{
                .name = try self.resolver.graph.addString(self.resolver.allocator, module.text(source.name)),
                .source = self.resolver.sourceFor(self.module_index, source.source),
                .ty = if (try self.expectedBindingType(id)) |ty| ty else if (source_ty) |ty|
                    try self.resolver.generics.instantiateParameterizedType(self.module_index, ty, self.substitutions)
                else
                    @enumFromInt(0),
                .initialization = null,
                .deferred_initialization = source.deferred_initialization,
                .mutability = source.mutability,
            });
            try self.binding_map.put(self.resolver.allocator, @intFromEnum(id), global);
            if (source.cleanup_arguments) |node| {
                const arguments = try self.instantiateNode(node);
                var updated = self.resolver.graph.binding(global);
                updated.cleanup_arguments = arguments;
                try self.resolver.graph.setBinding(self.resolver.allocator, global, updated);
            }
            if (source_ty == null) try self.resolver.graph.markBindingTypeUnresolved(self.resolver.allocator, global);
            if (source.initialization) |node| {
                const initialization = if (source_ty != null)
                    try self.instantiateNodeWithExpected(node, self.resolver.graph.bindings.items[@intFromEnum(global)].ty)
                else
                    try self.instantiateNode(node);
                if (source_ty == null and !source.deferred_initialization and
                    self.resolver.graph.node(initialization).content == .struct_value_literal and
                    self.resolver.graph.node(initialization).ty == null)
                {
                    self.resolver.generics.comptime_failure = .{
                        .source = self.resolver.sourceFor(self.module_index, source.source),
                        .reason = "cannot infer the type of this record literal; add an explicit type annotation",
                    };
                    return error.UncontextualizedRecordValue;
                }
                var updated = self.resolver.graph.binding(global);
                updated.initialization = initialization;
                try self.resolver.graph.setBinding(self.resolver.allocator, global, updated);
                if (source_ty == null) {
                    if (self.resolver.graph.nodes.items[@intFromEnum(initialization)].ty) |inferred| {
                        if (!self.resolver.graph.isTypeUnresolved(inferred)) {
                            try self.resolver.graph.resolveBindingType(self.resolver.allocator, global, inferred);
                        }
                    }
                }
            }
            return global;
        }

        fn instantiateBlock(self: *InstanceContext, id: ir.ParameterizedBlockId) anyerror!global_sg.GlobalBlockId {
            return self.instantiateBlockWithScope(id, true);
        }

        fn instantiateBlockWithScope(self: *InstanceContext, id: ir.ParameterizedBlockId, scoped: bool) anyerror!global_sg.GlobalBlockId {
            const mark = self.conditional_bindings.items.len;
            defer if (scoped) self.conditional_bindings.shrinkRetainingCapacity(mark);
            if (self.block_map.get(@intFromEnum(id))) |existing| return existing;
            const local = self.resolver.modules[self.module_index].semantic.parameterized_storage.ir.blocks.items[@intFromEnum(id)];
            const global: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.blocks.items.len)));
            try self.resolver.graph.blocks.append(self.resolver.allocator, .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = null });
            try self.block_map.put(self.resolver.allocator, @intFromEnum(id), global);

            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            var nodes: std.ArrayList(global_sg.GlobalNodeId) = .empty;
            defer nodes.deinit(self.resolver.allocator);
            var conditional_result = false;
            for (storage.node_refs.items[local.nodes.start..][0..local.nodes.len]) |node| {
                const expression = storage.nodes.items[@intFromEnum(node)];
                const selected = expression == .pending and storage.pending.items[@intFromEnum(expression.pending)] == .resolve_expression and
                    storage.pending.items[@intFromEnum(expression.pending)].resolve_expression.kind == .comptime_if;
                const instantiated = try self.instantiateNode(node);
                if (selected) {
                    // #if selects statements in the containing scope, just as
                    // source selection for target predicates does. It creates
                    // neither a runtime branch nor an earlier cleanup boundary.
                    const branch = self.resolver.graph.node(instantiated).content.code_block;
                    const block = self.resolver.graph.blocks.items[@intFromEnum(branch)];
                    try nodes.appendSlice(self.resolver.allocator, self.resolver.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]);
                    if (local.ret_val == node) conditional_result = true;
                } else {
                    try nodes.append(self.resolver.allocator, instantiated);
                    if (!scoped and expression == .resolved and expression.resolved.content == .binding_declaration) {
                        const binding = expression.resolved.content.binding_declaration;
                        try self.conditional_bindings.append(self.resolver.allocator, .{ .local = binding, .global = self.binding_map.get(@intFromEnum(binding)).? });
                    }
                }
            }
            const ret_val = if (local.ret_val) |node| if (conditional_result) null else try self.instantiateNode(node) else null;
            const start: u32 = @intCast(self.resolver.graph.node_refs.items.len);
            try self.resolver.graph.node_refs.appendSlice(self.resolver.allocator, nodes.items);
            try self.resolver.graph.setBlock(self.resolver.allocator, global, .{
                .nodes = .{ .start = start, .len = @intCast(nodes.items.len) },
                .ret_val = ret_val,
            });
            return global;
        }

        fn entryCaptureSource(self: *InstanceContext, local: ir.ParameterizedNodeId) anyerror!global_sg.GlobalNodeId {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            var current = self.active_parent;
            while (current) |parent| : (current = parent.active_parent) {
                if (parent.module_index != self.module_index) continue;
                if (parent.node_map.get(@intFromEnum(local))) |existing| return existing;
                switch (storage.nodes.items[@intFromEnum(local)]) {
                    .resolved => |node| if (node.content == .binding_use) {
                        const binding = node.content.binding_use;
                        if (parent.binding_map.get(@intFromEnum(binding)) == null) continue;
                        const global = try parent.lexicalBinding(binding);
                        if (self.resolver.graph.isBindingTypeUnresolved(global)) return error.UnresolvedCompileTimeCaptureType;
                        return self.resolver.core.appendNode(self.resolver.sourceFor(self.module_index, node.source), self.resolver.graph.binding(global).ty, .{ .binding_use = global });
                    },
                    .pending => |pending| {
                        const expression = storage.pending.items[@intFromEnum(pending)];
                        if (expression == .resolve_expression and expression.resolve_expression.kind == .entry_capture)
                            return parent.instantiateEntryCapture(local);
                    },
                }
            }
            if (self.function == null) return self.instantiateNode(local);
            return error.UnresolvedCompileTimeCaptureType;
        }

        fn instantiateEntryCapture(self: *InstanceContext, id: ir.ParameterizedNodeId) anyerror!global_sg.GlobalNodeId {
            if (self.node_map.get(@intFromEnum(id))) |existing| return existing;
            const module = &self.resolver.modules[self.module_index];
            const storage = &module.semantic.parameterized_storage.ir;
            const expression = storage.pending.items[@intFromEnum(storage.nodes.items[@intFromEnum(id)].pending)].resolve_expression;
            var value = switch (expression.detail) {
                .none => try self.entryCaptureSource(storage.node_refs.items[expression.operands.start]),
                .capture_module_value => |value_node| globalizer.globalNode(self.resolver.offsets[self.module_index], value_node),
                .capture_owner => |owner| blk: {
                    const binding = self.resolver.capture_lookup.?(self.resolver.capture_lookup_context.?, self.module_index, if (owner) |function| globalizer.globalFunction(self.resolver.offsets[self.module_index], function) else null, module.text(expression.name.?)) orelse {
                        self.resolver.generics.comptime_failure = .{ .source = self.resolver.sourceFor(self.module_index, expression.source), .reason = "unknown name in this scope", .unknown_name = module.text(expression.name.?) };
                        return error.UnknownParameterizedName;
                    };
                    if (self.resolver.graph.isBindingTypeUnresolved(binding)) return error.UnresolvedCompileTimeCaptureType;
                    break :blk try self.resolver.core.appendNode(self.resolver.sourceFor(self.module_index, expression.source), self.resolver.graph.binding(binding).ty, .{ .binding_use = binding });
                },
                else => return error.InvalidParameterizedEntryCapture,
            };
            const name = try self.resolver.graph.addString(self.resolver.allocator, module.text(expression.name.?));
            const source = self.resolver.sourceFor(self.module_index, expression.source);
            value = try self.forwardEntryCapture(name, source, value);
            const node = try self.captureEntryValue(name, source, value);
            try self.node_map.put(self.resolver.allocator, @intFromEnum(id), node);
            return node;
        }

        fn forwardEntryCapture(self: *InstanceContext, name: primitives.StringRange, source: primitives.SourceRef, original: global_sg.GlobalNodeId) !global_sg.GlobalNodeId {
            var scopes: std.ArrayList(*InstanceContext) = .empty;
            defer scopes.deinit(self.resolver.allocator);
            var current = self.active_parent;
            const content = self.resolver.graph.node(original).content;
            while (current) |parent| : (current = parent.active_parent) {
                const function = parent.function orelse break;
                if (content == .binding_use) {
                    var owned = parent.binding_map.containsValue(content.binding_use);
                    for (parent.entry_captures.items) |capture| if (capture.binding == content.binding_use) {
                        owned = true;
                        break;
                    };
                    if (owned) break;
                }
                if (!self.resolver.graph.function(function).flags.is_comptime_entry) break;
                try scopes.append(self.resolver.allocator, parent);
            }
            var value = original;
            var index = scopes.items.len;
            while (index != 0) {
                index -= 1;
                value = try scopes.items[index].captureEntryValue(name, source, value);
            }
            return value;
        }

        fn captureEntryValue(self: *InstanceContext, name: primitives.StringRange, source: primitives.SourceRef, value: global_sg.GlobalNodeId) !global_sg.GlobalNodeId {
            const content = self.resolver.graph.node(value).content;
            for (self.entry_captures.items) |capture| {
                if ((content == .binding_use and content.binding_use == capture.binding) or
                    (capture.field.default_value == value and std.mem.eql(u8, self.resolver.graph.text(capture.field.name), self.resolver.graph.text(name))))
                    return self.resolver.core.appendNode(source, capture.field.ty, .{ .binding_use = capture.binding });
            }
            const ty = self.resolver.graph.node(value).ty orelse return error.UnresolvedCompileTimeCaptureType;
            if (self.resolver.graph.isTypeUnresolved(ty)) return error.UnresolvedCompileTimeCaptureType;
            if (self.function == null) return value;
            const binding: global_sg.GlobalBindingId = @enumFromInt(self.resolver.graph.bindings.items.len);
            try self.resolver.graph.bindings.append(self.resolver.allocator, .{ .name = name, .source = source, .ty = ty, .mutability = .constant });
            try self.entry_captures.append(self.resolver.allocator, .{ .binding = binding, .field = .{ .name = name, .source = source, .ty = ty, .default_value = value } });
            return self.resolver.core.appendNode(source, ty, .{ .binding_use = binding });
        }

        fn publishEntryCaptures(self: *InstanceContext) !void {
            if (self.entry_captures.items.len == 0) return;
            const function_id = self.function orelse return error.InvalidParameterizedEntryCapture;
            const function = self.resolver.graph.function(function_id);
            if (!function.flags.is_comptime_entry) return error.InvalidParameterizedEntryCapture;
            var fields: std.ArrayList(global_sg.Field) = .empty;
            defer fields.deinit(self.resolver.allocator);
            var bindings: std.ArrayList(global_sg.GlobalBindingId) = .empty;
            defer bindings.deinit(self.resolver.allocator);
            try fields.appendSlice(self.resolver.allocator, self.resolver.graph.fields.items[function.input.start..][0..function.input.len]);
            try bindings.appendSlice(self.resolver.allocator, self.resolver.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]);
            for (self.entry_captures.items) |capture| {
                try fields.append(self.resolver.allocator, capture.field);
                try bindings.append(self.resolver.allocator, capture.binding);
            }
            const field_start: u32 = @intCast(self.resolver.graph.fields.items.len);
            try self.resolver.graph.fields.appendSlice(self.resolver.allocator, fields.items);
            const binding_start: u32 = @intCast(self.resolver.graph.binding_refs.items.len);
            try self.resolver.graph.binding_refs.appendSlice(self.resolver.allocator, bindings.items);
            var completed = self.resolver.graph.function(function_id);
            completed.input = .{ .start = field_start, .len = @intCast(fields.items.len) };
            completed.input_bindings = .{ .start = binding_start, .len = @intCast(bindings.items.len) };
            try self.resolver.graph.setFunction(self.resolver.allocator, function_id, completed);
        }

        fn instantiateNode(self: *InstanceContext, id: ir.ParameterizedNodeId) anyerror!global_sg.GlobalNodeId {
            const previous = self.resolver.active_instance;
            const previous_parent = self.active_parent;
            if (previous != self) {
                self.active_parent = previous;
                self.resolver.active_instance = self;
            }
            defer {
                self.resolver.active_instance = previous;
                self.active_parent = previous_parent;
            }
            if (self.node_map.get(@intFromEnum(id))) |existing| return existing;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const local = storage.nodes.items[@intFromEnum(id)];
            if (local == .pending) {
                const pending = storage.pending.items[@intFromEnum(local.pending)];
                if (pending == .resolve_expression and pending.resolve_expression.kind == .entry_capture)
                    return self.instantiateEntryCapture(id);
            }
            const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                .source = .{ .file_index = 0, .offset = 0 },
                .ty = null,
                .content = .break_statement,
            });
            try self.node_map.put(self.resolver.allocator, @intFromEnum(id), global);
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
            try self.resolver.graph.setNode(self.resolver.allocator, global, instantiated);
            if (local == .pending) {
                const pending = storage.pending.items[@intFromEnum(local.pending)];
                if (pending == .resolve_expression and pending.resolve_expression.comptime_run)
                    try self.resolver.graph.comptime_requests.append(self.resolver.allocator, global);
            }
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
                if (pending == .resolve_expression and pending.resolve_expression.kind == .list_value) {
                    // Pass the element context before building the list, including
                    // nested arrays and out-of-range literals checked by safety.
                    if (global_types.arrayElement(self.resolver.graph, expected)) |element| {
                        const operands = pending.resolve_expression.operands;
                        for (storage.node_refs.items[operands.start..][0..operands.len]) |child|
                            _ = try self.instantiateNodeWithExpected(child, element);
                    }
                    const global = try self.instantiateNode(id);
                    try self.resolver.core.contextualizeStoredValue(global, expected);
                    return global;
                }
                if (pending == .resolve_expression and pending.resolve_expression.kind == .choice_literal) {
                    if (self.node_map.get(@intFromEnum(id))) |existing| return existing;
                    const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
                    try self.resolver.graph.nodes.append(self.resolver.allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .break_statement });
                    try self.node_map.put(self.resolver.allocator, @intFromEnum(id), global);
                    // Resolving payloads can grow the node pool. Compute the
                    // value before taking the destination slot's address.
                    const resolved = try self.resolveChoiceLiteral(pending.resolve_expression, expected);
                    try self.resolver.graph.setNode(self.resolver.allocator, global, resolved);
                    self.resolver.stats.nodes += 1;
                    return global;
                }
            } else if (local.resolved.content == .struct_value_literal) {
                return self.instantiateStructValueWithExpected(id, local.resolved, expected);
            } else if (local.resolved.content == .string_literal or local.resolved.content == .int_literal or local.resolved.content == .float_literal) {
                const global = try self.instantiateNode(id);
                const current = self.resolver.graph.nodes.items[@intFromEnum(global)].ty;
                if (current == null or !global_types.equal(self.resolver.graph, current.?, expected))
                    try self.resolver.core.contextualizeStoredValue(global, expected);
                return global;
            }
            return self.instantiateNode(id);
        }

        fn instantiateStructValueWithExpected(self: *InstanceContext, id: ir.ParameterizedNodeId, node: ir.ResolvedNode, expected: global_sg.GlobalTypeId) !global_sg.GlobalNodeId {
            if (self.node_map.get(@intFromEnum(id))) |existing| return existing;
            const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = null, .content = .break_statement });
            try self.node_map.put(self.resolver.allocator, @intFromEnum(id), global);
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const local_fields = node.content.struct_value_literal.fields;
            const expected_fields = global_types.fields(self.resolver.graph, expected) orelse {
                // Empty parentheses can materialize Void or an empty array.
                // Reuse ordinary contextualization rather than requiring a
                // record field range merely because this body is specialized.
                if (local_fields.len != 0) return error.ParameterizedStructExpectedNonStruct;
                try self.resolver.graph.setNode(self.resolver.allocator, global, .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = null,
                    .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } },
                });
                if (!try self.resolver.core.coerceContextualValue(global, expected)) return error.ParameterizedStructExpectedNonStruct;
                self.resolver.stats.nodes += 1;
                return global;
            };
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
            try self.resolver.graph.setNode(self.resolver.allocator, global, .{
                .source = self.resolver.sourceFor(self.module_index, node.source),
                .ty = expected,
                .content = .{ .struct_value_literal = .{
                    .fields = .{ .start = start, .len = local_fields.len },
                    .dispatch_prefix_positional_count = node.content.struct_value_literal.dispatch_prefix_positional_count,
                } },
            });
            // Use ordinary default completion before publishing a value with
            // the complete contextual record type. A type annotation alone
            // cannot manufacture omitted runtime fields.
            const context = try self.operatorContext(null);
            defer self.resolver.allocator.free(context.global.visible_bindings);
            if (!try self.resolver.core.completeRecordValue(expected, global, context))
                return error.MissingParameterizedStructField;
            try self.resolver.graph.setNodeType(self.resolver.allocator, global, expected);
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
                const binding = if (declaration) try self.instantiateBinding(node.content.binding_declaration) else try self.lexicalBinding(node.content.binding_use);
                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = if (self.resolver.graph.isBindingTypeUnresolved(binding)) null else self.resolver.graph.bindings.items[@intFromEnum(binding)].ty,
                    .content = if (declaration) .{ .binding_declaration = binding } else .{ .binding_use = binding },
                };
            }
            if (node.content == .assignment) {
                const assignment = node.content.assignment;
                const binding = try self.lexicalBinding(assignment.binding);
                const expected = if (self.resolver.graph.isBindingTypeUnresolved(binding)) null else self.resolver.graph.binding(binding).ty;
                const value = if (expected) |target| try self.instantiateNodeWithExpected(assignment.value, target) else try self.instantiateNode(assignment.value);
                return .{ .source = self.resolver.sourceFor(self.module_index, node.source), .ty = expected, .content = .{ .assignment = .{ .binding = binding, .value = value } } };
            }
            const ty = if (node.ty) |value|
                try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions)
            else if (node.content == .string_literal)
                self.resolver.core.defaultStringLiteralType()
            else if (node.content == .char_literal)
                self.resolver.core.defaultScalarLiteralType()
            else
                null;
            return .{
                .source = self.resolver.sourceFor(self.module_index, node.source),
                .ty = ty,
                .content = switch (node.content) {
                    .binding_use, .binding_declaration, .assignment => unreachable,
                    .reach_directive => |reach| .{ .reach_directive = try self.instantiateReach(reach) },
                    .code_block => |block| .{ .code_block = try self.instantiateBlock(block) },
                    .value_sequence => |block| .{ .value_sequence = try self.instantiateBlock(block) },
                    .replacement => return error.InvalidParameterizedNode,
                    .int_literal => |value| .{ .int_literal = value },
                    .float_literal => |value| .{ .float_literal = value },
                    .char_literal => |value| .{ .char_literal = value },
                    .bool_literal => |value| .{ .bool_literal = value },
                    .string_literal => |value| .{ .string_literal = try self.copyString(value) },
                    .type_literal => |value| .{ .type_literal = try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions) },
                    .definition_literal => |value| .{ .definition_literal = .{
                        .origin = try self.resolver.generics.resolveParameterizedFamily(self.module_index, value.origin),
                        .captures = try self.resolver.generics.instantiateParameterizedArguments(self.module_index, value.captures, self.substitutions),
                    } },
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
            }
            // Value literals have no independent type identity. Calls and
            // annotated storage supply the expected nominal record later.
            var assumed: std.ArrayList(global_sg.ValueField) = .empty;
            defer assumed.deinit(self.resolver.allocator);
            if (self.callsite_reach) |context| {
                // A default executes in its caller's lexical environment.
                // Re-instantiating the declaration's assumed bindings creates
                // body-local slots that do not exist at that call site.
                const inherited = context.assumedFields();
                try assumed.appendSlice(self.resolver.allocator, self.resolver.graph.value_fields.items[inherited.start..][0..inherited.len]);
            } else {
                for (storage.value_fields.items[literal.assumed_fields.start..][0..literal.assumed_fields.len]) |field| {
                    try assumed.append(self.resolver.allocator, .{
                        .name = try self.copyString(field.name),
                        .value = try self.instantiateNode(field.value),
                    });
                }
            }
            const assumed_start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, assumed.items);
            const start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, values.items);
            return .{ .source = self.resolver.sourceFor(self.module_index, node.source), .ty = null, .content = .{
                .struct_value_literal = .{
                    .fields = .{ .start = start, .len = @intCast(values.items.len) },
                    .dispatch_prefix_positional_count = literal.dispatch_prefix_positional_count,
                    .assumed_fields = .{ .start = assumed_start, .len = @intCast(assumed.items.len) },
                },
            } };
        }

        fn isBareChoiceTag(self: *InstanceContext, id: ir.ParameterizedNodeId) bool {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const node = storage.nodes.items[@intFromEnum(id)];
            if (node != .pending) return false;
            const pending = storage.pending.items[@intFromEnum(node.pending)];
            return pending == .resolve_expression and pending.resolve_expression.kind == .choice_literal and
                pending.resolve_expression.operands.len == 0;
        }

        fn instantiateChoiceTag(self: *InstanceContext, id: ir.ParameterizedNodeId, choice_type: global_sg.GlobalTypeId) !global_sg.GlobalNodeId {
            if (self.node_map.get(@intFromEnum(id))) |existing| return existing;
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
            try self.node_map.put(self.resolver.allocator, @intFromEnum(id), global);
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
            if (try self.resolver.core.resolveEntityValue(self.module_index, .{
                .kind = .type,
                .module_path = null,
                .name = value.name,
                .source = value.source,
            })) |entity| {
                return switch (entity) {
                    .type => |ty| .{
                        .source = self.resolver.sourceFor(self.module_index, value.source),
                        .ty = try self.resolver.core.builtin(.Type),
                        .content = .{ .type_literal = ty },
                    },
                    .definition => |definition| .{
                        .source = self.resolver.sourceFor(self.module_index, value.source),
                        .ty = try global_types.definitionClass(self.resolver.allocator, self.resolver.graph, definition.origin),
                        .content = .{ .definition_literal = definition },
                    },
                };
            }
            if (self.resolver.generics.comptime_failure == null) self.resolver.generics.comptime_failure = .{
                .source = self.resolver.sourceFor(self.module_index, value.source),
                .reason = "unknown name in this scope",
                .unknown_name = name,
            };
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
            const local_operands = storage.node_refs.items[value.operands.start..][0..value.operands.len];
            // Select before instantiating either arm. Discarded names, types
            // and operations must never become semantic obligations.
            if (value.kind == .comptime_if) {
                if (local_operands.len < 2 or local_operands.len > 3) return error.InvalidParameterizedIf;
                const execute = self.resolver.generics.execute_boolean orelse return error.CompileTimeExecutionUnavailable;
                const selected = try execute(self.resolver.generics.execution_context.?, self.module_index, local_operands[0], self.substitutions);
                if (selected or local_operands.len == 3) {
                    const branch = storage.nodes.items[@intFromEnum(local_operands[if (selected) 1 else 2])].resolved;
                    const block = try self.instantiateBlockWithScope(branch.content.code_block, false);
                    return .{ .source = self.resolver.sourceFor(self.module_index, value.source), .ty = try self.resolver.generics.internType(.{ .builtin = .Void }), .content = .{ .code_block = block } };
                }
                const block: global_sg.GlobalBlockId = @enumFromInt(self.resolver.graph.blocks.items.len);
                try self.resolver.graph.blocks.append(self.resolver.allocator, .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = null });
                return .{ .source = self.resolver.sourceFor(self.module_index, value.source), .ty = try self.resolver.generics.internType(.{ .builtin = .Void }), .content = .{ .code_block = block } };
            }
            // Equality against a bare variant is a tag test. Infer its identity
            // from the other operand before attempting to instantiate the tag.
            // Canonicalize reversed tests so refinement and codegen see the value first.
            if (value.kind == .comparison and value.detail == .comparison and
                (value.detail.comparison == .equal or value.detail.comparison == .not_equal) and local_operands.len == 2)
            {
                for (0..2) |tag_index| {
                    if (!self.isBareChoiceTag(local_operands[tag_index]) or self.isBareChoiceTag(local_operands[1 - tag_index])) continue;
                    const other = try self.instantiateNode(local_operands[1 - tag_index]);
                    const choice_type = self.resolver.graph.node(other).ty orelse continue;
                    if (global_types.variants(self.resolver.graph, choice_type) == null) continue;
                    try operands.append(other);
                    try operands.append(try self.instantiateChoiceTag(local_operands[tag_index], choice_type));
                    break;
                }
            }
            if (operands.items.len == 0) for (local_operands) |operand|
                try operands.append(try self.instantiateNode(operand));

            return switch (value.kind) {
                .entry_capture => error.InvalidParameterizedEntryCapture,
                .assume_name => {
                    const resolved = try self.resolveName(.{ .name = value.name orelse return error.UnknownAssumedVariable, .source = value.source });
                    if (resolved.content != .binding_use) return error.UnknownAssumedVariable;
                    return self.emptyValue(try self.resolver.core.builtin(.Void), value.source);
                },
                .unknown_identifier => if (value.name) |name| self.resolveName(.{ .name = name, .source = value.source }) else error.UnknownParameterizedName,
                .comptime_parameter => self.resolveComptimeParameter(value),
                .entity_application => blk: {
                    const source = self.resolver.sourceFor(self.module_index, value.source);
                    const entity = try self.resolver.generics.instantiateEntityValue(self.module_index, value.detail.entity_application, self.substitutions, source);
                    break :blk switch (entity) {
                        .type => |ty| .{ .source = source, .ty = try self.resolver.core.builtin(.Type), .content = .{ .type_literal = ty } },
                        .definition => |definition| .{ .source = source, .ty = try global_types.definitionClass(self.resolver.allocator, self.resolver.graph, definition.origin), .content = .{ .definition_literal = definition } },
                    };
                },
                .generic_call => blk: {
                    const name = value.name orelse return error.GenericParameterizedCallWithoutName;
                    const args = try self.resolver.generics.instantiateParameterizedArguments(self.module_index, value.generic_arguments, self.substitutions);
                    const input = if (operands.items.len != 0) operands.items[0] else return error.GenericParameterizedCallWithoutInput;
                    if (value.detail == .callee_value) {
                        const callee = try self.instantiateNode(value.detail.callee_value);
                        if (global_types.definitionValue(self.resolver.graph, callee)) |definition| {
                            if (self.resolver.graph.familyDefinition(definition.origin).kind == .function) {
                                const reach = try self.operatorContext(value.assumed_arguments);
                                defer self.resolver.allocator.free(reach.global.visible_bindings);
                                break :blk try self.resolver.makeDefinitionCall(self.module_index, .{ .kind = .function, .module_path = null, .name = name, .source = value.source }, definition, args, input, reach, self.resolver.sourceFor(self.module_index, value.source));
                            }
                        }
                    }
                    if (value.contract_type) |contract| {
                        const base = try self.resolver.generics.instantiateParameterizedType(self.module_index, contract, self.substitutions);
                        var context = try self.operatorContext(value.assumed_arguments);
                        defer self.resolver.allocator.free(context.global.visible_bindings);
                        if (self.resolver.graph.node(input).content == .struct_value_literal)
                            context.global.assumed_fields = self.resolver.graph.node(input).content.struct_value_literal.assumed_fields;
                        const contracts = self.resolver.nested_call_context orelse return error.InvalidContractOperation;
                        break :blk try contracts.makeSpecializedScopedOperationCall(self.module_index, base, self.resolver.modules[self.module_index].text(name), args, input, context, self.resolver.sourceFor(self.module_index, value.source)) orelse error.InvalidContractOperation;
                    }
                    break :blk try self.makeNamedCall(name, value.module_path, args, input, value.source, if (value.expected_type) |ty|
                        try self.resolver.generics.instantiateParameterizedType(self.module_index, ty, self.substitutions)
                    else
                        null);
                },
                .binary => self.resolveBinary(operands.items, value.source, value.detail, value.assumed_arguments),
                .list_value => blk: {
                    const start: u32 = @intCast(self.resolver.graph.node_refs.items.len);
                    try self.resolver.graph.node_refs.appendSlice(self.resolver.allocator, operands.items);
                    break :blk .{
                        .source = self.resolver.sourceFor(self.module_index, value.source),
                        .ty = null,
                        .content = .{ .list_literal = .{ .elements = .{ .start = start, .len = @intCast(operands.items.len) } } },
                    };
                },
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
                .comptime_if => unreachable,
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
            defer errors.deinit();
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
            if (value.name) |name| {
                if (self.findGlobalBinding(self.resolver.modules[self.module_index].text(name))) |binding| {
                    return .{ .source = self.resolver.sourceFor(self.module_index, value.source), .ty = self.resolver.graph.bindings.items[@intFromEnum(binding)].ty, .content = .{ .binding_use = binding } };
                }
            }
            if (definition.kind == .type) {
                const ty = self.substitutions.types[@intFromEnum(parameter)] orelse return error.UnboundComptimeParameter;
                return .{ .source = self.resolver.sourceFor(self.module_index, value.source), .ty = try self.resolver.core.builtin(.Type), .content = .{ .type_literal = ty } };
            }
            if (definition.kind == .definition) {
                const entity = self.substitutions.definitions[@intFromEnum(parameter)] orelse return error.UnboundComptimeParameter;
                return .{ .source = self.resolver.sourceFor(self.module_index, value.source), .ty = try global_types.definitionClass(self.resolver.allocator, self.resolver.graph, entity.origin), .content = .{ .definition_literal = entity } };
            }
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
                defer control.deinit();
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
            const actual_child = global_types.nullableChild(self.resolver.graph, actual) orelse return false;
            return global_types.equal(self.resolver.graph, actual_child, child);
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
                    try self.resolver.graph.resolveBindingType(self.resolver.allocator, binding, try self.matchBindingType(payload, case.mode));
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
            if (module_path == null) if (standard_contracts.scalarComparisonPrimitive(name)) |operator| {
                const declaration = self.resolver.graph.declaration(globalizer.globalDecl(self.resolver.offsets[self.module_index], self.parameterized.declaration));
                const path = self.resolver.graph.text(self.resolver.graph.files.items[declaration.source.file_index].path);
                if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(path), "scalar_arithmetic.rg")) return error.NoMatchingGenericFunction;
                const literal = self.resolver.graph.node(input).content.struct_value_literal;
                if (literal.fields.len != 2) return error.InvalidScalarComparisonPrimitive;
                const left = self.resolver.core.recordFieldValue(literal, 0, "left") orelse return error.InvalidScalarComparisonPrimitive;
                const right = self.resolver.core.recordFieldValue(literal, 1, "right") orelse return error.InvalidScalarComparisonPrimitive;
                const left_type = self.resolver.graph.node(left).ty orelse return error.InvalidScalarComparisonPrimitive;
                const right_type = self.resolver.graph.node(right).ty orelse return error.InvalidScalarComparisonPrimitive;
                if (!self.resolver.core.isDirectComparison(operator, left_type, right_type)) return error.InvalidScalarComparisonPrimitive;
                return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = try self.resolver.generics.internType(.{ .builtin = .Bool }), .content = .{ .comparison = .{ .operator = operator, .left = left, .right = right } } };
            };
            if (module_path == null) if (standard_contracts.scalarArithmeticPrimitive(name)) |operator| {
                const declaration = self.resolver.graph.declaration(globalizer.globalDecl(self.resolver.offsets[self.module_index], self.parameterized.declaration));
                const path = self.resolver.graph.text(self.resolver.graph.files.items[declaration.source.file_index].path);
                if (!module.is_bundled_core or !std.mem.eql(u8, std.fs.path.basename(path), "scalar_arithmetic.rg")) return error.NoMatchingGenericFunction;
                const literal = self.resolver.graph.node(input).content.struct_value_literal;
                if (literal.fields.len != 2) return error.InvalidScalarArithmeticPrimitive;
                const left = self.resolver.core.recordFieldValue(literal, 0, "left") orelse return error.InvalidScalarArithmeticPrimitive;
                const right = self.resolver.core.recordFieldValue(literal, 1, "right") orelse return error.InvalidScalarArithmeticPrimitive;
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
            const nested_reach = try self.operatorContext(null);
            defer self.resolver.allocator.free(nested_reach.global.visible_bindings);
            {
                const operation_module = if (module_path) |path| try self.resolver.core.findModuleForQualifier(self.module_index, module.text(path)) else null;
                if (try self.resolver.resolveSpecializedOperationIdentityFiltered(self.module_index, name, input, nested_reach, self.resolver.sourceFor(self.module_index, source), operation_module, arguments, reference)) |operation| return operation;
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
                    // A pending ordinary call must not become a failed generic
                    // lookup while its caller's argument values are unresolved.
                    if (ordinary == .deferred) return error.DeferredGenericFunction;
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
                        return err;
                    };
                };
            };
            if (!try self.resolver.core.completeRecordFieldsWithContext(
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
            try self.resolver.core.contextualizeArithmeticPair(operands);
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
            try self.resolver.core.contextualizeArithmeticPair(operands);
            const bool_ty = try self.resolver.generics.internType(.{ .builtin = .Bool });
            const reach = try self.operatorContext(assumed);
            defer self.resolver.allocator.free(reach.global.visible_bindings);
            if (try self.resolver.makeComparisonCall(self.module_index, operator, operands, reach, null)) |call|
                return self.resolver.comparisonResult(self.resolver.lowerSelectedScalarComparison(call, if (operator == .not_equal) .equal else operator, operands), operator);
            const left = self.resolver.graph.node(operands[0]).ty orelse return error.UntypedParameterizedComparison;
            const right = self.resolver.graph.node(operands[1]).ty orelse return error.UntypedParameterizedComparison;
            if (self.resolver.core.isDirectComparison(operator, left, right)) return error.UnresolvedContractComparison;
            // Tag tests retain comparison nodes. Unsupported aggregate nodes
            // remain typed for the final semantizing diagnostic, so speculative
            // instantiation never emits errors for discarded candidates.
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
            const hit = global_types.findField(self.resolver.graph, ty, name) orelse {
                if (self.resolver.generics.comptime_failure == null) {
                    self.resolver.generics.comptime_failure = .{
                        .source = self.resolver.sourceFor(self.module_index, source),
                        .reason = try std.fmt.allocPrint(self.resolver.allocator, "type has no field '{s}'", .{name}),
                    };
                }
                return error.UnknownParameterizedField;
            };
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
            if (self.callsite_reach) |inherited| {
                const visible = try self.resolver.allocator.alloc(global_sg.GlobalBindingId, inherited.bindingCount());
                for (visible, 0..) |*binding, index| binding.* = inherited.bindingAt(index);
                var result = ReachInferenceContext.fromGlobal(visible, inherited.ownerFunction());
                result.global.assumed_fields = inherited.assumedFields();
                return result;
            }
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
                if (store) try self.resolver.core.contextualizeStoredValue(operands[2], element);
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
            defer control.deinit();
            // Resolve the iterator protocol before specializing the body: its
            // next output establishes the previously unknown item type. Both
            // concrete and generic loops use the same ownership wrapper.
            const operation = .{
                .node = @as(module_entities.ModuleNodeId, @enumFromInt(@intFromEnum(target))),
                .binding = @as(module_entities.ModuleBindingId, @enumFromInt(@intFromEnum(binding))),
                .iterable = @as(module_entities.ModuleNodeId, @enumFromInt(@intFromEnum(operands[0]))),
                .body = @as(module_entities.ModuleBlockId, @enumFromInt(@intFromEnum(empty))),
                .mode = detail.mode,
                .source = source,
            };
            const context = try self.operatorContext(value.assumed_arguments);
            defer self.resolver.allocator.free(context.global.visible_bindings);
            switch (try control.resolveForEach(self.module_index, std.mem.zeroes(globalizer.Offsets), operation, context)) {
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
            try graph.setBlock(self.resolver.allocator, body_id, .{ .nodes = .{ .start = start, .len = @intCast(nodes.len + 2) }, .ret_val = actual_body.ret_val });
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
                    try self.resolver.graph.setNodeType(self.resolver.allocator, operands[0], ty);
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
            var target = operands[0];
            if (self.callsite_reach != null) switch (self.resolver.graph.node(target).content) {
                .binding_use, .assignment, .struct_field_access, .choice_payload_access, .array_index, .dereference => {},
                else => {
                    const graph = self.resolver.graph;
                    const global_source = self.resolver.sourceFor(self.module_index, source);
                    const binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(graph.bindings.items.len)));
                    try graph.bindings.append(self.resolver.allocator, .{
                        .name = try graph.addString(self.resolver.allocator, "#address_temporary"),
                        .source = global_source,
                        .ty = child,
                        .initialization = target,
                        .deferred_initialization = true,
                        .mutability = .variable,
                    });
                    const declaration: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(graph.nodes.items.len)));
                    try graph.nodes.append(self.resolver.allocator, .{ .source = global_source, .ty = try self.resolver.generics.internType(.{ .builtin = .Void }), .content = .{ .binding_declaration = binding } });
                    try self.callsite_temporaries.append(self.resolver.allocator, declaration);
                    const assignment: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(graph.nodes.items.len)));
                    try graph.nodes.append(self.resolver.allocator, .{ .source = global_source, .ty = child, .content = .{ .assignment = .{ .binding = binding, .value = target } } });
                    target = assignment;
                },
            };
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = pointer, .content = .{ .address_of = target } };
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

        fn lexicalBinding(self: *InstanceContext, local: ir.ParameterizedBindingId) !global_sg.GlobalBindingId {
            const module = &self.resolver.modules[self.module_index];
            const name = module.text(module.semantic.parameterized_storage.ir.bindings.items[@intFromEnum(local)].name);
            var index = self.conditional_bindings.items.len;
            while (index != 0) {
                index -= 1;
                const entry = self.conditional_bindings.items[index];
                // Bindings are appended in declaration order. An inserted
                // declaration can shadow an earlier syntax binding, while a
                // later explicit declaration keeps its already-bound identity.
                if (@intFromEnum(entry.local) <= @intFromEnum(local)) continue;
                if (std.mem.eql(u8, self.resolver.graph.text(self.resolver.graph.binding(entry.global).name), name)) return entry.global;
            }
            return self.instantiateBinding(local);
        }

        fn findGlobalBinding(self: *InstanceContext, name: []const u8) ?global_sg.GlobalBindingId {
            var index = self.conditional_bindings.items.len;
            while (index != 0) {
                index -= 1;
                const binding = self.conditional_bindings.items[index].global;
                if (std.mem.eql(u8, self.resolver.graph.text(self.resolver.graph.binding(binding).name), name)) return binding;
            }
            if (self.function) |function_id| {
                const function = self.resolver.graph.function(function_id);
                inline for (.{ function.input_bindings, function.output_bindings }) |range| {
                    for (self.resolver.graph.binding_refs.items[range.start..][0..range.len]) |binding|
                        if (std.mem.eql(u8, self.resolver.graph.text(self.resolver.graph.binding(binding).name), name)) return binding;
                }
            }
            // A specialization has the defining module's namespace, never
            // another function's locals or an unrelated module's globals.
            return @import("name_lookup.zig").binding(self.resolver.graph, self.resolver.modules, self.resolver.offsets, self.module_index, name);
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

test "generic instance contexts reserve maps only when entries are used" {
    const allocator = std.testing.allocator;
    var module: module_sg.ModuleSemanticGraph = .{};
    defer module.deinit(allocator);
    try module.semantic.parameterized_storage.ir.bindings.appendNTimes(allocator, undefined, 1000);
    try module.semantic.parameterized_storage.ir.nodes.appendNTimes(allocator, undefined, 10000);
    try module.semantic.parameterized_storage.ir.blocks.appendNTimes(allocator, undefined, 1000);
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    var resolver: Resolver = .{ .allocator = failing.allocator(), .graph = undefined, .modules = &modules, .offsets = &.{}, .core = undefined, .generics = undefined };
    var substitutions: generic_mod.Resolver.Bindings = .{ .types = &.{}, .ints = &.{} };
    var context = Resolver.InstanceContext.init(&resolver, 0, std.mem.zeroes(parameterized_storage.ParameterizedFunction), &substitutions);
    defer context.deinit();
}

test "comparison negation patches its destination after node storage grows" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var core: core_mod.Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    var generics: generic_mod.Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core, .generics = &generics };
    const boolean = try generics.internType(.{ .builtin = .Bool });
    try graph.nodes.ensureTotalCapacityPrecise(allocator, 1);
    const placeholder: global_sg.Node = .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = boolean, .content = .{ .bool_literal = false } };
    try graph.nodes.appendNTimes(allocator, placeholder, graph.nodes.capacity);
    const capacity = graph.nodes.capacity;
    var selected = placeholder;
    selected.content = .{ .bool_literal = true };
    try resolver.patchComparisonResult(@enumFromInt(0), selected, .not_equal);
    try std.testing.expect(graph.nodes.capacity > capacity);
    const comparison = graph.nodes.items[0].content.comparison;
    try std.testing.expectEqual(primitives.ComparisonOperator.equal, comparison.operator);
    try std.testing.expect(graph.node(comparison.left).content.bool_literal);
    try std.testing.expect(!graph.node(comparison.right).content.bool_literal);
}

test "speculative entry capture rollback restores live parent contexts before IDs are reused" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const literal: global_sg.Node = .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } };
    try graph.nodes.append(allocator, literal);
    var module: module_sg.ModuleSemanticGraph = .{};
    defer module.deinit(allocator);
    try module.semantic.parameterized_storage.ir.nodes.appendNTimes(allocator, undefined, 2);
    try module.semantic.parameterized_storage.ir.bindings.appendNTimes(allocator, undefined, 2);
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var core: core_mod.Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &modules, .offsets = &.{} };
    defer core.deinit();
    var generics: generic_mod.Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &modules, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &modules, .offsets = &.{}, .core = &core, .generics = &generics };
    var substitutions: generic_mod.Resolver.Bindings = .{ .types = &.{}, .ints = &.{} };
    var parent = Resolver.InstanceContext.init(&resolver, 0, std.mem.zeroes(parameterized_storage.ParameterizedFunction), &substitutions);
    defer parent.deinit();
    parent.function = @enumFromInt(0);
    var child = Resolver.InstanceContext.init(&resolver, 0, std.mem.zeroes(parameterized_storage.ParameterizedFunction), &substitutions);
    defer child.deinit();
    child.active_parent = &parent;
    resolver.active_instance = &child;
    const name = try graph.addString(allocator, "value");
    const retained = try parent.captureEntryValue(name, source, @enumFromInt(0));
    const retained_binding = graph.node(retained).content.binding_use;
    try parent.node_map.put(allocator, 0, retained);
    try parent.binding_map.put(allocator, 0, retained_binding);

    var speculation = resolver.beginSpeculation();
    defer speculation.deinit();
    const provisional_value: global_sg.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(allocator, literal);
    const provisional = try parent.captureEntryValue(name, source, provisional_value);
    const provisional_binding = graph.node(provisional).content.binding_use;
    try parent.node_map.put(allocator, 1, provisional);
    try parent.binding_map.put(allocator, 1, provisional_binding);
    speculation.rollback();
    try std.testing.expectEqual(@as(usize, 1), parent.entry_captures.items.len);
    try std.testing.expectEqual(retained, parent.node_map.get(0).?);
    try std.testing.expectEqual(retained_binding, parent.binding_map.get(0).?);
    try std.testing.expectEqual(null, parent.node_map.get(1));
    try std.testing.expectEqual(null, parent.binding_map.get(1));

    try std.testing.expectEqual(@intFromEnum(provisional_value), graph.nodes.items.len);
    try graph.nodes.append(allocator, literal);
    const retried = try parent.captureEntryValue(name, source, provisional_value);
    try std.testing.expectEqual(provisional, retried);
    try std.testing.expectEqual(@as(usize, 2), parent.entry_captures.items.len);
}

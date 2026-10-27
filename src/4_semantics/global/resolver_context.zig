const std = @import("std");
const module_sg = @import("../module/graph.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
const core_mod = @import("core.zig");
const expression_mod = @import("expressions.zig");
const constructor_mod = @import("constructors.zig");
const control_mod = @import("control.zig");
const generic_mod = @import("generics.zig");
const generic_functions_mod = @import("generic_functions.zig");
const contract_mod = @import("contracts.zig");
const error_mod = @import("errors.zig");
const dispatch_mod = @import("dispatch.zig");
const ownership_mod = @import("ownership.zig");
const execution = @import("comptime_execution.zig");

/// Mutually recursive semantic resolvers and their retained resolution state.
/// Initialize in final storage; moving this value would invalidate callbacks.
/// The graph, modules and offsets are borrowed and must outlive the context.
pub const Context = struct {
    const StatsSnapshot = struct {
        core: @FieldType(core_mod.Resolver, "stats"),
        expressions: @FieldType(expression_mod.Resolver, "stats"),
        control: @FieldType(control_mod.Resolver, "stats"),
        generics: @FieldType(generic_mod.Resolver, "stats"),
        generic_functions: @FieldType(generic_functions_mod.Resolver, "stats"),
        contracts: @FieldType(contract_mod.Resolver, "stats"),
        errors: @FieldType(error_mod.Resolver, "stats"),
        ownership: @FieldType(ownership_mod.Resolver, "stats"),
    };
    // Retained semantic additions and suspended diagnostics need coordinated
    // undo. Operation owners and loop cleanup boundaries are call arguments,
    // so recursive work cannot overwrite them or add checkpoint obligations.
    pub const StateCheckpoint = struct {
        effects: generic_functions_mod.Resolver.SideEffectCheckpoint,
        execution: execution.Scheduler.StateCheckpoint,
        namespace: ?struct { modules: usize, declarations: usize, assumptions: usize },
        bindings: usize,
        continuation_bindings: usize,
        expression_continuation: ?global_sg.GlobalFunctionId,
        ownership_continuation: ?global_sg.GlobalFunctionId,
        denied_copy: @FieldType(ownership_mod.Resolver, "denied_copy"),
        argument_failure: @FieldType(generic_mod.Resolver, "argument_failure"),
        constraint_failure: @FieldType(generic_functions_mod.Resolver, "failed_constraint"),
        virtual_failure: @FieldType(contract_mod.Resolver, "virtual_signature_failure"),
        foreach_failure: @FieldType(control_mod.Resolver, "for_each_failure"),
        diagnostics: ?*diagnostics_mod.Diagnostics,
        stats: StatsSnapshot,
        call_stages: @FieldType(dispatch_mod.Resolver, "pending_call_stages"),
        selection_profile: @FieldType(generic_functions_mod.Resolver, "selection_profile"),
    };

    core: core_mod.Resolver,
    expressions: expression_mod.Resolver,
    constructors: constructor_mod.Resolver,
    control: control_mod.Resolver,
    generics: generic_mod.Resolver,
    generic_functions: generic_functions_mod.Resolver,
    contracts: contract_mod.Resolver,
    errors: error_mod.Resolver,
    dispatch: dispatch_mod.Resolver,
    ownership: ownership_mod.Resolver,
    staged_execution: execution.Scheduler,
    captured_expressions: core_mod.Resolver.CapturedExpressions,

    pub fn init(self: *Context, allocator: std.mem.Allocator, graph: *global_sg.GlobalSemanticGraph, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets, diagnostics: ?*diagnostics_mod.Diagnostics, profile_io: ?std.Io) void {
        self.core = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .profile_io = profile_io,
        };
        self.expressions = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
        };
        self.constructors = .{
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .core = &self.core,
            .diagnostics = diagnostics,
        };
        self.control = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .core = &self.core,
        };
        self.generics = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .core = &self.core,
            .profile_io = profile_io,
        };
        self.generic_functions = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .core = &self.core,
            .generics = &self.generics,
            .profile_io = profile_io,
        };
        self.staged_execution = .{
            .allocator = allocator,
            .functions = &self.generic_functions,
            .stable_type_count = graph.types.items.len,
            .stable_declaration_count = graph.declarations.items.len,
            .stable_node_count = graph.nodes.items.len,
        };
        self.generic_functions.capture_lookup_context = &self.expressions;
        self.generic_functions.capture_lookup = expression_mod.Resolver.captureBinding;
        self.generics.execution_context = &self.staged_execution;
        self.generics.checkpoint_execution = execution.Scheduler.checkpoint;
        self.generics.rollback_execution = execution.Scheduler.rollback;
        self.generics.execute_integer = execution.Scheduler.integer;
        self.generics.execute_boolean = execution.Scheduler.boolean;
        self.contracts = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .core = &self.core,
            .generics = &self.generics,
            .profile_implementation_scans = profile_io != null,
            .profile_io = profile_io,
        };
        self.generics.projection_context = &self.contracts;
        self.generics.projection_resolver = contract_mod.Resolver.resolveAssociatedType;
        self.generics.value_projection_resolver = @import("contract_projections.zig").resolveAssociatedValue;
        self.generics.definition_projection_resolver = contract_mod.Resolver.resolveAssociatedDefinition;
        self.generics.constant_projection_resolver = contract_mod.Resolver.resolveAssociatedInt;
        self.constructors.contracts = &self.contracts;
        self.control.generic_functions = &self.generic_functions;
        self.control.contracts = &self.contracts;
        self.core.session_value_bindings = &self.expressions.session_bindings;
        self.contracts.function_context = &self.generic_functions;
        self.contracts.instantiate_function = generic_functions_mod.Resolver.instantiateReferencedFunction;
        self.contracts.instantiate_operation_value = generic_functions_mod.Resolver.instantiateOperationValue;
        self.contracts.instantiate_alias = generic_functions_mod.Resolver.instantiateOperationAlias;
        self.contracts.infer_operation_parameters = generic_functions_mod.Resolver.inferOperationParameters;
        self.contracts.probe_implementation_operation = generic_functions_mod.Resolver.probeImplementationOperation;
        self.contracts.instantiate_generic_operation = generic_functions_mod.Resolver.instantiateGenericOperation;
        self.contracts.call_implementation_operation = generic_functions_mod.Resolver.callImplementationOperation;
        self.captured_expressions = .{
            .context = &self.generic_functions,
            .checkpoint = generic_functions_mod.Resolver.checkpointDefaultEffects,
            .rollback = generic_functions_mod.Resolver.rollbackDefaultEffects,
            .instantiate = generic_functions_mod.Resolver.instantiateCapturedExpression,
        };
        self.core.captured_expressions = &self.captured_expressions;
        self.generic_functions.nested_call_context = &self.contracts;
        self.generic_functions.nested_call_resolver = contract_mod.Resolver.resolveNestedCall;
        self.generic_functions.nested_constructor_context = &self.constructors;
        self.generic_functions.nested_constructor_resolver = constructor_mod.Resolver.resolveNestedCall;
        // Wire callbacks only after every target field has its final address.
        self.constructors.generics = &self.generics;
        self.constructors.generic_functions = &self.generic_functions;
        self.errors = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .core = &self.core,
        };
        self.dispatch = .{
            .core = &self.core,
            .generic_functions = &self.generic_functions,
            .constructors = &self.constructors,
            .contracts = &self.contracts,
            .control = &self.control,
            .errors = &self.errors,
            .profile_io = profile_io,
        };
        self.ownership = .{
            .allocator = allocator,
            .graph = graph,
            .modules = modules,
            .offsets = offsets,
            .core = &self.core,
            .dispatch = &self.dispatch,
            .profile_io = profile_io,
        };
        self.generic_functions.ownership_context = &self.ownership;
        self.generic_functions.register_defer = ownership_mod.Resolver.registerParameterizedDefer;
        self.generic_functions.ownership_checkpoint = ownership_mod.Resolver.parameterizedCheckpoint;
        self.generic_functions.rollback_ownership = ownership_mod.Resolver.rollbackParameterizedCheckpoint;
    }

    pub fn checkpointState(self: *const Context) StateCheckpoint {
        var saved: StateCheckpoint = .{
            .effects = self.generic_functions.checkpointSideEffects(),
            .execution = self.staged_execution.checkpointState(),
            .namespace = if (self.core.session_namespace) |namespace| .{ .modules = namespace.modules.items.len, .declarations = namespace.declarations.items.len, .assumptions = namespace.assumptions.items.len } else null,
            .bindings = self.expressions.session_bindings.items.len,
            .continuation_bindings = self.ownership.continuation_bindings.items.len,
            .expression_continuation = self.expressions.continuation_function,
            .ownership_continuation = self.ownership.continuation_function,
            .denied_copy = self.ownership.denied_copy,
            .argument_failure = self.generics.argument_failure,
            .constraint_failure = self.generic_functions.failed_constraint,
            .virtual_failure = self.contracts.virtual_signature_failure,
            .foreach_failure = self.control.for_each_failure,
            .diagnostics = self.constructors.diagnostics,
            .stats = undefined,
            .call_stages = self.dispatch.pending_call_stages,
            .selection_profile = self.generic_functions.selection_profile,
        };
        inline for (std.meta.fields(StatsSnapshot)) |field| @field(saved.stats, field.name) = @field(self, field.name).stats;
        return saved;
    }

    /// Restore execution completions before the producer-only callback undo:
    /// newly materialized requests may already contain executable node IDs.
    pub fn rollbackState(self: *Context, saved: StateCheckpoint) void {
        self.staged_execution.rollbackState(saved.execution);
        self.generic_functions.rollbackSideEffects(saved.effects);
        if (saved.namespace) |previous| {
            const namespace = self.core.session_namespace.?;
            namespace.modules.shrinkRetainingCapacity(previous.modules);
            namespace.declarations.shrinkRetainingCapacity(previous.declarations);
            namespace.assumptions.shrinkRetainingCapacity(previous.assumptions);
        } else if (self.core.session_namespace) |namespace| {
            namespace.modules.deinit(self.core.allocator);
            namespace.declarations.deinit(self.core.allocator);
            namespace.assumptions.deinit(self.core.allocator);
            self.core.allocator.destroy(namespace);
            self.core.session_namespace = null;
        }
        self.expressions.session_bindings.shrinkRetainingCapacity(saved.bindings);
        self.ownership.continuation_bindings.shrinkRetainingCapacity(saved.continuation_bindings);
        self.expressions.continuation_function = saved.expression_continuation;
        self.ownership.continuation_function = saved.ownership_continuation;
        self.ownership.denied_copy = saved.denied_copy;
        self.generics.argument_failure = saved.argument_failure;
        self.generic_functions.failed_constraint = saved.constraint_failure;
        self.contracts.virtual_signature_failure = saved.virtual_failure;
        self.control.for_each_failure = saved.foreach_failure;
        self.constructors.diagnostics = saved.diagnostics;
        inline for (std.meta.fields(StatsSnapshot)) |field| @field(self, field.name).stats = @field(saved.stats, field.name);
        self.dispatch.pending_call_stages = saved.call_stages;
        self.generic_functions.selection_profile = saved.selection_profile;
    }

    /// Fork retained effects into resolvers wired to an identity-preserving
    /// graph copy. Callback targets always belong to the destination context.
    /// Source modules remain borrowed; all mutable caches and effects are owned.
    pub fn cloneFrom(self: *Context, source: *const Context, allocator: std.mem.Allocator, graph: *global_sg.GlobalSemanticGraph, offsets: []const globalizer.Offsets, diagnostics: ?*diagnostics_mod.Diagnostics) !void {
        if (self == source or offsets.len != source.core.modules.len or graph.modules.items.len != source.core.modules.len or
            source.generic_functions.publishing_signature or source.generic_functions.active_instance != null)
            return error.InvalidSemanticForkState;
        self.init(allocator, graph, source.core.modules, offsets, diagnostics, source.core.profile_io);
        errdefer self.deinit();
        for (source.core.reached_calls.items) |call| {
            var retained = call;
            retained.visible = try allocator.dupe(global_sg.GlobalBindingId, call.visible);
            self.core.reached_calls.append(allocator, retained) catch |err| {
                allocator.free(retained.visible);
                return err;
            };
        }
        if (source.core.session_namespace) |previous| {
            const namespace = try self.core.sessionNamespace();
            try namespace.modules.appendSlice(allocator, previous.modules.items);
            try namespace.declarations.appendSlice(allocator, previous.declarations.items);
            try namespace.assumptions.appendSlice(allocator, previous.assumptions.items);
        }
        try self.expressions.session_bindings.appendSlice(allocator, source.expressions.session_bindings.items);
        self.expressions.continuation_function = source.expressions.continuation_function;
        self.generics.pointer_types = try source.generics.pointer_types.clone(allocator);
        self.generics.generic_types = try source.generics.generic_types.clone(allocator);
        self.generics.comptime_failure = source.generics.comptime_failure;
        self.generics.argument_failure = source.generics.argument_failure;
        self.contracts.constraint_declarations = try source.contracts.constraint_declarations.clone(allocator);
        self.contracts.resolved_contract_refs = try source.contracts.resolved_contract_refs.clone(allocator);
        var templates = source.contracts.implementation_templates.iterator();
        while (templates.next()) |entry| {
            var group = entry.value_ptr.*;
            group.entries = try group.entries.clone(allocator);
            self.contracts.implementation_templates.put(allocator, entry.key_ptr.*, group) catch |err| {
                group.entries.deinit(allocator);
                return err;
            };
        }
        try self.contracts.template_rewrites.appendSlice(allocator, source.contracts.template_rewrites.items);
        self.contracts.rollbackResolution(source.contracts.checkpointResolution());
        self.contracts.virtual_signature_failure = source.contracts.virtual_signature_failure;
        try self.ownership.deferred.appendSlice(allocator, source.ownership.deferred.items);
        try self.ownership.auto_nodes.appendSlice(allocator, source.ownership.auto_nodes.items);
        try self.ownership.continuation_bindings.appendSlice(allocator, source.ownership.continuation_bindings.items);
        self.ownership.replacement_candidates = try source.ownership.replacement_candidates.clone(allocator);
        try self.ownership.replacement_rewrites.appendSlice(allocator, source.ownership.replacement_rewrites.items);
        self.ownership.denied_copy = source.ownership.denied_copy;
        self.ownership.empty_block = source.ownership.empty_block;
        self.ownership.continuation_function = source.ownership.continuation_function;
        self.control.for_each_failure = source.control.for_each_failure;
        self.generic_functions.failed_constraint = source.generic_functions.failed_constraint;
        self.staged_execution = try source.staged_execution.clone(allocator, &self.generic_functions);
        // Error inference scratch is rebuilt on each pass; it carries no facts.
        inline for (.{ "core", "expressions", "control", "generics", "generic_functions", "contracts", "errors", "ownership" }) |field|
            @field(self, field).stats = @field(source, field).stats;
        self.dispatch.pending_call_stages = source.dispatch.pending_call_stages;
        self.generic_functions.selection_profile = source.generic_functions.selection_profile;
    }

    /// Rebind borrowed views after relocation appends an immutable module suffix.
    /// Existing module contents, imports and global identities must stay fixed.
    /// Registration and resolution are explicit subsequent coordinator steps.
    pub fn extendModuleViews(self: *Context, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets) !void {
        if (modules.len < self.core.modules.len or offsets.len != modules.len or self.core.graph.modules.items.len != modules.len)
            return error.InvalidSemanticModuleViews;
        self.rebindModuleViews(modules, offsets);
    }

    pub fn rebindModuleViews(self: *Context, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets) void {
        std.debug.assert(offsets.len == modules.len and self.core.graph.modules.items.len == modules.len);
        inline for (.{ "core", "expressions", "constructors", "control", "generics", "generic_functions", "contracts", "errors", "ownership" }) |field| {
            const resolver = &@field(self, field);
            resolver.modules = modules;
            resolver.offsets = offsets;
        }
    }

    pub fn deinit(self: *Context) void {
        self.expressions.deinit();
        self.ownership.deinit();
        self.errors.deinit();
        self.contracts.deinit();
        self.staged_execution.deinit();
        self.generics.deinit();
        self.core.deinit();
        self.* = undefined;
    }
};

test "resolver context retains staged demand through its callback transactions" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    var context: Context = undefined;
    context.init(a, &graph, &.{}, &.{}, null, null);
    defer context.deinit();
    var bindings = try generic_mod.Resolver.Bindings.init(a, 0);
    defer bindings.deinit(a);
    try std.testing.expect(context.constructors.core == &context.core);
    try std.testing.expect(context.constructors.generics.? == &context.generics);
    try std.testing.expect(context.control.contracts.? == &context.contracts);
    try std.testing.expect(context.contracts.generics == &context.generics);
    try std.testing.expect(context.staged_execution.functions == &context.generic_functions);
    try std.testing.expect(context.ownership.dispatch.? == &context.dispatch);
    const defaults = context.core.captured_expressions.?;
    const saved = defaults.checkpoint(defaults.context);
    const evaluate = context.generics.execute_integer.?;
    try std.testing.expectError(error.ComptimeExecutionPending, evaluate(context.generics.execution_context.?, 0, @enumFromInt(0), &bindings));
    try std.testing.expectEqual(@as(usize, 1), context.staged_execution.requests.items.len);
    defaults.rollback(defaults.context, saved);
    try std.testing.expectEqual(@as(usize, 0), context.staged_execution.requests.items.len);
    // A later request still reaches the same context after rollback.
    try std.testing.expectError(error.ComptimeExecutionPending, evaluate(context.generics.execution_context.?, 0, @enumFromInt(1), &bindings));
    try std.testing.expectEqual(@as(usize, 1), context.staged_execution.requests.items.len);
}

test "resolver contexts keep their graphs and pending evaluation independent" {
    const a = std.testing.allocator;
    var left_graph: global_sg.GlobalSemanticGraph = .{};
    defer left_graph.deinit(a);
    var right_graph: global_sg.GlobalSemanticGraph = .{};
    defer right_graph.deinit(a);
    var left: Context = undefined;
    left.init(a, &left_graph, &.{}, &.{}, null, null);
    defer left.deinit();
    var right: Context = undefined;
    right.init(a, &right_graph, &.{}, &.{}, null, null);
    defer right.deinit();
    var bindings = try generic_mod.Resolver.Bindings.init(a, 0);
    defer bindings.deinit(a);
    try std.testing.expectError(error.ComptimeExecutionPending, left.generics.execute_boolean.?(left.generics.execution_context.?, 0, @enumFromInt(0), &bindings));
    try std.testing.expectEqual(@as(usize, 0), right.staged_execution.requests.items.len);
    try std.testing.expect(left.ownership.graph == &left_graph);
    try std.testing.expect(right.ownership.graph == &right_graph);
    try std.testing.expect(left.dispatch.core == &left.core);
    try std.testing.expect(right.dispatch.core == &right.core);
}

fn registrationModule(allocator: std.mem.Allocator, dir: []const u8, source: []const u8) !module_sg.ModuleSemanticGraph {
    const files = [_]@import("../../1_base/source_files.zig").SourceFile{.{ .path = "main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();
    var tokenizer = @import("../../2_tokens/tokenizer.zig").Tokenizer.init(allocator, &diagnostics, source, @enumFromInt(0));
    defer tokenizer.deinit();
    _ = try tokenizer.tokenize();
    var syntaxer = @import("../../3_syntax/syntaxer.zig").Syntaxer.initFile(allocator, @import("../../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(@enumFromInt(0), tokenizer.takeTokens()), source, &diagnostics);
    defer syntaxer.deinit();
    var tree = try syntaxer.parse();
    defer tree.deinit(allocator);
    return (try @import("../module/semantizer.zig").build(allocator, dir, &.{.{ .path = "main.rg", .tree = &tree, .source = source }})).graph;
}

test "resolver context extends conformance registration without duplicating retained evidence" {
    const a = std.testing.allocator;
    var first = try registrationModule(a, "first", "Marker#(.Value: Type): Contract = ()\nimplement Marker#(Int32) ()\nimplement Marker#(UInt8) ()\n");
    defer first.deinit(a);
    var second = try registrationModule(a, "second", "Other#(.Value: Type): Contract = ()\nimplement Other#(Int64) ()\n");
    defer second.deinit(a);
    var duplicate = try registrationModule(a, "duplicate", "Broken#(.Value: Type): Contract = ()\nimplement Broken#(Int32) ()\nimplement Broken#(Int32) ()\n");
    defer duplicate.deinit(a);
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    var retained = try globalizer.relocate(a, modules[0..1], .allow_holes);
    defer retained.deinit(a);
    var context: Context = undefined;
    context.init(a, &retained.graph, modules[0..1], retained.offsets.items, null, null);
    defer context.deinit();
    const graph_checkpoint = retained.graph.checkpoint();
    const resolution_checkpoint = context.contracts.checkpointResolution();
    try context.contracts.prepareParticipantConformances();
    try std.testing.expectEqual(@as(usize, 2), retained.graph.contract_conformances.items.len);
    try context.contracts.prepareParticipantConformances();
    try std.testing.expectEqual(@as(usize, 2), retained.graph.contract_conformances.items.len);
    try std.testing.expectEqual(null, context.contracts.participant_conformance_failure);
    retained.graph.rollback(a, graph_checkpoint);
    context.contracts.rollbackResolution(resolution_checkpoint);
    try context.contracts.prepareParticipantConformances();
    try std.testing.expectEqual(@as(usize, 2), retained.graph.contract_conformances.items.len);
    try retained.append(a, modules[1..], .allow_holes);
    try context.extendModuleViews(&modules, retained.offsets.items);
    try context.contracts.prepareParticipantConformances();
    try std.testing.expectEqual(@as(usize, 3), retained.graph.contract_conformances.items.len);
    try context.contracts.prepareParticipantConformances();
    try std.testing.expectEqual(@as(usize, 3), retained.graph.contract_conformances.items.len);
    try std.testing.expectEqual(null, context.contracts.participant_conformance_failure);
    try std.testing.expectEqual(@as(usize, 2), context.ownership.modules.len);
    try std.testing.expectEqual(@as(usize, 2), context.generic_functions.offsets.len);
    try std.testing.expectError(error.InvalidSemanticModuleViews, context.extendModuleViews(modules[0..1], retained.offsets.items[0..1]));
    try std.testing.expectEqual(@as(usize, 2), context.core.modules.len);
    const extended = [_]module_sg.ModuleSemanticGraph{ first, second, duplicate };
    try retained.append(a, &.{duplicate}, .allow_holes);
    try context.extendModuleViews(&extended, retained.offsets.items);
    try context.contracts.prepareParticipantConformances();
    const failure = context.contracts.participant_conformance_failure orelse return error.ExpectedConformanceFailure;
    try std.testing.expectEqualStrings("ambiguous conformances for the same participant tuple", failure.reason);
    try std.testing.expectEqual(@as(usize, 4), retained.graph.contract_conformances.items.len);
}

fn cloneRetainedContext(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    var source: Context = undefined;
    source.init(a, &graph, &.{}, &.{}, null, null);
    defer source.deinit();
    const namespace = try source.core.sessionNamespace();
    try namespace.modules.append(a, @enumFromInt(0));
    try namespace.declarations.append(a, @enumFromInt(7));
    const visible = try a.dupe(global_sg.GlobalBindingId, &.{@enumFromInt(1)});
    try source.core.reached_calls.append(a, .{ .callee = @enumFromInt(2), .input = @enumFromInt(3), .owner = null, .skip_receiver = false, .visible = visible });
    try source.ownership.deferred.append(a, .{ .marker = @enumFromInt(4), .value = @enumFromInt(5) });
    try source.ownership.auto_nodes.append(a, .{ .binding = @enumFromInt(1), .node = @enumFromInt(6) });
    try source.ownership.replacement_candidates.put(a, @enumFromInt(6), {});
    try source.generics.pointer_types.put(a, .{ .child = @enumFromInt(0), .mutability = .read_only }, @enumFromInt(1));
    const group = try source.contracts.implementation_templates.getOrPut(a, .{ .declaration = @enumFromInt(7), .arity = 1 });
    group.value_ptr.* = .{};
    try group.value_ptr.entries.append(a, .{ .module = 0, .index = 0 });
    var bindings = try generic_mod.Resolver.Bindings.init(a, 0);
    defer bindings.deinit(a);
    try std.testing.expectError(error.ComptimeExecutionPending, source.generics.execute_integer.?(source.generics.execution_context.?, 0, @enumFromInt(0), &bindings));
    var candidate_graph = try graph.clone(a);
    defer candidate_graph.deinit(a);
    var candidate: Context = undefined;
    try candidate.cloneFrom(&source, allocator, &candidate_graph, &.{}, null);
    defer candidate.deinit();
    try std.testing.expect(candidate.core.graph == &candidate_graph);
    try std.testing.expect(candidate.generics.core == &candidate.core);
    try std.testing.expect(candidate.generic_functions.active_instance == null);
    try std.testing.expect(candidate.generic_functions.capture_lookup_context.? == @as(*anyopaque, &candidate.expressions));
    try std.testing.expect(candidate.generics.execution_context.? == @as(*anyopaque, &candidate.staged_execution));
    try std.testing.expect(candidate.staged_execution.functions == &candidate.generic_functions);
    try std.testing.expect(candidate.ownership.dispatch.? == &candidate.dispatch);
    candidate.core.reached_calls.items[0].visible[0] = @enumFromInt(9);
    candidate.core.session_namespace.?.modules.clearRetainingCapacity();
    candidate.core.session_namespace.?.declarations.clearRetainingCapacity();
    candidate.ownership.deferred.clearRetainingCapacity();
    candidate.ownership.auto_nodes.clearRetainingCapacity();
    _ = candidate.ownership.replacement_candidates.remove(@enumFromInt(6));
    candidate.generics.pointer_types.clearRetainingCapacity();
    candidate.contracts.implementation_templates.getPtr(.{ .declaration = @enumFromInt(7), .arity = 1 }).?.entries.clearRetainingCapacity();
    execution.Scheduler.rollback(&candidate.staged_execution, 0);
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(source.core.reached_calls.items[0].visible[0]));
    try std.testing.expectEqual(@as(usize, 1), namespace.modules.items.len);
    try std.testing.expectEqual(@as(usize, 1), namespace.declarations.items.len);
    try std.testing.expectEqual(@as(usize, 1), source.ownership.deferred.items.len);
    try std.testing.expectEqual(@as(usize, 1), source.ownership.auto_nodes.items.len);
    try std.testing.expect(source.ownership.replacement_candidates.contains(@enumFromInt(6)));
    try std.testing.expectEqual(@as(usize, 1), source.generics.pointer_types.count());
    try std.testing.expectEqual(@as(usize, 1), source.contracts.implementation_templates.get(.{ .declaration = @enumFromInt(7), .arity = 1 }).?.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), source.staged_execution.requests.items.len);
}

test "resolver context clones isolate retained effects and callback targets" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneRetainedContext, .{});
}

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
    argument_defaults: core_mod.Resolver.ArgumentDefaults,

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
        };
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
        self.generics.constant_projection_resolver = contract_mod.Resolver.resolveAssociatedInt;
        self.constructors.contracts = &self.contracts;
        self.control.generic_functions = &self.generic_functions;
        self.control.contracts = &self.contracts;
        self.contracts.function_context = &self.generic_functions;
        self.contracts.instantiate_function = generic_functions_mod.Resolver.instantiateReferencedFunction;
        self.contracts.instantiate_alias = generic_functions_mod.Resolver.instantiateOperationAlias;
        self.argument_defaults = .{
            .context = &self.generic_functions,
            .checkpoint = generic_functions_mod.Resolver.checkpointDefaultEffects,
            .rollback = generic_functions_mod.Resolver.rollbackDefaultEffects,
            .instantiate = generic_functions_mod.Resolver.instantiateArgumentDefault,
        };
        self.core.argument_defaults = &self.argument_defaults;
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

    pub fn deinit(self: *Context) void {
        self.ownership.deinit();
        self.errors.deinit();
        self.contracts.deinit();
        self.staged_execution.deinit();
        self.generics.deinit();
        self.core.deinitReachedCalls();
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
    const defaults = context.core.argument_defaults.?;
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

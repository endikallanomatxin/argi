const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const reach_context = @import("reach_context.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const constructor_mod = @import("constructors.zig");
const control_mod = @import("control.zig");
const generic_functions_mod = @import("generic_functions.zig");
const abstract_mod = @import("abstracts.zig");
const error_mod = @import("errors.zig");
const call_compatibility = @import("call_compatibility.zig");

pub const ImplicitLookupStats = struct {
    ordinary_calls: u64 = 0,
    ordinary_resolved: u64 = 0,
    ordinary_no_match: u64 = 0,
    ordinary_deferred: u64 = 0,
    ordinary_ambiguous: u64 = 0,
    ordinary_matching_ns: u64 = 0,
    ordinary_completion_calls: u64 = 0,
    ordinary_completion_deferred: u64 = 0,
    ordinary_completion_ns: u64 = 0,

    abstract_compatible_calls: u64 = 0,
    abstract_compatible_resolved: u64 = 0,
    abstract_compatible_no_match: u64 = 0,
    abstract_compatible_deferred: u64 = 0,
    abstract_compatible_ambiguous: u64 = 0,
    abstract_compatible_matching_ns: u64 = 0,
    abstract_compatible_completion_calls: u64 = 0,
    abstract_compatible_completion_deferred: u64 = 0,
    abstract_compatible_completion_ns: u64 = 0,

    generic_calls: u64 = 0,
    generic_resolved: u64 = 0,
    generic_no_match: u64 = 0,
    generic_deferred: u64 = 0,
    generic_ambiguous: u64 = 0,
    generic_matching_ns: u64 = 0,
    generic_completion_calls: u64 = 0,
    generic_completion_deferred: u64 = 0,
    generic_completion_ns: u64 = 0,
};

pub const PendingCallStage = enum {
    errors,
    ordinary,
    abstract_ordinary,
    generic,
    constructor,
    abstract,
    control,
};

pub const PendingCallStageStats = struct {
    attempts: u64 = 0,
    resolved: u64 = 0,
    deferred: u64 = 0,
    ns: u64 = 0,
};

/// Owns operations whose language-level resolution is deliberately composed
/// from several specialized strategies. Strategy fallback stays private to
/// this coordinator; callers only observe `deferred` or `resolved`.
pub const Resolver = struct {
    core: *core_mod.Resolver,
    generic_functions: *generic_functions_mod.Resolver,
    constructors: *constructor_mod.Resolver,
    abstracts: *abstract_mod.Resolver,
    control: *control_mod.Resolver,
    errors: *error_mod.Resolver,
    profile_io: ?std.Io = null,
    profile_generic_ns: i96 = 0,
    implicit_lookup_stats: ImplicitLookupStats = .{},
    pending_call_stages: [@typeInfo(PendingCallStage).@"enum".fields.len]PendingCallStageStats = @splat(.{}),

    fn profileTimestamp(self: *const Resolver) i96 {
        if (self.profile_io) |io| return std.Io.Timestamp.now(io, .boot).nanoseconds;
        return 0;
    }

    fn profileAccumulate(self: *Resolver, start: i96, elapsed: *u64) void {
        if (self.profile_io != null) elapsed.* += @intCast(self.profileTimestamp() - start);
    }

    fn profilePendingStage(self: *Resolver, stage: PendingCallStage, start: i96, result: resolution.Result) void {
        if (self.profile_io == null) return;
        const stats = &self.pending_call_stages[@intFromEnum(stage)];
        stats.attempts += 1;
        stats.resolved += @intFromBool(result == .resolved);
        stats.deferred += @intFromBool(result == .deferred);
        stats.ns += @intCast(self.profileTimestamp() - start);
    }

    pub fn resolveLocalReach(
        self: *Resolver,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !resolution.Result {
        const binding = globalizer.globalBinding(o, value.binding);
        if (self.core.graph.isBindingTypeUnresolved(binding)) return .deferred;
        const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);
        const compatibility = call_compatibility.Abstract{ .core = self.core, .abstracts = self.abstracts };
        const selected = try self.core.resolveReachedBindingWithCompatibility(
            reach,
            globalizer.globalNode(o, value.reach),
            binding,
            compatibility.additionalTypeCompatibility(),
        ) orelse return .deferred;
        const selected_type = self.core.graph.node(selected).ty orelse return .deferred;
        const stored = &self.core.graph.bindings.items[@intFromEnum(binding)];
        if (stored.mutability == .constant and compatibility.compatible(selected_type, stored.ty))
            stored.static_implementer = selected_type;
        self.core.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))] =
            self.core.graph.nodes.items[@intFromEnum(selected)];
        return .resolved;
    }

    pub fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        var stage_start = self.profileTimestamp();
        const error_result = try self.errors.tryResolveCall(module_index, module, o, operation);
        self.profilePendingStage(.errors, stage_start, error_result);
        if (!error_result.allowsFallback()) return error_result;
        stage_start = self.profileTimestamp();
        const core_result = try self.core.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.ordinary, stage_start, core_result);
        if (core_result == .resolved or core_result == .invalid) return core_result;

        // Abstract compatibility is not a competing callable family: it is a
        // richer matching policy for the same ordinary candidates. A Core
        // "deferred" result must therefore not hide a candidate that becomes
        // decidable once concrete-to-abstract compatibility is considered.
        stage_start = self.profileTimestamp();
        const abstract_ordinary_result = try call_compatibility.tryResolveOrdinaryCall(
            .{ .core = self.core, .abstracts = self.abstracts },
            module_index,
            module,
            o,
            operation,
        );
        self.profilePendingStage(.abstract_ordinary, stage_start, abstract_ordinary_result);
        if (abstract_ordinary_result == .resolved or abstract_ordinary_result == .invalid)
            return abstract_ordinary_result;
        if (core_result == .deferred or abstract_ordinary_result == .deferred)
            return .deferred;

        stage_start = self.profileTimestamp();
        const generic_result = try self.generic_functions.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.generic, stage_start, generic_result);
        if (!generic_result.allowsFallback()) return generic_result;

        stage_start = self.profileTimestamp();
        const constructor_result = try self.constructors.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.constructor, stage_start, constructor_result);
        if (!constructor_result.allowsFallback()) return constructor_result;

        stage_start = self.profileTimestamp();
        const abstract_result = try self.abstracts.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.abstract, stage_start, abstract_result);
        if (!abstract_result.allowsFallback()) return abstract_result;

        stage_start = self.profileTimestamp();
        const control_result = try self.control.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.control, stage_start, control_result);
        return if (control_result.allowsFallback()) .deferred else control_result;
    }

    pub const ImplicitFunctionCall = struct {
        function: global_sg.GlobalFunctionId,
        input: global_sg.GlobalNodeId,
    };

    pub fn resolveImplicitFunction(
        self: *Resolver,
        module_index: usize,
        name: []const u8,
        input: global_sg.GlobalNodeId,
        reach: reach_context.Context,
    ) !?ImplicitFunctionCall {
        if (self.profile_io != null) self.implicit_lookup_stats.ordinary_calls += 1;
        var stage_start = self.profileTimestamp();
        const ordinary = try self.core.matchUnqualifiedFunctionByNameWithReach(module_index, name, input, reach);
        self.profileAccumulate(stage_start, &self.implicit_lookup_stats.ordinary_matching_ns);
        switch (ordinary) {
            .function => |function| {
                if (self.profile_io != null) self.implicit_lookup_stats.ordinary_resolved += 1;
                if (self.profile_io != null) self.implicit_lookup_stats.ordinary_completion_calls += 1;
                stage_start = self.profileTimestamp();
                if (!try self.core.completeCallInputFieldsWithReach(
                    self.core.graph.functions.items[@intFromEnum(function)].input,
                    input,
                    reach,
                )) {
                    self.profileAccumulate(stage_start, &self.implicit_lookup_stats.ordinary_completion_ns);
                    if (self.profile_io != null) self.implicit_lookup_stats.ordinary_completion_deferred += 1;
                    return error.DeferredImplicitFunction;
                }
                self.profileAccumulate(stage_start, &self.implicit_lookup_stats.ordinary_completion_ns);
                return .{ .function = function, .input = input };
            },
            .ambiguous => {
                if (self.profile_io != null) self.implicit_lookup_stats.ordinary_ambiguous += 1;
                return error.AmbiguousImplicitFunction;
            },
            .deferred => if (self.profile_io != null) {
                self.implicit_lookup_stats.ordinary_deferred += 1;
            },
            .no_match => if (self.profile_io != null) {
                self.implicit_lookup_stats.ordinary_no_match += 1;
            },
        }

        const ordinary_deferred = ordinary == .deferred;
        const compatibility = call_compatibility.Abstract{ .core = self.core, .abstracts = self.abstracts };
        if (self.profile_io != null) self.implicit_lookup_stats.abstract_compatible_calls += 1;
        stage_start = self.profileTimestamp();
        const abstract_ordinary = try call_compatibility.matchUnqualifiedFunctionByNameWithReach(
            compatibility,
            module_index,
            name,
            input,
            reach,
        );
        self.profileAccumulate(stage_start, &self.implicit_lookup_stats.abstract_compatible_matching_ns);
        switch (abstract_ordinary) {
            .function => |function| {
                if (self.profile_io != null) self.implicit_lookup_stats.abstract_compatible_resolved += 1;
                if (self.profile_io != null) self.implicit_lookup_stats.abstract_compatible_completion_calls += 1;
                stage_start = self.profileTimestamp();
                if (!try self.core.completeCallInputFieldsWithReachCompatibility(
                    self.core.graph.functions.items[@intFromEnum(function)].input,
                    input,
                    reach,
                    compatibility.additionalTypeCompatibility(),
                )) {
                    self.profileAccumulate(stage_start, &self.implicit_lookup_stats.abstract_compatible_completion_ns);
                    if (self.profile_io != null) self.implicit_lookup_stats.abstract_compatible_completion_deferred += 1;
                    return error.DeferredImplicitFunction;
                }
                self.profileAccumulate(stage_start, &self.implicit_lookup_stats.abstract_compatible_completion_ns);
                return .{ .function = function, .input = input };
            },
            .deferred => {
                if (self.profile_io != null) self.implicit_lookup_stats.abstract_compatible_deferred += 1;
                return error.DeferredImplicitFunction;
            },
            .ambiguous => {
                if (self.profile_io != null) self.implicit_lookup_stats.abstract_compatible_ambiguous += 1;
                return error.AmbiguousImplicitFunction;
            },
            .no_match => {
                if (self.profile_io != null) self.implicit_lookup_stats.abstract_compatible_no_match += 1;
                if (ordinary_deferred) return error.DeferredImplicitFunction;
            },
        }

        if (self.profile_io != null) self.implicit_lookup_stats.generic_calls += 1;
        const generic_start = self.profileTimestamp();
        const generic_result = self.generic_functions.resolveImplicitGenericFunctionByName(
            module_index,
            name,
            input,
            reach,
        );
        self.profileAccumulate(generic_start, &self.implicit_lookup_stats.generic_matching_ns);
        if (self.profile_io) |io| self.profile_generic_ns += std.Io.Timestamp.now(io, .boot).nanoseconds - generic_start;
        const function = generic_result catch |err| switch (err) {
            error.NoMatchingGenericFunction, error.ConflictingGenericArgument => {
                if (self.profile_io != null) self.implicit_lookup_stats.generic_no_match += 1;
                return null;
            },
            error.DeferredGenericFunction => {
                if (self.profile_io != null) self.implicit_lookup_stats.generic_deferred += 1;
                return error.DeferredImplicitFunction;
            },
            error.AmbiguousGenericFunction => {
                if (self.profile_io != null) self.implicit_lookup_stats.generic_ambiguous += 1;
                return error.AmbiguousImplicitFunction;
            },
            else => return err,
        };
        if (self.profile_io != null) self.implicit_lookup_stats.generic_resolved += 1;
        if (self.profile_io != null) self.implicit_lookup_stats.generic_completion_calls += 1;
        stage_start = self.profileTimestamp();
        if (!try self.core.completeCallInputFieldsWithReach(
            self.core.graph.functions.items[@intFromEnum(function)].input,
            input,
            reach,
        )) {
            self.profileAccumulate(stage_start, &self.implicit_lookup_stats.generic_completion_ns);
            if (self.profile_io != null) self.implicit_lookup_stats.generic_completion_deferred += 1;
            return error.DeferredImplicitFunction;
        }
        self.profileAccumulate(stage_start, &self.implicit_lookup_stats.generic_completion_ns);
        return .{ .function = function, .input = input };
    }

    pub fn resolveIndex(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        const core_result = try self.core.tryResolve(module_index, module, o, operation);
        if (!core_result.allowsFallback()) return core_result;

        const generic_result = try self.generic_functions.tryResolve(module_index, module, o, operation);
        return if (generic_result.allowsFallback()) .deferred else generic_result;
    }
};

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

    pub fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        const error_result = try self.errors.tryResolveCall(module_index, module, o, operation);
        if (!error_result.allowsFallback()) return error_result;
        const core_result = try self.core.tryResolve(module_index, module, o, operation);
        if (!core_result.allowsFallback()) return core_result;

        const abstract_ordinary_result = try call_compatibility.tryResolveOrdinaryCall(
            .{ .core = self.core, .abstracts = self.abstracts },
            module_index,
            module,
            o,
            operation,
        );
        if (!abstract_ordinary_result.allowsFallback()) return abstract_ordinary_result;

        const generic_result = try self.generic_functions.tryResolve(module_index, module, o, operation);
        if (!generic_result.allowsFallback()) return generic_result;

        const constructor_result = try self.constructors.tryResolve(module_index, module, o, operation);
        if (!constructor_result.allowsFallback()) return constructor_result;

        const abstract_result = try self.abstracts.tryResolve(module_index, module, o, operation);
        if (!abstract_result.allowsFallback()) return abstract_result;

        const control_result = try self.control.tryResolve(module_index, module, o, operation);
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
        const ordinary = try self.core.matchUnqualifiedFunctionByNameWithReach(module_index, name, input, reach);
        switch (ordinary) {
            .function => |function| {
                if (!try self.core.completeCallInputFieldsWithReach(
                    self.core.graph.functions.items[@intFromEnum(function)].input,
                    input,
                    reach,
                )) return error.DeferredImplicitFunction;
                return .{ .function = function, .input = input };
            },
            .deferred => return error.DeferredImplicitFunction,
            .ambiguous => return error.AmbiguousImplicitFunction,
            .no_match => {},
        }

        const compatibility = call_compatibility.Abstract{ .core = self.core, .abstracts = self.abstracts };
        const abstract_ordinary = try call_compatibility.matchUnqualifiedFunctionByName(
            compatibility,
            module_index,
            name,
            input,
        );
        switch (abstract_ordinary) {
            .function => |function| {
                if (!try self.core.completeCallInputFieldsWithReach(
                    self.core.graph.functions.items[@intFromEnum(function)].input,
                    input,
                    reach,
                )) return error.DeferredImplicitFunction;
                return .{ .function = function, .input = input };
            },
            .deferred => return error.DeferredImplicitFunction,
            .ambiguous => return error.AmbiguousImplicitFunction,
            .no_match => {},
        }

        const function = self.generic_functions.resolveImplicitGenericFunctionByName(
            module_index,
            name,
            input,
            reach,
        ) catch |err| switch (err) {
            error.NoMatchingGenericFunction, error.ConflictingGenericArgument => return null,
            error.DeferredGenericFunction => return error.DeferredImplicitFunction,
            error.AmbiguousGenericFunction => return error.AmbiguousImplicitFunction,
            else => return err,
        };
        if (!try self.core.completeCallInputFieldsWithReach(
            self.core.graph.functions.items[@intFromEnum(function)].input,
            input,
            reach,
        )) return error.DeferredImplicitFunction;
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

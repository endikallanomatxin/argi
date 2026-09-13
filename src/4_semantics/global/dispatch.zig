const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const constructor_mod = @import("constructors.zig");
const control_mod = @import("control.zig");
const generic_functions_mod = @import("generic_functions.zig");
const abstract_mod = @import("abstracts.zig");

/// Owns operations whose language-level resolution is deliberately composed
/// from several specialized strategies. Strategy fallback stays private to
/// this coordinator; callers only observe `deferred` or `resolved`.
pub const Resolver = struct {
    core: *core_mod.Resolver,
    generic_functions: *generic_functions_mod.Resolver,
    constructors: *constructor_mod.Resolver,
    abstracts: *abstract_mod.Resolver,
    control: *control_mod.Resolver,

    pub fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        const core_result = try self.core.tryResolve(module_index, module, o, operation);
        if (!core_result.allowsFallback()) return core_result;

        const generic_result = try self.generic_functions.tryResolve(module_index, module, o, operation);
        if (!generic_result.allowsFallback()) return generic_result;

        const constructor_result = try self.constructors.tryResolve(module_index, module, o, operation);
        if (!constructor_result.allowsFallback()) return constructor_result;

        const abstract_result = try self.abstracts.tryResolve(module_index, module, o, operation);
        if (!abstract_result.allowsFallback()) return abstract_result;

        const control_result = try self.control.tryResolve(module_index, module, o, operation);
        return if (control_result.allowsFallback()) .deferred else control_result;
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

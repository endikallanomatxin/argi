const std = @import("std");
const primitives = @import("../primitives/schema.zig");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const call_context = @import("call_context.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const constructor_mod = @import("constructors.zig");
const control_mod = @import("control.zig");
const generic_functions_mod = @import("generic_functions.zig");
const contract_mod = @import("contracts.zig");
const error_mod = @import("errors.zig");

pub const PendingCallStage = enum {
    errors,
    ordinary,
    generic,
    constructor,
    contract,
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
    contracts: *contract_mod.Resolver,
    control: *control_mod.Resolver,
    errors: *error_mod.Resolver,
    profile_io: ?std.Io = null,
    pending_call_stages: [@typeInfo(PendingCallStage).@"enum".fields.len]PendingCallStageStats = @splat(.{}),

    fn profileTimestamp(self: *const Resolver) i96 {
        if (self.profile_io) |io| return std.Io.Timestamp.now(io, .boot).nanoseconds;
        return 0;
    }

    fn profilePendingStage(self: *Resolver, stage: PendingCallStage, start: i96, result: resolution.Result) void {
        if (self.profile_io == null) return;
        const stats = &self.pending_call_stages[@intFromEnum(stage)];
        stats.attempts += 1;
        stats.resolved += @intFromBool(result == .resolved);
        stats.deferred += @intFromBool(result == .deferred);
        stats.ns += @intCast(self.profileTimestamp() - start);
    }

    pub fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        if (operation == .resolve_call and operation.resolve_call.contract_type != null)
            return self.contracts.resolveScopedOperation(module_index, module, o, operation.resolve_call);
        // Retained interactive bindings have the same static callable identity
        // as lexical bindings lowered directly into the current module.
        if (operation == .resolve_call and operation.resolve_call.callee_value == null) {
            const call = operation.resolve_call;
            const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
            if (reference.module_path == null) if (self.generic_functions.capture_lookup) |lookup| {
                const owner = if (call.owner_function) |function| globalizer.globalFunction(o, function) else null;
                if (lookup(self.generic_functions.capture_lookup_context.?, module_index, owner, module.text(reference.name))) |binding| {
                    if (@import("types.zig").staticDefinitionBinding(self.core.graph, binding)) |definition| {
                        if (self.core.graph.familyDefinition(definition.origin).kind == .function)
                            return self.generic_functions.resolveDefinitionCall(module_index, module, o, call, definition);
                    }
                }
            };
        }
        // A lexical callable value shadows named functions and constructors.
        if (operation == .resolve_call and operation.resolve_call.callee_value != null) {
            const call = operation.resolve_call;
            const callee = globalizer.globalNode(o, call.callee_value.?);
            const ty = self.core.graph.node(callee).ty orelse return .deferred;
            if (self.core.graph.isTypeUnresolved(ty)) return .deferred;
            if (@import("types.zig").definitionValue(self.core.graph, callee)) |definition| {
                if (self.core.graph.familyDefinition(definition.origin).kind == .function)
                    return self.generic_functions.resolveDefinitionCall(module_index, module, o, call, definition);
            }
            return self.core.tryResolve(module_index, module, o, operation);
        }
        if (operation == .resolve_call) {
            const call = operation.resolve_call;
            const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
            {
                const context = call_context.Context.fromModule(o, call.owner_function);
                const operation_module = if (reference.module_path) |path| try self.core.findModuleForQualifier(module_index, module.text(path)) else null;
                const arguments = try self.generic_functions.generics.resolveCallArguments(module_index, reference) orelse primitives.Range(global_sg.GlobalGenericArgId){ .start = 0, .len = 0 };
                const selected = self.generic_functions.resolveSpecializedOperationIdentityFiltered(module_index, module.text(reference.name), globalizer.globalNode(o, call.input), context, .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset }, operation_module, arguments, reference) catch |err| switch (err) {
                    error.AmbiguousOperationIdentity => return .invalid,
                    error.DeferredOperationIdentity => return .deferred,
                    else => return err,
                };
                if (selected) |node| {
                    try self.core.graph.setNode(self.core.allocator, globalizer.globalNode(o, call.node), node);
                    return .resolved;
                }
            }
        }
        var stage_start = self.profileTimestamp();
        const error_result = try self.errors.tryResolveCall(module_index, module, o, operation);
        self.profilePendingStage(.errors, stage_start, error_result);
        if (!error_result.allowsFallback()) return error_result;
        stage_start = self.profileTimestamp();
        const core_result = try self.core.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.ordinary, stage_start, core_result);
        if (core_result == .resolved or core_result == .invalid) return core_result;

        if (core_result == .deferred) return .deferred;

        stage_start = self.profileTimestamp();
        const generic_result = try self.generic_functions.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.generic, stage_start, generic_result);
        if (!generic_result.allowsFallback()) return generic_result;

        stage_start = self.profileTimestamp();
        const constructor_result = try self.constructors.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.constructor, stage_start, constructor_result);
        if (!constructor_result.allowsFallback()) return constructor_result;

        stage_start = self.profileTimestamp();
        const contract_result = try self.contracts.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.contract, stage_start, contract_result);
        if (!contract_result.allowsFallback()) return contract_result;

        stage_start = self.profileTimestamp();
        const control_result = try self.control.tryResolve(module_index, module, o, operation);
        self.profilePendingStage(.control, stage_start, control_result);
        return if (control_result.allowsFallback()) .deferred else control_result;
    }
};

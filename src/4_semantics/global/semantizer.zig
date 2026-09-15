const std = @import("std");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
const tok = @import("../../2_tokens/token.zig");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const module_views = @import("../module/views.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const module_linker = @import("module_linker.zig");
const global_verify = @import("verify.zig");
const core_mod = @import("core.zig");
const expression_mod = @import("expressions.zig");
const constructor_mod = @import("constructors.zig");
const control_mod = @import("control.zig");
const generic_mod = @import("generics.zig");
const generic_functions_mod = @import("generic_functions.zig");
const abstract_mod = @import("abstracts.zig");
const error_mod = @import("errors.zig");
const ownership_mod = @import("ownership.zig");
const resolution = @import("resolution.zig");
const dispatch_mod = @import("dispatch.zig");
const reachability_mod = @import("reachability.zig");

pub const Options = struct {
    selected_test_name: ?[]const u8 = null,
    exhaustive_function_bodies: bool = true,
    diagnostics: ?*diagnostics_mod.Diagnostics = null,
};

pub const Stats = struct {
    core: core_mod.Stats = .{},
    expressions: expression_mod.Stats = .{},
    control: control_mod.Stats = .{},
    generics: generic_mod.Stats = .{},
    generic_functions: generic_functions_mod.Stats = .{},
    abstracts: abstract_mod.Stats = .{},
    errors: error_mod.Stats = .{},
    ownership: ownership_mod.Stats = .{},
    pending_total: u32 = 0,
    pending_resolved: u32 = 0,
    pending_attempts: u64 = 0,
    remaining: u32 = 0,
};

pub const Result = struct {
    graph: global_sg.GlobalSemanticGraph,
    stats: Stats,
};

/// Top-level semantic ownership is stable for the lifetime of a pending
/// operation. Composite owners such as calls and indexing may try multiple
/// implementation strategies internally, but those strategies never compete
/// for ownership at the GlobalSema boundary.
const PendingOwner = enum {
    types,
    calls,
    indexing,
    core,
    expressions,
    control,
    abstracts,
    errors,
    ownership,
};

const PendingTag = @typeInfo(module_entities.PendingOperation).@"union".tag_type.?;

const PendingPhase = enum {
    types_and_generics,
    expressions_and_calls,
    control_and_abstracts,
    errors,
    ownership,
};

const pending_phases = [_]PendingPhase{
    .types_and_generics,
    .expressions_and_calls,
    .control_and_abstracts,
    .errors,
    .ownership,
};

const PendingWorkItem = struct {
    module_index: u32,
    operation_index: u32,
    flat_index: u32,
    owner_function: ?global_sg.GlobalFunctionId = null,
};

/// Pending operations are routed once, then only unresolved work is retained.
/// This preserves source order inside each phase while avoiding repeated scans
/// of unrelated phases and already-resolved operations on every fixed-point
/// iteration.
const PendingWorklists = struct {
    types_and_generics: std.ArrayList(PendingWorkItem) = .empty,
    expressions_and_calls: std.ArrayList(PendingWorkItem) = .empty,
    control_and_abstracts: std.ArrayList(PendingWorkItem) = .empty,
    errors: std.ArrayList(PendingWorkItem) = .empty,
    ownership: std.ArrayList(PendingWorkItem) = .empty,

    fn init(allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, offsets: []const globalizer.Offsets) !PendingWorklists {
        var result: PendingWorklists = .{};
        errdefer result.deinit(allocator);
        var flat: u32 = 0;
        for (modules, 0..) |*module, module_index| {
            for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
                try result.forPhase(pendingPhase(operation)).append(allocator, .{
                    .module_index = @intCast(module_index),
                    .operation_index = @intCast(operation_index),
                    .flat_index = flat,
                    .owner_function = if (operation_index < module.semantic.pending_owner_functions.items.len)
                        if (module.semantic.pending_owner_functions.items[operation_index]) |owner|
                            globalizer.globalFunction(offsets[module_index], owner)
                        else
                            null
                    else
                        null,
                });
                flat = std.math.add(u32, flat, 1) catch return error.TooManyPendingOperations;
            }
        }
        return result;
    }

    fn deinit(self: *PendingWorklists, allocator: std.mem.Allocator) void {
        self.types_and_generics.deinit(allocator);
        self.expressions_and_calls.deinit(allocator);
        self.control_and_abstracts.deinit(allocator);
        self.errors.deinit(allocator);
        self.ownership.deinit(allocator);
    }

    fn forPhase(self: *PendingWorklists, phase: PendingPhase) *std.ArrayList(PendingWorkItem) {
        return switch (phase) {
            .types_and_generics => &self.types_and_generics,
            .expressions_and_calls => &self.expressions_and_calls,
            .control_and_abstracts => &self.control_and_abstracts,
            .errors => &self.errors,
            .ownership => &self.ownership,
        };
    }

    fn remaining(self: *const PendingWorklists, reachable: ?*const reachability_mod.FunctionSet) usize {
        var count: usize = 0;
        for (pending_phases) |phase| for (self.forPhaseConst(phase).items) |item| {
            if (isActive(item, reachable)) count += 1;
        };
        return count;
    }

    fn forPhaseConst(self: *const PendingWorklists, phase: PendingPhase) *const std.ArrayList(PendingWorkItem) {
        return switch (phase) {
            .types_and_generics => &self.types_and_generics,
            .expressions_and_calls => &self.expressions_and_calls,
            .control_and_abstracts => &self.control_and_abstracts,
            .errors => &self.errors,
            .ownership => &self.ownership,
        };
    }
};

pub fn semantize(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
) !Result {
    return semantizeWithOptions(allocator, modules, .{});
}

pub fn semantizeWithOptions(
    allocator: std.mem.Allocator,
    modules: []const module_sg.ModuleSemanticGraph,
    options: Options,
) !Result {
    var relocation = try globalizer.relocate(allocator, modules, .allow_holes);
    errdefer relocation.deinit(allocator);
    try module_linker.link(allocator, &relocation.graph, modules, relocation.offsets.items);

    // The globalizer preallocates stable GlobalTypeId slots. Record which of
    // those slots are genuinely unresolved before any resolver can inspect
    // them; unresolved is construction state, not the language type `Any`.
    try markUnresolvedTypeSlots(allocator, &relocation.graph, modules, relocation.offsets.items);

    var core = core_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
    };
    var expressions = expression_mod.Resolver{
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
    };
    var constructors = constructor_mod.Resolver{
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var control = control_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var generics = generic_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var generic_functions = generic_functions_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .generics = &generics,
    };
    var abstracts = abstract_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .generics = &generics,
    };
    defer abstracts.deinit();
    generic_functions.nested_call_context = &abstracts;
    generic_functions.nested_call_resolver = abstract_mod.Resolver.resolveNestedCall;
    var errors = error_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    var ownership = ownership_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    defer ownership.deinit();
    var dispatch = dispatch_mod.Resolver{
        .core = &core,
        .generic_functions = &generic_functions,
        .constructors = &constructors,
        .abstracts = &abstracts,
        .control = &control,
        .errors = &errors,
    };

    try core.resolveExternalTypes();
    try generics.resolveExternalTypes();
    _ = relocation.graph.reconcileTypeResolution();
    _ = try generics.materializeKnownTypes();
    try control.materializeSugarTypes();

    const total = totalPending(modules);
    const resolved = try allocator.alloc(bool, total);
    defer allocator.free(resolved);
    @memset(resolved, false);
    var worklists = try PendingWorklists.init(allocator, modules, relocation.offsets.items);
    defer worklists.deinit(allocator);
    var reachable_storage: reachability_mod.FunctionSet = undefined;
    var reachable: ?*reachability_mod.FunctionSet = null;
    if (!options.exhaustive_function_bodies) {
        reachable_storage = try reachability_mod.roots(allocator, &relocation.graph, options.selected_test_name);
        reachable = &reachable_storage;
    }
    defer if (reachable) |set| set.deinit();
    var pending_attempts: u64 = 0;

    // GlobalSema is staged by semantic domain. Ownership finalization can add
    // cleanup calls to functions absent from the source call graph. Each newly
    // reachable body gets another resolution pass before its cleanup is built.
    var finalized_functions = std.AutoHashMap(global_sg.GlobalFunctionId, void).init(allocator);
    defer finalized_functions.deinit();
    var changed = true;
    while (true) {
        while (changed) {
            changed = false;
            for (pending_phases) |phase| {
                if (try resolvePendingPhase(
                    &core,
                    &expressions,
                    &dispatch,
                    &control,
                    &generics,
                    &abstracts,
                    &errors,
                    &ownership,
                    modules,
                    relocation.offsets.items,
                    resolved,
                    worklists.forPhase(phase),
                    reachable,
                    &pending_attempts,
                )) changed = true;
            }

            if (relocation.graph.reconcileTypeResolution()) changed = true;
            if (relocation.graph.reconcileBindingTypeResolution()) changed = true;
            if (core.materializeStringLiteralTypes()) changed = true;
            if (core.materializeBindingTypes()) changed = true;
            if (relocation.graph.reconcileBindingTypeResolution()) {
                changed = true;
                if (core.materializeBindingTypes()) changed = true;
            }
            if (core.materializeAssignmentValues()) changed = true;
            if (core.materializeDereferences()) changed = true;
            if (try core.materializeAddresses()) changed = true;
            if (try generics.materializeKnownTypes()) changed = true;
            if (try abstracts.materializeAbstractFieldStorage()) changed = true;
            try control.materializeSugarTypes();
            if (try errors.inferFunctionErrorReasons()) changed = true;
            if (reachable) |set| {
                if (try reachability_mod.expand(allocator, &relocation.graph, set)) changed = true;
            }
        }
        var finalized_any = false;
        for (relocation.graph.functions.items, 0..) |function, raw| {
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (reachable) |set| {
                if (!set.contains(id)) continue;
            }
            if (function.body) |body| {
                if ((try finalized_functions.getOrPut(id)).found_existing) continue;
                try ownership.finalizeFunctionBody(body);
                finalized_any = true;
            }
        }
        const reached_cleanup = if (reachable) |set|
            try reachability_mod.expand(allocator, &relocation.graph, set)
        else
            false;
        if (!finalized_any and !reached_cleanup) break;
        changed = true;
    }

    try abstracts.validateGenericFunctionInstances();
    control.annotateChoiceTests();

    if (reachable) |set| try retireDormantBindingResolution(&relocation.graph, set, try core.builtin(.Any));

    const remaining = worklists.remaining(reachable);
    var resolved_count: usize = 0;
    for (resolved) |done| if (done) {
        resolved_count += 1;
    };
    if (remaining != 0) {
        if (options.diagnostics) |diagnostics|
            if (try diagnoseUnresolvedCall(allocator, &relocation.graph, modules, resolved, reachable, relocation.offsets.items, diagnostics))
                return error.Reported;
        dumpUnresolved(modules, resolved, reachable, relocation.offsets.items);
        return error.UnsupportedGlobalSemantic;
    }
    _ = relocation.graph.reconcileTypeResolution();
    _ = relocation.graph.reconcileBindingTypeResolution();
    if (relocation.graph.hasUnresolvedTypes()) {
        std.debug.print("global sema unresolved global type slots remain\n", .{});
        return error.UnsupportedGlobalSemantic;
    }
    if (relocation.graph.hasUnresolvedBindingTypes()) {
        std.debug.print("global sema unresolved binding types remain\n", .{});
        return error.UnsupportedGlobalSemantic;
    }

    try abstracts.closeVirtualMethodRegistries();

    // Construction-only resolution metadata must disappear before the graph is
    // exposed to Safety, Codegen or editor consumers.
    try relocation.graph.finishTypeResolution(allocator);
    try relocation.graph.finishBindingTypeResolution(allocator);

    if (reachable) |set| {
        for (relocation.graph.functions.items, 0..) |*function, raw| {
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (!set.contains(id)) function.body = null;
        }
    }

    var stats = Stats{
        .core = core.stats,
        .expressions = expressions.stats,
        .control = control.stats,
        .generics = generics.stats,
        .generic_functions = generic_functions.stats,
        .abstracts = abstracts.stats,
        .errors = errors.stats,
        .ownership = ownership.stats,
        .pending_total = @intCast(total),
        .pending_resolved = @intCast(resolved_count),
        .pending_attempts = pending_attempts,
        .remaining = 0,
    };

    try global_verify.verifyGlobal(&relocation.graph);
    stats.remaining = 0;
    return .{ .graph = relocation.takeGraph(allocator), .stats = stats };
}

fn resolvePendingPhase(
    core: *core_mod.Resolver,
    expressions: *expression_mod.Resolver,
    dispatch: *dispatch_mod.Resolver,
    control: *control_mod.Resolver,
    generics: *generic_mod.Resolver,
    abstracts: *abstract_mod.Resolver,
    errors: *error_mod.Resolver,
    ownership: *ownership_mod.Resolver,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    resolved: []bool,
    work: *std.ArrayList(PendingWorkItem),
    reachable: ?*const reachability_mod.FunctionSet,
    pending_attempts: *u64,
) !bool {
    var changed = false;
    var write: usize = 0;
    const original_len = work.items.len;
    for (work.items[0..original_len]) |item| {
        if (!isActive(item, reachable)) {
            work.items[write] = item;
            write += 1;
            continue;
        }
        pending_attempts.* += 1;
        const module_index: usize = @intCast(item.module_index);
        const operation_index: usize = @intCast(item.operation_index);
        const flat_index: usize = @intCast(item.flat_index);
        const module = &modules[module_index];
        const operation = module.semantic.pending_operations.items[operation_index];
        const result = try resolvePendingOperation(
            core,
            expressions,
            dispatch,
            control,
            generics,
            abstracts,
            errors,
            ownership,
            module_index,
            module,
            offsets[module_index],
            operation,
        );
        if (result.isResolved()) {
            resolved[flat_index] = true;
            changed = true;
        } else {
            work.items[write] = item;
            write += 1;
        }
    }
    work.shrinkRetainingCapacity(write);
    return changed;
}

fn isActive(item: PendingWorkItem, reachable: ?*const reachability_mod.FunctionSet) bool {
    const set = reachable orelse return true;
    const owner = item.owner_function orelse return true;
    return set.contains(owner);
}

/// ModuleSG owns relocatable storage for every lowered body. Selective
/// semantizing publishes only the reachable bodies, so provisional binding
/// types in the remaining dormant storage must not keep GlobalSG in its
/// construction state. Any is used solely as a valid inert payload for those
/// unreachable records; no published body can observe it.
fn retireDormantBindingResolution(
    graph: *global_sg.GlobalSemanticGraph,
    reachable: *const reachability_mod.FunctionSet,
    dormant_type: global_sg.GlobalTypeId,
) !void {
    const limit = @min(graph.binding_type_resolution.items.len, graph.bindings.items.len);
    for (graph.binding_type_resolution.items[0..limit], 0..) |*state, raw| {
        if (state.* != .unresolved) continue;
        const binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        if (reachable.containsBinding(binding)) continue;
        graph.bindings.items[raw].ty = dormant_type;
        state.* = .resolved;
    }
}

fn pendingOwnerTag(tag: PendingTag) PendingOwner {
    return switch (tag) {
        .resolve_type => .types,
        .resolve_call => .calls,
        .resolve_index => .indexing,
        .resolve_field,
        .resolve_binary,
        .resolve_comparison,
        .resolve_dereference,
        .resolve_address,
        => .core,
        .resolve_name_use,
        .resolve_name_assignment,
        .resolve_import,
        => .expressions,
        .resolve_choice_literal,
        .resolve_choice_payload,
        .resolve_nullable_unwrap,
        .resolve_nullable_test,
        .resolve_for_each,
        .resolve_match,
        .resolve_match_case,
        => .control,
        .resolve_abstract => .abstracts,
        .resolve_error_propagation => .errors,
        .resolve_defer,
        .resolve_keep,
        .resolve_keep_name,
        .resolve_copy,
        .resolve_deinit,
        => .ownership,
    };
}

fn pendingOwner(operation: module_entities.PendingOperation) PendingOwner {
    return pendingOwnerTag(std.meta.activeTag(operation));
}

fn pendingPhase(operation: module_entities.PendingOperation) PendingPhase {
    return switch (pendingOwner(operation)) {
        .types => .types_and_generics,
        .calls,
        .indexing,
        .core,
        .expressions,
        => .expressions_and_calls,
        .control,
        .abstracts,
        => .control_and_abstracts,
        .errors => .errors,
        .ownership => .ownership,
    };
}

/// A single-owner resolver rejecting its assigned operation is an internal
/// routing bug. Composite owners consume `not_applicable` themselves while
/// selecting an implementation strategy and expose only deferred/resolved.
fn ownedResult(result: resolution.Result) resolution.Result {
    std.debug.assert(result != .not_applicable);
    return result;
}

fn resolveTypeOperation(
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    module_index: usize,
    module: *const module_sg.ModuleSemanticGraph,
    o: globalizer.Offsets,
    operation: module_entities.PendingOperation,
) !resolution.Result {
    const value = switch (operation) {
        .resolve_type => |value| value,
        else => unreachable,
    };
    const reference = module.semantic.external_refs.items[@intFromEnum(value.external)];
    const result = if (reference.generic_arguments != null)
        try generics.tryResolve(module_index, module, o, operation)
    else
        try core.tryResolve(module_index, module, o, operation);
    return ownedResult(result);
}

fn resolvePendingOperation(
    core: *core_mod.Resolver,
    expressions: *expression_mod.Resolver,
    dispatch: *dispatch_mod.Resolver,
    control: *control_mod.Resolver,
    generics: *generic_mod.Resolver,
    abstracts: *abstract_mod.Resolver,
    errors: *error_mod.Resolver,
    ownership: *ownership_mod.Resolver,
    module_index: usize,
    module: *const module_sg.ModuleSemanticGraph,
    o: globalizer.Offsets,
    operation: module_entities.PendingOperation,
) !resolution.Result {
    return switch (pendingOwner(operation)) {
        .types => resolveTypeOperation(core, generics, module_index, module, o, operation),
        .calls => dispatch.resolveCall(module_index, module, o, operation),
        .indexing => dispatch.resolveIndex(module_index, module, o, operation),
        .core => ownedResult(try core.tryResolve(module_index, module, o, operation)),
        .expressions => ownedResult(try expressions.tryResolve(module_index, module, o, operation)),
        .control => ownedResult(try control.tryResolve(module_index, module, o, operation)),
        .abstracts => ownedResult(try abstracts.tryResolve(module_index, module, o, operation)),
        .errors => ownedResult(try errors.tryResolve(module_index, module, o, operation)),
        .ownership => ownedResult(try ownership.tryResolve(module_index, module, o, operation)),
    };
}

fn markUnresolvedTypeSlots(
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
) !void {
    for (modules, 0..) |*module, module_index| {
        for (0..module_views.typeCount(module)) |raw| {
            const local: module_entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            switch (try module_views.typeView(module, local)) {
                .resolved => {},
                .external => try graph.markTypeUnresolved(allocator, globalizer.globalType(offsets[module_index], local)),
            }
        }
    }
}

fn diagnoseUnresolvedCall(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
    diagnostics: *diagnostics_mod.Diagnostics,
) !bool {
    var flat: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            defer flat += 1;
            const call = switch (operation) {
                .resolve_call => |value| value,
                else => continue,
            };
            const owner = if (operation_index < module.semantic.pending_owner_functions.items.len)
                if (module.semantic.pending_owner_functions.items[operation_index]) |value| globalizer.globalFunction(offsets[module_index], value) else null
            else
                null;
            if (resolved[flat] or (reachable != null and owner != null and !reachable.?.contains(owner.?))) continue;
            const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
            const name = module.text(reference.name);
            const input_id = globalizer.globalNode(offsets[module_index], call.input);
            const input = switch (graph.node(input_id).content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
            var input_complete = true;
            for (graph.value_fields.items[input.fields.start..][0..input.fields.len]) |field| {
                const ty = graph.node(field.value).ty orelse {
                    input_complete = false;
                    break;
                };
                if (graph.isTypeUnresolved(ty)) {
                    input_complete = false;
                    break;
                }
            }
            if (!input_complete) continue;
            var candidates: std.ArrayList(global_sg.GlobalFunctionId) = .empty;
            defer candidates.deinit(allocator);
            for (graph.functions.items, 0..) |function, raw| {
                const declaration = graph.declaration(function.declaration);
                if (std.mem.eql(u8, graph.text(declaration.name), name))
                    try candidates.append(allocator, @enumFromInt(@as(u32, @intCast(raw))));
            }
            if (candidates.items.len == 0) continue;

            var message = std.array_list.Managed(u8).init(allocator);
            defer message.deinit();
            try message.appendSlice("no overload of '");
            try message.appendSlice(name);
            try message.appendSlice("' accepts arguments ");
            try appendValueShape(&message, graph, input);
            try message.appendSlice(". Available signatures:");
            for (candidates.items) |candidate| {
                const function = graph.functions.items[@intFromEnum(candidate)];
                try message.appendSlice("\n  - ");
                try message.appendSlice(name);
                try message.append(' ');
                try appendFieldShape(&message, graph, function.input);
                try message.appendSlice(" -> ");
                try appendFieldShape(&message, graph, function.output);
            }
            const location = diagnosticLocation(graph, diagnostics, .{
                .file_index = offsets[module_index].file_base + reference.source.file_index,
                .offset = reference.source.offset + @as(u32, @intCast(name.len)),
            });
            try diagnostics.add(location, .semantic, "{s}", .{message.items});
            return true;
        }
    }
    return false;
}

fn appendValueShape(buffer: *std.array_list.Managed(u8), graph: *const global_sg.GlobalSemanticGraph, literal: anytype) !void {
    try buffer.append('(');
    for (graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, index| {
        if (index != 0) try buffer.appendSlice(", ");
        try buffer.append('.');
        try buffer.appendSlice(graph.text(field.name));
        try buffer.appendSlice(": ");
        const ty = graph.node(field.value).ty orelse {
            try buffer.appendSlice("?");
            continue;
        };
        try appendTypeName(buffer, graph, ty);
    }
    try buffer.append(')');
}

fn appendFieldShape(buffer: *std.array_list.Managed(u8), graph: *const global_sg.GlobalSemanticGraph, range: global_sg.FieldRange) !void {
    try buffer.append('(');
    for (graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
        if (index != 0) try buffer.appendSlice(", ");
        try buffer.append('.');
        try buffer.appendSlice(graph.text(field.name));
        try buffer.appendSlice(": ");
        try appendTypeName(buffer, graph, field.ty);
    }
    try buffer.append(')');
}

fn appendTypeName(buffer: *std.array_list.Managed(u8), graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) !void {
    switch (graph.semanticType(ty)) {
        .builtin => |builtin| try buffer.appendSlice(@tagName(builtin)),
        .declared => |declaration| try buffer.appendSlice(graph.text(graph.declaration(declaration).name)),
        .pointer => |pointer| {
            try buffer.appendSlice(if (pointer.mutability == .read_write) "$&" else "&");
            try appendTypeName(buffer, graph, pointer.child);
        },
        else => try buffer.appendSlice("<type>"),
    }
}

fn diagnosticLocation(graph: *const global_sg.GlobalSemanticGraph, diagnostics: *const diagnostics_mod.Diagnostics, source: @import("../primitives/schema.zig").SourceRef) tok.Location {
    if (source.file_index < graph.files.items.len) {
        const graph_file = graph.files.items[source.file_index];
        const wanted_name = graph.text(graph_file.path);
        const wanted_dir = graph.text(graph.modules.items[@intFromEnum(graph_file.module)].dir);
        for (diagnostics.source_files, 0..) |file, index| {
            if (std.mem.eql(u8, std.fs.path.basename(file.path), wanted_name) and
                std.mem.eql(u8, std.fs.path.dirname(file.path) orelse ".", wanted_dir))
                return .{ .file = @enumFromInt(@as(u32, @intCast(index))), .offset = source.offset };
        }
    }
    return .{ .file = @enumFromInt(0), .offset = source.offset };
}

fn dumpUnresolved(
    modules: []const module_sg.ModuleSemanticGraph,
    resolved: []const bool,
    reachable: ?*const reachability_mod.FunctionSet,
    offsets: []const globalizer.Offsets,
) void {
    var flat: usize = 0;
    var shown: usize = 0;
    for (modules, 0..) |*module, module_index| {
        for (module.semantic.pending_operations.items, 0..) |operation, operation_index| {
            const item: PendingWorkItem = .{
                .module_index = @intCast(module_index),
                .operation_index = @intCast(operation_index),
                .flat_index = @intCast(flat),
                .owner_function = if (operation_index < module.semantic.pending_owner_functions.items.len)
                    if (module.semantic.pending_owner_functions.items[operation_index]) |owner|
                        globalizer.globalFunction(offsets[module_index], owner)
                    else
                        null
                else
                    null,
            };
            if (!resolved[flat] and isActive(item, reachable) and shown < 8) {
                switch (operation) {
                    .resolve_call => |call| {
                        const reference = module.semantic.external_refs.items[@intFromEnum(call.callee)];
                        std.debug.print(
                            "global sema unresolved: module={d} dir={s} op=resolve_call name={s} generic={any} input={d}\n",
                            .{ module_index, module.module_dir, module.text(reference.name), reference.generic_arguments != null, @intFromEnum(call.input) },
                        );
                    },
                    .resolve_name_use => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_name_use name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.name), @intFromEnum(value.node) },
                    ),
                    .resolve_name_assignment => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_name_assignment name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.name), @intFromEnum(value.node) },
                    ),
                    .resolve_import => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_import path={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.path), @intFromEnum(value.node) },
                    ),
                    .resolve_keep_name => |value| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_keep_name name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(value.name), @intFromEnum(value.node) },
                    ),
                    .resolve_choice_literal => |choice| {
                        const reference = module.semantic.external_refs.items[@intFromEnum(choice.option)];
                        std.debug.print(
                            "global sema unresolved: module={d} dir={s} op=resolve_choice_literal name={s} source={d} payload={any} expected={any}\n",
                            .{ module_index, module.module_dir, module.text(reference.name), reference.source.offset, choice.payload, choice.expected_type },
                        );
                    },
                    .resolve_field => |field| std.debug.print(
                        "global sema unresolved: module={d} dir={s} op=resolve_field name={s} node={d}\n",
                        .{ module_index, module.module_dir, module.text(field.field_name), @intFromEnum(field.node) },
                    ),
                    else => std.debug.print(
                        "global sema unresolved: module={d} dir={s} op={s}\n",
                        .{ module_index, module.module_dir, @tagName(operation) },
                    ),
                }
                shown += 1;
            }
            flat += 1;
        }
    }
    if (shown == 8) std.debug.print("global sema unresolved: additional operations omitted\n", .{});
}

fn totalPending(modules: []const module_sg.ModuleSemanticGraph) usize {
    var total: usize = 0;
    for (modules) |module| total += module.semantic.pending_operations.items.len;
    return total;
}

test "pending operation ownership is explicit" {
    try std.testing.expectEqual(PendingOwner.types, pendingOwnerTag(.resolve_type));
    try std.testing.expectEqual(PendingOwner.calls, pendingOwnerTag(.resolve_call));
    try std.testing.expectEqual(PendingOwner.indexing, pendingOwnerTag(.resolve_index));
    try std.testing.expectEqual(PendingOwner.core, pendingOwnerTag(.resolve_field));
    try std.testing.expectEqual(PendingOwner.expressions, pendingOwnerTag(.resolve_name_use));
    try std.testing.expectEqual(PendingOwner.control, pendingOwnerTag(.resolve_match));
    try std.testing.expectEqual(PendingOwner.abstracts, pendingOwnerTag(.resolve_abstract));
    try std.testing.expectEqual(PendingOwner.errors, pendingOwnerTag(.resolve_error_propagation));
    try std.testing.expectEqual(PendingOwner.ownership, pendingOwnerTag(.resolve_deinit));
}

test "global semantizer accepts an empty program" {
    const allocator = std.testing.allocator;
    var result = try semantize(allocator, &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.graph.nodes.items.len);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
    try std.testing.expectEqual(@as(u64, 0), result.stats.pending_attempts);
    try std.testing.expectEqual(@as(usize, 0), result.graph.type_resolution.items.len);
}

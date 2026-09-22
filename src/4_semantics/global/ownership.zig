const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const name_lookup = @import("name_lookup.zig");
const core_mod = @import("core.zig");
const dispatch_mod = @import("dispatch.zig");
const reach_context = @import("reach_context.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    copies: u32 = 0,
    deinit_checks: u32 = 0,
    auto_deinits: u32 = 0,
    defers: u32 = 0,
    keeps: u32 = 0,
    cleanup_edges: u32 = 0,
};

const Deferred = struct { marker: global_sg.GlobalNodeId, value: global_sg.GlobalNodeId };
const Kept = struct { marker: global_sg.GlobalNodeId, binding: global_sg.GlobalBindingId };
const AutoNode = struct { binding: global_sg.GlobalBindingId, node: ?global_sg.GlobalNodeId };
const ResolvedDestructor = struct {
    function: global_sg.GlobalFunctionId,
    input: global_sg.GlobalNodeId,
    self_field_index: u32,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    dispatch: ?*dispatch_mod.Resolver = null,
    deferred: std.ArrayList(Deferred) = .empty,
    kept: std.ArrayList(Kept) = .empty,
    auto_nodes: std.ArrayList(AutoNode) = .empty,
    empty_block: ?global_sg.GlobalBlockId = null,
    stats: Stats = .{},

    pub fn deinit(self: *Resolver) void {
        self.deferred.deinit(self.allocator);
        self.kept.deinit(self.allocator);
        self.auto_nodes.deinit(self.allocator);
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        return switch (operation) {
            .resolve_defer => |value| resolution.Result.fromBool(try self.resolveDefer(o, value)),
            .resolve_keep => |value| resolution.Result.fromBool(try self.resolveKeep(o, value)),
            .resolve_keep_name => |value| resolution.Result.fromBool(try self.resolveKeepName(module_index, module, o, value)),
            .resolve_copy => |value| resolution.Result.fromBool(try self.resolveCopy(o, value)),
            .resolve_deinit => |value| resolution.Result.fromBool(try self.resolveExplicitDeinit(o, value)),
            else => .not_applicable,
        };
    }

    pub fn finalize(self: *Resolver) !void {
        const count = self.graph.functions.items.len;
        for (0..count) |raw| {
            const function = self.graph.functions.items[raw];
            if (function.body == null) continue;
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            _ = try self.finalizeFunctionBody(id);
        }
    }

    pub fn finalizeFunctionBody(self: *Resolver, function_id: global_sg.GlobalFunctionId) !bool {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const body = function.body orelse return true;
        if (!self.functionReadyForCleanup(function, body)) return false;
        var visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer visible.deinit(self.allocator);
        try visible.appendSlice(
            self.allocator,
            self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len],
        );
        try visible.appendSlice(
            self.allocator,
            self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len],
        );

        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        const module = self.graph.moduleForDeclaration(function.declaration) orelse return error.MissingFunctionModule;
        try self.finalizeBlock(body, &active, &defers, &visible, &.{}, function_id, @intCast(@intFromEnum(module)));
        return true;
    }

    fn functionReadyForCleanup(
        self: *const Resolver,
        function: global_sg.Function,
        body: global_sg.GlobalBlockId,
    ) bool {
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |binding|
            if (self.graph.isBindingTypeUnresolved(binding)) return false;
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding|
            if (self.graph.isBindingTypeUnresolved(binding)) return false;
        return self.blockReadyForCleanup(body);
    }

    fn blockReadyForCleanup(self: *const Resolver, block_id: global_sg.GlobalBlockId) bool {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            switch (node.content) {
                .binding_declaration => |binding| if (self.graph.isBindingTypeUnresolved(binding)) return false,
                .binding_use => |binding| if (self.graph.isBindingTypeUnresolved(binding)) return false,
                .assignment => |assignment| if (self.graph.isBindingTypeUnresolved(assignment.binding)) return false,
                .code_block => |child| if (!self.blockReadyForCleanup(child)) return false,
                .if_statement => |statement| {
                    if (!self.blockReadyForCleanup(statement.then_block)) return false;
                    if (statement.else_block) |child|
                        if (!self.blockReadyForCleanup(child)) return false;
                },
                .while_statement => |statement| if (!self.blockReadyForCleanup(statement.body)) return false,
                .for_statement => |statement| {
                    if (statement.init) |init| {
                        const init_node = self.graph.nodes.items[@intFromEnum(init)];
                        if (init_node.content == .code_block and !self.blockReadyForCleanup(init_node.content.code_block))
                            return false;
                    }
                    if (!self.blockReadyForCleanup(statement.body)) return false;
                },
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case| {
                        if (case.payload_binding) |binding|
                            if (self.graph.isBindingTypeUnresolved(binding)) return false;
                        if (!self.blockReadyForCleanup(case.body)) return false;
                    }
                    if (sw.default_block) |child|
                        if (!self.blockReadyForCleanup(child)) return false;
                },
                else => {},
            }
        }
        return true;
    }

    fn resolveDefer(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const marker = globalizer.globalNode(o, value.node);
        const deferred_value = globalizer.globalNode(o, value.value);
        try self.registerDefer(marker, deferred_value);
        return true;
    }

    pub fn registerParameterizedDefer(context: *anyopaque, marker: global_sg.GlobalNodeId, deferred_value: global_sg.GlobalNodeId) anyerror!void {
        const self: *Resolver = @ptrCast(@alignCast(context));
        try self.registerDefer(marker, deferred_value);
    }

    fn registerDefer(self: *Resolver, marker: global_sg.GlobalNodeId, deferred_value: global_sg.GlobalNodeId) !void {
        try self.deferred.append(self.allocator, .{ .marker = marker, .value = deferred_value });
        try self.makeNoop(marker, self.graph.nodes.items[@intFromEnum(deferred_value)].source);
        self.stats.defers += 1;
    }

    fn resolveKeep(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        return self.registerKeep(globalizer.globalNode(o, value.node), globalizer.globalBinding(o, value.binding));
    }

    fn resolveKeepName(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const binding = name_lookup.binding(self.modules, self.offsets, module_index, module.text(value.name)) orelse return false;
        return self.registerKeep(globalizer.globalNode(o, value.node), binding);
    }

    fn registerKeep(self: *Resolver, marker: global_sg.GlobalNodeId, binding: global_sg.GlobalBindingId) !bool {
        try self.kept.append(self.allocator, .{ .marker = marker, .binding = binding });
        try self.makeNoop(marker, self.graph.bindings.items[@intFromEnum(binding)].source);
        self.stats.keeps += 1;
        return true;
    }

    fn resolveCopy(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const source = globalizer.globalNode(o, value.value);
        const target = globalizer.globalNode(o, value.node);
        const ty = self.graph.nodes.items[@intFromEnum(source)].ty orelse return false;
        // Index syntax can resolve to an operator call after lowering has
        // inserted an implicit copy. The call already produces a fresh value;
        // copying its result would require a spurious copy of owned outputs.
        if (self.graph.nodes.items[@intFromEnum(source)].content == .function_call) {
            self.graph.nodes.items[@intFromEnum(target)] = self.graph.nodes.items[@intFromEnum(source)];
            return true;
        }
        if (self.implementsNamedAbstract(ty, "ImplicitlyCopyable")) {
            const original = self.graph.nodes.items[@intFromEnum(source)];
            self.graph.nodes.items[@intFromEnum(target)] = original;
            self.stats.copies += 1;
            return true;
        }
        // An explicit copy contract does not grant permission to insert that
        // operation implicitly. This also keeps fallible copy results visible.
        if (self.findUnaryFunction("copy", ty) != null) return false;
        if (!self.triviallyCopyable(ty)) return false;
        self.graph.nodes.items[@intFromEnum(target)] = self.graph.nodes.items[@intFromEnum(source)];
        self.stats.copies += 1;
        return true;
    }

    fn implementsNamedAbstract(self: *Resolver, concrete: global_sg.GlobalTypeId, name: []const u8) bool {
        const dispatch = self.dispatch orelse return false;
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .abstract_type or !std.mem.eql(u8, self.graph.text(declaration.name), name)) continue;
            const abstract_decl: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            for (self.graph.types.items, 0..) |candidate, type_raw| {
                if (candidate != .declared or candidate.declared != abstract_decl) continue;
                const abstract_type: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(type_raw)));
                if (dispatch.abstracts.concreteImplements(concrete, abstract_type)) return true;
            }
        }
        return false;
    }

    fn resolveExplicitDeinit(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const binding = globalizer.globalBinding(o, value.binding);
        _ = self.autoDeinitNode(binding);
        self.stats.deinit_checks += 1;
        return true;
    }

    fn finalizeExpressionCleanup(
        self: *Resolver,
        node_id: global_sg.GlobalNodeId,
        active: []const global_sg.GlobalBindingId,
        defers: []const global_sg.GlobalNodeId,
    ) anyerror!void {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .binding_declaration => |binding| if (self.graph.bindings.items[@intFromEnum(binding)].initialization) |initialization|
                try self.finalizeExpressionCleanup(initialization, active, defers),
            .error_propagation => |propagation_id| {
                const propagation = &self.graph.error_propagations.items[@intFromEnum(propagation_id)];
                try self.finalizeExpressionCleanup(propagation.errable_value, active, defers);
                propagation.cleanup_nodes = try self.appendCleanup(active, defers);
            },
            .error_context => |context_id| {
                const context = &self.graph.error_contexts.items[@intFromEnum(context_id)];
                try self.finalizeExpressionCleanup(context.errable_value, active, defers);
                try self.finalizeExpressionCleanup(context.context, active, defers);
                context.cleanup_nodes = try self.appendCleanup(active, defers);
            },
            .move_value, .address_of => |child| try self.finalizeExpressionCleanup(child, active, defers),
            .assignment => |assignment| try self.finalizeExpressionCleanup(assignment.value, active, defers),
            .function_call => |call| try self.finalizeExpressionCleanup(call.input, active, defers),
            .virtualize => |virtualize_id| try self.finalizeExpressionCleanup(
                self.graph.virtualizes.items[@intFromEnum(virtualize_id)].value,
                active,
                defers,
            ),
            .virtual_call => |virtual_call_id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(virtual_call_id)];
                try self.finalizeExpressionCleanup(call.handle, active, defers);
                try self.finalizeExpressionCleanup(call.input, active, defers);
            },
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    try self.finalizeExpressionCleanup(field.value, active, defers);
            },
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.finalizeExpressionCleanup(element, active, defers);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |element|
                    try self.finalizeExpressionCleanup(element, active, defers);
            },
            .choice_literal => |literal| if (literal.payload) |payload|
                try self.finalizeExpressionCleanup(payload, active, defers),
            .struct_field_access => |access| try self.finalizeExpressionCleanup(access.value, active, defers),
            .choice_payload_access => |access| try self.finalizeExpressionCleanup(access.value, active, defers),
            .nullable_unwrap_or => |unwrap_id| {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
                try self.finalizeExpressionCleanup(unwrap.nullable_value, active, defers);
                try self.finalizeExpressionCleanup(unwrap.fallback_value, active, defers);
            },
            .array_index => |access| {
                try self.finalizeExpressionCleanup(access.array_ptr, active, defers);
                try self.finalizeExpressionCleanup(access.index, active, defers);
            },
            .array_store => |store| {
                try self.finalizeExpressionCleanup(store.array_ptr, active, defers);
                try self.finalizeExpressionCleanup(store.index, active, defers);
                try self.finalizeExpressionCleanup(store.value, active, defers);
            },
            .struct_field_store => |store| {
                try self.finalizeExpressionCleanup(store.struct_ptr, active, defers);
                try self.finalizeExpressionCleanup(store.value, active, defers);
            },
            .binary_operation => |operation| {
                try self.finalizeExpressionCleanup(operation.left, active, defers);
                try self.finalizeExpressionCleanup(operation.right, active, defers);
            },
            .comparison => |comparison| {
                try self.finalizeExpressionCleanup(comparison.left, active, defers);
                try self.finalizeExpressionCleanup(comparison.right, active, defers);
            },
            .logical_operation => |operation| {
                try self.finalizeExpressionCleanup(operation.left, active, defers);
                try self.finalizeExpressionCleanup(operation.right, active, defers);
            },
            .pointer_assignment => |assignment| {
                try self.finalizeExpressionCleanup(assignment.pointer, active, defers);
                try self.finalizeExpressionCleanup(assignment.value, active, defers);
            },
            .explicit_cast => |cast| try self.finalizeExpressionCleanup(cast.value, active, defers),
            .type_initializer => |initializer| try self.finalizeExpressionCleanup(initializer.args, active, defers),
            .testing_expect_error => |expect_id| {
                const expect = self.graph.testing_expect_errors.items[@intFromEnum(expect_id)];
                try self.finalizeExpressionCleanup(expect.expected_reason, active, defers);
                try self.finalizeExpressionCleanup(expect.actual_result, active, defers);
            },
            else => {},
        }
    }

    fn finalizeBlock(
        self: *Resolver,
        block_id: global_sg.GlobalBlockId,
        inherited_active: *std.ArrayList(global_sg.GlobalBindingId),
        inherited_defers: *std.ArrayList(global_sg.GlobalNodeId),
        inherited_visible: *std.ArrayList(global_sg.GlobalBindingId),
        introduced_bindings: []const global_sg.GlobalBindingId,
        owner_function: global_sg.GlobalFunctionId,
        module_index: usize,
    ) anyerror!void {
        const original = self.graph.blocks.items[@intFromEnum(block_id)];
        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        try active.appendSlice(self.allocator, inherited_active.items);
        const active_base = active.items.len;
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        try defers.appendSlice(self.allocator, inherited_defers.items);
        const defer_base = defers.items.len;
        var visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer visible.deinit(self.allocator);
        try visible.appendSlice(self.allocator, inherited_visible.items);
        for (introduced_bindings) |binding| {
            try visible.append(self.allocator, binding);
            try self.prepareAutoDeinit(
                binding,
                reach_context.Context.fromGlobal(visible.items, owner_function),
                module_index,
            );
            try active.append(self.allocator, binding);
        }

        var rebuilt: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer rebuilt.deinit(self.allocator);
        // Recursive finalization appends cleanup edges to graph.node_refs and
        // may reallocate it. Keep a stable copy of this block's original node IDs.
        const nodes = try self.allocator.dupe(global_sg.GlobalNodeId, self.graph.node_refs.items[original.nodes.start..][0..original.nodes.len]);
        defer self.allocator.free(nodes);
        for (nodes) |node_id| {
            try rebuilt.append(self.allocator, node_id);
            try self.finalizeExpressionCleanup(node_id, active.items, defers.items);
            const node = &self.graph.nodes.items[@intFromEnum(node_id)];
            if (self.deferValue(node_id)) |deferred_value| {
                try defers.append(self.allocator, deferred_value);
                continue;
            }
            if (self.keepBinding(node_id)) |binding| {
                removeBinding(&active, binding);
                continue;
            }
            switch (node.content) {
                .binding_declaration => |binding| {
                    try visible.append(self.allocator, binding);
                    try self.prepareAutoDeinit(
                        binding,
                        reach_context.Context.fromGlobal(visible.items, owner_function),
                        module_index,
                    );
                    try active.append(self.allocator, binding);
                },
                .return_statement => |*ret| ret.cleanup = try self.appendCleanup(active.items, defers.items),
                .code_block => |child| try self.finalizeBlock(child, &active, &defers, &visible, &.{}, owner_function, module_index),
                .if_statement => |statement| {
                    try self.finalizeBlock(statement.then_block, &active, &defers, &visible, &.{}, owner_function, module_index);
                    if (statement.else_block) |child|
                        try self.finalizeBlock(child, &active, &defers, &visible, &.{}, owner_function, module_index);
                },
                .while_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers, &visible, &.{}, owner_function, module_index),
                .for_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers, &visible, &.{}, owner_function, module_index),
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case| {
                        const bindings: []const global_sg.GlobalBindingId = if (case.payload_binding) |*binding| binding[0..1] else &.{};
                        try self.finalizeBlock(case.body, &active, &defers, &visible, bindings, owner_function, module_index);
                    }
                    if (sw.default_block) |child|
                        try self.finalizeBlock(child, &active, &defers, &visible, &.{}, owner_function, module_index);
                },
                else => {},
            }
        }

        // Normal scope exit executes only cleanup introduced by this block.
        var local_cleanup: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer local_cleanup.deinit(self.allocator);
        var i = defers.items.len;
        while (i > defer_base) {
            i -= 1;
            try local_cleanup.append(self.allocator, defers.items[i]);
        }
        i = active.items.len;
        while (i > active_base) {
            i -= 1;
            if (self.autoDeinitNode(active.items[i])) |node| try local_cleanup.append(self.allocator, node);
        }
        try rebuilt.appendSlice(self.allocator, local_cleanup.items);

        const start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.appendSlice(self.allocator, rebuilt.items);
        self.graph.blocks.items[@intFromEnum(block_id)].nodes = .{ .start = start, .len = @intCast(rebuilt.items.len) };
        if (local_cleanup.items.len != 0) self.stats.cleanup_edges += @intCast(local_cleanup.items.len);
    }

    fn appendCleanup(
        self: *Resolver,
        active: []const global_sg.GlobalBindingId,
        defers: []const global_sg.GlobalNodeId,
    ) !primitives.Range(global_sg.GlobalNodeId) {
        const start: u32 = @intCast(self.graph.node_refs.items.len);
        var count: u32 = 0;
        var i = defers.len;
        while (i != 0) {
            i -= 1;
            try self.graph.node_refs.append(self.allocator, defers[i]);
            count += 1;
        }
        i = active.len;
        while (i != 0) {
            i -= 1;
            if (self.autoDeinitNode(active[i])) |node| {
                try self.graph.node_refs.append(self.allocator, node);
                count += 1;
            }
        }
        self.stats.cleanup_edges += count;
        return .{ .start = start, .len = count };
    }

    fn autoDeinitNode(self: *const Resolver, binding: global_sg.GlobalBindingId) ?global_sg.GlobalNodeId {
        for (self.auto_nodes.items) |entry| if (entry.binding == binding) return entry.node;
        return null;
    }

    fn prepareAutoDeinit(
        self: *Resolver,
        binding: global_sg.GlobalBindingId,
        context: reach_context.Context,
        module_index: usize,
    ) !void {
        for (self.auto_nodes.items) |entry| if (entry.binding == binding) return;
        if (self.graph.isBindingTypeUnresolved(binding)) return error.UnresolvedAutoDeinitBinding;
        const record = self.graph.bindings.items[@intFromEnum(binding)];
        const target = try self.appendNode(record.source, record.ty, .{ .binding_use = binding });
        const descriptor = try self.buildAutoDeinit(binding, target, record.ty, context, module_index);
        var cleanup_node: ?global_sg.GlobalNodeId = null;
        if (descriptor) |resolved| {
            const auto_id: global_sg.GlobalAutoDeinitId = @enumFromInt(@as(u32, @intCast(self.graph.auto_deinits.items.len)));
            try self.graph.auto_deinits.append(self.allocator, resolved);
            cleanup_node = try self.appendNode(record.source, try self.builtin(.Void), .{ .auto_deinit_binding = auto_id });
            self.stats.auto_deinits += 1;
        }
        try self.auto_nodes.append(self.allocator, .{ .binding = binding, .node = cleanup_node });
    }

    fn buildAutoDeinit(
        self: *Resolver,
        binding: global_sg.GlobalBindingId,
        target: global_sg.GlobalNodeId,
        ty: global_sg.GlobalTypeId,
        context: reach_context.Context,
        module_index: usize,
    ) !?global_sg.AutoDeinit {
        // References never own their pointee.
        if (self.graph.semanticType(ty) == .pointer) return null;
        if (try self.resolveDestructor(target, context, module_index)) |resolved| {
            return .{
                .binding = binding,
                .deinit_fn = resolved.function,
                .input = resolved.input,
                .self_field_index = resolved.self_field_index,
            };
        }

        const fields = global_types.fields(self.graph, ty) orelse return null;
        const start: u32 = @intCast(self.graph.auto_deinit_fields.items.len);
        var count: u32 = 0;
        for (0..fields.len) |index| {
            const field = self.graph.fields.items[fields.start + @as(u32, @intCast(index))];
            const projected = try self.appendNode(
                self.graph.nodes.items[@intFromEnum(target)].source,
                field.ty,
                .{ .struct_field_access = .{
                    .value = target,
                    .field_name = field.name,
                    .field_index = @intCast(index),
                } },
            );
            if (try self.appendAutoField(@intCast(index), projected, field.ty, context, module_index)) count += 1;
        }
        if (count == 0) return null;
        return .{
            .binding = binding,
            .deinit_fn = null,
            .fields = .{ .start = start, .len = count },
        };
    }

    fn appendAutoField(
        self: *Resolver,
        field_index: u32,
        target: global_sg.GlobalNodeId,
        ty: global_sg.GlobalTypeId,
        context: reach_context.Context,
        module_index: usize,
    ) !bool {
        if (self.graph.semanticType(ty) == .pointer) return false;
        if (try self.resolveDestructor(target, context, module_index)) |resolved| {
            try self.graph.auto_deinit_fields.append(self.allocator, .{
                .field_index = field_index,
                .deinit_fn = resolved.function,
                .input = resolved.input,
                .self_field_index = resolved.self_field_index,
            });
            return true;
        }

        const fields = global_types.fields(self.graph, ty) orelse return false;
        const child_start: u32 = @intCast(self.graph.auto_deinit_fields.items.len);
        var child_count: u32 = 0;
        for (0..fields.len) |index| {
            const field = self.graph.fields.items[fields.start + @as(u32, @intCast(index))];
            const projected = try self.appendNode(
                self.graph.nodes.items[@intFromEnum(target)].source,
                field.ty,
                .{ .struct_field_access = .{
                    .value = target,
                    .field_name = field.name,
                    .field_index = @intCast(index),
                } },
            );
            if (try self.appendAutoField(@intCast(index), projected, field.ty, context, module_index)) child_count += 1;
        }
        if (child_count == 0) return false;
        try self.graph.auto_deinit_fields.append(self.allocator, .{
            .field_index = field_index,
            .deinit_fn = null,
            .fields = .{ .start = child_start, .len = child_count },
        });
        return true;
    }

    fn resolveDestructor(
        self: *Resolver,
        target: global_sg.GlobalNodeId,
        context: reach_context.Context,
        module_index: usize,
    ) !?ResolvedDestructor {
        const target_ty = self.graph.nodes.items[@intFromEnum(target)].ty orelse return null;
        const dispatch = self.dispatch orelse return error.MissingOwnershipDispatch;
        const pointer_ty = try self.core.pointerType(target_ty, .read_write);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const address = try self.appendNode(source, pointer_ty, .{ .address_of = target });

        var receiver_names = std.StringHashMap(void).init(self.allocator);
        defer receiver_names.deinit();
        try self.collectDestructorReceiverNames(module_index, &receiver_names);

        var selected: ?ResolvedDestructor = null;
        var names = receiver_names.keyIterator();
        while (names.next()) |name_ptr| {
            const input = try self.singleNamedInput(name_ptr.*, address, source);
            const call = dispatch.resolveImplicitFunction(
                module_index,
                "deinit",
                input,
                context,
            ) catch |err| switch (err) {
                error.DeferredImplicitFunction => continue,
                error.AmbiguousImplicitFunction => return err,
                else => return err,
            } orelse continue;
            const self_index = self.findReceiverIndex(call.function, call.input, target) orelse continue;
            const candidate = ResolvedDestructor{
                .function = call.function,
                .input = call.input,
                .self_field_index = self_index,
            };
            if (selected) |previous| {
                if (previous.function != candidate.function or previous.self_field_index != candidate.self_field_index)
                    return error.AmbiguousImplicitDestructor;
            } else {
                selected = candidate;
            }
        }
        return selected;
    }

    fn collectDestructorReceiverNames(
        self: *Resolver,
        module_index: usize,
        names: *std.StringHashMap(void),
    ) !void {
        for (self.graph.functions.items) |function| {
            if (!function.flags.is_deinit) continue;
            if (!self.core.declarationVisible(module_index, function.declaration, null)) continue;
            for (self.graph.fields.items[function.input.start..][0..function.input.len]) |field| {
                const pointer = switch (self.graph.semanticType(field.ty)) {
                    .pointer => |value| value,
                    else => continue,
                };
                if (pointer.mutability != .read_write) continue;
                try names.put(self.graph.text(field.name), {});
            }
        }

        for (self.modules, 0..) |*candidate_module, candidate_index| {
            const storage = &candidate_module.semantic.parameterized_storage;
            for (storage.parameterized_functions.items) |function| {
                if (!function.is_deinit) continue;
                const declaration = globalizer.globalDecl(self.offsets[candidate_index], function.declaration);
                if (!self.core.declarationVisible(module_index, declaration, null)) continue;
                const shape = switch (storage.ir.types.items[@intFromEnum(function.input)]) {
                    .resolved => |ty| switch (ty) {
                        .structural => |value| value,
                        else => continue,
                    },
                    else => continue,
                };
                for (storage.ir.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                    const pointer = switch (storage.ir.types.items[@intFromEnum(field.ty)]) {
                        .resolved => |ty| switch (ty) {
                            .pointer => |value| value,
                            else => continue,
                        },
                        else => continue,
                    };
                    if (pointer.mutability != .read_write) continue;
                    try names.put(candidate_module.text(field.name), {});
                }
            }
        }
    }

    fn singleNamedInput(
        self: *Resolver,
        name: []const u8,
        value: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !global_sg.GlobalNodeId {
        const field_start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.append(self.allocator, .{
            .name = try self.graph.addString(self.allocator, name),
            .value = value,
        });
        return self.appendNode(source, null, .{ .struct_value_literal = .{
            .fields = .{ .start = field_start, .len = 1 },
        } });
    }

    fn findReceiverIndex(
        self: *const Resolver,
        function_id: global_sg.GlobalFunctionId,
        input: global_sg.GlobalNodeId,
        target: global_sg.GlobalNodeId,
    ) ?u32 {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        if (literal.fields.len != function.input.len) return null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, index| {
            const node = self.graph.nodes.items[@intFromEnum(field.value)];
            if (node.content != .address_of or node.content.address_of != target) continue;
            return @intCast(index);
        }
        return null;
    }

    fn appendNode(
        self: *Resolver,
        source: primitives.SourceRef,
        ty: ?global_sg.GlobalTypeId,
        content: global_sg.Node.Content,
    ) !global_sg.GlobalNodeId {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = ty, .content = content });
        return id;
    }

    fn findUnaryFunction(self: *Resolver, name: []const u8, ty: global_sg.GlobalTypeId) ?global_sg.GlobalFunctionId {
        for (self.graph.functions.items, 0..) |function, raw| {
            const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(declaration.name), name) or function.input.len != 1) continue;
            const expected = self.graph.fields.items[function.input.start].ty;
            if (typeAccepts(self.graph, expected, ty)) return @enumFromInt(@as(u32, @intCast(raw)));
        }
        return null;
    }

    fn triviallyCopyable(self: *Resolver, ty: global_sg.GlobalTypeId) bool {
        if (global_types.deinitFunction(self.graph, ty) != null) return false;
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .builtin, .pointer, .virtual => true,
            .array => |array| self.triviallyCopyable(array.element),
            .structural => blk: {
                const fields = global_types.fields(self.graph, ty) orelse break :blk false;
                for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
                    if (!self.triviallyCopyable(field.ty)) break :blk false;
                break :blk true;
            },
            .declared => blk: {
                if (global_types.fields(self.graph, ty)) |fields|
                    break :blk self.fieldsTriviallyCopyable(fields);
                if (global_types.variants(self.graph, ty)) |variants|
                    break :blk self.variantsTriviallyCopyable(variants);
                break :blk false;
            },
            .generic => blk: {
                const instance = global_types.genericInstance(self.graph, ty) orelse break :blk false;
                break :blk switch (instance.shape) {
                    .structure => |shape| self.fieldsTriviallyCopyable(shape.fields),
                    .choice => |shape| self.variantsTriviallyCopyable(shape.variants),
                    .array => |shape| self.triviallyCopyable(shape.element),
                    .alias => |target| self.triviallyCopyable(target),
                };
            },
            .structural_choice, .inferred_choice => blk: {
                const variants = global_types.variants(self.graph, ty) orelse break :blk false;
                break :blk self.variantsTriviallyCopyable(variants);
            },
            .nullable, .inferred_errable => |child| self.triviallyCopyable(child),
        };
    }

    fn fieldsTriviallyCopyable(self: *Resolver, fields: global_sg.FieldRange) bool {
        for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
            if (!self.triviallyCopyable(field.ty)) return false;
        return true;
    }

    fn variantsTriviallyCopyable(self: *Resolver, variants: global_sg.VariantRange) bool {
        for (self.graph.variants.items[variants.start..][0..variants.len]) |variant|
            if (variant.payload_type) |payload| if (!self.triviallyCopyable(payload)) return false;
        return true;
    }

    fn deferValue(self: *Resolver, marker: global_sg.GlobalNodeId) ?global_sg.GlobalNodeId {
        for (self.deferred.items) |entry| if (entry.marker == marker) return entry.value;
        return null;
    }

    fn keepBinding(self: *Resolver, marker: global_sg.GlobalNodeId) ?global_sg.GlobalBindingId {
        for (self.kept.items) |entry| if (entry.marker == marker) return entry.binding;
        return null;
    }

    fn makeNoop(self: *Resolver, marker: global_sg.GlobalNodeId, source: primitives.SourceRef) !void {
        const block = if (self.empty_block) |id| id else blk: {
            const id: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.graph.blocks.items.len)));
            try self.graph.blocks.append(self.allocator, .{ .nodes = .{ .start = @intCast(self.graph.node_refs.items.len), .len = 0 }, .ret_val = null });
            self.empty_block = id;
            break :blk id;
        };
        self.graph.nodes.items[@intFromEnum(marker)] = .{
            .source = source,
            .ty = try self.builtin(.Void),
            .content = .{ .code_block = block },
        };
    }

    fn builtin(self: *Resolver, wanted: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == wanted) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .builtin = wanted });
        return id;
    }
};

fn removeBinding(list: *std.ArrayList(global_sg.GlobalBindingId), binding: global_sg.GlobalBindingId) void {
    var i: usize = list.items.len;
    while (i != 0) {
        i -= 1;
        if (list.items[i] == binding) {
            _ = list.orderedRemove(i);
            return;
        }
    }
}

fn typeAccepts(graph: *const global_sg.GlobalSemanticGraph, expected: global_sg.GlobalTypeId, concrete: global_sg.GlobalTypeId) bool {
    if (global_types.equal(graph, expected, concrete)) return true;
    return switch (graph.types.items[@intFromEnum(expected)]) {
        .pointer => |pointer| global_types.equal(graph, pointer.child, concrete),
        else => false,
    };
}

test "ownership cleanup resolver stores cleanup as GlobalNodeId edges" {
    try std.testing.expect(@sizeOf(global_sg.GlobalAutoDeinitId) == 4);
    try std.testing.expect(@sizeOf(global_sg.GlobalNodeId) == 4);
}

test "error propagation cleanup captures active lexical obligations" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const int_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const empty = try graph.addString(allocator, "");

    const deferred_node: global_sg.GlobalNodeId = @enumFromInt(0);
    const propagation_node: global_sg.GlobalNodeId = @enumFromInt(1);
    const assignment_node: global_sg.GlobalNodeId = @enumFromInt(2);
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .int_literal = 0 },
    });
    try graph.error_propagations.append(allocator, .{
        .errable_value = deferred_node,
        .cleanup_nodes = .{ .start = 0, .len = 0 },
        .ok_variant = @enumFromInt(0),
        .ok_value_field_index = null,
        .error_variant = @enumFromInt(0),
        .propagated_errable_type = int_ty,
        .propagated_error_variant = @enumFromInt(0),
        .ok_payload_type = int_ty,
        .error_payload_type = int_ty,
        .propagated_error_payload_type = int_ty,
        .diagnostic_line = 0,
        .diagnostic_column = 0,
        .diagnostic_source_line = empty,
    });
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .error_propagation = @enumFromInt(0) },
    });
    try graph.bindings.append(allocator, .{
        .name = empty,
        .source = source,
        .ty = int_ty,
        .mutability = .variable,
    });
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = int_ty,
        .content = .{ .assignment = .{ .binding = @enumFromInt(0), .value = propagation_node } },
    });

    var core: core_mod.Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
    };
    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = &core,
    };
    defer resolver.deinit();

    try resolver.finalizeExpressionCleanup(assignment_node, &.{}, &.{deferred_node});
    const cleanup = graph.error_propagations.items[0].cleanup_nodes;
    try std.testing.expectEqual(@as(u32, 1), cleanup.len);
    try std.testing.expectEqual(deferred_node, graph.node_refs.items[cleanup.start]);
}

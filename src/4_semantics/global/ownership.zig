const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const name_lookup = @import("name_lookup.zig");
const core_mod = @import("core.zig");
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
const AutoNode = struct { binding: global_sg.GlobalBindingId, node: global_sg.GlobalNodeId };

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
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
        for (self.graph.functions.items) |function| if (function.body) |body|
            try self.finalizeFunctionBody(body);
    }

    pub fn finalizeFunctionBody(self: *Resolver, body: global_sg.GlobalBlockId) !void {
        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        try self.finalizeBlock(body, &active, &defers);
    }

    fn resolveDefer(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const marker = globalizer.globalNode(o, value.node);
        const deferred_value = globalizer.globalNode(o, value.value);
        try self.deferred.append(self.allocator, .{ .marker = marker, .value = deferred_value });
        try self.makeNoop(marker, self.graph.nodes.items[@intFromEnum(deferred_value)].source);
        self.stats.defers += 1;
        return true;
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
        if (self.triviallyCopyable(ty)) {
            const original = self.graph.nodes.items[@intFromEnum(source)];
            self.graph.nodes.items[@intFromEnum(target)] = original;
            self.stats.copies += 1;
            return true;
        }
        const copy_fn = self.findUnaryFunction("copy", ty) orelse return false;
        const input = try self.core.makeCallInput(copy_fn, &.{source});
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(source)].source,
            .ty = try self.core.functionOutputType(copy_fn),
            .content = .{ .function_call = .{ .callee = copy_fn, .input = input } },
        };
        self.stats.copies += 1;
        return true;
    }

    fn resolveExplicitDeinit(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const binding = globalizer.globalBinding(o, value.binding);
        _ = try self.autoDeinitNode(binding);
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
                .binding_declaration => |binding| try active.append(self.allocator, binding),
                .return_statement => |*ret| ret.cleanup = try self.appendCleanup(active.items, defers.items),
                .code_block => |child| try self.finalizeBlock(child, &active, &defers),
                .if_statement => |statement| {
                    try self.finalizeBlock(statement.then_block, &active, &defers);
                    if (statement.else_block) |child| try self.finalizeBlock(child, &active, &defers);
                },
                .while_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers),
                .for_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers),
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case|
                        try self.finalizeBlock(case.body, &active, &defers);
                    if (sw.default_block) |child| try self.finalizeBlock(child, &active, &defers);
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
            if (try self.autoDeinitNode(active.items[i])) |node| try local_cleanup.append(self.allocator, node);
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
            if (try self.autoDeinitNode(active[i])) |node| {
                try self.graph.node_refs.append(self.allocator, node);
                count += 1;
            }
        }
        self.stats.cleanup_edges += count;
        return .{ .start = start, .len = count };
    }

    fn autoDeinitNode(self: *Resolver, binding: global_sg.GlobalBindingId) !?global_sg.GlobalNodeId {
        for (self.auto_nodes.items) |entry| if (entry.binding == binding) return entry.node;
        if (self.graph.isBindingTypeUnresolved(binding)) return null;
        const record = self.graph.bindings.items[@intFromEnum(binding)];
        const descriptor = try self.buildAutoDeinit(binding, record.ty) orelse return null;
        const auto_id: global_sg.GlobalAutoDeinitId = @enumFromInt(@as(u32, @intCast(self.graph.auto_deinits.items.len)));
        try self.graph.auto_deinits.append(self.allocator, descriptor);
        const node: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{
            .source = record.source,
            .ty = try self.builtin(.Void),
            .content = .{ .auto_deinit_binding = auto_id },
        });
        try self.auto_nodes.append(self.allocator, .{ .binding = binding, .node = node });
        self.stats.auto_deinits += 1;
        return node;
    }

    fn buildAutoDeinit(
        self: *Resolver,
        binding: global_sg.GlobalBindingId,
        ty: global_sg.GlobalTypeId,
    ) !?global_sg.AutoDeinit {
        // A reference does not own its pointee. Its cleanup belongs to the
        // pointee's storage owner, including when the reference is writable.
        if (self.graph.semanticType(ty) == .pointer) return null;
        if (global_types.deinitFunction(self.graph, ty)) |function| return .{ .binding = binding, .deinit_fn = function };
        const fields = global_types.fields(self.graph, ty) orelse return null;
        const start: u32 = @intCast(self.graph.auto_deinit_fields.items.len);
        var count: u32 = 0;
        for (0..fields.len) |index| {
            const field_ty = self.graph.fields.items[fields.start + @as(u32, @intCast(index))].ty;
            if (try self.appendAutoField(@intCast(index), field_ty)) count += 1;
        }
        if (count == 0) return null;
        return .{ .binding = binding, .deinit_fn = null, .fields = .{ .start = start, .len = count } };
    }

    fn appendAutoField(self: *Resolver, field_index: u32, ty: global_sg.GlobalTypeId) !bool {
        if (self.graph.semanticType(ty) == .pointer) return false;
        if (global_types.deinitFunction(self.graph, ty)) |function| {
            try self.graph.auto_deinit_fields.append(self.allocator, .{ .field_index = field_index, .deinit_fn = function });
            return true;
        }
        const fields = global_types.fields(self.graph, ty) orelse return false;
        const child_start: u32 = @intCast(self.graph.auto_deinit_fields.items.len);
        var child_count: u32 = 0;
        for (0..fields.len) |index| {
            const child_ty = self.graph.fields.items[fields.start + @as(u32, @intCast(index))].ty;
            if (try self.appendAutoField(@intCast(index), child_ty)) child_count += 1;
        }
        if (child_count == 0) return false;
        try self.graph.auto_deinit_fields.append(self.allocator, .{
            .field_index = field_index,
            .deinit_fn = null,
            .fields = .{ .start = child_start, .len = child_count },
        });
        return true;
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
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .builtin, .pointer => true,
            .array => |array| self.triviallyCopyable(array.element),
            .structural, .declared, .generic => blk: {
                const fields = global_types.fields(self.graph, ty) orelse break :blk false;
                for (self.graph.fields.items[fields.start..][0..fields.len]) |field|
                    if (!self.triviallyCopyable(field.ty)) break :blk false;
                break :blk true;
            },
            else => false,
        };
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

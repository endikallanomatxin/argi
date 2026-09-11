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
        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        for (self.graph.functions.items) |function| if (function.body) |body| {
            active.clearRetainingCapacity();
            defers.clearRetainingCapacity();
            try self.finalizeBlock(body, &active, &defers);
        };
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
        if (self.findDeinitFunction(ty)) |function| return .{ .binding = binding, .deinit_fn = function };
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
        if (self.findDeinitFunction(ty)) |function| {
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

    fn findDeinitFunction(self: *Resolver, ty: global_sg.GlobalTypeId) ?global_sg.GlobalFunctionId {
        for (self.graph.functions.items, 0..) |function, raw| {
            if (!function.flags.is_deinit or function.input.len == 0) continue;
            const first = self.graph.fields.items[function.input.start].ty;
            if (typeAccepts(self.graph, first, ty)) return @enumFromInt(@as(u32, @intCast(raw)));
        }
        return null;
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

const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const p = @import("../../4_semantics/primitives/schema.zig");
const b = @import("bytecode.zig");
const types = @import("../../4_semantics/global/types.zig");
const cleanup_layout = @import("../cleanup_layout.zig");
const cleanup_plan = @import("../cleanup_plan.zig");

pub const Lower = struct {
    allocator: std.mem.Allocator,
    graph: *const g.GlobalSemanticGraph,
    functions: []?b.Function,
    cleanup_bindings: []const bool,
    cleanup_types: []const bool,
    bool_type: ?b.Type,
    pending: std.ArrayList(g.GlobalFunctionId) = .empty,
    source: p.SourceRef = .{ .file_index = 0, .offset = 0 },
    unsupported: []const u8 = "",
    session: ?b.Session = null,

    pub fn init(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) !Lower {
        const functions = try a.alloc(?b.Function, graph.functions.items.len);
        @memset(functions, null);
        const cleanup_bindings = try cleanup_layout.requiredBindings(a, graph);
        const cleanup_types = try cleanup_layout.owningTypes(a, graph);
        const bool_type: ?b.Type = for (graph.types.items, 0..) |ty, i| {
            if (ty == .builtin and ty.builtin == .Bool) break @as(b.Type, @enumFromInt(i));
        } else null;
        return .{ .allocator = a, .graph = graph, .functions = functions, .cleanup_bindings = cleanup_bindings, .cleanup_types = cleanup_types, .bool_type = bool_type };
    }
    pub fn initSession(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, session: b.Session) !Lower {
        var result = try init(a, graph);
        result.session = session;
        return result;
    }
    fn sessionIndex(self: *const Lower, binding: g.GlobalBindingId) ?u32 {
        const session = self.session orelse return null;
        for (session.bindings, 0..) |entry, index| if (entry.binding == binding) return @intCast(index);
        return null;
    }
    // All bytecode allocations belong to the caller's compilation arena.
    // VM initialization verifies the completed program before accepting it.
    pub fn compile(self: *Lower, entry: g.GlobalFunctionId) !b.Program {
        if (@intFromEnum(entry) >= self.functions.len) return error.InvalidEntry;
        try self.pending.append(self.allocator, entry);
        return self.finish(null);
    }

    /// Lower a checked session-exit cleanup list through the ordinary cleanup
    /// emitter. This entry has no invented semantic function identity. Its
    /// dependency bodies and persistent layouts must belong to the checked graph.
    pub fn compileSessionCleanup(self: *Lower, nodes: []const g.GlobalNodeId) !b.Program {
        if (self.session == null) return error.InvalidBytecode;
        for (nodes) |id| {
            if (@intFromEnum(id) >= self.graph.nodes.items.len) return error.InvalidBytecode;
            const node = self.graph.node(id);
            if (node.content != .auto_deinit_binding) return error.InvalidBytecode;
            const cleanup = self.graph.auto_deinits.items[@intFromEnum(node.content.auto_deinit_binding)];
            if (self.sessionIndex(cleanup.binding) == null) return error.InvalidBytecode;
        }
        var function = FunctionLower{ .parent = self };
        return self.finish(try function.compileCleanup(nodes));
    }

    // An expression has its own entry frame, not a fabricated GlobalFunctionId.
    // Inputs replace already-evaluated operand nodes; normal lowering still
    // selects every instruction, call and control-flow edge.
    pub fn compileExpression(self: *Lower, node: g.GlobalNodeId, operands: []const g.GlobalNodeId) !b.Program {
        const root = self.graph.node(node);
        if (self.cleanup_types[@intFromEnum(root.ty orelse return error.InvalidBytecode)])
            return self.reject(root.source, "owning expression entry result");
        for (operands) |operand| {
            const value = self.graph.node(operand);
            if (self.cleanup_types[@intFromEnum(value.ty orelse return error.InvalidBytecode)])
                return self.reject(value.source, "owning expression entry input");
        }
        errdefer {
            self.pending.deinit(self.allocator);
            self.pending = .empty;
        }
        var function = FunctionLower{ .parent = self };
        return self.finish(try function.compileExpression(node, operands));
    }

    fn finish(self: *Lower, expression: ?b.Function) !b.Program {
        defer {
            self.pending.deinit(self.allocator);
            self.pending = .empty;
        }
        var compiled: std.ArrayList(g.GlobalFunctionId) = .empty;
        defer compiled.deinit(self.allocator);
        // A caller can finish lowering before a dependency fails. Roll back
        // every new cache entry so retrying it cannot publish an incomplete
        // dependency closure. Previously published code stays reusable.
        errdefer for (compiled.items) |id| {
            self.functions[@intFromEnum(id)] = null;
        };
        while (self.pending.pop()) |id| {
            if (self.functions[@intFromEnum(id)] != null) continue;
            try compiled.append(self.allocator, id);
            var f = FunctionLower{ .parent = self };
            self.functions[@intFromEnum(id)] = try f.compile(id);
        }
        // Published programs are immutable snapshots of the retained cache.
        // A later entry may compile more functions, but must not mutate a
        // table already verified and in use by an execution context.
        const entry = if (expression) |value| blk: {
            const stored = try self.allocator.create(b.Function);
            stored.* = value;
            break :blk stored;
        } else null;
        return .{ .graph = self.graph, .functions = try self.allocator.dupe(?b.Function, self.functions), .expression = entry, .session = self.session };
    }
    fn reject(self: *Lower, source: p.SourceRef, name: []const u8) error{UnsupportedExecution} {
        self.source = source;
        self.unsupported = name;
        return error.UnsupportedExecution;
    }
};

const Loop = struct { breaks: std.ArrayList(u32) = .empty, continues: std.ArrayList(u32) = .empty };
const DropState = enum(u32) { _ };
// One preorder table during lowering; handles stay valid when it grows.
// Each subtree ends at `end`, so projection skips siblings without a second
// recursively allocated tree or entries for payloadless variants.
const CleanupEntry = struct { place: b.Place, flag: b.Slot, end: u32 };
const FunctionLower = struct {
    parent: *Lower,
    slots: std.ArrayList(b.Type) = .empty,
    code: std.ArrayList(b.Instruction) = .empty,
    bindings: std.AutoHashMapUnmanaged(g.GlobalBindingId, b.Slot) = .empty,
    outputs: []const b.Slot = &.{},
    drops: std.AutoHashMapUnmanaged(g.GlobalBindingId, DropState) = .empty,
    cleanup: std.ArrayList(CleanupEntry) = .empty,
    write_destinations: std.ArrayList(b.Type) = .empty,
    loops: std.ArrayList(Loop) = .empty,

    precomputed: []const struct { node: g.GlobalNodeId, slot: b.Slot } = &.{},

    fn compileCleanup(self: *FunctionLower, nodes: []const g.GlobalNodeId) !b.Function {
        const a = self.parent.allocator;
        defer self.bindings.deinit(a);
        defer self.drops.deinit(a);
        defer self.cleanup.deinit(a);
        defer self.loops.deinit(a);
        try self.prepareSessionDrops();
        for (nodes) |node| try self.statement(node);
        _ = try self.emit(self.parent.source, .{ .ret = &.{} });
        return .{ .slots = try self.slots.toOwnedSlice(a), .inputs = &.{}, .outputs = &.{}, .code = try self.code.toOwnedSlice(a), .cleanup = try self.finishCleanup(), .write_destinations = try self.write_destinations.toOwnedSlice(a) };
    }

    fn compileExpression(self: *FunctionLower, root: g.GlobalNodeId, operands: []const g.GlobalNodeId) !b.Function {
        const a = self.parent.allocator;
        defer self.bindings.deinit(a);
        defer self.drops.deinit(a);
        defer self.cleanup.deinit(a);
        defer self.loops.deinit(a);
        try self.prepareSessionDrops();
        const inputs = try a.alloc(b.Slot, operands.len);
        const mapped = try a.alloc(@typeInfo(@TypeOf(self.precomputed)).pointer.child, operands.len);
        for (operands, inputs, mapped) |node, *slot, *mapping| {
            slot.* = try self.newSlot(self.parent.graph.node(node).ty orelse return error.InvalidBytecode);
            mapping.* = .{ .node = node, .slot = slot.* };
        }
        self.precomputed = mapped;
        const outputs = try a.alloc(b.Slot, 1);
        outputs[0] = try self.expression(root);
        _ = try self.emit(self.parent.graph.node(root).source, .{ .ret = outputs });
        return .{ .slots = try self.slots.toOwnedSlice(a), .inputs = inputs, .outputs = outputs, .code = try self.code.toOwnedSlice(a), .cleanup = try self.finishCleanup(), .write_destinations = try self.write_destinations.toOwnedSlice(a) };
    }

    fn compile(self: *FunctionLower, id: g.GlobalFunctionId) !b.Function {
        const a = self.parent.allocator;
        defer self.bindings.deinit(a);
        defer self.drops.deinit(a);
        defer self.cleanup.deinit(a);
        defer self.loops.deinit(a);
        const f = self.parent.graph.function(id);
        const source = self.parent.graph.declaration(f.declaration).source;
        self.parent.source = source;
        if (f.body == null or f.flags.is_c_abi or f.flags.is_once) return self.parent.reject(source, "foreign or once function");
        try self.prepareSessionDrops();
        const inputs = try a.alloc(b.Slot, f.input_bindings.len);
        for (inputs, self.parent.graph.binding_refs.items[f.input_bindings.start..][0..f.input_bindings.len]) |*slot, binding| {
            slot.* = try self.bindingSlot(binding);
            if (self.drops.get(binding)) |drop| try self.setDrop(drop, true);
        }
        const outputs = try a.alloc(b.Slot, f.output_bindings.len);
        self.outputs = outputs;
        for (outputs, self.parent.graph.binding_refs.items[f.output_bindings.start..][0..f.output_bindings.len]) |*slot, binding| {
            slot.* = try self.bindingSlot(binding);
            if (self.parent.graph.binding(binding).initialization != null) return error.InvalidBytecode;
        }
        try self.block(f.body.?);
        _ = try self.emit(source, .{ .ret = outputs });
        return .{ .slots = try self.slots.toOwnedSlice(a), .inputs = inputs, .outputs = outputs, .code = try self.code.toOwnedSlice(a), .cleanup = try self.finishCleanup(), .write_destinations = try self.write_destinations.toOwnedSlice(a) };
    }

    fn prepareSessionDrops(self: *FunctionLower) !void {
        const session = self.parent.session orelse return;
        for (session.bindings, 0..) |binding, index| {
            if (binding.cleanup.len == 0) continue;
            const drop = try self.buildDrop(binding.slots[0], .{ .root = @intCast(index), .region = .session, .path = &.{} });
            const entries = self.cleanup.items[@intFromEnum(drop)..];
            if (entries.len != binding.cleanup.len) return error.InvalidBytecode;
            for (entries, binding.cleanup) |entry, supplied| {
                if (entry.place.path.len != supplied.path.len) return error.InvalidBytecode;
                for (entry.place.path, supplied.path) |expected, actual| switch (expected) {
                    .field => |field| if (actual != .field or actual.field != field) return error.InvalidBytecode,
                    .variant => |variant| if (actual != .variant or actual.variant != @intFromEnum(variant)) return error.InvalidBytecode,
                    else => return error.InvalidBytecode,
                };
            }
            try self.drops.put(self.parent.allocator, binding.binding, drop);
        }
    }
    fn boolType(self: *FunctionLower) !b.Type {
        return self.parent.bool_type orelse error.InvalidBytecode;
    }
    fn buildDrop(self: *FunctionLower, ty: b.Type, target: b.Place) anyerror!DropState {
        const a = self.parent.allocator;
        const id: DropState = @enumFromInt(@as(u32, @intCast(self.cleanup.items.len)));
        const flag = if (target.region == .local) try self.newSlot(try self.boolType()) else 0;
        try self.cleanup.append(a, .{ .place = target, .flag = flag, .end = 0 });
        const shape = cleanup_layout.Shape.of(self.parent.graph, ty);
        for (0..shape.len()) |index| if (shape.child(self.parent.graph, index)) |child| {
            const projection: b.Projection = switch (child.projection) {
                .field => |field| .{ .field = field },
                .variant => |variant| .{ .variant = variant },
            };
            _ = try self.buildDrop(child.ty, try self.project(target, projection));
        };
        self.cleanup.items[@intFromEnum(id)].end = @intCast(self.cleanup.items.len);
        return id;
    }
    fn finishCleanup(self: *FunctionLower) ![]const b.Cleanup {
        const a = self.parent.allocator;
        var count: usize = 0;
        for (self.cleanup.items) |entry| if (entry.place.region == .local) {
            count += 1;
        };
        const result = try a.alloc(b.Cleanup, count);
        var output_index: usize = 0;
        for (self.cleanup.items) |entry| {
            if (entry.place.region != .local) continue;
            const out = &result[output_index];
            output_index += 1;
            const path = try a.alloc(@import("value.zig").Projection, entry.place.path.len);
            for (entry.place.path, path) |projection, *part| part.* = switch (projection) {
                .field => |index| .{ .field = index },
                .variant => |variant| .{ .variant = @intFromEnum(variant) },
                else => return error.InvalidBytecode,
            };
            out.* = .{ .root = entry.place.root, .path = path, .flag = entry.flag };
        }
        return result;
    }
    fn dropChild(self: *FunctionLower, parent: DropState, projection: b.Projection) ?DropState {
        const end = self.cleanup.items[@intFromEnum(parent)].end;
        var index = @intFromEnum(parent) + 1;
        while (index < end) {
            const entry = self.cleanup.items[index];
            if (std.meta.eql(entry.place.path[entry.place.path.len - 1], projection)) return @enumFromInt(index);
            index = entry.end;
        }
        return null;
    }
    fn setDrop(self: *FunctionLower, drop: DropState, enabled: bool) anyerror!void {
        _ = try self.emit(self.parent.source, .{ .cleanup_set = .{ .place = self.cleanup.items[@intFromEnum(drop)].place, .enabled = enabled } });
    }
    fn nodeDrop(self: *FunctionLower, id: g.GlobalNodeId) ?DropState {
        return switch (self.parent.graph.node(id).content) {
            .binding_use => |binding| self.drops.get(binding),
            .address_of => |value| self.nodeDrop(value),
            .dereference => |value| self.nodeDrop(value.pointer),
            .struct_field_access => |value| blk: {
                const parent = self.nodeDrop(value.value) orelse break :blk null;
                break :blk self.dropChild(parent, .{ .field = value.field_index });
            },
            .choice_payload_access => |value| blk: {
                const parent = self.nodeDrop(value.value) orelse break :blk null;
                break :blk self.dropChild(parent, .{ .variant = value.variant });
            },
            else => null,
        };
    }
    // A reference field's drop flag belongs to its slot, not its referent.
    // Only the direct local destinations finalized by ownership lowering have
    // both a replacement cleanup plan and the matching runtime flags.
    fn trackedDestination(self: *FunctionLower, pointer: g.GlobalNodeId, cleanup_target: ?g.GlobalNodeId) bool {
        if (cleanup_target) |target| return self.directStorage(target) and self.nodeDrop(target) != null;
        const node = self.parent.graph.node(pointer);
        if (node.content != .address_of) return false;
        return self.directStorage(node.content.address_of) and self.nodeDrop(node.content.address_of) != null;
    }
    fn directStorage(self: *FunctionLower, id: g.GlobalNodeId) bool {
        return @import("../../4_semantics/global/lexical_storage.zig").root(self.parent.graph, id) != null;
    }
    fn autoDeinit(self: *FunctionLower, id: g.GlobalAutoDeinitId) anyerror!void {
        const auto = self.parent.graph.auto_deinits.items[@intFromEnum(id)];
        if (auto.target) |target| {
            const drop = self.nodeDrop(target) orelse return error.InvalidBytecode;
            return self.cleanupStorage(auto.deinit_fn, auto.input, auto.self_field_index, auto.fields, try self.place(target), self.parent.graph.node(target).ty.?, drop);
        }
        if (self.parent.sessionIndex(auto.binding)) |index| {
            const drop = self.drops.get(auto.binding) orelse return error.InvalidBytecode;
            return self.cleanupStorage(auto.deinit_fn, auto.input, auto.self_field_index, auto.fields, .{ .root = index, .region = .session, .path = &.{} }, self.parent.graph.binding(auto.binding).ty, drop);
        }
        const root = self.bindings.get(auto.binding) orelse return error.InvalidBytecode;
        try self.cleanupStorage(auto.deinit_fn, auto.input, auto.self_field_index, auto.fields, .{ .root = root, .path = &.{} }, self.slots.items[root], self.drops.get(auto.binding).?);
    }
    fn cleanupStorage(self: *FunctionLower, callee: ?g.GlobalFunctionId, input: ?g.GlobalNodeId, self_index: u32, fields: p.Range(g.GlobalAutoDeinitFieldId), target: b.Place, ty: b.Type, drop: DropState) anyerror!void {
        try cleanup_plan.emit(CleanupEmitter{ .lower = self }, self.parent.graph, .{
            .deinit_fn = callee,
            .input = input,
            .self_field_index = self_index,
            .fields = fields,
        }, CleanupEmitter.Target{ .place = target, .ty = ty, .drop = drop });
    }
    const CleanupEmitter = struct {
        lower: *FunctionLower,
        const Target = struct { place: b.Place, ty: b.Type, drop: DropState };

        pub fn begin(self: @This(), target: Target) !u32 {
            const lower = self.lower;
            const live = try lower.newSlot(try lower.boolType());
            _ = try lower.emit(lower.parent.source, .{ .cleanup_test = .{ .dst = live, .place = lower.cleanup.items[@intFromEnum(target.drop)].place } });
            return lower.emit(lower.parent.source, .{ .branch = .{ .condition = live, .yes = lower.position() + 1, .no = 0 } });
        }
        pub fn call(self: @This(), target: Target, id: g.GlobalFunctionId, input: ?g.GlobalNodeId, self_index: u32) !void {
            const source = self.lower.parent.source;
            const function = self.lower.parent.graph.function(id);
            if (function.output.len != 0) return self.lower.parent.reject(source, "destructor with outputs");
            const args = try self.lower.parent.allocator.alloc(b.Slot, function.input.len);
            for (args, self.lower.parent.graph.fields.items[function.input.start..][0..function.input.len], 0..) |*arg, field, index| {
                if (index == self_index) {
                    arg.* = try self.lower.newSlot(field.ty);
                    _ = try self.lower.emit(source, .{ .borrow = .{ .dst = arg.*, .place = target.place } });
                } else {
                    const value = try cleanup_plan.argument(self.lower.parent.graph, input, field);
                    arg.* = try self.lower.coerce(source, try self.lower.expression(value), field.ty);
                }
            }
            try self.lower.parent.pending.append(self.lower.parent.allocator, id);
            _ = try self.lower.emit(source, .{ .call = .{ .function = id, .args = args, .outputs = &.{} } });
        }
        pub fn beginVariant(self: @This(), target: Target, _: g.AutoDeinitField, selected: cleanup_plan.Child) !u32 {
            const lower = self.lower;
            const value = try lower.newSlot(target.ty);
            _ = try lower.emit(lower.parent.source, .{ .load = .{ .dst = value, .place = target.place } });
            return lower.emit(lower.parent.source, .{ .branch_variant = .{ .src = value, .variant = selected.variant.?, .yes = lower.position() + 1, .no = 0 } });
        }
        pub fn endVariant(self: @This(), branch: u32) !void {
            self.lower.code.items[branch].op.branch_variant.no = self.lower.position();
        }
        pub fn project(self: @This(), target: Target, field: g.AutoDeinitField, selected: cleanup_plan.Child) !Target {
            const projection: b.Projection = if (selected.variant) |variant| .{ .variant = variant } else .{ .field = field.field_index };
            return .{ .place = try self.lower.project(target.place, projection), .ty = selected.ty, .drop = self.lower.dropChild(target.drop, projection) orelse return error.InvalidBytecode };
        }
        pub fn finish(self: @This(), target: Target, branch: u32) !void {
            try self.lower.setDrop(target.drop, false);
            self.lower.code.items[branch].op.branch.no = self.lower.position();
        }
    };
    fn newSlot(self: *FunctionLower, ty: b.Type) !b.Slot {
        if (!b.supportedType(self.parent.graph, ty, 0)) return self.parent.reject(self.parent.source, "type outside the supported VM subset");
        const id: b.Slot = @intCast(self.slots.items.len);
        try self.slots.append(self.parent.allocator, ty);
        return id;
    }
    fn bindingSlot(self: *FunctionLower, id: g.GlobalBindingId) !b.Slot {
        if (self.bindings.get(id)) |slot_id| return slot_id;
        const slot_id = try self.newSlot(self.parent.graph.binding(id).ty);
        try self.bindings.put(self.parent.allocator, id, slot_id);
        if (self.parent.cleanup_bindings[@intFromEnum(id)]) try self.drops.put(self.parent.allocator, id, try self.buildDrop(self.parent.graph.binding(id).ty, .{ .root = slot_id, .path = &.{} }));
        return slot_id;
    }
    fn emit(self: *FunctionLower, source: p.SourceRef, op: @FieldType(b.Instruction, "op")) !u32 {
        const pc: u32 = @intCast(self.code.items.len);
        try self.code.append(self.parent.allocator, .{ .source = source, .op = op });
        return pc;
    }
    fn position(self: *FunctionLower) u32 {
        return @intCast(self.code.items.len);
    }
    fn block(self: *FunctionLower, id: g.GlobalBlockId) anyerror!void {
        const block_ = self.parent.graph.blocks.items[@intFromEnum(id)];
        for (self.parent.graph.node_refs.items[block_.nodes.start..][0..block_.nodes.len]) |node| try self.statement(node);
    }
    fn statement(self: *FunctionLower, id: g.GlobalNodeId) anyerror!void {
        const node = self.parent.graph.node(id);
        self.parent.source = node.source;
        switch (node.content) {
            .binding_declaration => |binding_id| {
                const binding_ = self.parent.graph.binding(binding_id);
                if (self.parent.sessionIndex(binding_id)) |index| {
                    if (binding_.deferred_initialization) return self.parent.reject(node.source, "deferred session publication requires vacant binding plans");
                    const initializer = binding_.initialization orelse return self.parent.reject(node.source, "session declaration without initialization");
                    const value = try self.coerce(node.source, try self.expression(initializer), binding_.ty);
                    _ = try self.emit(node.source, .{ .session_initialize = .{ .binding = index, .value = value } });
                    if (self.drops.get(binding_id)) |drop| try self.setDrop(drop, true);
                    return;
                }
                const dst = try self.bindingSlot(binding_id);
                if (!binding_.deferred_initialization) {
                    if (binding_.initialization) |value| {
                        try self.copyTo(node.source, dst, try self.expression(value));
                        if (self.drops.get(binding_id)) |drop| try self.setDrop(drop, true);
                    }
                }
            },
            .assignment => |x| {
                if (self.parent.sessionIndex(x.binding)) |index| {
                    const ty = self.parent.graph.binding(x.binding).ty;
                    if (self.parent.cleanup_types[@intFromEnum(ty)]) return self.parent.reject(node.source, "session owner replacement requires a checked cleanup plan");
                    const destination = try self.captureWrite(node.source, .{ .root = index, .region = .session, .path = &.{} }, ty, false);
                    const value = try self.coerce(node.source, try self.expression(x.value), ty);
                    try self.commitWrite(node.source, destination, value);
                    return;
                }
                const dst = self.bindings.get(x.binding) orelse return self.parent.reject(node.source, "global or captured storage");
                try self.copyTo(node.source, dst, try self.expression(x.value));
                if (self.drops.get(x.binding)) |drop| try self.setDrop(drop, true);
            },
            .array_store => |x| {
                if (self.parent.cleanup_types[@intFromEnum(x.element_type)])
                    return self.parent.reject(node.source, "owning replacement in indexed storage");
                const base = try self.place(x.array_ptr);
                const index = try self.expression(x.index);
                const target = try self.project(base, .{ .element = index });
                const destination = try self.captureWrite(node.source, target, x.element_type, false);
                const value = try self.coerce(node.source, try self.expression(x.value), x.element_type);
                try self.commitWrite(node.source, destination, value);
            },
            .pointer_assignment => |x| {
                const child = self.parent.graph.semanticType(self.parent.graph.node(x.pointer).ty.?).pointer.child;
                if (self.parent.cleanup_types[@intFromEnum(child)] and x.checked_initialization != true and !self.trackedDestination(x.pointer, x.cleanup_target))
                    return self.parent.reject(node.source, "owning replacement through a runtime reference");
                const target = try self.addressedPlace(x.pointer);
                const destination = try self.captureWrite(node.source, target, child, self.targetHasCleanup(x.cleanup_target) or
                    (x.checked_initialization == true and self.parent.cleanup_types[@intFromEnum(child)]));
                const value = try self.coerce(node.source, try self.expression(x.value), self.parent.graph.semanticType(self.parent.graph.node(x.pointer).ty.?).pointer.child);
                try self.commitWrite(node.source, destination, value);
            },
            .struct_field_store => |x| {
                if (self.parent.cleanup_types[@intFromEnum(x.field_type)] and !self.trackedDestination(x.struct_ptr, x.cleanup_target))
                    return self.parent.reject(node.source, "owning replacement through a runtime reference");
                const base = try self.addressedPlace(x.struct_ptr);
                const target = try self.project(base, .{ .field = x.field_index });
                const destination = try self.captureWrite(node.source, target, x.field_type, self.targetHasCleanup(x.cleanup_target));
                const value = try self.coerce(node.source, try self.expression(x.value), x.field_type);
                try self.commitWrite(node.source, destination, value);
            },
            .auto_deinit_binding => |auto| try self.autoDeinit(auto),
            .code_block => |block_id| try self.block(block_id),
            .replacement => {
                const plan = try @import("../../4_semantics/global/replacement.zig").plan(self.parent.graph, id);
                try self.block(plan.block);
            },
            .return_statement => |x| {
                if (x.expression != null) return self.parent.reject(node.source, "explicit return expression");
                for (self.parent.graph.node_refs.items[x.cleanup.start..][0..x.cleanup.len]) |cleanup| try self.statement(cleanup);
                _ = try self.emit(node.source, .{ .ret = self.outputs });
            },
            .if_statement => |x| {
                const condition = try self.expression(x.condition);
                const branch = try self.emit(node.source, .{ .branch = .{ .condition = condition, .yes = 0, .no = 0 } });
                const yes = self.position();
                try self.block(x.then_block);
                const end = try self.emit(node.source, .{ .jump = 0 });
                const no = self.position();
                if (x.else_block) |other| try self.block(other);
                self.code.items[branch].op.branch.yes = yes;
                self.code.items[branch].op.branch.no = no;
                self.code.items[end].op.jump = self.position();
            },
            .switch_statement => |switch_id| try self.matchStatement(switch_id, node.source),
            .while_statement => |x| try self.loop(x.condition, x.body, null, node.source),
            .for_statement => |x| {
                if (x.init) |init| try self.statement(init);
                try self.loop(x.condition, x.body, x.increment, node.source);
            },
            .break_statement => {
                if (self.loops.items.len == 0) return error.InvalidBytecode;
                const jump = try self.emit(node.source, .{ .jump = 0 });
                try self.loops.items[self.loops.items.len - 1].breaks.append(self.parent.allocator, jump);
            },
            .continue_statement => {
                if (self.loops.items.len == 0) return error.InvalidBytecode;
                const jump = try self.emit(node.source, .{ .jump = 0 });
                try self.loops.items[self.loops.items.len - 1].continues.append(self.parent.allocator, jump);
            },
            .abort_statement => {
                _ = try self.emit(node.source, .abort_);
            },
            .function_call => {
                _ = try self.call(id);
            },
            else => {
                _ = try self.expression(id);
            },
        }
    }
    fn loop(self: *FunctionLower, condition_node: g.GlobalNodeId, body: g.GlobalBlockId, increment: ?g.GlobalNodeId, source: p.SourceRef) anyerror!void {
        const start = self.position();
        const condition = try self.expression(condition_node);
        const branch = try self.emit(source, .{ .branch = .{ .condition = condition, .yes = self.position() + 1, .no = 0 } });
        try self.loops.append(self.parent.allocator, .{});
        // Retain loop patch lists even if nested lowering fails.
        defer {
            var current = self.loops.pop().?;
            current.breaks.deinit(self.parent.allocator);
            current.continues.deinit(self.parent.allocator);
        }
        try self.block(body);
        const next = self.position();
        if (increment) |node| try self.statement(node);
        _ = try self.emit(source, .{ .jump = start });
        const end = self.position();
        const current = self.loops.items[self.loops.items.len - 1];
        for (current.breaks.items) |jump| self.code.items[jump].op.jump = end;
        for (current.continues.items) |jump| self.code.items[jump].op.jump = if (increment != null) next else start;
        self.code.items[branch].op.branch.no = end;
    }
    fn matchStatement(self: *FunctionLower, id: g.GlobalSwitchId, source: p.SourceRef) anyerror!void {
        const sw = self.parent.graph.switches.items[@intFromEnum(id)];
        const cases = self.parent.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len];
        var borrowed = false;
        for (cases) |case| if (case.payload_mode == .borrow or case.payload_mode == .mut_borrow) {
            borrowed = true;
        };
        const target: ?b.Place = if (borrowed) try self.place(sw.expression) else null;
        const value = if (target) |place_| blk: {
            const slot = try self.newSlot(self.parent.graph.node(sw.expression).ty.?);
            _ = try self.emit(source, .{ .load = .{ .dst = slot, .place = place_ } });
            break :blk slot;
        } else try self.expression(sw.expression);
        var ends: std.ArrayList(u32) = .empty;
        defer ends.deinit(self.parent.allocator);
        for (cases) |case| {
            const branch = try self.emit(source, .{ .branch_variant = .{ .src = value, .variant = case.variant, .yes = self.position() + 1, .no = 0 } });
            if (case.payload_binding) |binding| {
                const dst = try self.bindingSlot(binding);
                switch (case.payload_mode) {
                    .borrow, .mut_borrow => {
                        const place_ = try self.project(target.?, .{ .variant = case.variant });
                        _ = try self.emit(source, .{ .borrow = .{ .dst = dst, .place = place_ } });
                    },
                    .value, .move => _ = try self.emit(source, .{ .payload = .{ .dst = dst, .src = value, .variant = case.variant } }),
                }
            }
            if (case.payload_binding) |binding| {
                if (case.payload_mode == .move) if (self.nodeDrop(sw.expression)) |drop| try self.setDrop(drop, false);
                if (self.drops.get(binding)) |drop| try self.setDrop(drop, true);
            }
            try self.block(case.body);
            try ends.append(self.parent.allocator, try self.emit(source, .{ .jump = 0 }));
            self.code.items[branch].op.branch_variant.no = self.position();
        }
        if (sw.default_block) |other| {
            try self.block(other);
        } else if (sw.exhaustive) {
            // Checked exhaustive switches cannot reach this path. An explicit
            // trap preserves definite-initialization facts without inventing a
            // fallthrough edge, and protects malformed runtime values.
            _ = try self.emit(source, .abort_);
        }
        for (ends.items) |jump| self.code.items[jump].op.jump = self.position();
    }
    fn coerce(self: *FunctionLower, source: p.SourceRef, slot: b.Slot, target: b.Type) !b.Slot {
        if (types.equal(self.parent.graph, self.slots.items[slot], target)) return slot;
        const from = self.parent.graph.semanticType(self.slots.items[slot]);
        const to = self.parent.graph.semanticType(target);
        if (from == .pointer and to == .pointer and from.pointer.mutability == .read_write and to.pointer.mutability == .read_only and types.equal(self.parent.graph, from.pointer.child, to.pointer.child)) {
            const dst = try self.newSlot(target);
            _ = try self.emit(source, .{ .readonly = .{ .dst = dst, .src = slot } });
            return dst;
        }
        return self.parent.reject(source, "conversion outside the supported VM subset");
    }
    fn copyTo(self: *FunctionLower, source: p.SourceRef, dst: b.Slot, value: b.Slot) !void {
        const src = try self.coerce(source, value, self.slots.items[dst]);
        _ = try self.emit(source, .{ .copy = .{ .dst = dst, .src = src } });
    }
    fn targetHasCleanup(self: *FunctionLower, target: ?g.GlobalNodeId) bool {
        return if (target) |node| self.nodeDrop(node) != null else false;
    }
    fn commitWrite(self: *FunctionLower, source: p.SourceRef, destination: b.Destination, value: b.Slot) !void {
        _ = try self.emit(source, .{ .check_write_cleanup = destination });
        _ = try self.emit(source, .{ .store = .{ .destination = destination, .value = value } });
        _ = try self.emit(source, .{ .activate_write_cleanup = destination });
    }
    fn captureWrite(self: *FunctionLower, source: p.SourceRef, place_: b.Place, ty: b.Type, activate_cleanup: bool) !b.Destination {
        const destination: b.Destination = @intCast(self.write_destinations.items.len);
        try self.write_destinations.append(self.parent.allocator, ty);
        _ = try self.emit(source, .{ .capture_write = .{ .dst = destination, .place = place_, .activate_cleanup = activate_cleanup } });
        return destination;
    }
    fn addressedPlace(self: *FunctionLower, id: g.GlobalNodeId) anyerror!b.Place {
        const node = self.parent.graph.node(id);
        if (node.content == .address_of) return self.place(node.content.address_of);
        return self.project(.{ .root = try self.expression(id), .path = &.{} }, .dereference);
    }
    fn project(self: *FunctionLower, base: b.Place, projection: b.Projection) !b.Place {
        if (base.path.len >= 64) return self.parent.reject(self.parent.source, "storage projection depth");
        const path = try self.parent.allocator.alloc(b.Projection, base.path.len + 1);
        @memcpy(path[0..base.path.len], base.path);
        path[base.path.len] = projection;
        return .{ .root = base.root, .region = base.region, .path = path };
    }
    // Resolve storage syntactically, without evaluating it into a copied value.
    // Address operations retain storage identity. Intermediate array bounds are checked
    // before later indices or the RHS, matching native address evaluation.
    fn place(self: *FunctionLower, id: g.GlobalNodeId) anyerror!b.Place {
        const node = self.parent.graph.node(id);
        self.parent.source = node.source;
        return switch (node.content) {
            .binding_use => |binding| if (self.parent.sessionIndex(binding)) |index|
                .{ .root = index, .region = .session, .path = &.{} }
            else
                .{ .root = self.bindings.get(binding) orelse return self.parent.reject(node.source, "global or captured storage"), .path = &.{} },
            .address_of => |value| self.place(value),
            .dereference => |x| self.project(.{ .root = try self.expression(x.pointer), .path = &.{} }, .dereference),
            .struct_field_access => |x| self.project(try self.place(x.value), .{ .field = x.field_index }),
            .choice_payload_access => |x| self.project(try self.place(x.value), .{ .variant = x.variant }),
            .array_index => |x| blk: {
                const base = try self.place(x.array_ptr);
                const index = try self.expression(x.index);
                const target = try self.project(base, .{ .element = index });
                _ = try self.emit(node.source, .{ .check_place = target });
                break :blk target;
            },
            else => self.parent.reject(node.source, "write through unsupported storage"),
        };
    }
    fn updateCallCleanup(self: *FunctionLower, node: g.GlobalNodeId, enabled: bool, fields: p.Range(g.GlobalValueFieldId), args: []const b.Slot) !void {
        // Use the evaluated argument snapshot, never reevaluate an expression
        // after the call or update the slot containing a reference.
        if (self.parent.graph.node(node).ty) |ty| {
            const semantic = self.parent.graph.semanticType(ty);
            if (semantic == .pointer and self.parent.cleanup_types[@intFromEnum(semantic.pointer.child)]) {
                for (self.parent.graph.value_fields.items[fields.start..][0..fields.len], args) |field, slot| {
                    if (field.value != node) continue;
                    const target = try self.project(.{ .root = slot, .path = &.{} }, .dereference);
                    _ = try self.emit(self.parent.source, .{ .cleanup_set = .{ .place = target, .enabled = enabled } });
                    return;
                }
            }
        }
        if (self.nodeDrop(node)) |drop| try self.setDrop(drop, enabled);
    }
    fn call(self: *FunctionLower, id: g.GlobalNodeId) anyerror!?b.Slot {
        const node = self.parent.graph.node(id);
        const x = node.content.function_call;
        if (x.callee_value != null) return self.parent.reject(node.source, "indirect call");
        const input = self.parent.graph.node(x.input).content;
        if (input != .struct_value_literal) return self.parent.reject(node.source, "non-record call arguments");
        const fields = input.struct_value_literal.fields;
        const args = try self.parent.allocator.alloc(b.Slot, fields.len);
        const f = self.parent.graph.function(x.callee);
        for (args, self.parent.graph.value_fields.items[fields.start..][0..fields.len], 0..) |*arg, field, index| arg.* = try self.coerce(node.source, try self.expression(field.value), self.parent.graph.fields.items[f.input.start + index].ty);
        const outputs = try self.parent.allocator.alloc(b.Slot, f.output.len);
        for (outputs, self.parent.graph.fields.items[f.output.start..][0..f.output.len]) |*slot, field| slot.* = try self.newSlot(field.ty);
        try self.parent.pending.append(self.parent.allocator, x.callee);
        _ = try self.emit(node.source, .{ .call = .{ .outputs = outputs, .function = x.callee, .args = args } });
        if (x.consumes_auto_deinit) |value| try self.updateCallCleanup(value, false, fields, args);
        for (x.consumed_auto_deinits) |value| try self.updateCallCleanup(value, false, fields, args);
        for (x.initialized_auto_deinits) |value| try self.updateCallCleanup(value, true, fields, args);
        for (x.outcome_cleanups) |cleanup| {
            const drop = self.nodeDrop(cleanup.place) orelse continue;
            var path = try cleanup_plan.OutcomePath.init(self.parent.graph, f.output, cleanup);
            var value = outputs[cleanup.output_index];
            var branches: std.ArrayList(u32) = .empty;
            defer branches.deinit(self.parent.allocator);
            while (try path.next()) |step| {
                const variant = step.variant;
                try branches.append(self.parent.allocator, try self.emit(node.source, .{ .branch_variant = .{ .src = value, .variant = variant, .yes = self.position() + 1, .no = 0 } }));
                if (step.payload) |payload| {
                    const child = try self.newSlot(payload);
                    _ = try self.emit(node.source, .{ .payload = .{ .dst = child, .src = value, .variant = variant } });
                    value = child;
                }
            }
            try self.setDrop(drop, cleanup.enabled);
            for (branches.items) |branch| self.code.items[branch].op.branch_variant.no = self.position();
        }
        if (x.initializes_auto_deinit) |value| try self.updateCallCleanup(value, true, fields, args);
        if (outputs.len == 0) return null;
        if (outputs.len == 1) return outputs[0];
        const result = try self.newSlot(node.ty orelse return self.parent.reject(node.source, "untyped call result"));
        _ = try self.emit(node.source, .{ .record = .{ .dst = result, .fields = outputs } });
        return result;
    }
    fn expression(self: *FunctionLower, id: g.GlobalNodeId) anyerror!b.Slot {
        for (self.precomputed) |operand| if (operand.node == id) return operand.slot;
        const node = self.parent.graph.node(id);
        self.parent.source = node.source;
        if (node.content == .binding_use) {
            if (self.parent.sessionIndex(node.content.binding_use)) |index| {
                const dst = try self.newSlot(node.ty orelse return error.InvalidBytecode);
                _ = try self.emit(node.source, .{ .load = .{ .dst = dst, .place = .{ .root = index, .region = .session, .path = &.{} } } });
                return dst;
            }
            const src = self.bindings.get(node.content.binding_use) orelse return self.parent.reject(node.source, "global or captured storage");
            const dst = try self.newSlot(self.slots.items[src]);
            _ = try self.emit(node.source, .{ .copy = .{ .dst = dst, .src = src } });
            return dst;
        }
        if (node.content == .move_value) {
            const value = try self.expression(node.content.move_value);
            if (self.nodeDrop(node.content.move_value)) |drop| try self.setDrop(drop, false);
            return value;
        }
        if (node.content == .function_call) return (try self.call(id)) orelse self.parent.reject(node.source, "void expression");
        if (node.content == .value_sequence or node.content == .replacement) {
            const block_id = if (node.content == .replacement)
                (try @import("../../4_semantics/global/replacement.zig").plan(self.parent.graph, id)).block
            else
                node.content.value_sequence;
            const block_ = self.parent.graph.blocks.items[@intFromEnum(block_id)];
            const result_node = block_.ret_val orelse return self.parent.reject(node.source, "sequence without result");
            var result: ?b.Slot = null;
            for (self.parent.graph.node_refs.items[block_.nodes.start..][0..block_.nodes.len]) |child| {
                if (child == result_node) result = try self.expression(child) else try self.statement(child);
            }
            return result orelse try self.expression(result_node);
        }
        const dst = try self.newSlot(node.ty orelse return self.parent.reject(node.source, "untyped expression"));
        switch (node.content) {
            .address_of => |value| {
                const target = try self.place(value);
                _ = try self.emit(node.source, .{ .borrow = .{ .dst = dst, .place = target } });
            },
            .dereference => |x| {
                const pointer = try self.expression(x.pointer);
                const target = try self.project(.{ .root = pointer, .path = &.{} }, .dereference);
                _ = try self.emit(node.source, .{ .load = .{ .dst = dst, .place = target } });
            },
            .choice_literal => |x| {
                const payload = if (x.payload) |value| try self.coerce(node.source, try self.expression(value), self.parent.graph.variants.items[@intFromEnum(x.variant)].payload_type.?) else null;
                _ = try self.emit(node.source, .{ .choice = .{ .dst = dst, .variant = x.variant, .payload = payload } });
            },
            .choice_payload_access => |x| {
                _ = try self.emit(node.source, .{ .payload = .{ .dst = dst, .src = try self.expression(x.value), .variant = x.variant } });
            },
            .int_literal => |value| {
                _ = try self.emit(node.source, .{ .constant = .{ .dst = dst, .value = .{ .integer = value } } });
            },
            .bool_literal => |value| {
                _ = try self.emit(node.source, .{ .constant = .{ .dst = dst, .value = .{ .boolean = value } } });
            },
            .struct_value_literal => |x| {
                const ty = self.parent.graph.semanticType(self.slots.items[dst]);
                if (ty == .builtin and ty.builtin == .Void) {
                    _ = try self.emit(node.source, .{ .constant = .{ .dst = dst, .value = .unit } });
                    return dst;
                }
                const fields = try self.parent.allocator.alloc(b.Slot, x.fields.len);
                const expected = types.fields(self.parent.graph, self.slots.items[dst]).?;
                for (fields, self.parent.graph.value_fields.items[x.fields.start..][0..x.fields.len], 0..) |*field, value, index| field.* = try self.coerce(node.source, try self.expression(value.value), self.parent.graph.fields.items[expected.start + index].ty);
                _ = try self.emit(node.source, .{ .record = .{ .dst = dst, .fields = fields } });
            },
            .array_literal => |x| {
                const elements = try self.parent.allocator.alloc(b.Slot, x.elements.len);
                for (elements, self.parent.graph.node_refs.items[x.elements.start..][0..x.elements.len]) |*element, value| element.* = try self.coerce(node.source, try self.expression(value), x.element_type);
                _ = try self.emit(node.source, .{ .array = .{ .dst = dst, .elements = elements } });
            },
            .array_index => |x| {
                const target = self.parent.graph.node(x.array_ptr);
                const base = try self.expression(if (target.content == .address_of) target.content.address_of else x.array_ptr);
                const index = try self.expression(x.index);
                _ = try self.emit(node.source, .{ .index = .{ .dst = dst, .base = base, .index = index } });
            },
            .struct_field_access => |x| {
                _ = try self.emit(node.source, .{ .field = .{ .dst = dst, .base = try self.expression(x.value), .index = x.field_index } });
            },
            .binary_operation => |x| {
                _ = try self.emit(node.source, .{ .binary = .{ .dst = dst, .left = try self.expression(x.left), .right = try self.expression(x.right), .operator = x.operator } });
            },
            .comparison => |x| {
                const left = try self.expression(x.left);
                const right = self.parent.graph.node(x.right);
                if (types.variants(self.parent.graph, self.slots.items[left])) |variants| {
                    if (right.content == .int_literal and (x.operator == .equal or x.operator == .not_equal)) {
                        const tag = right.content.int_literal;
                        if (tag < 0 or tag >= variants.len) return self.parent.reject(node.source, "choice comparison tag");
                        _ = try self.emit(node.source, .{ .is_variant = .{ .dst = dst, .src = left, .variant = @enumFromInt(variants.start + @as(u32, @intCast(tag))), .invert = x.operator == .not_equal } });
                        return dst;
                    }
                }
                _ = try self.emit(node.source, .{ .compare = .{ .dst = dst, .left = left, .right = try self.expression(x.right), .operator = x.operator } });
            },
            .logical_operation => |x| {
                const left = try self.expression(x.left);
                _ = try self.emit(node.source, .{ .copy = .{ .dst = dst, .src = left } });
                const branch = try self.emit(node.source, .{ .branch = .{ .condition = left, .yes = 0, .no = 0 } });
                const evaluate = self.position();
                _ = try self.emit(node.source, .{ .copy = .{ .dst = dst, .src = try self.expression(x.right) } });
                self.code.items[branch].op.branch.yes = if (x.operator == .and_) evaluate else self.position();
                self.code.items[branch].op.branch.no = if (x.operator == .and_) self.position() else evaluate;
            },
            else => return self.parent.reject(node.source, @tagName(node.content)),
        }
        return dst;
    }
};

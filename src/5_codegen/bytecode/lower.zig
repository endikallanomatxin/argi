const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const p = @import("../../4_semantics/primitives/schema.zig");
const b = @import("bytecode.zig");
const types = @import("../../4_semantics/global/types.zig");
const standard_contracts = @import("../../4_semantics/global/standard_contracts.zig");

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

    pub fn init(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) !Lower {
        const functions = try a.alloc(?b.Function, graph.functions.items.len);
        @memset(functions, null);
        const cleanup_bindings = try a.alloc(bool, graph.bindings.items.len);
        @memset(cleanup_bindings, false);
        for (graph.auto_deinits.items) |auto| cleanup_bindings[@intFromEnum(auto.binding)] = true;
        const cleanup_types = try a.alloc(bool, graph.types.items.len);
        @memset(cleanup_types, false);
        if (standard_contracts.standardDeclaration(graph, "Deinit")) |deinit| {
            for (graph.contract_conformances.items) |conformance| {
                if (conformance.declaration != deinit or conformance.participants.len == 0) continue;
                const participant = graph.generic_arguments.items[conformance.participants.start].value;
                if (participant == .type and graph.semanticType(participant.type) != .pointer)
                    cleanup_types[@intFromEnum(participant.type)] = true;
            }
        }
        // Read selected frontend evidence and structural ownership. This is
        // only a lowering boundary check, never another conformance resolver.
        var changed = true;
        while (changed) {
            changed = false;
            for (graph.types.items, 0..) |_, index| {
                if (cleanup_types[index]) continue;
                const ty: b.Type = @enumFromInt(index);
                if (graph.semanticType(ty) == .pointer) continue;
                var owns_cleanup = false;
                if (types.arrayElement(graph, ty)) |element| {
                    owns_cleanup = cleanup_types[@intFromEnum(element)];
                } else if (types.fields(graph, ty)) |fields| {
                    for (graph.fields.items[fields.start..][0..fields.len]) |field| {
                        if (cleanup_types[@intFromEnum(field.ty)]) {
                            owns_cleanup = true;
                            break;
                        }
                    }
                } else if (types.variants(graph, ty)) |variants| {
                    for (graph.variants.items[variants.start..][0..variants.len]) |variant| {
                        if (variant.payload_type) |payload| if (cleanup_types[@intFromEnum(payload)]) {
                            owns_cleanup = true;
                            break;
                        };
                    }
                }
                if (owns_cleanup) {
                    cleanup_types[index] = true;
                    changed = true;
                }
            }
        }
        const bool_type: ?b.Type = for (graph.types.items, 0..) |ty, i| {
            if (ty == .builtin and ty.builtin == .Bool) break @as(b.Type, @enumFromInt(i));
        } else null;
        return .{ .allocator = a, .graph = graph, .functions = functions, .cleanup_bindings = cleanup_bindings, .cleanup_types = cleanup_types, .bool_type = bool_type };
    }
    // All bytecode allocations belong to the caller's compilation arena.
    pub fn compile(self: *Lower, entry: g.GlobalFunctionId) !b.Program {
        try self.pending.append(self.allocator, entry);
        defer self.pending.deinit(self.allocator);
        while (self.pending.pop()) |id| {
            if (self.functions[@intFromEnum(id)] != null) continue;
            var f = FunctionLower{ .parent = self };
            self.functions[@intFromEnum(id)] = try f.compile(id);
        }
        const program = b.Program{ .graph = self.graph, .functions = self.functions };
        try b.verify(self.allocator, program);
        return program;
    }
    fn reject(self: *Lower, source: p.SourceRef, name: []const u8) error{UnsupportedExecution} {
        self.source = source;
        self.unsupported = name;
        return error.UnsupportedExecution;
    }
};

const Loop = struct { breaks: std.ArrayList(u32) = .empty, continues: std.ArrayList(u32) = .empty };
const DropState = struct { flag: b.Slot, fields: []const DropState = &.{} };
const FunctionLower = struct {
    parent: *Lower,
    slots: std.ArrayList(b.Type) = .empty,
    code: std.ArrayList(b.Instruction) = .empty,
    bindings: std.AutoHashMapUnmanaged(g.GlobalBindingId, b.Slot) = .empty,
    outputs: []const b.Slot = &.{},
    drops: std.AutoHashMapUnmanaged(g.GlobalBindingId, DropState) = .empty,
    drop_flags: std.ArrayList(b.Slot) = .empty,
    loops: std.ArrayList(Loop) = .empty,

    fn compile(self: *FunctionLower, id: g.GlobalFunctionId) !b.Function {
        const a = self.parent.allocator;
        defer self.bindings.deinit(a);
        defer self.drops.deinit(a);
        defer self.drop_flags.deinit(a);
        defer self.loops.deinit(a);
        const f = self.parent.graph.function(id);
        const source = self.parent.graph.declaration(f.declaration).source;
        self.parent.source = source;
        if (f.body == null or f.flags.is_c_abi or f.flags.is_once) return self.parent.reject(source, "foreign or once function");
        const inputs = try a.alloc(b.Slot, f.input_bindings.len);
        for (inputs, self.parent.graph.binding_refs.items[f.input_bindings.start..][0..f.input_bindings.len]) |*slot, binding| {
            slot.* = try self.bindingSlot(binding);
            if (self.drops.get(binding)) |drop| try self.setDrop(drop, true);
        }
        const outputs = try a.alloc(b.Slot, f.output_bindings.len);
        self.outputs = outputs;
        for (outputs, self.parent.graph.binding_refs.items[f.output_bindings.start..][0..f.output_bindings.len]) |*slot, binding| {
            slot.* = try self.bindingSlot(binding);
            const record = self.parent.graph.binding(binding);
            if (record.initialization) |node| {
                try self.copyTo(source, slot.*, try self.expression(node));
                if (self.drops.get(binding)) |drop| try self.setDrop(drop, true);
            }
        }
        try self.block(f.body.?);
        _ = try self.emit(source, .{ .ret = outputs });
        // Flags are entry storage, including bindings first encountered in a branch.
        // Initialize them in a prologue so every CFG join has defined state.
        const prefix: u32 = @intCast(self.drop_flags.items.len);
        const code = try a.alloc(b.Instruction, prefix + self.code.items.len);
        for (self.drop_flags.items, 0..) |flag, i| code[i] = .{ .source = source, .op = .{ .constant = .{ .dst = flag, .value = .{ .boolean = false } } } };
        for (self.code.items, code[prefix..]) |instruction, *out| {
            out.* = instruction;
            switch (out.op) {
                .jump => |*pc| pc.* += prefix,
                .branch => |*branch| {
                    branch.yes += prefix;
                    branch.no += prefix;
                },
                .branch_variant => |*branch| {
                    branch.yes += prefix;
                    branch.no += prefix;
                },
                else => {},
            }
        }
        self.code.deinit(a);
        return .{ .slots = try self.slots.toOwnedSlice(a), .inputs = inputs, .outputs = outputs, .code = code };
    }
    fn boolType(self: *FunctionLower) !b.Type {
        return self.parent.bool_type orelse error.InvalidBytecode;
    }
    fn buildDrop(self: *FunctionLower, ty: b.Type) anyerror!DropState {
        var drop = DropState{ .flag = try self.newSlot(try self.boolType()) };
        try self.drop_flags.append(self.parent.allocator, drop.flag);
        if (types.variants(self.parent.graph, ty)) |range| {
            const children = try self.parent.allocator.alloc(DropState, range.len);
            for (children, self.parent.graph.variants.items[range.start..][0..range.len]) |*child, variant| child.* = try self.buildDrop(variant.payload_type orelse try self.boolType());
            drop.fields = children;
        } else if (types.fields(self.parent.graph, ty)) |range| {
            const children = try self.parent.allocator.alloc(DropState, range.len);
            for (children, self.parent.graph.fields.items[range.start..][0..range.len]) |*child, field| child.* = try self.buildDrop(field.ty);
            drop.fields = children;
        }
        return drop;
    }
    fn setDrop(self: *FunctionLower, drop: DropState, enabled: bool) anyerror!void {
        _ = try self.emit(self.parent.source, .{ .constant = .{ .dst = drop.flag, .value = .{ .boolean = enabled } } });
        for (drop.fields) |child| try self.setDrop(child, enabled);
    }
    fn nodeDrop(self: *FunctionLower, id: g.GlobalNodeId) ?DropState {
        return switch (self.parent.graph.node(id).content) {
            .binding_use => |binding| self.drops.get(binding),
            .address_of => |value| self.nodeDrop(value),
            .dereference => |value| self.nodeDrop(value.pointer),
            .struct_field_access => |value| blk: {
                const parent = self.nodeDrop(value.value) orelse break :blk null;
                break :blk if (value.field_index < parent.fields.len) parent.fields[value.field_index] else null;
            },
            .choice_payload_access => |value| blk: {
                const parent = self.nodeDrop(value.value) orelse break :blk null;
                const range = types.variants(self.parent.graph, self.parent.graph.node(value.value).ty.?) orelse break :blk null;
                const index = @intFromEnum(value.variant) - range.start;
                break :blk if (index < parent.fields.len) parent.fields[index] else null;
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
        const root = self.bindings.get(auto.binding) orelse return error.InvalidBytecode;
        try self.cleanupStorage(auto.deinit_fn, auto.input, auto.self_field_index, auto.fields, .{ .root = root, .path = &.{} }, self.slots.items[root], self.drops.get(auto.binding).?);
    }
    fn cleanupStorage(self: *FunctionLower, callee: ?g.GlobalFunctionId, input: ?g.GlobalNodeId, self_index: u32, fields: p.Range(g.GlobalAutoDeinitFieldId), target: b.Place, ty: b.Type, drop: DropState) anyerror!void {
        const source = self.parent.source;
        const branch = try self.emit(source, .{ .branch = .{ .condition = drop.flag, .yes = self.position() + 1, .no = 0 } });
        if (callee) |id| {
            const function = self.parent.graph.function(id);
            if (function.output.len != 0) return self.parent.reject(source, "destructor with outputs");
            const args = try self.parent.allocator.alloc(b.Slot, function.input.len);
            for (args, self.parent.graph.fields.items[function.input.start..][0..function.input.len], 0..) |*arg, field, index| {
                if (index == self_index) {
                    arg.* = try self.newSlot(field.ty);
                    _ = try self.emit(source, .{ .borrow = .{ .dst = arg.*, .place = target } });
                } else {
                    var value = field.default_value;
                    if (input) |node| {
                        const content = self.parent.graph.node(node).content;
                        if (content == .struct_value_literal) for (self.parent.graph.value_fields.items[content.struct_value_literal.fields.start..][0..content.struct_value_literal.fields.len]) |supplied| {
                            if (std.mem.eql(u8, self.parent.graph.text(supplied.name), self.parent.graph.text(field.name))) {
                                value = supplied.value;
                                break;
                            }
                        };
                    }
                    arg.* = try self.coerce(source, try self.expression(value orelse return error.InvalidBytecode), field.ty);
                }
            }
            try self.parent.pending.append(self.parent.allocator, id);
            _ = try self.emit(source, .{ .call = .{ .function = id, .args = args, .outputs = &.{} } });
        } else for (self.parent.graph.auto_deinit_fields.items[fields.start..][0..fields.len]) |field| {
            if (field.field_index >= drop.fields.len) return error.InvalidBytecode;
            if (field.is_variant) {
                const range = types.variants(self.parent.graph, ty) orelse return error.InvalidBytecode;
                const variant: g.GlobalVariantId = @enumFromInt(range.start + field.field_index);
                const value = try self.newSlot(ty);
                _ = try self.emit(source, .{ .load = .{ .dst = value, .place = target } });
                const active = try self.emit(source, .{ .branch_variant = .{ .src = value, .variant = variant, .yes = self.position() + 1, .no = 0 } });
                try self.cleanupStorage(field.deinit_fn, field.input, field.self_field_index, field.fields, try self.project(target, .{ .variant = variant }), self.parent.graph.variants.items[@intFromEnum(variant)].payload_type.?, drop.fields[field.field_index]);
                self.code.items[active].op.branch_variant.no = self.position();
            } else {
                const range = types.fields(self.parent.graph, ty) orelse return error.InvalidBytecode;
                try self.cleanupStorage(field.deinit_fn, field.input, field.self_field_index, field.fields, try self.project(target, .{ .field = field.field_index }), self.parent.graph.fields.items[range.start + field.field_index].ty, drop.fields[field.field_index]);
            }
        }
        try self.setDrop(drop, false);
        self.code.items[branch].op.branch.no = self.position();
    }
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
        if (self.parent.cleanup_bindings[@intFromEnum(id)]) try self.drops.put(self.parent.allocator, id, try self.buildDrop(self.parent.graph.binding(id).ty));
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
                const dst = try self.bindingSlot(binding_id);
                if (!binding_.deferred_initialization) {
                    if (binding_.initialization) |value| {
                        try self.copyTo(node.source, dst, try self.expression(value));
                        if (self.drops.get(binding_id)) |drop| try self.setDrop(drop, true);
                    }
                }
            },
            .assignment => |x| {
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
                _ = try self.emit(node.source, .{ .check_place = target });
                const value = try self.coerce(node.source, try self.expression(x.value), x.element_type);
                _ = try self.emit(node.source, .{ .store = .{ .place = target, .value = value } });
            },
            .pointer_assignment => |x| {
                const child = self.parent.graph.semanticType(self.parent.graph.node(x.pointer).ty.?).pointer.child;
                if (self.parent.cleanup_types[@intFromEnum(child)] and !self.trackedDestination(x.pointer, x.cleanup_target))
                    return self.parent.reject(node.source, "owning replacement through a runtime reference");
                const target = try self.addressedPlace(x.pointer);
                const value = try self.coerce(node.source, try self.expression(x.value), self.parent.graph.semanticType(self.parent.graph.node(x.pointer).ty.?).pointer.child);
                _ = try self.emit(node.source, .{ .store = .{ .place = target, .value = value } });
                if (self.nodeDrop(x.cleanup_target orelse x.pointer)) |drop| try self.setDrop(drop, true);
            },
            .struct_field_store => |x| {
                if (self.parent.cleanup_types[@intFromEnum(x.field_type)] and !self.trackedDestination(x.struct_ptr, x.cleanup_target))
                    return self.parent.reject(node.source, "owning replacement through a runtime reference");
                const base = try self.addressedPlace(x.struct_ptr);
                const target = try self.project(base, .{ .field = x.field_index });
                const value = try self.coerce(node.source, try self.expression(x.value), x.field_type);
                _ = try self.emit(node.source, .{ .store = .{ .place = target, .value = value } });
                if (x.cleanup_target) |destination| {
                    if (self.nodeDrop(destination)) |drop| try self.setDrop(drop, true);
                } else if (self.nodeDrop(x.struct_ptr)) |drop| if (x.field_index < drop.fields.len) try self.setDrop(drop.fields[x.field_index], true);
            },
            .auto_deinit_binding => |auto| try self.autoDeinit(auto),
            .code_block => |block_id| try self.block(block_id),
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
        return .{ .root = base.root, .path = path };
    }
    // Resolve storage syntactically, without evaluating it into a copied value.
    // Address operations retain storage identity. Intermediate array bounds are checked
    // before later indices or the RHS, matching native address evaluation.
    fn place(self: *FunctionLower, id: g.GlobalNodeId) anyerror!b.Place {
        const node = self.parent.graph.node(id);
        self.parent.source = node.source;
        return switch (node.content) {
            .binding_use => |binding| .{
                .root = self.bindings.get(binding) orelse return self.parent.reject(node.source, "global or captured storage"),
                .path = &.{},
            },
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
    fn call(self: *FunctionLower, id: g.GlobalNodeId) anyerror!?b.Slot {
        const node = self.parent.graph.node(id);
        const x = node.content.function_call;
        if (x.callee_value != null) return self.parent.reject(node.source, "indirect call");
        if (x.initialized_auto_deinits.len != 0 or x.initializes_auto_deinit != null)
            return self.parent.reject(node.source, "output storage initialization");
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
        if (x.consumes_auto_deinit) |value| if (self.nodeDrop(value)) |drop| try self.setDrop(drop, false);
        for (x.consumed_auto_deinits) |value| if (self.nodeDrop(value)) |drop| try self.setDrop(drop, false);
        for (x.outcome_cleanups) |cleanup| {
            const drop = self.nodeDrop(cleanup.place) orelse continue;
            if (cleanup.output_index >= outputs.len) return error.InvalidBytecode;
            var value = outputs[cleanup.output_index];
            var branches: std.ArrayList(u32) = .empty;
            defer branches.deinit(self.parent.allocator);
            for (0..cleanup.parent_variants.len + 1) |depth| {
                const index = if (depth < cleanup.parent_variants.len) cleanup.parent_variants[depth] else cleanup.variant_index;
                const range = types.variants(self.parent.graph, self.slots.items[value]) orelse return error.InvalidBytecode;
                if (index >= range.len) return error.InvalidBytecode;
                const variant: g.GlobalVariantId = @enumFromInt(range.start + index);
                try branches.append(self.parent.allocator, try self.emit(node.source, .{ .branch_variant = .{ .src = value, .variant = variant, .yes = self.position() + 1, .no = 0 } }));
                if (depth < cleanup.parent_variants.len) {
                    const child = try self.newSlot(self.parent.graph.variants.items[@intFromEnum(variant)].payload_type orelse return error.InvalidBytecode);
                    _ = try self.emit(node.source, .{ .payload = .{ .dst = child, .src = value, .variant = variant } });
                    value = child;
                }
            }
            try self.setDrop(drop, cleanup.enabled);
            for (branches.items) |branch| self.code.items[branch].op.branch_variant.no = self.position();
        }
        if (outputs.len == 0) return null;
        if (outputs.len == 1) return outputs[0];
        const result = try self.newSlot(node.ty orelse return self.parent.reject(node.source, "untyped call result"));
        _ = try self.emit(node.source, .{ .record = .{ .dst = result, .fields = outputs } });
        return result;
    }
    fn expression(self: *FunctionLower, id: g.GlobalNodeId) anyerror!b.Slot {
        const node = self.parent.graph.node(id);
        self.parent.source = node.source;
        if (node.content == .binding_use) {
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
        if (node.content == .value_sequence) {
            const block_ = self.parent.graph.blocks.items[@intFromEnum(node.content.value_sequence)];
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

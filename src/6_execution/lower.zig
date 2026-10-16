const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const b = @import("bytecode.zig");

pub const Lower = struct {
    allocator: std.mem.Allocator,
    graph: *const g.GlobalSemanticGraph,
    functions: []?b.Function,
    pending: std.ArrayList(g.GlobalFunctionId) = .empty,
    source: p.SourceRef = .{ .file_index = 0, .offset = 0 },
    unsupported: []const u8 = "",

    pub fn init(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph) !Lower {
        const functions = try a.alloc(?b.Function, graph.functions.items.len);
        @memset(functions, null);
        return .{ .allocator = a, .graph = graph, .functions = functions };
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

const Loop = struct { start: u32, breaks: std.ArrayList(u32) = .empty };
const FunctionLower = struct {
    parent: *Lower,
    slots: std.ArrayList(b.Type) = .empty,
    code: std.ArrayList(b.Instruction) = .empty,
    bindings: std.AutoHashMapUnmanaged(g.GlobalBindingId, b.Slot) = .empty,
    outputs: []const b.Slot = &.{},
    loops: std.ArrayList(Loop) = .empty,

    fn compile(self: *FunctionLower, id: g.GlobalFunctionId) !b.Function {
        const a = self.parent.allocator;
        defer self.bindings.deinit(a);
        defer self.loops.deinit(a);
        const f = self.parent.graph.function(id);
        const source = self.parent.graph.declaration(f.declaration).source;
        self.parent.source = source;
        if (f.body == null or f.flags.is_c_abi or f.flags.is_deinit or f.flags.is_once) return self.parent.reject(source, "foreign, lifecycle or once function");
        if (f.output.len > 1) return self.parent.reject(source, "multiple function outputs");
        const inputs = try a.alloc(b.Slot, f.input_bindings.len);
        for (inputs, self.parent.graph.binding_refs.items[f.input_bindings.start..][0..f.input_bindings.len]) |*slot, binding| slot.* = try self.bindingSlot(binding);
        const outputs = try a.alloc(b.Slot, f.output_bindings.len);
        self.outputs = outputs;
        for (outputs, self.parent.graph.binding_refs.items[f.output_bindings.start..][0..f.output_bindings.len]) |*slot, binding| {
            slot.* = try self.bindingSlot(binding);
            const record = self.parent.graph.binding(binding);
            if (record.initialization) |node| _ = try self.emit(source, .{ .copy = .{ .dst = slot.*, .src = try self.expression(node) } });
        }
        try self.block(f.body.?);
        _ = try self.emit(source, .{ .ret = outputs });
        return .{ .slots = try self.slots.toOwnedSlice(a), .inputs = inputs, .outputs = outputs, .code = try self.code.toOwnedSlice(a) };
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
                    if (binding_.initialization) |value| _ = try self.emit(node.source, .{ .copy = .{ .dst = dst, .src = try self.expression(value) } });
                }
            },
            .assignment => |x| {
                const dst = self.bindings.get(x.binding) orelse return self.parent.reject(node.source, "global or captured storage");
                _ = try self.emit(node.source, .{ .copy = .{ .dst = dst, .src = try self.expression(x.value) } });
            },
            .array_store => |x| {
                const base = try self.place(x.array_ptr);
                const index = try self.expression(x.index);
                const target = try self.project(base, .{ .element = index });
                const value = try self.expression(x.value);
                _ = try self.emit(node.source, .{ .store = .{ .place = target, .value = value } });
            },
            .pointer_assignment => |x| {
                const target = try self.place(x.pointer);
                const value = try self.expression(x.value);
                _ = try self.emit(node.source, .{ .store = .{ .place = target, .value = value } });
            },
            .struct_field_store => |x| {
                const base = try self.place(x.struct_ptr);
                const target = try self.project(base, .{ .field = x.field_index });
                const value = try self.expression(x.value);
                _ = try self.emit(node.source, .{ .store = .{ .place = target, .value = value } });
            },
            .code_block => |block_id| try self.block(block_id),
            .return_statement => |x| {
                if (x.expression != null) return self.parent.reject(node.source, "explicit return expression");
                if (x.cleanup.len != 0) return self.parent.reject(node.source, "cleanup");
                _ = try self.emit(node.source, .{ .ret = self.outputs });
            },
            .if_statement => |x| {
                if (x.choice_test != null) return self.parent.reject(node.source, "choice test");
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
            .while_statement => |x| {
                const start = self.position();
                const condition = try self.expression(x.condition);
                const branch = try self.emit(node.source, .{ .branch = .{ .condition = condition, .yes = self.position() + 1, .no = 0 } });
                try self.loops.append(self.parent.allocator, .{ .start = start });
                try self.block(x.body);
                _ = try self.emit(node.source, .{ .jump = start });
                var loop = self.loops.pop().?;
                defer loop.breaks.deinit(self.parent.allocator);
                for (loop.breaks.items) |jump| self.code.items[jump].op.jump = self.position();
                self.code.items[branch].op.branch.no = self.position();
            },
            .break_statement => {
                if (self.loops.items.len == 0) return error.InvalidBytecode;
                const jump = try self.emit(node.source, .{ .jump = 0 });
                try self.loops.items[self.loops.items.len - 1].breaks.append(self.parent.allocator, jump);
            },
            .continue_statement => {
                if (self.loops.items.len == 0) return error.InvalidBytecode;
                _ = try self.emit(node.source, .{ .jump = self.loops.items[self.loops.items.len - 1].start });
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
    fn project(self: *FunctionLower, base: b.Place, projection: b.Projection) !b.Place {
        if (base.path.len >= 64) return self.parent.reject(self.parent.source, "storage projection depth");
        const path = try self.parent.allocator.alloc(b.Projection, base.path.len + 1);
        @memcpy(path[0..base.path.len], base.path);
        path[base.path.len] = projection;
        return .{ .root = base.root, .path = path };
    }
    // Resolve storage syntactically, without evaluating it into a copied value.
    // Real references remain unsupported; address_of here only marks the checked
    // graph's direct local destination. Intermediate array bounds are checked
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
            .struct_field_access => |x| self.project(try self.place(x.value), .{ .field = x.field_index }),
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
        const input = self.parent.graph.node(x.input).content;
        if (input != .struct_value_literal) return self.parent.reject(node.source, "non-record call arguments");
        const fields = input.struct_value_literal.fields;
        const args = try self.parent.allocator.alloc(b.Slot, fields.len);
        for (args, self.parent.graph.value_fields.items[fields.start..][0..fields.len]) |*arg, field| arg.* = try self.expression(field.value);
        const f = self.parent.graph.function(x.callee);
        if (f.output.len > 1) return self.parent.reject(node.source, "multiple function outputs");
        const dst = if (f.output.len == 1) try self.newSlot(self.parent.graph.fields.items[f.output.start].ty) else null;
        try self.parent.pending.append(self.parent.allocator, x.callee);
        _ = try self.emit(node.source, .{ .call = .{ .dst = dst, .function = x.callee, .args = args } });
        return dst;
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
        if (node.content == .move_value) return self.expression(node.content.move_value);
        if (node.content == .function_call) return (try self.call(id)) orelse self.parent.reject(node.source, "void expression");
        if (node.content == .value_sequence) {
            const block_ = self.parent.graph.blocks.items[@intFromEnum(node.content.value_sequence)];
            try self.block(node.content.value_sequence);
            return self.expression(block_.ret_val orelse return self.parent.reject(node.source, "sequence without result"));
        }
        const dst = try self.newSlot(node.ty orelse return self.parent.reject(node.source, "untyped expression"));
        switch (node.content) {
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
                for (fields, self.parent.graph.value_fields.items[x.fields.start..][0..x.fields.len]) |*field, v| field.* = try self.expression(v.value);
                _ = try self.emit(node.source, .{ .record = .{ .dst = dst, .fields = fields } });
            },
            .array_literal => |x| {
                const elements = try self.parent.allocator.alloc(b.Slot, x.elements.len);
                for (elements, self.parent.graph.node_refs.items[x.elements.start..][0..x.elements.len]) |*element, value| element.* = try self.expression(value);
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
                _ = try self.emit(node.source, .{ .compare = .{ .dst = dst, .left = try self.expression(x.left), .right = try self.expression(x.right), .operator = x.operator } });
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

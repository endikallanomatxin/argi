const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const b = @import("../5_codegen/bytecode/bytecode.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const diag = @import("../1_base/diagnostic.zig");

// Execute explicit source requests only. Function resolution, specialization,
// ownership and safety remain frontend responsibilities; this pass consumes
// finalized dependencies and freezes values through the shared evaluator.
pub fn resolve(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, diagnostics: *diag.Diagnostics) !void {
    if (graph.comptime_requests.items.len == 0) return;
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var context = Context{ .allocator = allocator, .temporary = temporary, .graph = graph, .diagnostics = diagnostics };
    context.states = try temporary.alloc(State, graph.comptime_requests.items.len);
    @memset(context.states, .waiting);
    for (graph.comptime_requests.items, 0..) |request, index| {
        context.process(index) catch |err| {
            if (err == error.OutOfMemory or err == error.Reported) return err;
            try context.report(context.failure_source orelse graph.node(request).source, err);
            return error.Reported;
        };
    }
    graph.comptime_requests.clearRetainingCapacity();
}

// The staged frontend evaluates one ready request without touching unrelated
// requests whose types/bodies are still pending. Nested requests keep the same
// dependency ordering, proof, budgets and freeze boundary as final evaluation.
pub fn resolveRequest(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, diagnostics: *diag.Diagnostics, root: g.GlobalNodeId) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var context = Context{ .allocator = allocator, .temporary = scratch.allocator(), .graph = graph, .diagnostics = diagnostics };
    context.states = try context.temporary.alloc(State, graph.comptime_requests.items.len);
    @memset(context.states, .waiting);
    for (graph.comptime_requests.items, 0..) |request, index| {
        if (request != root) continue;
        context.process(index) catch |err| {
            if (err == error.OutOfMemory or err == error.Reported) return err;
            try context.report(context.failure_source orelse graph.node(root).source, err);
            return error.Reported;
        };
        return;
    }
    return error.MissingCompileTimeRequest;
}

const State = enum { waiting, executing, done };
const Context = struct {
    allocator: std.mem.Allocator,
    temporary: std.mem.Allocator,
    graph: *g.GlobalSemanticGraph,
    diagnostics: *diag.Diagnostics,
    states: []State = &.{},
    failure_source: ?p.SourceRef = null,
    depth: usize = 0,
    budget: @import("vm.zig").Limits = .{},

    fn process(self: *Context, index: usize) anyerror!void {
        switch (self.states[index]) {
            .done => return,
            .executing => return error.CompileTimeEvaluationCycle,
            .waiting => {},
        }
        if (self.depth >= 128) return error.CompileTimeDependencyDepthLimit;
        self.depth += 1;
        defer self.depth -= 1;
        self.states[index] = .executing;
        const id = self.graph.comptime_requests.items[index];
        const node = self.graph.node(id);
        errdefer if (self.failure_source == null) {
            self.failure_source = node.source;
        };
        // Compiler-recognized pure queries can already be literals.
        if (node.content == .int_literal or node.content == .bool_literal or node.content == .type_literal) {
            self.states[index] = .done;
            return;
        }
        const previous_budget = self.budget;
        self.budget = .{};
        defer self.budget = previous_budget;
        const result = switch (node.content) {
            .function_call => try self.callConstant(id, 0),
            .binary_operation, .comparison, .struct_field_access, .array_index => try self.expressionConstant(id, 0),
            else => return error.UnsupportedCompileTimeExpression,
        };
        self.graph.nodes.items[@intFromEnum(id)] = self.graph.node(result);
        self.states[index] = .done;
    }

    // Arguments execute ordinary selected functions through the VM. Do not
    // reproduce arithmetic, dispatch or function bodies in a constant folder.
    // Implicit argument evaluation does not rewrite its runtime source nodes.
    fn callConstant(self: *Context, id: g.GlobalNodeId, depth: usize) anyerror!g.GlobalNodeId {
        if (depth > 64) return error.CompileTimeConstantDepthLimit;
        const node = self.graph.node(id);
        if (node.content != .function_call) return error.UnsupportedCompileTimeCall;
        const call = node.content.function_call;
        if (call.callee_value != null) return error.UnsupportedCompileTimeCall;
        var unit = try @import("../4_semantics/global/reachability.zig").dependencyUnit(self.temporary, self.graph, &.{call.callee});
        defer unit.deinit();
        // Freeze requests inside called bodies before lowering those bodies.
        // The DFS detects compile-time dependency cycles rather than repeatedly
        // executing a still-runtime call or imposing declaration order.
        for (self.graph.comptime_requests.items, 0..) |dependency, dependency_index| {
            if (unit.containsNode(dependency)) try self.process(dependency_index);
        }
        const input = self.graph.node(call.input);
        if (input.content != .struct_value_literal) return error.NonConstantCompileTimeArgument;
        const fields = input.content.struct_value_literal.fields;
        const args = try self.temporary.alloc(b.Value, fields.len);
        for (args, 0..) |*value, offset| {
            const argument = self.graph.value_fields.items[fields.start + offset].value;
            value.* = try self.constant(argument, depth + 1);
        }
        const values = try @import("evaluate.zig").evaluateBudgeted(self.allocator, self.graph, self.diagnostics, call.callee, args, node.source, &self.budget);
        defer self.allocator.free(values);
        if (values.len == 1) {
            return values[0];
        } else {
            const start: u32 = @intCast(self.graph.value_fields.items.len);
            const outputs = self.graph.function(call.callee).output;
            for (values, self.graph.fields.items[outputs.start..][0..outputs.len]) |value, field|
                try self.graph.value_fields.append(self.allocator, .{ .name = field.name, .value = value });
            var ty = node.ty;
            if (ty == null and values.len == 0) {
                for (self.graph.types.items, 0..) |candidate, raw| {
                    if (candidate == .builtin and candidate.builtin == .Void) {
                        ty = @enumFromInt(raw);
                        break;
                    }
                }
            }
            const result: g.GlobalNodeId = @enumFromInt(self.graph.nodes.items.len);
            try self.graph.nodes.append(self.allocator, .{ .source = node.source, .ty = ty, .content = .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = @intCast(values.len) } } } });
            return result;
        }
    }

    fn constant(self: *Context, id: g.GlobalNodeId, depth: usize) anyerror!b.Value {
        if (depth > 64) return error.CompileTimeConstantDepthLimit;
        for (self.graph.comptime_requests.items, 0..) |request, index| if (request == id) {
            try self.process(index);
            break;
        };
        const node = self.graph.node(id);
        return switch (node.content) {
            .int_literal => |value| .{ .integer = @import("../5_codegen/integer_arithmetic.zig").encode(value, b.integerBounds(self.graph, node.ty.?).?) },
            .float_literal => |value| switch (self.graph.semanticType(node.ty.?).builtin) {
                .Float16 => .{ .float16 = @floatCast(value) },
                .Float32 => .{ .float32 = @floatCast(value) },
                .Float64 => .{ .float64 = @floatCast(value) },
                else => return error.NonConstantCompileTimeArgument,
            },
            .bool_literal => |value| .{ .boolean = value },
            .function_call => try self.constant(try self.callConstant(id, depth + 1), depth + 1),
            .binary_operation, .comparison, .struct_field_access, .array_index => try self.constant(try self.expressionConstant(id, depth + 1), depth + 1),
            .binding_use => |id_binding| blk: {
                const binding = self.graph.binding(id_binding);
                if (binding.mutability != .constant) return error.NonConstantCompileTimeArgument;
                break :blk try self.constant(binding.initialization orelse return error.NonConstantCompileTimeArgument, depth + 1);
            },
            .struct_value_literal => |literal| blk: {
                if (node.ty) |ty| {
                    const semantic = self.graph.semanticType(ty);
                    if (semantic == .builtin and semantic.builtin == .Void) break :blk .unit;
                }
                const values = try self.temporary.alloc(b.Value, literal.fields.len);
                for (values, 0..) |*value, offset| {
                    const child = self.graph.value_fields.items[literal.fields.start + offset].value;
                    value.* = try self.constant(child, depth + 1);
                }
                break :blk .{ .record = values };
            },
            .array_literal => |literal| blk: {
                const values = try self.temporary.alloc(b.Value, literal.elements.len);
                for (values, 0..) |*value, offset| {
                    const child = self.graph.node_refs.items[literal.elements.start + offset];
                    value.* = try self.constant(child, depth + 1);
                }
                break :blk .{ .array = values };
            },
            .choice_literal => |literal| blk: {
                var payload: ?*b.Value = null;
                if (literal.payload) |child| {
                    payload = try self.temporary.create(b.Value);
                    payload.?.* = try self.constant(child, depth + 1);
                }
                break :blk .{ .choice = .{ .variant = try b.variantOrdinal(self.graph, node.ty orelse return error.InvalidBytecode, literal.variant), .payload = payload } };
            },
            else => error.NonConstantCompileTimeArgument,
        };
    }

    fn expressionConstant(self: *Context, id: g.GlobalNodeId, depth: usize) !g.GlobalNodeId {
        const node = self.graph.node(id);
        var operands: [2]g.GlobalNodeId = undefined;
        const count: usize = switch (node.content) {
            .binary_operation => |value| setOperands(&operands, value.left, value.right),
            .comparison => |value| setOperands(&operands, value.left, value.right),
            .struct_field_access => |value| one: {
                operands[0] = value.value;
                break :one 1;
            },
            .array_index => |value| two: {
                const base = self.graph.node(value.array_ptr);
                // Array indexing can carry a direct value or its borrow.
                // Capture the aggregate, never export that reference.
                const array = if (base.content == .address_of) base.content.address_of else value.array_ptr;
                break :two setOperands(&operands, array, value.index);
            },
            else => unreachable,
        };
        var args: [2]b.Value = undefined;
        for (operands[0..count], args[0..count]) |operand, *arg|
            arg.* = try self.constant(operand, depth + 1);
        const result = try @import("evaluate.zig").evaluateExpression(self.allocator, self.graph, id, operands[0..count], args[0..count], &self.budget);
        return result;
    }

    fn setOperands(operands: *[2]g.GlobalNodeId, left: g.GlobalNodeId, right: g.GlobalNodeId) usize {
        operands.* = .{ left, right };
        return 2;
    }

    fn report(self: *Context, source: p.SourceRef, err: anyerror) !void {
        const location = @import("../4_semantics/global/source_location.zig").location(self.graph, self.diagnostics, source);
        const message: ?[]const u8 = switch (err) {
            error.RuntimeStorageInCompileTime => "#run cannot access mutable runtime global storage; use a compile-time-known constant instead",
            error.NonConstantCompileTimeArgument => "#run arguments must be compile-time constants; runtime values cannot be used",
            error.CompileTimeDependencyDepthLimit => "#run dependencies exceeded their nesting limit",
            error.CompileTimeEvaluationCycle => "cyclic dependency between #run evaluations",
            error.ExecutionAborted => "#run evaluation aborted",
            error.ExecutionIndexOutOfBounds => "#run array index is out of bounds",
            error.ExecutionInstructionLimit => "#run evaluation exceeded its instruction limit",
            error.ExecutionCancelled => "#run evaluation was cancelled",
            error.ExecutionCallDepthLimit => "#run evaluation exceeded its call depth limit",
            error.ExecutionMemoryLimit => "#run evaluation exceeded its storage limit",
            error.UnfreezableEvaluationInput => "#run arguments cannot contain references or values requiring cleanup",
            error.UnfreezableEvaluationResult => "#run cannot return references or values requiring cleanup",
            error.UnsupportedExecution => "#run uses an operation outside the supported bytecode subset",
            error.UnsupportedCompileTimeCall => "#run requires a supported direct function call",
            else => null,
        };
        if (message) |text|
            try self.diagnostics.add(location, .semantic, "{s}", .{text})
        else
            try self.diagnostics.add(location, .semantic, "#run failed: {s}", .{@errorName(err)});
    }
};

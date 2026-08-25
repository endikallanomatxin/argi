const std = @import("std");
const diagnostics = @import("../1_base/diagnostic.zig");
const sg = @import("semantic_graph.zig");
const facts = @import("safety_facts.zig");

/// Infers temporal effects from semantized bodies. Summaries are deliberately
/// compiler-owned: ordinary functions have no source contract to maintain.
pub const SafetyChecker = struct {
    allocator: *const std.mem.Allocator,
    diagnostics: *diagnostics.Diagnostics,
    summaries: std.AutoHashMap(*const sg.FunctionDeclaration, facts.FunctionSummary),

    pub fn init(allocator: *const std.mem.Allocator, diags: *diagnostics.Diagnostics) SafetyChecker {
        return .{
            .allocator = allocator,
            .diagnostics = diags,
            .summaries = std.AutoHashMap(*const sg.FunctionDeclaration, facts.FunctionSummary).init(allocator.*),
        };
    }

    pub fn deinit(self: *SafetyChecker) void {
        self.summaries.deinit();
    }

    pub fn analyze(self: *SafetyChecker, nodes: []const *sg.SGNode) !void {
        var functions = std.array_list.Managed(*const sg.FunctionDeclaration).init(self.allocator.*);
        defer functions.deinit();
        for (nodes) |node| switch (node.content) {
            .function_declaration => |function| try functions.append(function),
            .test_declaration => |test_decl| try functions.append(test_decl.function),
            else => {},
        };

        for (functions.items) |function| try self.ensureEmptySummary(function);
        const limit = @max(functions.items.len + 1, 1);
        for (0..limit) |_| {
            var changed = false;
            for (functions.items) |function| changed = (try self.infer(function)) or changed;
            if (!changed) break;
        }
    }

    fn ensureEmptySummary(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        if (self.summaries.contains(function)) return;
        const outputs = try self.allocator.alloc(facts.OutputEffect, function.output.fields.len);
        @memset(outputs, .independent);
        try self.summaries.put(function, .{ .outputs = outputs });
    }

    fn infer(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !bool {
        if (std.mem.eql(u8, function.name, "establish_fresh_reference"))
            return self.replaceSingleOutput(function, .fresh);
        if (std.mem.eql(u8, function.name, "establish_inherited_reference"))
            return self.replaceSingleOutput(function, .{ .depends_on_input = 1 });
        const body = function.body orelse return false;
        const previous = self.summaries.get(function).?;
        const outputs = try self.allocator.dupe(facts.OutputEffect, previous.outputs);
        try self.inferBlock(function, body, outputs);
        if (effectsEqual(previous.outputs, outputs)) return false;
        try self.summaries.put(function, .{ .outputs = outputs });
        return true;
    }

    fn replaceSingleOutput(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        effect: facts.OutputEffect,
    ) !bool {
        const previous = self.summaries.get(function).?;
        if (previous.outputs.len != 1 or std.meta.eql(previous.outputs[0], effect)) return false;
        const outputs = try self.allocator.alloc(facts.OutputEffect, 1);
        outputs[0] = effect;
        try self.summaries.put(function, .{ .outputs = outputs });
        return true;
    }

    fn inferBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        outputs: []facts.OutputEffect,
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .binding_assignment => |assignment| {
                const output_index = bindingIndex(function.output_bindings, assignment.sym_id) orelse continue;
                outputs[output_index] = self.inferExpression(function, assignment.value);
            },
            .if_statement => |statement| {
                try self.inferBlock(function, statement.then_block, outputs);
                if (statement.else_block) |else_block| try self.inferBlock(function, else_block, outputs);
            },
            .while_statement => |statement| try self.inferBlock(function, statement.body, outputs),
            .for_statement => |statement| try self.inferBlock(function, statement.body, outputs),
            .switch_statement => |statement| {
                for (statement.cases) |case| try self.inferBlock(function, case.body, outputs);
                if (statement.default_case) |default_case| try self.inferBlock(function, default_case, outputs);
            },
            else => {},
        };
    }

    fn inferExpression(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
    ) facts.OutputEffect {
        return switch (node.content) {
            .binding_use => |binding| if (bindingIndex(function.input_bindings, binding)) |index|
                .{ .depends_on_input = @intCast(index) }
            else
                .independent,
            .move_value => |value| switch (self.inferExpression(function, value)) {
                .depends_on_input => |index| .{ .transfers_input = index },
                else => |effect| effect,
            },
            .address_of => |value| self.inferExpression(function, value),
            .struct_field_access => |access| self.inferExpression(function, access.struct_value),
            .explicit_cast => |cast| self.inferExpression(function, cast.value),
            .function_call => |call| self.inferCall(function, call),
            else => .independent,
        };
    }

    fn inferCall(self: *SafetyChecker, function: *const sg.FunctionDeclaration, call: *const sg.FunctionCall) facts.OutputEffect {
        if (std.mem.eql(u8, call.callee.name, "establish_fresh_reference")) return .fresh;
        const callee_summary = self.summaries.get(call.callee) orelse return .independent;
        if (callee_summary.outputs.len != 1) return .independent;
        const effect = callee_summary.outputs[0];
        const input_index = switch (effect) {
            .depends_on_input => |index| index,
            .transfers_input => |index| index,
            else => return effect,
        };
        if (call.input.content != .struct_value_literal or input_index >= call.input.content.struct_value_literal.fields.len)
            return .independent;
        const argument = call.input.content.struct_value_literal.fields[input_index].value;
        const caller_effect = self.inferExpression(function, argument);
        return if (effect == .transfers_input) switch (caller_effect) {
            .depends_on_input => |index| .{ .transfers_input = index },
            else => caller_effect,
        } else caller_effect;
    }
};

fn bindingIndex(bindings: []const *const sg.BindingDeclaration, target: *const sg.BindingDeclaration) ?usize {
    for (bindings, 0..) |binding, index| if (binding == target) return index;
    return null;
}

fn effectsEqual(left: []const facts.OutputEffect, right: []const facts.OutputEffect) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

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
        const diagnostic_count = self.diagnostics.list.items.len;
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
        for (functions.items) |function| try self.validateFunction(function);
        if (self.diagnostics.list.items.len != diagnostic_count) return error.Reported;
    }

    const FunctionState = struct {
        tracker: facts.Tracker,
        values: std.AutoHashMap(*const sg.BindingDeclaration, facts.ValueFacts),
        storage_roots: std.AutoHashMap(*const sg.BindingDeclaration, facts.RootId),

        fn init(allocator: std.mem.Allocator) FunctionState {
            return .{
                .tracker = facts.Tracker.init(allocator),
                .values = std.AutoHashMap(*const sg.BindingDeclaration, facts.ValueFacts).init(allocator),
                .storage_roots = std.AutoHashMap(*const sg.BindingDeclaration, facts.RootId).init(allocator),
            };
        }

        fn deinit(self: *FunctionState) void {
            self.tracker.deinit();
            self.values.deinit();
            self.storage_roots.deinit();
        }
    };

    fn validateFunction(self: *SafetyChecker, function: *const sg.FunctionDeclaration) !void {
        const body = function.body orelse return;
        if (function.origin_kind != .declared) return;
        if (isRootingPrimitive(function.name)) return;
        if (std.mem.indexOf(u8, function.location.file, "/core/") != null) return;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        for (function.input_bindings) |binding| {
            if (binding.ty == .pointer_type) {
                const root = try state.tracker.establish(.fresh);
                try state.values.put(binding, .{ .dependencies = try self.oneDependency(root) });
            }
        }
        try self.validateBlock(function, body, &state);
    }

    fn validateBlock(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        state: *FunctionState,
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .binding_declaration => |binding| {
                const value = if (binding.initialization) |initialization|
                    try self.evaluate(function, initialization, state)
                else
                    facts.ValueFacts{};
                try state.values.put(binding, value);
            },
            .binding_assignment => |assignment| try state.values.put(
                assignment.sym_id,
                try self.evaluate(function, assignment.value, state),
            ),
            .function_call, .dereference, .explicit_cast => _ = try self.evaluate(function, node, state),
            .if_statement => |statement| {
                _ = try self.evaluate(function, statement.condition, state);
                try self.validateBlock(function, statement.then_block, state);
                if (statement.else_block) |else_block| try self.validateBlock(function, else_block, state);
            },
            .while_statement => |statement| {
                _ = try self.evaluate(function, statement.condition, state);
                try self.validateBlock(function, statement.body, state);
            },
            .for_statement => |statement| {
                if (statement.init) |initialization| _ = try self.evaluate(function, initialization, state);
                _ = try self.evaluate(function, statement.condition, state);
                try self.validateBlock(function, statement.body, state);
                if (statement.increment) |increment| _ = try self.evaluate(function, increment, state);
            },
            .return_statement => |statement| if (statement.expression) |expression| {
                _ = try self.evaluate(function, expression, state);
            },
            else => {},
        };
    }

    fn evaluate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        return switch (node.content) {
            .binding_use => |binding| state.values.get(binding) orelse .{},
            .move_value => |value| blk: {
                const result = try self.evaluate(function, value, state);
                if (value.content == .binding_use) try state.values.put(value.content.binding_use, .{});
                break :blk result;
            },
            .address_of => |value| .{ .dependencies = try self.oneDependency(try self.storageRoot(value, state)) },
            .dereference => |dereference| blk: {
                const pointer = try self.evaluate(function, dereference.pointer, state);
                if (!state.tracker.dependenciesAreAlive(pointer)) {
                    try self.diagnostics.add(function.location, .semantic, "reference depends on a root that has ended", .{});
                }
                break :blk facts.ValueFacts{};
            },
            .struct_value_literal => |literal| try self.aggregate(function, literal.fields, state),
            .struct_field_access => |access| try self.evaluate(function, access.struct_value, state),
            .explicit_cast => |cast| try self.evaluate(function, cast.value, state),
            .function_call => |call| try self.evaluateCall(function, call, state),
            .binary_operation => |operation| blk: {
                _ = try self.evaluate(function, operation.left, state);
                _ = try self.evaluate(function, operation.right, state);
                break :blk .{};
            },
            .comparison => |comparison| blk: {
                _ = try self.evaluate(function, comparison.left, state);
                _ = try self.evaluate(function, comparison.right, state);
                break :blk .{};
            },
            .logical_operation => |operation| blk: {
                _ = try self.evaluate(function, operation.left, state);
                _ = try self.evaluate(function, operation.right, state);
                break :blk .{};
            },
            else => .{},
        };
    }

    fn evaluateCall(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        call: *const sg.FunctionCall,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var arguments: []const sg.StructValueLiteralField = &.{};
        if (call.input.content == .struct_value_literal) arguments = call.input.content.struct_value_literal.fields;
        if (std.mem.eql(u8, call.callee.name, "deallocate") and arguments.len > 1) {
            const data = try self.evaluate(function, arguments[1].value, state);
            for (data.dependencies) |dependency| state.tracker.end(dependency.root);
            return .{};
        }
        const summary = self.summaries.get(call.callee) orelse return .{};
        for (summary.deinitializes_inputs) |index| {
            if (index >= arguments.len) continue;
            if (rootBinding(arguments[index].value)) |binding| {
                if (state.values.get(binding)) |value| {
                    for (value.cleanup_responsibilities) |responsibility| state.tracker.end(responsibility.root);
                }
                try state.values.put(binding, .{});
            }
        }
        if (summary.outputs.len != 1) return .{};
        return switch (summary.outputs[0]) {
            .independent => .{},
            .fresh => blk: {
                const root = try state.tracker.establish(.fresh);
                break :blk .{
                    .dependencies = try self.oneDependency(root),
                    .cleanup_responsibilities = try self.oneResponsibility(root),
                };
            },
            .depends_on_input, .transfers_input => |index| if (index < arguments.len)
                try self.evaluate(function, arguments[index].value, state)
            else
                .{},
        };
    }

    fn aggregate(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        fields: []const sg.StructValueLiteralField,
        state: *FunctionState,
    ) anyerror!facts.ValueFacts {
        var dependencies = std.array_list.Managed(facts.ReferenceDependency).init(self.allocator.*);
        var responsibilities = std.array_list.Managed(facts.CleanupResponsibility).init(self.allocator.*);
        for (fields) |field| {
            const value = try self.evaluate(function, field.value, state);
            try dependencies.appendSlice(value.dependencies);
            try responsibilities.appendSlice(value.cleanup_responsibilities);
        }
        return .{
            .dependencies = try dependencies.toOwnedSlice(),
            .cleanup_responsibilities = try responsibilities.toOwnedSlice(),
        };
    }

    fn storageRoot(self: *SafetyChecker, node: *const sg.SGNode, state: *FunctionState) !facts.RootId {
        _ = self;
        const binding = rootBinding(node) orelse return state.tracker.establish(.fresh);
        if (state.storage_roots.get(binding)) |root| return root;
        const root = try state.tracker.establish(.fresh);
        try state.storage_roots.put(binding, root);
        return root;
    }

    fn oneDependency(self: *SafetyChecker, root: facts.RootId) ![]const facts.ReferenceDependency {
        const result = try self.allocator.alloc(facts.ReferenceDependency, 1);
        result[0] = .{ .root = root };
        return result;
    }

    fn oneResponsibility(self: *SafetyChecker, root: facts.RootId) ![]const facts.CleanupResponsibility {
        const result = try self.allocator.alloc(facts.CleanupResponsibility, 1);
        result[0] = .{ .root = root };
        return result;
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
        var deinitialized = std.array_list.Managed(u32).init(self.allocator.*);
        try self.inferDeinitializedInputs(function, body, &deinitialized);
        const deinitialized_slice = try deinitialized.toOwnedSlice();
        if (effectsEqual(previous.outputs, outputs) and
            std.mem.eql(u32, previous.deinitializes_inputs, deinitialized_slice)) return false;
        try self.summaries.put(function, .{
            .outputs = outputs,
            .deinitializes_inputs = deinitialized_slice,
        });
        return true;
    }

    fn inferDeinitializedInputs(
        self: *SafetyChecker,
        function: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        result: *std.array_list.Managed(u32),
    ) !void {
        for (block.nodes) |node| switch (node.content) {
            .function_call => |call| {
                if (call.input.content != .struct_value_literal) continue;
                const arguments = call.input.content.struct_value_literal.fields;
                if (std.mem.eql(u8, call.callee.name, "deallocate")) {
                    if (arguments.len > 1) try appendEffectInput(self.inferExpression(function, arguments[1].value), result);
                    continue;
                }
                const summary = self.summaries.get(call.callee) orelse continue;
                for (summary.deinitializes_inputs) |callee_index| {
                    if (callee_index < arguments.len)
                        try appendEffectInput(self.inferExpression(function, arguments[callee_index].value), result);
                }
            },
            .if_statement => |statement| {
                try self.inferDeinitializedInputs(function, statement.then_block, result);
                if (statement.else_block) |else_block| try self.inferDeinitializedInputs(function, else_block, result);
            },
            .while_statement => |statement| try self.inferDeinitializedInputs(function, statement.body, result),
            .for_statement => |statement| try self.inferDeinitializedInputs(function, statement.body, result),
            else => {},
        };
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
            .dereference => |value| self.inferExpression(function, value.pointer),
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

fn appendEffectInput(effect: facts.OutputEffect, result: *std.array_list.Managed(u32)) !void {
    const index = switch (effect) {
        .depends_on_input, .transfers_input => |input| input,
        else => return,
    };
    for (result.items) |existing| if (existing == index) return;
    try result.append(index);
}

fn isRootingPrimitive(name: []const u8) bool {
    return std.mem.eql(u8, name, "establish_fresh_reference") or
        std.mem.eql(u8, name, "establish_inherited_reference");
}

fn rootBinding(node: *const sg.SGNode) ?*const sg.BindingDeclaration {
    return switch (node.content) {
        .binding_use => |binding| binding,
        .struct_field_access => |access| rootBinding(access.struct_value),
        .array_index => |index| rootBinding(index.array_ptr),
        .dereference => |dereference| rootBinding(dereference.pointer),
        .address_of => |value| rootBinding(value),
        else => null,
    };
}

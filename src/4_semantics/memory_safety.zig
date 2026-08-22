const std = @import("std");

const diagnostics = @import("../1_base/diagnostic.zig");
const sg = @import("semantic_graph.zig");
const temporal_place = @import("temporal_place.zig");

const CapturedPlace = struct {
    place: temporal_place.Place,
    invalidation_cursor: usize,
};

const ReferenceFact = struct {
    captured: CapturedPlace,
};

const Invalidation = struct {
    place: temporal_place.Place,
    location: @import("../2_tokens/token.zig").Location,
};

const FunctionState = struct {
    references: std.AutoHashMap(*const sg.BindingDeclaration, ReferenceFact),
    invalidations: std.array_list.Managed(Invalidation),

    fn init(allocator: std.mem.Allocator) FunctionState {
        return .{
            .references = std.AutoHashMap(*const sg.BindingDeclaration, ReferenceFact).init(allocator),
            .invalidations = std.array_list.Managed(Invalidation).init(allocator),
        };
    }

    fn deinit(self: *FunctionState) void {
        self.references.deinit();
        self.invalidations.deinit();
    }
};

/// Runs after semantizing has produced complete function bodies and before any
/// consumer can hand the graph to codegen. Temporal properties intentionally
/// live here instead of being folded into type checking: source types describe
/// reference permissions, while this pass reasons about the identities those
/// references capture at particular program points.
pub const MemorySafetyAnalyzer = struct {
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
    analyzed_functions: std.AutoHashMap(*const sg.FunctionDeclaration, void),

    pub fn init(
        allocator: *const std.mem.Allocator,
        diags: *diagnostics.Diagnostics,
    ) MemorySafetyAnalyzer {
        return .{
            .allocator = allocator,
            .diags = diags,
            .analyzed_functions = std.AutoHashMap(*const sg.FunctionDeclaration, void).init(allocator.*),
        };
    }

    pub fn deinit(self: *MemorySafetyAnalyzer) void {
        self.analyzed_functions.deinit();
    }

    pub fn analyze(self: *MemorySafetyAnalyzer, nodes: []const *sg.SGNode) !void {
        for (nodes) |node| switch (node.content) {
            .function_declaration => |function| try self.analyzeFunction(function),
            .test_declaration => |test_decl| try self.analyzeFunction(test_decl.function),
            else => {},
        };
    }

    pub fn analyzeFunction(self: *MemorySafetyAnalyzer, function: *const sg.FunctionDeclaration) !void {
        if (self.analyzed_functions.contains(function)) return;
        try self.analyzed_functions.put(function, {});

        const body = function.body orelse return;
        var state = FunctionState.init(self.allocator.*);
        defer state.deinit();
        try self.analyzeCodeBlock(body, &state);
    }

    fn analyzeCodeBlock(self: *MemorySafetyAnalyzer, block: *const sg.CodeBlock, state: *FunctionState) anyerror!void {
        for (block.nodes) |node| try self.analyzeNode(node, state);
        if (block.ret_val) |value| try self.analyzeNode(value, state);
    }

    fn analyzeNode(self: *MemorySafetyAnalyzer, node: *const sg.SGNode, state: *FunctionState) anyerror!void {
        switch (node.content) {
            .binding_declaration => |binding| {
                if (binding.initialization) |initialization| {
                    try self.analyzeNode(initialization, state);
                    try self.updateReferenceFact(binding, initialization, state);
                }
            },
            .binding_assignment => |assignment| {
                try self.analyzeNode(assignment.value, state);
                try self.updateReferenceFact(assignment.sym_id, assignment.value, state);
            },
            .binding_use => |binding| try self.validateReferenceUse(binding, node, state),
            .move_value => |inner| try self.analyzeNode(inner, state),
            .function_call => |call| {
                try self.analyzeNode(call.input, state);
                try self.recordDirectCallInvalidations(call, node, state);
            },
            .code_block => |block| try self.analyzeCodeBlock(block, state),
            .struct_value_literal => |value| for (value.fields) |field| try self.analyzeNode(field.value, state),
            .list_literal => |value| for (value.elements) |element| try self.analyzeNode(element, state),
            .array_literal => |value| for (value.elements) |element| try self.analyzeNode(element, state),
            .choice_literal => |value| if (value.payload) |payload| try self.analyzeNode(payload, state),
            .struct_field_access => |access| try self.analyzeNode(access.struct_value, state),
            .choice_payload_access => |access| try self.analyzeNode(access.choice_value, state),
            .array_index => |access| {
                try self.analyzeNode(access.array_ptr, state);
                try self.analyzeNode(access.index, state);
            },
            .dereference => |access| try self.analyzeNode(access.pointer, state),
            .address_of => {},
            .array_store => |store| {
                try self.analyzeNode(store.array_ptr, state);
                try self.analyzeNode(store.index, state);
                try self.analyzeNode(store.value, state);
            },
            .struct_field_store => |store| {
                try self.analyzeNode(store.struct_ptr, state);
                try self.analyzeNode(store.value, state);
            },
            .pointer_assignment => |assignment| {
                try self.analyzeNode(assignment.pointer, state);
                try self.analyzeNode(assignment.value, state);
            },
            .binary_operation => |operation| {
                try self.analyzeNode(operation.left, state);
                try self.analyzeNode(operation.right, state);
            },
            .comparison => |comparison| {
                try self.analyzeNode(comparison.left, state);
                try self.analyzeNode(comparison.right, state);
            },
            .logical_operation => |operation| {
                try self.analyzeNode(operation.left, state);
                try self.analyzeNode(operation.right, state);
            },
            .if_statement => |statement| {
                try self.analyzeNode(statement.condition, state);
                try self.analyzeCodeBlock(statement.then_block, state);
                if (statement.else_block) |else_block| try self.analyzeCodeBlock(else_block, state);
            },
            .while_statement => |statement| {
                try self.analyzeNode(statement.condition, state);
                try self.analyzeCodeBlock(statement.body, state);
            },
            .for_statement => |statement| {
                if (statement.init) |initializer| try self.analyzeNode(initializer, state);
                try self.analyzeNode(statement.condition, state);
                try self.analyzeCodeBlock(statement.body, state);
                if (statement.increment) |increment| try self.analyzeNode(increment, state);
            },
            .switch_statement => |statement| {
                try self.analyzeNode(statement.expression, state);
                for (statement.cases) |case| {
                    try self.analyzeNode(case.value, state);
                    try self.analyzeCodeBlock(case.body, state);
                }
                if (statement.default_case) |default_case| try self.analyzeCodeBlock(default_case, state);
            },
            .return_statement => |statement| {
                if (statement.expression) |expression| try self.analyzeNode(expression, state);
                for (statement.cleanup_nodes) |cleanup| try self.analyzeNode(cleanup, state);
            },
            .nullable_unwrap_or => |unwrap| {
                try self.analyzeNode(unwrap.nullable_value, state);
                try self.analyzeNode(unwrap.fallback_value, state);
            },
            .testing_expect_error => |expectation| {
                try self.analyzeNode(expectation.expected_reason, state);
                try self.analyzeNode(expectation.actual_result, state);
            },
            .error_propagation => |propagation| {
                try self.analyzeNode(propagation.errable_value, state);
                for (propagation.cleanup_nodes) |cleanup| try self.analyzeNode(cleanup, state);
            },
            .error_context => |context| {
                try self.analyzeNode(context.errable_value, state);
                try self.analyzeNode(context.context, state);
                for (context.cleanup_nodes) |cleanup| try self.analyzeNode(cleanup, state);
            },
            .explicit_cast => |cast| try self.analyzeNode(cast.value, state),
            .type_initializer => |initializer| try self.analyzeNode(initializer.args, state),
            .auto_deinit_binding,
            .break_statement,
            .continue_statement,
            .choice_option_declaration,
            .type_declaration,
            .function_declaration,
            .test_declaration,
            .reach_directive,
            .value_literal,
            .type_literal,
            => {},
        }
    }

    fn updateReferenceFact(
        self: *MemorySafetyAnalyzer,
        binding: *const sg.BindingDeclaration,
        value: *const sg.SGNode,
        state: *FunctionState,
    ) !void {
        if (try self.referenceFactFromValue(value, state)) |fact| {
            try state.references.put(binding, fact);
        } else {
            _ = state.references.remove(binding);
        }
    }

    fn referenceFactFromValue(
        self: *MemorySafetyAnalyzer,
        value: *const sg.SGNode,
        state: *const FunctionState,
    ) !?ReferenceFact {
        return switch (value.content) {
            .address_of => |target| blk: {
                const place = try temporal_place.Place.fromNode(target, self.allocator) orelse break :blk null;
                break :blk .{ .captured = .{
                    .place = place,
                    .invalidation_cursor = state.invalidations.items.len,
                } };
            },
            .binding_use => |binding| state.references.get(binding),
            .move_value => |inner| try self.referenceFactFromValue(inner, state),
            else => null,
        };
    }

    fn validateReferenceUse(
        self: *MemorySafetyAnalyzer,
        binding: *const sg.BindingDeclaration,
        use_node: *const sg.SGNode,
        state: *const FunctionState,
    ) !void {
        const fact = state.references.get(binding) orelse return;
        for (state.invalidations.items[fact.captured.invalidation_cursor..]) |invalidation| {
            if (!temporal_place.Place.mayOverlap(fact.captured.place, invalidation.place)) continue;
            try self.diags.add(
                use_node.location,
                .semantic,
                "reference '{s}' is no longer valid; it refers to '{s}', which was invalidated at {s}:{d}:{d}",
                .{
                    binding.name,
                    fact.captured.place.root.name,
                    invalidation.location.file,
                    invalidation.location.line,
                    invalidation.location.column,
                },
            );
            return;
        }
    }

    fn recordDirectCallInvalidations(
        self: *MemorySafetyAnalyzer,
        call: *const sg.FunctionCall,
        call_node: *const sg.SGNode,
        state: *FunctionState,
    ) !void {
        if (!std.mem.eql(u8, call.callee.name, "deinit")) return;
        if (call.input.content != .struct_value_literal) return;

        const input = call.input.content.struct_value_literal;
        for (input.fields, 0..) |field, index| {
            if (index >= call.callee.input.fields.len) break;
            const parameter = call.callee.input.fields[index];
            if (parameter.ty != .pointer_type or parameter.ty.pointer_type.mutability != .exclusive) continue;
            if (field.value.content != .address_of) continue;
            const place = try temporal_place.Place.fromNode(field.value.content.address_of, self.allocator) orelse continue;
            try state.invalidations.append(.{
                .place = place,
                .location = call_node.location,
            });
        }
    }
};

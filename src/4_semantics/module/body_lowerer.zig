const std = @import("std");
const literals = @import("../semantic_literals.zig");
const syn = @import("../../3_syntax/syntax_tree.zig");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const primitives = @import("../primitives/schema.zig");
const views = @import("views.zig");
const writer_mod = @import("writer.zig");
const type_lowerer = @import("type_lowerer.zig");

pub const Stats = struct { lowered_functions: u32 = 0 };

const NamedBinding = struct {
    name: primitives.StringRange,
    id: entities.ModuleBindingId,
    ty: ?entities.ModuleTypeId,
};
pub const Lowered = struct { node: entities.ModuleNodeId, ty: ?entities.ModuleTypeId };
const ExpressionMode = enum { body, initializer };

pub fn lowerMissingFunctions(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !Stats {
    var context = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .writer = writer_mod.Writer.init(allocator, graph),
        .bindings = std.array_list.Managed(NamedBinding).init(allocator),
        .scope_marks = std.array_list.Managed(usize).init(allocator),
    };
    defer context.bindings.deinit();
    defer context.scope_marks.deinit();
    return context.lowerFunctions();
}

pub fn lowerInitializerExpression(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    file_index: u32,
    node: syn.NodeIndex,
    expected: ?entities.ModuleTypeId,
) !Lowered {
    var context = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .writer = writer_mod.Writer.init(allocator, graph),
        .bindings = std.array_list.Managed(NamedBinding).init(allocator),
        .scope_marks = std.array_list.Managed(usize).init(allocator),
        .expression_mode = .initializer,
    };
    defer context.bindings.deinit();
    defer context.scope_marks.deinit();
    context.file_index = file_index;
    const file = files[@intCast(file_index)];
    context.tree = file.tree;
    context.source = file.source;
    try context.seedGlobalBindings();
    return context.lowerNode(node, expected);
}

const Context = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    bindings: std.array_list.Managed(NamedBinding),
    scope_marks: std.array_list.Managed(usize),
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},
    pipe_value: ?Lowered = null,
    expression_mode: ExpressionMode = .body,

    fn lowerFunctions(self: *Context) !Stats {
        var stats: Stats = .{};
        for (self.graph.functions.items, 0..) |interface, raw_index| {
            const function_id: entities.ModuleFunctionId = @enumFromInt(@as(u32, @intCast(raw_index)));
            if (hasFunctionSemantic(self.graph, function_id)) continue;
            const legacy_decl = self.graph.declarations.items[@intFromEnum(interface.declaration)];
            self.file_index = legacy_decl.module_file_index;
            const file = self.files[@intCast(self.file_index)];
            self.tree = file.tree;
            self.source = file.source;
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, legacy_decl) orelse continue;
            const declaration = switch (legacy_decl.kind) {
                .function => self.tree.functionDeclaration(declaration_node) orelse continue,
                .test_function => (self.tree.testDeclaration(declaration_node) orelse continue).function,
                else => continue,
            };
            if (declaration.generic_params.len != 0 or declaration.generic_params_struct != null) continue;

            self.bindings.clearRetainingCapacity();
            self.scope_marks.clearRetainingCapacity();
            try self.pushScope();
            var inputs = std.array_list.Managed(entities.ModuleBindingId).init(self.allocator);
            defer inputs.deinit();
            var outputs = std.array_list.Managed(entities.ModuleBindingId).init(self.allocator);
            defer outputs.deinit();
            try self.bindInterface(interface.input, .constant, &inputs);
            try self.bindInterface(interface.output, .variable, &outputs);
            const input_range = try self.writer.appendBindingRefs(inputs.items);
            const output_range = try self.writer.appendBindingRefs(outputs.items);
            const body = if (declaration.body) |body_node| try self.lowerBlock(body_node) else null;
            try self.graph.semantic.function_semantics.append(self.allocator, .{
                .function = function_id,
                .body = body,
                .input_bindings = input_range,
                .output_bindings = output_range,
                .flags = .{
                    .is_once = declaration.is_once,
                    .is_test = legacy_decl.kind == .test_function,
                    .has_declared_body = declaration.body != null,
                },
            });
            self.popScope();
            stats.lowered_functions += 1;
        }
        return stats;
    }

    fn bindInterface(
        self: *Context,
        range: graph_mod.FieldRange,
        mutability: primitives.Mutability,
        result: *std.array_list.Managed(entities.ModuleBindingId),
    ) !void {
        for (0..range.len) |offset| {
            const field_id: entities.ModuleFieldId = @enumFromInt(range.start + @as(u32, @intCast(offset)));
            const field = try views.fieldView(self.graph, field_id);
            const id = try self.writer.addBinding(.{
                .name = field.name,
                .source = field.source,
                .ty = field.ty,
                .mutability = mutability,
            });
            try result.append(id);
            try self.bindings.append(.{ .name = field.name, .id = id, .ty = field.ty });
        }
    }

    fn lowerBlock(self: *Context, node: syn.NodeIndex) anyerror!entities.ModuleBlockId {
        const block = self.tree.codeBlock(node) orelse return error.ExpectedCodeBlock;
        try self.pushScope();
        defer self.popScope();
        var nodes = std.array_list.Managed(entities.ModuleNodeId).init(self.allocator);
        defer nodes.deinit();
        var ret_val: ?entities.ModuleNodeId = null;
        for (block.statements) |statement| {
            const value = try self.lowerNode(statement, null);
            try nodes.append(value.node);
            ret_val = value.node;
        }
        return self.writer.addBlock(.{ .nodes = try self.writer.appendNodeRefs(nodes.items), .ret_val = ret_val });
    }

    fn lowerNode(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) anyerror!Lowered {
        if (self.expression_mode == .initializer) switch (self.tree.tag(node)) {
            .literal,
            .identifier,
            .function_call,
            .struct_value_literal,
            .list_literal,
            .struct_field_access,
            .index_access,
            .binary_add,
            .binary_subtract,
            .binary_multiply,
            .binary_divide,
            .binary_modulo,
            .compare_equal,
            .compare_not_equal,
            .compare_less,
            .compare_greater,
            .compare_less_equal,
            .compare_greater_equal,
            .logical_and,
            .logical_or,
            .address_of,
            .address_of_mut,
            .dereference,
            .reach_directive,
            .type_name,
            .pointer_type,
            .pointer_type_mut,
            .nullable_type,
            .inferred_errable_type,
            .array_type,
            .generic_type_instantiation,
            .struct_type_literal,
            .choice_type_literal,
            => {},
            else => return error.UnsupportedInitializerExpression,
        };
        return switch (self.tree.tag(node)) {
            .literal => self.lowerLiteral(node),
            .identifier => self.lowerIdentifier(node, expected),
            .pipe_placeholder => self.pipe_value orelse return error.PipePlaceholderOutsidePipe,
            .symbol_declaration_constant, .symbol_declaration_variable => self.lowerBinding(node),
            .assignment => self.lowerAssignment(node, expected),
            .expression_statement => self.lowerNode(self.tree.unaryOperand(node).?, expected),
            .move_expression => self.wrapUnary(node, .move_value, expected),
            .pipe_expression => self.lowerPipe(node, expected),
            .unwrap_or, .unwrap_or_do => self.lowerUnwrap(node, expected),
            .function_call => self.lowerCall(node, expected),
            .code_block => self.lowerBlockNode(node),
            .list_literal => self.lowerList(node),
            .struct_value_literal => self.lowerStructValue(node),
            .choice_literal, .choice_some_literal => self.lowerChoiceLiteral(node, expected),
            .struct_field_access => self.lowerField(node, expected),
            .choice_payload_access => self.lowerChoicePayload(node, expected),
            .error_propagation => self.lowerErrorPropagation(node, expected, null),
            .error_context => self.lowerErrorContext(node, expected),
            .nullable_test => self.lowerNullableTest(node),
            .index_access => self.lowerIndex(node, expected, null),
            .return_statement => self.lowerReturn(node),
            .break_statement => self.resolvedVoid(node, .break_statement),
            .continue_statement => self.resolvedVoid(node, .continue_statement),
            .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => self.lowerBinary(node, expected),
            .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal => self.lowerComparison(node),
            .logical_and, .logical_or => self.lowerLogical(node),
            .if_statement => self.lowerIf(node),
            .for_value, .for_borrow, .for_mut_borrow => self.lowerFor(node),
            .while_statement => self.lowerWhile(node),
            .match_statement => self.lowerMatch(node),
            .defer_statement => self.lowerDefer(node),
            .keep_statement => self.lowerKeep(node),
            .reach_directive => self.lowerReach(node),
            .index_assignment => self.lowerIndexAssignment(node, expected),
            .address_of, .address_of_mut => self.lowerAddress(node),
            .dereference => self.lowerDereference(node, expected),
            .pointer_assignment => self.lowerPointerAssignment(node, expected),
            .type_name, .pointer_type, .pointer_type_mut, .nullable_type, .inferred_errable_type, .array_type, .generic_type_instantiation, .struct_type_literal, .choice_type_literal => self.lowerTypeLiteral(node),
            .import_statement => self.lowerImport(node, expected),
            else => return error.UnexpectedBodySyntaxNode,
        };
    }

    fn lowerLiteral(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.literal(node).?;
        const value = self.tree.tokenContent(literal.token).literal;
        return switch (value) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => blk: {
                const parsed = try literals.integer(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                break :blk try self.resolved(node, try self.builtin(.Int32), .{ .int_literal = parsed });
            },
            .regular_float_literal, .scientific_float_literal => blk: {
                const parsed = try literals.float(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                break :blk try self.resolved(node, try self.builtin(.Float32), .{ .float_literal = parsed });
            },
            .bool_literal => |item| self.resolved(node, try self.builtin(.Bool), .{ .bool_literal = item }),
            .char_literal => |item| self.resolved(node, try self.builtin(.Char), .{ .char_literal = item }),
            .string_literal => blk: {
                const text = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token));
                break :blk try self.resolved(node, try self.builtin(.Any), .{ .string_literal = text });
            },
        };
    }

    fn lowerIdentifier(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
        if (self.lookupBinding(text)) |binding|
            return self.resolved(node, binding.ty, .{ .binding_use = binding.id });
        return self.pending(node, .{ .resolve_name_use = .{
            .node = self.nextNodeId(),
            .name = try self.writer.addString(text),
        } }, expected);
    }

    fn lowerBinding(self: *Context, node: syn.NodeIndex) !Lowered {
        const declaration = self.tree.symbolDeclaration(node).?;
        const value = if (declaration.value) |value_node| try self.lowerNode(value_node, null) else null;
        const semantic_ty: ?entities.ModuleTypeId = if (declaration.type_node) |type_node|
            try self.lowerType(type_node)
        else if (value) |item|
            item.ty
        else
            null;
        const name_text = self.tree.tokenTextFromSource(self.source, declaration.name_token);
        const name_range = try self.writer.addString(name_text);
        const source = self.sourceRef(node);
        const initialization = if (value) |item| item.node else null;
        const mutability = graph_mod.mutabilityFromSyntax(declaration.mutability);
        const binding = if (semantic_ty) |stored_ty|
            try self.writer.addBinding(.{
                .name = name_range,
                .source = source,
                .ty = stored_ty,
                .initialization = initialization,
                .mutability = mutability,
            })
        else
            try self.writer.addUnresolvedBinding(name_range, source, initialization, mutability);
        const name = self.graph.semantic.bindings.items[@intFromEnum(binding)].name;
        try self.bindings.append(.{ .name = name, .id = binding, .ty = semantic_ty });
        return self.resolved(node, semantic_ty, .{ .binding_declaration = binding });
    }

    fn lowerAssignment(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const assignment = self.tree.assignment(node).?;
        const name_text = self.tree.tokenTextFromSource(self.source, assignment.name_token);
        if (self.lookupBinding(name_text)) |binding| {
            const value = try self.lowerNode(assignment.value, binding.ty);
            return self.resolved(node, binding.ty, .{ .assignment = .{ .binding = binding.id, .value = value.node } });
        }
        const value = try self.lowerNode(assignment.value, expected);
        return self.pending(node, .{ .resolve_name_assignment = .{
            .node = self.nextNodeId(),
            .name = try self.writer.addString(name_text),
            .value = value.node,
        } }, expected orelse value.ty);
    }

    fn lowerPipe(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const op = self.tree.binaryOperation(node).?;
        const lhs = try self.lowerNode(op.lhs, null);
        const previous = self.pipe_value;
        self.pipe_value = lhs;
        defer self.pipe_value = previous;
        return self.lowerNode(op.rhs, expected);
    }

    fn lowerUnwrap(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const op = self.tree.binaryOperation(node).?;
        const value = try self.lowerNode(op.lhs, null);
        const fallback = try self.lowerNode(op.rhs, expected);
        return self.pending(node, .{ .resolve_nullable_unwrap = .{
            .node = self.nextNodeId(),
            .nullable_value = value.node,
            .fallback_value = fallback.node,
        } }, expected orelse fallback.ty);
    }

    fn lowerCall(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const call = self.tree.functionCall(node).?;
        const input = try self.lowerNode(call.input, null);
        const name_text = self.tree.tokenTextFromSource(self.source, call.callee_token);
        const module_path = if (call.module_qualifier) |token_index|
            try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))
        else
            null;
        const external = try self.writer.addExternalRef(.{
            .kind = .function,
            .module_path = module_path,
            .name = try self.writer.addString(name_text),
            .source = self.sourceRef(node),
        });
        return self.pending(node, .{ .resolve_call = .{
            .node = self.nextNodeId(),
            .callee = external,
            .input = input.node,
            .expected_type = expected,
        } }, expected);
    }

    fn lowerBlockNode(self: *Context, node: syn.NodeIndex) !Lowered {
        const block = try self.lowerBlock(node);
        return self.resolved(node, try self.builtin(.Any), .{ .code_block = block });
    }

    fn lowerList(self: *Context, node: syn.NodeIndex) !Lowered {
        const list = self.tree.listLiteral(node).?;
        var nodes = std.array_list.Managed(entities.ModuleNodeId).init(self.allocator);
        defer nodes.deinit();
        var types = std.array_list.Managed(entities.ModuleTypeId).init(self.allocator);
        defer types.deinit();
        for (list.elements) |child| {
            const value = try self.lowerNode(child, null);
            try nodes.append(value.node);
            try types.append(try self.compatibilityType(value.ty));
        }
        return self.resolved(node, try self.builtin(.Any), .{ .list_literal = .{
            .elements = try self.writer.appendNodeRefs(nodes.items),
            .element_types = try self.writer.appendTypeRefs(types.items),
        } });
    }

    fn lowerStructValue(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.structValueLiteral(node).?;
        var values: std.ArrayList(entities.ValueField) = .empty;
        defer values.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.valueField(field_node).?;
            const value = try self.lowerNode(field.value, null);
            const name = if (field.name_token) |token_index|
                try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))
            else
                try self.writer.addString("");
            try values.append(self.allocator, .{ .name = name, .value = value.node });
        }
        const start: u32 = @intCast(self.graph.semantic.value_fields.items.len);
        try self.graph.semantic.value_fields.appendSlice(self.allocator, values.items);
        const ty = try self.builtin(.Any);
        return self.resolved(node, ty, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(literal.fields.len) },
            .ty = ty,
            .dispatch_prefix_positional_count = literal.positional_prefix_count,
        } });
    }

    fn lowerChoiceLiteral(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const literal = self.tree.choiceLiteral(node).?;
        const payload = if (literal.payload) |payload_node| (try self.lowerNode(payload_node, null)).node else null;
        const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.name_token));
        const option = try self.writer.addExternalRef(.{
            .kind = .choice_option,
            .module_path = null,
            .name = name,
            .source = self.sourceRef(node),
        });
        return self.pending(node, .{ .resolve_choice_literal = .{
            .node = self.nextNodeId(),
            .option = option,
            .payload = payload,
            .expected_type = expected,
        } }, expected);
    }

    fn lowerField(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const access = self.tree.structFieldAccess(node).?;
        const value = try self.lowerNode(access.value, null);
        return self.pending(node, .{ .resolve_field = .{
            .node = self.nextNodeId(),
            .value = value.node,
            .field_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)),
        } }, expected);
    }

    fn lowerChoicePayload(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const access = self.tree.choicePayloadAccess(node).?;
        const value = try self.lowerNode(access.value, null);
        return self.pending(node, .{ .resolve_choice_payload = .{
            .node = self.nextNodeId(),
            .value = value.node,
            .option_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)),
        } }, expected);
    }

    fn lowerErrorPropagation(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId, context: ?entities.ModuleNodeId) !Lowered {
        const child = try self.lowerNode(self.tree.unaryOperand(node).?, null);
        return self.pending(node, .{ .resolve_error_propagation = .{
            .node = self.nextNodeId(),
            .errable_value = child.node,
            .context = context,
        } }, expected);
    }

    fn lowerErrorContext(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const op = self.tree.binaryOperation(node).?;
        const value = try self.lowerNode(op.lhs, null);
        const context = try self.lowerNode(op.rhs, null);
        return self.pending(node, .{ .resolve_error_propagation = .{
            .node = self.nextNodeId(),
            .errable_value = value.node,
            .context = context.node,
        } }, expected);
    }

    fn lowerNullableTest(self: *Context, node: syn.NodeIndex) !Lowered {
        const value = try self.lowerNode(self.tree.unaryOperand(node).?, null);
        return self.pending(node, .{ .resolve_nullable_test = .{ .node = self.nextNodeId(), .value = value.node } }, try self.builtin(.Bool));
    }

    fn lowerIndex(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId, store: ?entities.ModuleNodeId) !Lowered {
        const access = self.tree.indexAccess(node).?;
        const value = try self.lowerNode(access.value, null);
        const index = try self.lowerNode(access.index, try self.builtin(.Int32));
        return self.pending(node, .{ .resolve_index = .{
            .node = self.nextNodeId(),
            .value = value.node,
            .index = index.node,
            .store_value = store,
        } }, expected);
    }

    fn lowerIndexAssignment(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const assignment = self.tree.indexAssignment(node).?;
        const target = self.tree.indexAccess(assignment.target) orelse return error.InvalidIndexAssignmentTarget;
        const collection = try self.lowerNode(target.value, null);
        const index = try self.lowerNode(target.index, try self.builtin(.Int32));
        const value = try self.lowerNode(assignment.value, expected);
        return self.pending(node, .{ .resolve_index = .{
            .node = self.nextNodeId(),
            .value = collection.node,
            .index = index.node,
            .store_value = value.node,
        } }, expected orelse value.ty);
    }

    fn lowerReturn(self: *Context, node: syn.NodeIndex) !Lowered {
        const ret = self.tree.returnStatement(node).?;
        const value = if (ret.value) |child| try self.lowerNode(child, null) else null;
        const ty: ?entities.ModuleTypeId = if (value) |item| item.ty else try self.builtin(.Void);
        return self.resolved(node, ty, .{ .return_statement = .{
            .expression = if (value) |item| item.node else null,
            .cleanup = .{ .start = @intCast(self.graph.semantic.node_refs.items.len), .len = 0 },
        } });
    }

    fn lowerBinary(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const op = self.tree.binaryOperation(node).?;
        const lhs = try self.lowerNode(op.lhs, null);
        const rhs = try self.lowerNode(op.rhs, lhs.ty);
        const operator: primitives.BinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .addition,
            .binary_subtract => .subtraction,
            .binary_multiply => .multiplication,
            .binary_divide => .division,
            .binary_modulo => .modulo,
            else => unreachable,
        };
        return self.pending(node, .{ .resolve_binary = .{
            .node = self.nextNodeId(),
            .operator = operator,
            .left = lhs.node,
            .right = rhs.node,
        } }, expected orelse lhs.ty);
    }

    fn lowerComparison(self: *Context, node: syn.NodeIndex) !Lowered {
        const op = self.tree.binaryOperation(node).?;
        const lhs = try self.lowerNode(op.lhs, null);
        const rhs = try self.lowerNode(op.rhs, lhs.ty);
        const operator: primitives.ComparisonOperator = switch (self.tree.tag(node)) {
            .compare_equal => .equal,
            .compare_not_equal => .not_equal,
            .compare_less => .less_than,
            .compare_greater => .greater_than,
            .compare_less_equal => .less_than_or_equal,
            .compare_greater_equal => .greater_than_or_equal,
            else => unreachable,
        };
        return self.pending(node, .{ .resolve_comparison = .{
            .node = self.nextNodeId(),
            .operator = operator,
            .left = lhs.node,
            .right = rhs.node,
        } }, try self.builtin(.Bool));
    }

    fn lowerLogical(self: *Context, node: syn.NodeIndex) !Lowered {
        const op = self.tree.binaryOperation(node).?;
        const bool_ty = try self.builtin(.Bool);
        const lhs = try self.lowerNode(op.lhs, bool_ty);
        const rhs = try self.lowerNode(op.rhs, bool_ty);
        return self.resolved(node, bool_ty, .{ .logical_operation = .{
            .operator = if (self.tree.tag(node) == .logical_and) .and_ else .or_,
            .left = lhs.node,
            .right = rhs.node,
        } });
    }

    fn lowerIf(self: *Context, node: syn.NodeIndex) !Lowered {
        const statement = self.tree.ifStatement(node).?;
        const condition = try self.lowerNode(statement.condition, try self.builtin(.Bool));
        const then_block = try self.lowerBlock(statement.then_block);
        const else_block = if (statement.else_block) |child| try self.lowerBlock(child) else null;
        return self.resolved(node, try self.builtin(.Void), .{ .if_statement = .{
            .condition = condition.node,
            .then_block = then_block,
            .else_block = else_block,
        } });
    }

    fn lowerWhile(self: *Context, node: syn.NodeIndex) !Lowered {
        const statement = self.tree.whileStatement(node).?;
        const condition = try self.lowerNode(statement.condition, try self.builtin(.Bool));
        const body = try self.lowerBlock(statement.body);
        return self.resolved(node, try self.builtin(.Void), .{ .while_statement = .{ .condition = condition.node, .body = body } });
    }

    fn lowerFor(self: *Context, node: syn.NodeIndex) !Lowered {
        const statement = self.tree.forStatement(node).?;
        const iterable = try self.lowerNode(statement.iterable, null);
        const name_text = self.tree.tokenTextFromSource(self.source, statement.name_token);
        const binding = try self.writer.addUnresolvedBinding(
            try self.writer.addString(name_text),
            self.sourceRef(node),
            null,
            if (statement.mode == .mut_borrow) .variable else .constant,
        );
        try self.pushScope();
        const name = self.graph.semantic.bindings.items[@intFromEnum(binding)].name;
        try self.bindings.append(.{ .name = name, .id = binding, .ty = null });
        const body = try self.lowerBlock(statement.body);
        self.popScope();
        return self.pending(node, .{ .resolve_for_each = .{
            .node = self.nextNodeId(),
            .binding = binding,
            .iterable = iterable.node,
            .body = body,
            .mode = graph_mod.forModeFromSyntax(statement.mode),
        } }, try self.builtin(.Void));
    }

    fn lowerMatch(self: *Context, node: syn.NodeIndex) !Lowered {
        const statement = self.tree.matchStatement(node).?;
        const value = try self.lowerNode(statement.value, null);
        var case_nodes = std.array_list.Managed(entities.ModuleNodeId).init(self.allocator);
        defer case_nodes.deinit();
        for (statement.cases) |case_node| {
            const case = self.tree.matchCase(case_node).?;
            const option_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, case.variant_token));
            const option = try self.writer.addExternalRef(.{
                .kind = .choice_option,
                .module_path = null,
                .name = option_name,
                .source = self.sourceRef(case_node),
            });
            var payload_binding: ?entities.ModuleBindingId = null;
            try self.pushScope();
            if (case.payload_name) |token_index| {
                const text = self.tree.tokenTextFromSource(self.source, token_index);
                const id = try self.writer.addUnresolvedBinding(
                    try self.writer.addString(text),
                    self.sourceRef(case_node),
                    null,
                    if (case.mode == .mut_borrow) .variable else .constant,
                );
                payload_binding = id;
                const name = self.graph.semantic.bindings.items[@intFromEnum(id)].name;
                try self.bindings.append(.{ .name = name, .id = id, .ty = null });
            }
            const body = try self.lowerBlock(case.body);
            self.popScope();
            const case_id = self.nextNodeId();
            const pending_id = try self.writer.addPendingOperation(.{ .resolve_match_case = .{
                .node = case_id,
                .option = option,
                .payload_binding = payload_binding,
                .body = body,
                .mode = graph_mod.matchCaseModeFromSyntax(case.mode),
            } });
            const stored = try self.writer.addNode(.{ .pending = pending_id });
            try case_nodes.append(stored);
        }
        return self.pending(node, .{ .resolve_match = .{
            .node = self.nextNodeId(),
            .value = value.node,
            .cases = try self.writer.appendNodeRefs(case_nodes.items),
        } }, try self.builtin(.Void));
    }

    fn lowerDefer(self: *Context, node: syn.NodeIndex) !Lowered {
        const value = try self.lowerNode(self.tree.unaryOperand(node).?, null);
        return self.pending(node, .{ .resolve_defer = .{ .node = self.nextNodeId(), .value = value.node } }, try self.builtin(.Void));
    }

    fn lowerKeep(self: *Context, node: syn.NodeIndex) !Lowered {
        const keep = self.tree.keepStatement(node).?;
        const name = self.tree.tokenTextFromSource(self.source, keep.name_token);
        if (self.lookupBinding(name)) |binding|
            return self.pending(node, .{ .resolve_keep = .{ .node = self.nextNodeId(), .binding = binding.id } }, try self.builtin(.Void));
        return self.pending(node, .{ .resolve_keep_name = .{
            .node = self.nextNodeId(),
            .name = try self.writer.addString(name),
        } }, try self.builtin(.Void));
    }

    fn lowerReach(self: *Context, node: syn.NodeIndex) !Lowered {
        const directive = self.tree.reachDirective(node).?;
        const alt_start: u32 = @intCast(self.graph.semantic.reach_alternatives.items.len);
        for (directive.alternatives) |alt_node| {
            const alt = self.tree.reachAlternative(alt_node).?;
            const seg_start: u32 = @intCast(self.graph.semantic.reach_segments.items.len);
            for (alt.segments) |segment| {
                try self.graph.semantic.reach_segments.append(self.allocator, try self.writer.addString(self.tree.tokenTextFromSource(self.source, self.tree.mainToken(segment))));
            }
            try self.graph.semantic.reach_alternatives.append(self.allocator, .{
                .segments = .{ .start = seg_start, .len = @intCast(alt.segments.len) },
            });
        }
        const reach_id: entities.ModuleReachId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.reaches.items.len)));
        try self.graph.semantic.reaches.append(self.allocator, .{
            .alternatives = .{ .start = alt_start, .len = @intCast(directive.alternatives.len) },
        });
        return self.resolved(node, try self.builtin(.Void), .{ .reach_directive = reach_id });
    }

    fn lowerAddress(self: *Context, node: syn.NodeIndex) !Lowered {
        const address = self.tree.addressOf(node).?;
        const value = try self.lowerNode(address.value, null);
        const child_ty = try self.compatibilityType(value.ty);
        const ty = try self.writer.addResolvedType(.{ .pointer = .{ .child = child_ty, .mutability = graph_mod.pointerMutabilityFromSyntax(address.mutability) } });
        return self.resolved(node, ty, .{ .address_of = value.node });
    }

    fn lowerDereference(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const value = try self.lowerNode(self.tree.unaryOperand(node).?, null);
        if (value.ty) |pointer_ty| {
            if (try self.pointerChild(pointer_ty)) |child_ty| {
                return self.resolved(node, child_ty, .{ .dereference = .{
                    .pointer = value.node,
                    .ty = child_ty,
                    .pointer_type = pointer_ty,
                } });
            }
        }
        return self.pending(node, .{ .resolve_dereference = .{
            .node = self.nextNodeId(),
            .pointer = value.node,
        } }, expected);
    }

    fn pointerChild(self: *Context, ty: entities.ModuleTypeId) !?entities.ModuleTypeId {
        return switch (try views.typeView(self.graph, ty)) {
            .external => null,
            .resolved => |semantic_type| switch (semantic_type) {
                .pointer => |pointer| pointer.child,
                else => null,
            },
        };
    }

    fn lowerPointerAssignment(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const assignment = self.tree.pointerAssignment(node).?;
        const pointer = try self.lowerNode(assignment.target, null);
        const value = try self.lowerNode(assignment.value, expected);
        const ty: ?entities.ModuleTypeId = expected orelse value.ty;
        return self.resolved(node, ty, .{ .pointer_assignment = .{ .pointer = pointer.node, .value = value.node } });
    }

    fn lowerTypeLiteral(self: *Context, node: syn.NodeIndex) !Lowered {
        const value = try self.lowerType(node);
        return self.resolved(node, try self.builtin(.Type), .{ .type_literal = value });
    }

    fn wrapUnary(self: *Context, node: syn.NodeIndex, comptime tag: anytype, expected: ?entities.ModuleTypeId) !Lowered {
        const value = try self.lowerNode(self.tree.unaryOperand(node).?, expected);
        return self.resolved(node, value.ty, @unionInit(entities.ResolvedNode.Content, @tagName(tag), value.node));
    }

    fn lowerImport(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const statement = self.tree.importStatement(node).?;
        const path = self.tree.tokenTextFromSource(self.source, statement.path_token);
        return self.pending(node, .{ .resolve_import = .{
            .node = self.nextNodeId(),
            .path = try self.writer.addString(path),
        } }, expected);
    }

    fn pending(self: *Context, node: syn.NodeIndex, operation: entities.PendingOperation, ty: ?entities.ModuleTypeId) !Lowered {
        _ = node;
        const id = try self.writer.addPendingNode(operation);
        return .{ .node = id, .ty = ty };
    }

    fn resolved(self: *Context, node: syn.NodeIndex, ty: ?entities.ModuleTypeId, content: entities.ResolvedNode.Content) !Lowered {
        return .{ .node = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = content }), .ty = ty };
    }

    fn resolvedVoid(self: *Context, node: syn.NodeIndex, content: entities.ResolvedNode.Content) !Lowered {
        return self.resolved(node, try self.builtin(.Void), content);
    }

    /// Temporary boundary for semantic payloads that still require a concrete
    /// ModuleTypeId during local lowering. Unknown expression types themselves
    /// are represented as `null`; every remaining `Any` introduced here is a
    /// compatibility bridge to be removed as those payloads become pending-aware.
    fn compatibilityType(self: *Context, ty: ?entities.ModuleTypeId) !entities.ModuleTypeId {
        return ty orelse self.builtin(.Any);
    }

    fn lowerType(self: *Context, node: syn.NodeIndex) !entities.ModuleTypeId {
        var lowerer = type_lowerer.Context{
            .graph = self.graph,
            .writer = &self.writer,
            .file_index = self.file_index,
            .tree = self.tree,
            .source = self.source,
        };
        return lowerer.lower(node);
    }

    fn builtin(self: *Context, value: primitives.BuiltinType) !entities.ModuleTypeId {
        for (0..views.typeCount(self.graph)) |index| {
            const id: entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(index)));
            switch (try views.typeView(self.graph, id)) {
                .resolved => |candidate| switch (candidate) {
                    .builtin => |builtin_value| if (builtin_value == value) return id,
                    else => {},
                },
                .external => {},
            }
        }
        return self.writer.addResolvedType(.{ .builtin = value });
    }

    fn sourceRef(self: *const Context, node: syn.NodeIndex) primitives.SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }

    fn nextNodeId(self: *const Context) entities.ModuleNodeId {
        return @enumFromInt(@as(u32, @intCast(self.graph.semantic.nodes.items.len)));
    }

    fn seedGlobalBindings(self: *Context) !void {
        self.bindings.clearRetainingCapacity();
        for (self.graph.semantic.declaration_bindings.items) |relation| {
            const declaration = self.graph.declarations.items[@intFromEnum(relation.declaration)];
            const binding = self.graph.semantic.bindings.items[@intFromEnum(relation.binding)];
            try self.bindings.append(.{
                .name = declaration.name,
                .id = relation.binding,
                .ty = if (views.bindingTypeUnresolved(self.graph, relation.binding)) null else binding.ty,
            });
        }
    }

    fn pushScope(self: *Context) !void {
        try self.scope_marks.append(self.bindings.items.len);
    }
    fn popScope(self: *Context) void {
        const mark = self.scope_marks.pop().?;
        self.bindings.shrinkRetainingCapacity(mark);
    }
    fn lookupBinding(self: *const Context, name: []const u8) ?NamedBinding {
        var index = self.bindings.items.len;
        while (index != 0) {
            index -= 1;
            if (std.mem.eql(u8, self.graph.text(self.bindings.items[index].name), name)) return self.bindings.items[index];
        }
        return null;
    }
};

fn hasFunctionSemantic(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) bool {
    for (graph.semantic.function_semantics.items) |semantic| if (semantic.function == id) return true;
    return false;
}

test "module body lowerer keeps unresolved expression types explicit" {
    try std.testing.expect(@sizeOf(Lowered) <= 12);
}

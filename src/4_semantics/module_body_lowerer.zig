const std = @import("std");
const literals = @import("semantic_literals.zig");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const graph_mod = @import("module_semantic_graph.zig");
const entities = @import("module_semantic_entities.zig");
const primitives = @import("semantic_primitives.zig");
const views = @import("module_semantic_views.zig");
const writer_mod = @import("module_semantic_writer.zig");
const type_lowerer = @import("module_type_lowerer.zig");

pub const Result = struct {
    lowered_functions: u32 = 0,
    deferred_functions: u32 = 0,
};

const NamedBinding = struct {
    name: []const u8,
    id: entities.ModuleBindingId,
};

const Lowered = struct {
    node: entities.ModuleNodeId,
    ty: ?entities.ModuleTypeId,
};

const Checkpoint = struct {
    bindings: usize,
    nodes: usize,
    blocks: usize,
    value_fields: usize,
    switches: usize,
    switch_cases: usize,
    node_refs: usize,
    type_refs: usize,
    binding_refs: usize,
    pending: usize,
    external_refs: usize,
    canonical_types: usize,
    canonical_fields: usize,
    canonical_variants: usize,
    canonical_generic_args: usize,
    function_semantics: usize,
    scopes: usize,
    roots: usize,

    fn capture(graph: *const graph_mod.ModuleSemanticGraph) Checkpoint {
        const s = &graph.semantic;
        return .{
            .bindings = s.bindings.items.len,
            .nodes = s.nodes.items.len,
            .blocks = s.blocks.items.len,
            .value_fields = s.value_fields.items.len,
            .switches = s.switches.items.len,
            .switch_cases = s.switch_cases.items.len,
            .node_refs = s.node_refs.items.len,
            .type_refs = s.type_refs.items.len,
            .binding_refs = s.binding_refs.items.len,
            .pending = s.pending_operations.items.len,
            .external_refs = s.external_refs.items.len,
            .canonical_types = s.types.items.len,
            .canonical_fields = s.fields.items.len,
            .canonical_variants = s.variants.items.len,
            .canonical_generic_args = s.generic_arguments.items.len,
            .function_semantics = s.function_semantics.items.len,
            .scopes = s.scopes.items.len,
            .roots = s.roots.items.len,
        };
    }

    fn restore(self: Checkpoint, graph: *graph_mod.ModuleSemanticGraph) void {
        const s = &graph.semantic;
        s.bindings.shrinkRetainingCapacity(self.bindings);
        s.nodes.shrinkRetainingCapacity(self.nodes);
        s.blocks.shrinkRetainingCapacity(self.blocks);
        s.value_fields.shrinkRetainingCapacity(self.value_fields);
        s.switches.shrinkRetainingCapacity(self.switches);
        s.switch_cases.shrinkRetainingCapacity(self.switch_cases);
        s.node_refs.shrinkRetainingCapacity(self.node_refs);
        s.type_refs.shrinkRetainingCapacity(self.type_refs);
        s.binding_refs.shrinkRetainingCapacity(self.binding_refs);
        s.pending_operations.shrinkRetainingCapacity(self.pending);
        s.external_refs.shrinkRetainingCapacity(self.external_refs);
        s.types.shrinkRetainingCapacity(self.canonical_types);
        s.fields.shrinkRetainingCapacity(self.canonical_fields);
        s.variants.shrinkRetainingCapacity(self.canonical_variants);
        s.generic_arguments.shrinkRetainingCapacity(self.canonical_generic_args);
        s.function_semantics.shrinkRetainingCapacity(self.function_semantics);
        s.scopes.shrinkRetainingCapacity(self.scopes);
        s.roots.shrinkRetainingCapacity(self.roots);
    }
};

pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !Result {
    var ctx = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .writer = writer_mod.Writer.init(allocator, graph),
        .bindings = std.array_list.Managed(NamedBinding).init(allocator),
        .scope_marks = std.array_list.Managed(usize).init(allocator),
    };
    defer ctx.bindings.deinit();
    defer ctx.scope_marks.deinit();
    return ctx.lowerFunctions();
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

    fn lowerFunctions(self: *Context) !Result {
        var result: Result = .{};
        for (self.graph.functions.items, 0..) |interface, raw_function_index| {
            const function_id: entities.ModuleFunctionId = @enumFromInt(@as(u32, @intCast(raw_function_index)));
            if (hasFunctionSemantic(self.graph, function_id)) continue;
            const declaration = self.graph.declarations.items[@intFromEnum(interface.declaration)];
            self.file_index = declaration.module_file_index;
            const input = self.files[@intCast(self.file_index)];
            self.tree = input.tree;
            self.source = input.source;
            const function = switch (declaration.kind) {
                .function => self.tree.functionDeclaration(declaration.syntax_node) orelse continue,
                .test_function => (self.tree.testDeclaration(declaration.syntax_node) orelse continue).function,
                else => continue,
            };
            if (function.generic_params.len != 0 or function.generic_params_struct != null) continue;

            const checkpoint = Checkpoint.capture(self.graph);
            self.bindings.clearRetainingCapacity();
            self.scope_marks.clearRetainingCapacity();
            try self.pushScope();
            self.lowerOneFunction(function_id, interface, function, declaration.kind == .test_function) catch |err| switch (err) {
                error.UnsupportedLocalSemantic,
                error.UnresolvedLocalType,
                error.CannotInferLocalType,
                => {
                    checkpoint.restore(self.graph);
                    result.deferred_functions += 1;
                    continue;
                },
                else => return err,
            };
            self.popScope();
            result.lowered_functions += 1;
        }
        return result;
    }

    fn lowerOneFunction(
        self: *Context,
        function_id: entities.ModuleFunctionId,
        interface: graph_mod.FunctionInterface,
        declaration: syn.FunctionDeclaration,
        is_test: bool,
    ) !void {
        var input_ids = std.array_list.Managed(entities.ModuleBindingId).init(self.allocator);
        defer input_ids.deinit();
        var output_ids = std.array_list.Managed(entities.ModuleBindingId).init(self.allocator);
        defer output_ids.deinit();

        try self.bindInterfaceFields(interface.input, .constant, &input_ids);
        try self.bindInterfaceFields(interface.output, .variable, &output_ids);
        const input_range = try self.writer.appendBindingRefs(input_ids.items);
        const output_range = try self.writer.appendBindingRefs(output_ids.items);

        const body = if (declaration.body) |body_node| try self.lowerBlock(body_node) else null;
        var scope_ids = std.array_list.Managed(entities.ModuleBindingId).init(self.allocator);
        defer scope_ids.deinit();
        for (self.bindings.items) |binding| try scope_ids.append(binding.id);
        const scope_bindings = try self.writer.appendBindingRefs(scope_ids.items);
        try self.graph.semantic.scopes.append(self.allocator, .{
            .parent = .none,
            .bindings = scope_bindings,
        });
        try self.graph.semantic.function_semantics.append(self.allocator, .{
            .function = function_id,
            .body = body,
            .input_bindings = input_range,
            .output_bindings = output_range,
            .flags = .{
                .is_once = declaration.is_once,
                .is_test = is_test,
                .has_declared_body = declaration.body != null,
            },
        });
    }

    fn bindInterfaceFields(
        self: *Context,
        range: graph_mod.FieldRange,
        mutability: syn.Mutability,
        ids: *std.array_list.Managed(entities.ModuleBindingId),
    ) !void {
        const start: usize = range.start;
        const count: usize = range.len;
        for (self.graph.fields.items[start..][0..count]) |field| {
            const id = try self.writer.addBinding(.{
                .name = field.name,
                .source = .{ .file_index = field.module_file_index, .offset = field.source_offset },
                .ty = field.ty,
                .mutability = mutability,
            });
            try ids.append(id);
            try self.bindings.append(.{ .name = self.graph.text(field.name), .id = id });
        }
    }

    fn lowerBlock(self: *Context, node: syn.NodeIndex) anyerror!entities.ModuleBlockId {
        const block = self.tree.codeBlock(node) orelse return error.UnsupportedLocalSemantic;
        try self.pushScope();
        defer self.popScope();

        var nodes = std.array_list.Managed(entities.ModuleNodeId).init(self.allocator);
        defer nodes.deinit();
        var ret_val: ?entities.ModuleNodeId = null;
        for (block.statements) |statement| {
            const lowered = try self.lowerNode(statement, null);
            try nodes.append(lowered.node);
            ret_val = lowered.node;
        }
        const range = try self.writer.appendNodeRefs(nodes.items);
        return self.writer.addBlock(.{ .nodes = range, .ret_val = ret_val });
    }

    fn lowerNode(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) anyerror!Lowered {
        return switch (self.tree.tag(node)) {
            .literal => self.lowerLiteral(node),
            .identifier => self.lowerIdentifier(node),
            .symbol_declaration_constant, .symbol_declaration_variable => self.lowerBindingDeclaration(node),
            .assignment => self.lowerAssignment(node),
            .expression_statement => self.lowerNode(self.tree.unaryOperand(node).?, expected),
            .move_expression => self.lowerMove(node, expected),
            .code_block => blk: {
                const block = try self.lowerBlock(node);
                const id = try self.writer.addResolvedNode(.{
                    .source = self.sourceRef(node),
                    .ty = null,
                    .content = .{ .code_block = block },
                });
                break :blk .{ .node = id, .ty = null };
            },
            .return_statement => self.lowerReturn(node),
            .if_statement => self.lowerIf(node),
            .while_statement => self.lowerWhile(node),
            .break_statement => self.simpleStatement(node, .break_statement),
            .continue_statement => self.simpleStatement(node, .continue_statement),
            .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => self.lowerBinary(node),
            .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal => self.lowerComparison(node),
            .logical_and, .logical_or => self.lowerLogical(node),
            .function_call => self.lowerCall(node),
            .struct_value_literal => self.lowerStructValue(node),
            .list_literal => self.lowerList(node),
            .struct_field_access => self.lowerFieldAccess(node),
            .address_of, .address_of_mut => self.lowerAddressOf(node),
            .dereference => self.lowerDereference(node),
            .pointer_assignment => self.lowerPointerAssignment(node),
            .index_access => self.lowerIndexAccess(node),
            .index_assignment => self.lowerIndexAssignment(node),
            .type_name, .pointer_type, .pointer_type_mut, .nullable_type, .inferred_errable_type, .array_type, .generic_type_instantiation => self.lowerTypeLiteral(node),
            else => error.UnsupportedLocalSemantic,
        };
    }

    fn lowerLiteral(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.literal(node) orelse return error.UnsupportedLocalSemantic;
        const content = self.tree.tokenContent(literal.token).literal;
        return switch (content) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => blk: {
                const value = try literals.integer(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                const ty = try self.builtinType(.Int32);
                const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .int_literal = value } });
                break :blk .{ .node = id, .ty = ty };
            },
            .regular_float_literal, .scientific_float_literal => blk: {
                const value = try literals.float(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                const ty = try self.builtinType(.Float32);
                const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .float_literal = value } });
                break :blk .{ .node = id, .ty = ty };
            },
            .bool_literal => |value| blk: {
                const ty = try self.builtinType(.Bool);
                const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .bool_literal = value } });
                break :blk .{ .node = id, .ty = ty };
            },
            .char_literal => |value| blk: {
                const ty = try self.builtinType(.Char);
                const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .char_literal = value } });
                break :blk .{ .node = id, .ty = ty };
            },
            .string_literal => blk: {
                const text = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token));
                const type_name = try self.writer.addString("StringView");
                const external = try self.writer.addExternalRef(.{
                    .kind = .type,
                    .module_path = null,
                    .name = type_name,
                    .source = self.sourceRef(node),
                });
                const ty = try self.writer.addExternalType(external);
                const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .string_literal = text } });
                break :blk .{ .node = id, .ty = ty };
            },
        };
    }

    fn lowerIdentifier(self: *Context, node: syn.NodeIndex) !Lowered {
        const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
        const binding = self.lookupBinding(name) orelse return error.UnsupportedLocalSemantic;
        const record = self.graph.semantic.bindings.items[@intFromEnum(binding)];
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = record.ty, .content = .{ .binding_use = binding } });
        return .{ .node = id, .ty = record.ty };
    }

    fn lowerBindingDeclaration(self: *Context, node: syn.NodeIndex) !Lowered {
        const declaration = self.tree.symbolDeclaration(node) orelse return error.UnsupportedLocalSemantic;
        const value = if (declaration.value) |value_node| try self.lowerNode(value_node, null) else null;
        const ty = if (declaration.type_node) |type_node|
            try self.lowerType(type_node)
        else if (value) |resolved|
            resolved.ty orelse return error.CannotInferLocalType
        else
            return error.CannotInferLocalType;
        const name_text = self.tree.tokenTextFromSource(self.source, declaration.name_token);
        const name = try self.writer.addString(name_text);
        const binding = try self.writer.addBinding(.{
            .name = name,
            .source = self.sourceRef(node),
            .ty = ty,
            .initialization = if (value) |resolved| resolved.node else null,
            .mutability = declaration.mutability,
        });
        try self.bindings.append(.{ .name = name_text, .id = binding });
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .binding_declaration = binding } });
        return .{ .node = id, .ty = ty };
    }

    fn lowerAssignment(self: *Context, node: syn.NodeIndex) !Lowered {
        const assignment = self.tree.assignment(node) orelse return error.UnsupportedLocalSemantic;
        const name = self.tree.tokenTextFromSource(self.source, assignment.name_token);
        const binding = self.lookupBinding(name) orelse return error.UnsupportedLocalSemantic;
        const binding_ty = self.graph.semantic.bindings.items[@intFromEnum(binding)].ty;
        const value = try self.lowerNode(assignment.value, binding_ty);
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = binding_ty,
            .content = .{ .assignment = .{ .binding = binding, .value = value.node } },
        });
        return .{ .node = id, .ty = binding_ty };
    }

    fn lowerMove(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const child = try self.lowerNode(self.tree.unaryOperand(node).?, expected);
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = child.ty, .content = .{ .move_value = child.node } });
        return .{ .node = id, .ty = child.ty };
    }

    fn lowerReturn(self: *Context, node: syn.NodeIndex) !Lowered {
        const ret = self.tree.returnStatement(node) orelse return error.UnsupportedLocalSemantic;
        const value = if (ret.value) |value_node| try self.lowerNode(value_node, null) else null;
        const void_ty = try self.builtinType(.Void);
        const result_ty: ?entities.ModuleTypeId = if (value) |resolved| resolved.ty else void_ty;
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = result_ty,
            .content = .{ .return_statement = .{
                .expression = if (value) |resolved| resolved.node else null,
                .cleanup = .{ .start = @intCast(self.graph.semantic.node_refs.items.len), .len = 0 },
            } },
        });
        return .{ .node = id, .ty = result_ty };
    }

    fn lowerIf(self: *Context, node: syn.NodeIndex) !Lowered {
        const statement = self.tree.ifStatement(node) orelse return error.UnsupportedLocalSemantic;
        const bool_ty = try self.builtinType(.Bool);
        const condition = try self.lowerNode(statement.condition, bool_ty);
        const then_block = try self.lowerBlock(statement.then_block);
        const else_block = if (statement.else_block) |else_node| try self.lowerBlock(else_node) else null;
        const void_ty = try self.builtinType(.Void);
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = void_ty,
            .content = .{ .if_statement = .{
                .condition = condition.node,
                .then_block = then_block,
                .else_block = else_block,
            } },
        });
        return .{ .node = id, .ty = void_ty };
    }

    fn lowerWhile(self: *Context, node: syn.NodeIndex) !Lowered {
        const statement = self.tree.whileStatement(node) orelse return error.UnsupportedLocalSemantic;
        const condition = try self.lowerNode(statement.condition, try self.builtinType(.Bool));
        const body = try self.lowerBlock(statement.body);
        const void_ty = try self.builtinType(.Void);
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = void_ty,
            .content = .{ .while_statement = .{ .condition = condition.node, .body = body } },
        });
        return .{ .node = id, .ty = void_ty };
    }

    fn simpleStatement(self: *Context, node: syn.NodeIndex, content: entities.ResolvedNode.Content) !Lowered {
        const ty = try self.builtinType(.Void);
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = content });
        return .{ .node = id, .ty = ty };
    }

    fn lowerBinary(self: *Context, node: syn.NodeIndex) !Lowered {
        const operation = self.tree.binaryOperation(node) orelse return error.UnsupportedLocalSemantic;
        const lhs = try self.lowerNode(operation.lhs, null);
        const rhs = try self.lowerNode(operation.rhs, lhs.ty);
        const ty = lhs.ty orelse rhs.ty orelse return error.CannotInferLocalType;
        const operator: tok.BinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .addition,
            .binary_subtract => .subtraction,
            .binary_multiply => .multiplication,
            .binary_divide => .division,
            .binary_modulo => .modulo,
            else => unreachable,
        };
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .binary_operation = .{ .operator = operator, .left = lhs.node, .right = rhs.node } } });
        return .{ .node = id, .ty = ty };
    }

    fn lowerComparison(self: *Context, node: syn.NodeIndex) !Lowered {
        const operation = self.tree.binaryOperation(node) orelse return error.UnsupportedLocalSemantic;
        const lhs = try self.lowerNode(operation.lhs, null);
        const rhs = try self.lowerNode(operation.rhs, lhs.ty);
        const operator: tok.ComparisonOperator = switch (self.tree.tag(node)) {
            .compare_equal => .equal,
            .compare_not_equal => .not_equal,
            .compare_less => .less_than,
            .compare_greater => .greater_than,
            .compare_less_equal => .less_than_or_equal,
            .compare_greater_equal => .greater_than_or_equal,
            else => unreachable,
        };
        const ty = try self.builtinType(.Bool);
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .comparison = .{ .operator = operator, .left = lhs.node, .right = rhs.node } } });
        return .{ .node = id, .ty = ty };
    }

    fn lowerLogical(self: *Context, node: syn.NodeIndex) !Lowered {
        const operation = self.tree.binaryOperation(node) orelse return error.UnsupportedLocalSemantic;
        const ty = try self.builtinType(.Bool);
        const lhs = try self.lowerNode(operation.lhs, ty);
        const rhs = try self.lowerNode(operation.rhs, ty);
        const operator: primitives.LogicalOperator = if (self.tree.tag(node) == .logical_and) .and_ else .or_;
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = .{ .logical_operation = .{ .operator = operator, .left = lhs.node, .right = rhs.node } } });
        return .{ .node = id, .ty = ty };
    }

    fn lowerCall(self: *Context, node: syn.NodeIndex) !Lowered {
        const call = self.tree.functionCall(node) orelse return error.UnsupportedLocalSemantic;
        const input = try self.lowerNode(call.input, null);
        const name_text = self.tree.tokenTextFromSource(self.source, call.callee_token);
        if (call.module_qualifier == null) {
            var found: ?entities.ModuleFunctionId = null;
            var ambiguous = false;
            for (self.graph.declarationsNamed(name_text)) |decl_id| {
                const declaration = self.graph.declarations.items[@intFromEnum(decl_id)];
                const function = declaration.function_id orelse continue;
                if (found != null) {
                    ambiguous = true;
                    break;
                }
                found = function;
            }
            if (found != null and !ambiguous) {
                const function = try views.functionView(self.graph, found.?);
                const result_ty = try self.functionOutputType(function);
                const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = result_ty, .content = .{ .function_call = .{ .callee = found.?, .input = input.node } } });
                return .{ .node = id, .ty = result_ty };
            }
        }
        return self.lowerPendingCall(node, call, input, name_text);
    }

    fn lowerPendingCall(self: *Context, node: syn.NodeIndex, call: syn.FunctionCall, input: Lowered, name_text: []const u8) !Lowered {
        const name = try self.writer.addString(name_text);
        const module_path = if (call.module_qualifier) |qualifier|
            try self.writer.addString(self.tree.tokenTextFromSource(self.source, qualifier))
        else
            null;
        const external = try self.writer.addExternalRef(.{
            .kind = .function,
            .module_path = module_path,
            .name = name,
            .source = self.sourceRef(node),
        });
        const node_id: entities.ModuleNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.nodes.items.len)));
        const pending_id: entities.PendingOperationId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.pending_operations.items.len)));
        try self.graph.semantic.nodes.append(self.allocator, .{ .pending = pending_id });
        try self.graph.semantic.pending_operations.append(self.allocator, .{ .resolve_call = .{ .node = node_id, .callee = external, .input = input.node } });
        return .{ .node = node_id, .ty = null };
    }

    fn lowerStructValue(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.structValueLiteral(node) orelse return error.UnsupportedLocalSemantic;
        const value_start: u32 = @intCast(self.graph.semantic.value_fields.items.len);
        var type_first: ?entities.ModuleFieldId = null;
        var field_count: u32 = 0;
        for (literal.fields) |field_node| {
            const field = self.tree.valueField(field_node) orelse return error.UnsupportedLocalSemantic;
            const value = try self.lowerNode(field.value, null);
            const ty = value.ty orelse return error.CannotInferLocalType;
            const name_text = if (field.name_token) |name_token|
                self.tree.tokenTextFromSource(self.source, name_token)
            else
                "";
            const name = try self.writer.addString(name_text);
            try self.graph.semantic.value_fields.append(self.allocator, .{ .name = name, .value = value.node });
            const type_field = try self.writer.addField(.{ .name = name, .ty = ty, .source = self.sourceRef(field_node) });
            if (type_first == null) type_first = type_field;
            field_count += 1;
        }
        const structural_ty = try self.writer.addResolvedType(.{ .structural = .{
            .fields = .{ .start = if (type_first) |id| @intFromEnum(id) else @intCast(views.fieldCount(self.graph)), .len = field_count },
            .layout = .regular,
        } });
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = structural_ty,
            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = value_start, .len = field_count },
                .ty = structural_ty,
                .dispatch_prefix_positional_count = literal.positional_prefix_count,
            } },
        });
        return .{ .node = id, .ty = structural_ty };
    }

    fn lowerList(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.listLiteral(node) orelse return error.UnsupportedLocalSemantic;
        var node_ids = std.array_list.Managed(entities.ModuleNodeId).init(self.allocator);
        defer node_ids.deinit();
        var type_ids = std.array_list.Managed(entities.ModuleTypeId).init(self.allocator);
        defer type_ids.deinit();
        for (literal.elements) |element_node| {
            const element = try self.lowerNode(element_node, null);
            try node_ids.append(element.node);
            try type_ids.append(element.ty orelse return error.CannotInferLocalType);
        }
        const element_range = try self.writer.appendNodeRefs(node_ids.items);
        const type_start: u32 = @intCast(self.graph.semantic.type_refs.items.len);
        try self.graph.semantic.type_refs.appendSlice(self.allocator, type_ids.items);
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = null,
            .content = .{ .list_literal = .{
                .elements = element_range,
                .element_types = .{ .start = type_start, .len = @intCast(type_ids.items.len) },
            } },
        });
        return .{ .node = id, .ty = null };
    }

    fn lowerFieldAccess(self: *Context, node: syn.NodeIndex) !Lowered {
        const access = self.tree.structFieldAccess(node) orelse return error.UnsupportedLocalSemantic;
        const value = try self.lowerNode(access.value, null);
        const value_ty = value.ty orelse return self.pendingField(node, value, access.field_token);
        const field_name = self.tree.tokenTextFromSource(self.source, access.field_token);
        if (try self.findField(value_ty, field_name)) |field| {
            const id = try self.writer.addResolvedNode(.{
                .source = self.sourceRef(node),
                .ty = field.ty,
                .content = .{ .struct_field_access = .{
                    .value = value.node,
                    .field_name = try self.writer.addString(field_name),
                    .field_index = field.index,
                } },
            });
            return .{ .node = id, .ty = field.ty };
        }
        return self.pendingField(node, value, access.field_token);
    }

    fn pendingField(self: *Context, _: syn.NodeIndex, value: Lowered, field_token: syn.TokenIndex) !Lowered {
        const field_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field_token));
        const node_id: entities.ModuleNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.nodes.items.len)));
        const pending_id: entities.PendingOperationId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.pending_operations.items.len)));
        try self.graph.semantic.nodes.append(self.allocator, .{ .pending = pending_id });
        try self.graph.semantic.pending_operations.append(self.allocator, .{ .resolve_field = .{ .node = node_id, .value = value.node, .field_name = field_name } });
        return .{ .node = node_id, .ty = null };
    }

    fn lowerAddressOf(self: *Context, node: syn.NodeIndex) !Lowered {
        const address = self.tree.addressOf(node) orelse return error.UnsupportedLocalSemantic;
        const value = try self.lowerNode(address.value, null);
        const child_ty = value.ty orelse return error.CannotInferLocalType;
        const pointer_ty = try self.writer.addResolvedType(.{ .pointer = .{ .child = child_ty, .mutability = address.mutability } });
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = pointer_ty, .content = .{ .address_of = value.node } });
        return .{ .node = id, .ty = pointer_ty };
    }

    fn lowerDereference(self: *Context, node: syn.NodeIndex) !Lowered {
        const pointer = try self.lowerNode(self.tree.unaryOperand(node).?, null);
        const pointer_ty = pointer.ty orelse return error.CannotInferLocalType;
        const child_ty = (try self.pointerChild(pointer_ty)) orelse return error.UnresolvedLocalType;
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = child_ty,
            .content = .{ .dereference = .{ .pointer = pointer.node, .ty = child_ty, .pointer_type = pointer_ty } },
        });
        return .{ .node = id, .ty = child_ty };
    }

    fn lowerPointerAssignment(self: *Context, node: syn.NodeIndex) !Lowered {
        const assignment = self.tree.pointerAssignment(node) orelse return error.UnsupportedLocalSemantic;
        const pointer = try self.lowerNode(assignment.target, null);
        const pointer_ty = pointer.ty orelse return error.CannotInferLocalType;
        const child_ty = (try self.pointerChild(pointer_ty)) orelse return error.UnresolvedLocalType;
        const value = try self.lowerNode(assignment.value, child_ty);
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = child_ty, .content = .{ .pointer_assignment = .{ .pointer = pointer.node, .value = value.node } } });
        return .{ .node = id, .ty = child_ty };
    }

    fn lowerIndexAccess(self: *Context, node: syn.NodeIndex) !Lowered {
        const access = self.tree.indexAccess(node) orelse return error.UnsupportedLocalSemantic;
        const value = try self.lowerNode(access.value, null);
        const index = try self.lowerNode(access.index, try self.builtinType(.Int32));
        const array_ty = value.ty orelse return error.CannotInferLocalType;
        const element_ty = (try self.arrayElement(array_ty)) orelse return error.UnresolvedLocalType;
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = element_ty,
            .content = .{ .array_index = .{ .array_ptr = value.node, .index = index.node, .element_type = element_ty, .array_type = array_ty } },
        });
        return .{ .node = id, .ty = element_ty };
    }

    fn lowerIndexAssignment(self: *Context, node: syn.NodeIndex) !Lowered {
        const assignment = self.tree.indexAssignment(node) orelse return error.UnsupportedLocalSemantic;
        const access = self.tree.indexAccess(assignment.target) orelse return error.UnsupportedLocalSemantic;
        const array = try self.lowerNode(access.value, null);
        const index = try self.lowerNode(access.index, try self.builtinType(.Int32));
        const array_ty = array.ty orelse return error.CannotInferLocalType;
        const element_ty = (try self.arrayElement(array_ty)) orelse return error.UnresolvedLocalType;
        const value = try self.lowerNode(assignment.value, element_ty);
        const id = try self.writer.addResolvedNode(.{
            .source = self.sourceRef(node),
            .ty = element_ty,
            .content = .{ .array_store = .{ .array_ptr = array.node, .index = index.node, .value = value.node, .element_type = element_ty, .array_type = array_ty } },
        });
        return .{ .node = id, .ty = element_ty };
    }

    fn lowerTypeLiteral(self: *Context, node: syn.NodeIndex) !Lowered {
        const ty = try self.lowerType(node);
        const type_type = try self.builtinType(.Type);
        const id = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = type_type, .content = .{ .type_literal = ty } });
        return .{ .node = id, .ty = type_type };
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

    fn functionOutputType(self: *Context, function: entities.Function) !?entities.ModuleTypeId {
        if (function.output.len == 0) return try self.builtinType(.Void);
        if (function.output.len == 1) return (try views.fieldView(self.graph, @enumFromInt(function.output.start))).ty;
        return null;
    }

    const FieldLookup = struct { index: u32, ty: entities.ModuleTypeId };

    fn findField(self: *Context, ty: entities.ModuleTypeId, name: []const u8) !?FieldLookup {
        const fields = (try self.fieldsOf(ty)) orelse return null;
        for (0..fields.len) |offset| {
            const field_id: entities.ModuleFieldId = @enumFromInt(fields.start + @as(u32, @intCast(offset)));
            const field = try views.fieldView(self.graph, field_id);
            if (std.mem.eql(u8, self.graph.text(field.name), name)) return .{ .index = @intCast(offset), .ty = field.ty };
        }
        return null;
    }

    fn fieldsOf(self: *Context, ty: entities.ModuleTypeId) !?entities.FieldRange {
        const value = try views.typeView(self.graph, ty);
        return switch (value) {
            .external => null,
            .resolved => |resolved| switch (resolved) {
                .structural => |shape| shape.fields,
                .declared => |decl| blk: {
                    const declaration = try views.declarationView(self.graph, decl);
                    break :blk declaration.struct_fields;
                },
                .generic => blk: {
                    for (self.graph.semantic.generic_instances.items) |instance| {
                        if (instance.type_id != ty) continue;
                        break :blk switch (instance.shape) {
                            .structure => |shape| shape.fields,
                            else => null,
                        };
                    }
                    break :blk null;
                },
                else => null,
            },
        };
    }

    fn pointerChild(self: *Context, ty: entities.ModuleTypeId) !?entities.ModuleTypeId {
        const value = try views.typeView(self.graph, ty);
        return switch (value) {
            .external => null,
            .resolved => |resolved| switch (resolved) {
                .pointer => |pointer| pointer.child,
                else => null,
            },
        };
    }

    fn arrayElement(self: *Context, ty: entities.ModuleTypeId) !?entities.ModuleTypeId {
        const value = try views.typeView(self.graph, ty);
        return switch (value) {
            .external => null,
            .resolved => |resolved| switch (resolved) {
                .array => |array| array.element,
                .generic => blk: {
                    for (self.graph.semantic.generic_instances.items) |instance| {
                        if (instance.type_id != ty) continue;
                        break :blk switch (instance.shape) {
                            .array => |array| array.element,
                            else => null,
                        };
                    }
                    break :blk null;
                },
                else => null,
            },
        };
    }

    fn builtinType(self: *Context, builtin: primitives.BuiltinType) !entities.ModuleTypeId {
        for (0..views.typeCount(self.graph)) |index| {
            const id: entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(index)));
            const value = try views.typeView(self.graph, id);
            switch (value) {
                .resolved => |resolved| switch (resolved) {
                    .builtin => |candidate| if (candidate == builtin) return id,
                    else => {},
                },
                .external => {},
            }
        }
        return self.writer.addResolvedType(.{ .builtin = builtin });
    }

    fn sourceRef(self: *const Context, node: syn.NodeIndex) primitives.SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }

    fn pushScope(self: *Context) !void {
        try self.scope_marks.append(self.bindings.items.len);
    }

    fn popScope(self: *Context) void {
        const mark = self.scope_marks.pop().?;
        self.bindings.shrinkRetainingCapacity(mark);
    }

    fn lookupBinding(self: *const Context, name: []const u8) ?entities.ModuleBindingId {
        var index = self.bindings.items.len;
        while (index > 0) {
            index -= 1;
            const binding = self.bindings.items[index];
            if (std.mem.eql(u8, binding.name, name)) return binding.id;
        }
        return null;
    }
};

fn hasFunctionSemantic(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) bool {
    for (graph.semantic.function_semantics.items) |semantic| if (semantic.function == id) return true;
    return false;
}

test "module body lowerer checkpoints are transactional" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);
    try graph.semantic.nodes.append(allocator, .{ .resolved = .{
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = null,
        .content = .break_statement,
    } });
    const checkpoint = Checkpoint.capture(&graph);
    try graph.semantic.nodes.append(allocator, .{ .resolved = .{
        .source = .{ .file_index = 0, .offset = 1 },
        .ty = null,
        .content = .continue_statement,
    } });
    checkpoint.restore(&graph);
    try std.testing.expectEqual(@as(usize, 1), graph.semantic.nodes.items.len);
}

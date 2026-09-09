const std = @import("std");
const literals = @import("semantic_literals.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const tok = @import("../2_tokens/token.zig");
const graph_mod = @import("module_semantic_graph.zig");
const entities = @import("module_semantic_entities.zig");
const writer_mod = @import("module_semantic_writer.zig");
const views = @import("module_semantic_views.zig");
const templates = @import("module_semantic_templates.zig");
const ir = @import("module_semantic_template_ir.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    generic_types: u32 = 0,
    generic_functions: u32 = 0,
    abstract_definitions: u32 = 0,
};

pub const ParameterBinding = struct {
    name: []const u8,
    id: ir.TemplateParameterId,
    kind: templates.GenericParameterKind,
};

const BindingName = struct {
    name: []const u8,
    id: ir.TemplateBindingId,
};

pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !Stats {
    var ctx = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .writer = writer_mod.Writer.init(allocator, graph),
        .parameters = std.array_list.Managed(ParameterBinding).init(allocator),
        .bindings = std.array_list.Managed(BindingName).init(allocator),
    };
    defer ctx.parameters.deinit();
    defer ctx.bindings.deinit();
    return ctx.lowerDeclarations();
}

pub const Context = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    parameters: std.array_list.Managed(ParameterBinding),
    bindings: std.array_list.Managed(BindingName),
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},

    fn lowerDeclarations(self: *Context) !Stats {
        var stats: Stats = .{};
        for (self.graph.declarations.items, 0..) |declaration, raw_decl| {
            self.file_index = declaration.module_file_index;
            const file = self.files[@intCast(self.file_index)];
            self.tree = file.tree;
            self.source = file.source;
            const decl_id: entities.ModuleDeclId = @enumFromInt(@as(u32, @intCast(raw_decl)));

            switch (declaration.kind) {
                .type => {
                    const payload = self.genericTypePayload(declaration.syntax_node) orelse continue;
                    if (!hasGenericParameters(payload.params, payload.params_struct)) continue;
                    self.parameters.clearRetainingCapacity();
                    const params = try self.lowerParameters(payload.params, payload.params_struct);
                    const body = try self.lowerType(payload.value, false);
                    try self.graph.semantic.templates.generic_type_templates.append(self.allocator, .{
                        .declaration = decl_id,
                        .parameters = params,
                        .body = body,
                    });
                    stats.generic_types += 1;
                },
                .function => {
                    const function = self.tree.functionDeclaration(declaration.syntax_node) orelse continue;
                    if (!hasGenericParameters(function.generic_params, function.generic_params_struct)) continue;
                    self.parameters.clearRetainingCapacity();
                    self.bindings.clearRetainingCapacity();
                    const params = try self.lowerParameters(function.generic_params, function.generic_params_struct);
                    const input = try self.lowerType(function.input, false);
                    const output = try self.lowerType(function.output, false);
                    const input_start: u32 = @intCast(self.graph.semantic.templates.ir.bindings.items.len);
                    try self.seedFunctionBindings(function.input);
                    const output_start: u32 = @intCast(self.graph.semantic.templates.ir.bindings.items.len);
                    try self.seedFunctionBindings(function.output);
                    const output_end: u32 = @intCast(self.graph.semantic.templates.ir.bindings.items.len);
                    const body = if (function.body) |node| try self.lowerBlock(node) else null;
                    try self.graph.semantic.templates.generic_function_templates.append(self.allocator, .{
                        .declaration = decl_id,
                        .parameters = params,
                        .input = input,
                        .output = output,
                        .body = body,
                        .input_bindings = .{ .start = input_start, .len = output_start - input_start },
                        .output_bindings = .{ .start = output_start, .len = output_end - output_start },
                    });
                    stats.generic_functions += 1;
                },
                .abstract_type => {
                    const abstract = self.tree.abstractDeclaration(declaration.syntax_node) orelse continue;
                    self.parameters.clearRetainingCapacity();
                    const params = try self.lowerParameters(abstract.generic_params, abstract.generic_params_struct);
                    const req_start: u32 = @intCast(self.graph.semantic.templates.abstract_requirements.items.len);
                    for (abstract.requires_functions) |requirement_node| {
                        const requirement = self.tree.abstractFunctionRequirement(requirement_node) orelse continue;
                        const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, requirement.name_token));
                        const input = try self.lowerType(requirement.input, true);
                        const output = try self.lowerType(requirement.output, true);
                        try self.graph.semantic.templates.abstract_requirements.append(self.allocator, .{
                            .name = name,
                            .input = input,
                            .output = output,
                        });
                    }
                    try self.graph.semantic.templates.abstract_definitions.append(self.allocator, .{
                        .declaration = decl_id,
                        .parameters = params,
                        .requirements = .{
                            .start = req_start,
                            .len = @intCast(self.graph.semantic.templates.abstract_requirements.items.len - req_start),
                        },
                    });
                    stats.abstract_definitions += 1;
                },
                else => {},
            }
        }
        return stats;
    }

    const GenericTypePayload = struct {
        params: []const syn.NodeIndex,
        params_struct: ?syn.NodeIndex,
        value: syn.NodeIndex,
    };

    fn genericTypePayload(self: *Context, node: syn.NodeIndex) ?GenericTypePayload {
        return switch (self.tree.tag(node)) {
            .type_declaration => blk: {
                const value = self.tree.typeDeclaration(node).?;
                break :blk .{ .params = value.generic_params, .params_struct = value.generic_params_struct, .value = value.value };
            },
            .c_enum_declaration => blk: {
                const value = self.tree.cEnumDeclaration(node).?;
                break :blk .{ .params = value.generic_params, .params_struct = value.generic_params_struct, .value = value.value };
            },
            .c_union_declaration => blk: {
                const value = self.tree.cUnionDeclaration(node).?;
                break :blk .{ .params = value.generic_params, .params_struct = value.generic_params_struct, .value = value.value };
            },
            else => null,
        };
    }

    fn lowerParameters(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.TemplateParameterId) {
        const start: u32 = @intCast(self.graph.semantic.templates.generic_parameters.items.len);
        if (params_struct) |struct_node| {
            const literal = self.tree.structTypeLiteral(struct_node) orelse return error.InvalidGenericParameters;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                const value_type_node = field.type_node orelse return error.InvalidGenericParameter;
                const kind: templates.GenericParameterKind = if (isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;
                const id: ir.TemplateParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.generic_parameters.items.len)));
                try self.graph.semantic.templates.generic_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                    .value_type = if (kind == .comptime_int) try self.lowerType(value_type_node, false) else null,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = kind });
            }
        } else {
            for (params) |param_node| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param_node));
                const id: ir.TemplateParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.generic_parameters.items.len)));
                try self.graph.semantic.templates.generic_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = .type,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.templates.generic_parameters.items.len - start) };
    }

    pub fn lowerType(self: *Context, node: syn.NodeIndex, allow_self: bool) anyerror!ir.TemplateTypeId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedTemplateType;
        return switch (syntax_type) {
            .name => |name| self.lowerNamedType(node, name.name_token, name.qualifier_token, allow_self),
            .pointer => |value| blk: {
                const child = try self.lowerType(value.child, allow_self);
                break :blk try self.addType(.{ .resolved = .{ .pointer = .{ .child = child, .mutability = value.mutability } } });
            },
            .nullable => |child| try self.addType(.{ .resolved = .{ .nullable = try self.lowerType(child, allow_self) } }),
            .inferred_errable => |child| try self.addType(.{ .resolved = .{ .inferred_errable = try self.lowerType(child, allow_self) } }),
            .array => |value| blk: {
                const length = try self.lowerIntExpressionFromToken(value.length_token);
                const element = try self.lowerType(value.element, allow_self);
                break :blk try self.addType(.{ .array = .{ .length = length, .element = element } });
            },
            .generic => |value| self.lowerGenericType(value, allow_self),
            .struct_literal => |literal| self.lowerStructType(literal, allow_self),
            .choice_literal => |literal| self.lowerChoiceType(literal, allow_self),
        };
    }

    fn lowerNamedType(self: *Context, owner: syn.NodeIndex, name_token: syn.TokenIndex, qualifier: ?syn.TokenIndex, allow_self: bool) !ir.TemplateTypeId {
        const name = self.tree.tokenTextFromSource(self.source, name_token);
        if (allow_self and std.mem.eql(u8, name, "Self")) return self.addType(.abstract_self);
        if (qualifier == null) {
            if (self.parameter(name)) |binding| if (binding.kind == .type) return self.addType(.{ .parameter = binding.id });
            if (builtinFromName(name)) |builtin| {
                const concrete = try self.moduleBuiltin(builtin);
                return self.addType(.{ .concrete = concrete });
            }
            if (self.localType(name)) |local| {
                const ty = self.graph.declarations.items[@intFromEnum(local)].type_id orelse return error.TypeDeclarationWithoutType;
                return self.addType(.{ .concrete = ty });
            }
        }
        const external = try self.writer.addExternalRef(.{
            .kind = .type,
            .module_path = if (qualifier) |token_index| try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index)) else null,
            .name = try self.writer.addString(name),
            .source = self.sourceRef(owner),
        });
        return self.addType(.{ .external = external });
    }

    fn lowerGenericType(self: *Context, generic: syn.GenericType, allow_self: bool) !ir.TemplateTypeId {
        const base = self.tree.syntaxType(generic.base) orelse return error.InvalidGenericTemplateBase;
        if (base != .name) return error.InvalidGenericTemplateBase;
        const name = base.name;
        const base_text = self.tree.tokenTextFromSource(self.source, name.name_token);
        const declaration_ref = if (name.qualifier_token == null and self.localType(base_text) != null)
            ir.DeclarationRef{ .module = self.localType(base_text).? }
        else blk: {
            const external = try self.writer.addExternalRef(.{
                .kind = .type,
                .module_path = if (name.qualifier_token) |token_index| try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index)) else null,
                .name = try self.writer.addString(base_text),
                .source = self.sourceRef(generic.base),
            });
            break :blk ir.DeclarationRef{ .external = external };
        };
        const template_decl: ir.TemplateDeclId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.declarations.items.len)));
        try self.graph.semantic.templates.ir.declarations.append(self.allocator, .{ .target = declaration_ref });

        const literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidGenericTemplateArguments;
        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericTemplateArgument;
            const name_range = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
            const arg_value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                .{ .type = try self.lowerType(type_node, allow_self) }
            else if (field.default_value) |value_node|
                try self.lowerGenericValue(value_node, allow_self)
            else
                return error.InvalidGenericTemplateArgument;
            try arguments.append(self.allocator, .{ .name = name_range, .value = arg_value });
        }
        const arg_start: u32 = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len);
        try self.graph.semantic.templates.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        return self.addType(.{ .resolved = .{ .generic = .{
            .base = template_decl,
            .arguments = .{ .start = arg_start, .len = @intCast(literal.fields.len) },
        } } });
    }

    fn lowerStructType(self: *Context, literal: syn.StructTypeLiteral, allow_self: bool) !ir.TemplateTypeId {
        // Recursive types can append to the same pool. Publish immediate fields
        // together only after their children have been lowered.
        var fields: std.ArrayList(ir.Field) = .empty;
        defer fields.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidTemplateStructField;
            const type_node = field.type_node orelse return error.InvalidTemplateStructField;
            try fields.append(self.allocator, .{
                .name = try self.writer.addString(if (field.inferred_result) "result" else self.tree.tokenTextFromSource(self.source, field.name_token)),
                .ty = try self.lowerType(type_node, allow_self),
                .source = self.sourceRef(field_node),
            });
        }
        const start: u32 = @intCast(self.graph.semantic.templates.ir.fields.items.len);
        try self.graph.semantic.templates.ir.fields.appendSlice(self.allocator, fields.items);
        return self.addType(.{ .resolved = .{ .structural = .{
            .fields = .{ .start = start, .len = @intCast(literal.fields.len) },
        } } });
    }

    pub fn lowerGenericValue(self: *Context, node: syn.NodeIndex, allow_self: bool) !ir.GenericArgument.Value {
        if (self.tree.tag(node) == .identifier) {
            const token = self.tree.mainToken(node);
            const name = self.tree.tokenTextFromSource(self.source, token);
            if (self.parameter(name)) |binding| {
                if (binding.kind == .type) return .{ .type = try self.addType(.{ .parameter = binding.id }) };
            } else if (builtinFromName(name) != null or self.localType(name) != null) {
                return .{ .type = try self.lowerNamedType(node, token, null, allow_self) };
            }
        }
        if (self.tree.syntaxType(node) != null) return .{ .type = try self.lowerType(node, allow_self) };
        return .{ .comptime_int = try self.lowerIntExpression(node) };
    }

    fn lowerChoiceType(self: *Context, literal: syn.ChoiceTypeLiteral, allow_self: bool) !ir.TemplateTypeId {
        var variants: std.ArrayList(ir.Variant) = .empty;
        defer variants.deinit(self.allocator);
        for (literal.variants, 0..) |variant_node, index| {
            const variant = self.tree.choiceTypeVariant(variant_node) orelse return error.InvalidTemplateChoiceVariant;
            try variants.append(self.allocator, .{ .semantic = .{
                .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, variant.name_token)),
                .payload_type = if (variant.payload_type) |payload| try self.lowerType(payload, allow_self) else null,
                .source = self.sourceRef(variant_node),
                .value = @intCast(index),
            } });
        }
        const start: u32 = @intCast(self.graph.semantic.templates.ir.variants.items.len);
        try self.graph.semantic.templates.ir.variants.appendSlice(self.allocator, variants.items);
        return self.addType(.{ .resolved = .{ .structural_choice = .{
            .variants = .{ .start = start, .len = @intCast(literal.variants.len) },
        } } });
    }

    fn lowerIntExpressionFromToken(self: *Context, token_index: syn.TokenIndex) !ir.TemplateIntExprId {
        const text = self.tree.tokenTextFromSource(self.source, token_index);
        if (self.parameter(text)) |binding| if (binding.kind == .comptime_int) {
            return self.addInt(.{ .parameter = binding.id });
        };
        const value = std.fmt.parseInt(i64, text, 0) catch return error.InvalidTemplateComptimeInteger;
        return self.addInt(.{ .literal = value });
    }

    fn lowerIntExpression(self: *Context, node: syn.NodeIndex) anyerror!ir.TemplateIntExprId {
        if (self.tree.literal(node)) |literal| {
            const text = self.tree.tokenTextFromSource(self.source, literal.token);
            var value = std.fmt.parseInt(i64, text, 0) catch return error.InvalidTemplateComptimeInteger;
            if (literal.negative) value = -value;
            return self.addInt(.{ .literal = value });
        }
        if (self.tree.tag(node) == .identifier) {
            const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            const binding = self.parameter(name) orelse return error.UnknownTemplateComptimeParameter;
            if (binding.kind != .comptime_int) return error.ExpectedTemplateComptimeParameter;
            return self.addInt(.{ .parameter = binding.id });
        }
        const op = self.tree.binaryOperation(node) orelse return error.InvalidTemplateComptimeInteger;
        const operator: ir.IntBinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .add,
            .binary_subtract => .subtract,
            .binary_multiply => .multiply,
            .binary_divide => .divide,
            .binary_modulo => .modulo,
            else => return error.InvalidTemplateComptimeInteger,
        };
        return self.addInt(.{ .binary = .{
            .operator = operator,
            .left = try self.lowerIntExpression(op.lhs),
            .right = try self.lowerIntExpression(op.rhs),
        } });
    }

    fn seedFunctionBindings(self: *Context, struct_node: syn.NodeIndex) !void {
        const literal = self.tree.structTypeLiteral(struct_node) orelse return;
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse continue;
            const type_node = field.type_node orelse continue;
            const name = if (field.inferred_result) "result" else self.tree.tokenTextFromSource(self.source, field.name_token);
            const binding_id: ir.TemplateBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.bindings.items.len)));
            try self.graph.semantic.templates.ir.bindings.append(self.allocator, .{
                .name = try self.writer.addString(name),
                .source = self.sourceRef(field_node),
                .ty = try self.lowerType(type_node, false),
                .mutability = if (field.inferred_result) .variable else .constant,
            });
            try self.bindings.append(.{ .name = name, .id = binding_id });
        }
    }

    fn lowerBlock(self: *Context, node: syn.NodeIndex) anyerror!ir.TemplateBlockId {
        const block = self.tree.codeBlock(node) orelse return error.ExpectedTemplateBlock;
        const binding_mark = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(binding_mark);
        var statements: std.ArrayList(ir.TemplateNodeId) = .empty;
        defer statements.deinit(self.allocator);
        var ret_val: ?ir.TemplateNodeId = null;
        for (block.statements) |statement| {
            const lowered = try self.lowerBodyNode(statement);
            try statements.append(self.allocator, lowered);
            ret_val = lowered;
        }
        const start: u32 = @intCast(self.graph.semantic.templates.ir.node_refs.items.len);
        try self.graph.semantic.templates.ir.node_refs.appendSlice(self.allocator, statements.items);
        const id: ir.TemplateBlockId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.blocks.items.len)));
        try self.graph.semantic.templates.ir.blocks.append(self.allocator, .{
            .nodes = .{ .start = start, .len = @intCast(block.statements.len) },
            .ret_val = ret_val,
        });
        return id;
    }

    fn lowerBodyNode(self: *Context, node: syn.NodeIndex) anyerror!ir.TemplateNodeId {
        if (self.tree.tag(node) == .expression_statement)
            return self.lowerBodyNode(self.tree.unaryOperand(node).?);
        if (self.tree.functionCall(node)) |call| {
            const input = try self.lowerBodyNode(call.input);
            var arguments: std.ArrayList(ir.GenericArgument) = .empty;
            defer arguments.deinit(self.allocator);
            if (call.type_arguments_struct) |struct_node| {
                const literal = self.tree.structTypeLiteral(struct_node) orelse return error.InvalidTemplateCallArguments;
                for (literal.fields) |field_node| {
                    const field = self.tree.structTypeField(field_node) orelse return error.InvalidTemplateCallArgument;
                    const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                        .{ .type = try self.lowerType(type_node, false) }
                    else if (field.default_value) |value_node|
                        try self.lowerGenericValue(value_node, false)
                    else
                        return error.InvalidTemplateCallArgument;
                    try arguments.append(self.allocator, .{
                        .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token)),
                        .value = value,
                    });
                }
            } else for (call.type_arguments) |type_node| {
                try arguments.append(self.allocator, .{ .name = try self.writer.addString(""), .value = .{ .type = try self.lowerType(type_node, false) } });
            }
            const start: u32 = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len);
            try self.graph.semantic.templates.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
            const id = try self.addPending(node, .generic_call, &.{input}, try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token)), null, 0);
            const pending_id = self.graph.semantic.templates.ir.nodes.items[@intFromEnum(id)].pending;
            self.graph.semantic.templates.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.generic_arguments = .{ .start = start, .len = @intCast(arguments.items.len) };
            self.graph.semantic.templates.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.module_path = if (call.module_qualifier) |token| try self.writer.addString(self.tree.tokenTextFromSource(self.source, token)) else null;
            return id;
        }
        if (self.tree.symbolDeclaration(node)) |declaration| {
            const initialization = if (declaration.value) |value| try self.lowerBodyNode(value) else null;
            const ty = if (declaration.type_node) |value| try self.lowerType(value, false) else try self.templateBuiltin(.Any);
            const name = self.tree.tokenTextFromSource(self.source, declaration.name_token);
            const binding: ir.TemplateBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.bindings.items.len)));
            try self.graph.semantic.templates.ir.bindings.append(self.allocator, .{
                .name = try self.writer.addString(name),
                .source = self.sourceRef(node),
                .ty = ty,
                .initialization = initialization,
                .mutability = declaration.mutability,
            });
            try self.bindings.append(.{ .name = name, .id = binding });
            return self.addResolvedNode(node, try self.templateBuiltin(.Void), .{ .binding_declaration = binding });
        }
        if (self.tree.assignment(node)) |assignment| {
            const name = self.tree.tokenTextFromSource(self.source, assignment.name_token);
            const binding = self.templateBinding(name) orelse return error.UnknownTemplateAssignment;
            return self.addResolvedNode(node, try self.templateBuiltin(.Void), .{ .assignment = .{
                .binding = binding,
                .value = try self.lowerBodyNode(assignment.value),
            } });
        }
        if (self.tree.structValueLiteral(node)) |literal| {
            var fields: std.ArrayList(ir.ValueField) = .empty;
            defer fields.deinit(self.allocator);
            for (literal.fields) |field_node| {
                const field = self.tree.valueField(field_node) orelse return error.InvalidTemplateValueField;
                try fields.append(self.allocator, .{
                    .name = try self.writer.addString(if (field.name_token) |token| self.tree.tokenTextFromSource(self.source, token) else ""),
                    .value = try self.lowerBodyNode(field.value),
                });
            }
            const start: u32 = @intCast(self.graph.semantic.templates.ir.value_fields.items.len);
            try self.graph.semantic.templates.ir.value_fields.appendSlice(self.allocator, fields.items);
            const ty = try self.templateBuiltin(.Any);
            return self.addResolvedNode(node, ty, .{ .struct_value_literal = .{
                .fields = .{ .start = start, .len = @intCast(fields.items.len) },
                .ty = ty,
            } });
        }
        // Keep the few parameter-independent leaves compact and represent every
        // semantic composition uniformly as a syntax-free pending expression.
        if (self.tree.literal(node)) |literal| {
            const token_content = self.tree.tokenContent(literal.token).literal;
            return switch (token_content) {
                .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => blk: {
                    const value = try literals.integer(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                    break :blk self.addResolvedNode(node, try self.templateBuiltin(.Int32), .{ .int_literal = value });
                },
                .regular_float_literal, .scientific_float_literal => blk: {
                    const value = try literals.float(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                    break :blk self.addResolvedNode(node, try self.templateBuiltin(.Float32), .{ .float_literal = value });
                },
                .bool_literal => |value| self.addResolvedNode(node, try self.templateBuiltin(.Bool), .{ .bool_literal = value }),
                .char_literal => |value| self.addResolvedNode(node, try self.templateBuiltin(.Char), .{ .char_literal = value }),
                .string_literal => self.addResolvedNode(node, try self.templateBuiltin(.Any), .{
                    .string_literal = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token)),
                }),
            };
        }
        if (self.tree.tag(node) == .identifier) {
            const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            if (self.templateBinding(name)) |binding| {
                const ty = self.graph.semantic.templates.ir.bindings.items[@intFromEnum(binding)].ty;
                return self.addResolvedNode(node, ty, .{ .binding_use = binding });
            }
            if (self.parameter(name)) |parameter_binding| {
                if (parameter_binding.kind == .type) {
                    const value = try self.addType(.{ .parameter = parameter_binding.id });
                    return self.addResolvedNode(node, try self.templateBuiltin(.Type), .{ .type_literal = value });
                }
            }
            return self.addPending(node, .unknown_identifier, &.{}, try self.writer.addString(name), null, 0);
        }

        var operands = std.array_list.Managed(ir.TemplateNodeId).init(self.allocator);
        defer operands.deinit();
        try self.collectBodyOperands(node, &operands);
        const kind = templateKindForTag(self.tree.tag(node));
        const name = switch (self.tree.tag(node)) {
            .function_call => if (self.tree.functionCall(node)) |call| try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token)) else null,
            .struct_field_access => if (self.tree.structFieldAccess(node)) |access| try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)) else null,
            .choice_payload_access => if (self.tree.choicePayloadAccess(node)) |access| try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)) else null,
            .keep_statement => if (self.tree.keepStatement(node)) |keep| try self.writer.addString(self.tree.tokenTextFromSource(self.source, keep.name_token)) else null,
            else => null,
        };
        return self.addPending(node, kind, operands.items, name, null, @intFromEnum(self.tree.tag(node)));
    }

    fn collectBodyOperands(self: *Context, node: syn.NodeIndex, result: *std.array_list.Managed(ir.TemplateNodeId)) anyerror!void {
        if (self.tree.structFieldAccess(node)) |access| {
            try result.append(try self.lowerBodyNode(access.value));
            return;
        }
        if (self.tree.choicePayloadAccess(node)) |access| {
            try result.append(try self.lowerBodyNode(access.value));
            return;
        }
        if (self.tree.binaryOperation(node)) |operation| {
            try result.append(try self.lowerBodyNode(operation.lhs));
            try result.append(try self.lowerBodyNode(operation.rhs));
            return;
        }
        if (self.tree.unaryOperand(node)) |operand| {
            try result.append(try self.lowerBodyNode(operand));
            return;
        }
        if (self.tree.functionCall(node)) |call| {
            try result.append(try self.lowerBodyNode(call.input));
            return;
        }
        if (self.tree.ifStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.condition));
            try result.append(try self.blockAsNode(statement.then_block));
            if (statement.else_block) |else_block| try result.append(try self.blockAsNode(else_block));
            return;
        }
        if (self.tree.whileStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.condition));
            try result.append(try self.blockAsNode(statement.body));
            return;
        }
        if (self.tree.forStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.iterable));
            try result.append(try self.blockAsNode(statement.body));
            return;
        }
        if (self.tree.matchStatement(node)) |statement| {
            try result.append(try self.lowerBodyNode(statement.value));
            for (statement.cases) |case_node| {
                const case = self.tree.matchCase(case_node) orelse continue;
                try result.append(try self.blockAsNode(case.body));
            }
            return;
        }
        if (self.tree.codeBlock(node) != null) {
            try result.append(try self.blockAsNode(node));
            return;
        }
        if (self.tree.structValueLiteral(node)) |literal| {
            for (literal.fields) |field_node| if (self.tree.valueField(field_node)) |field|
                try result.append(try self.lowerBodyNode(field.value));
            return;
        }
        if (self.tree.listLiteral(node)) |literal| {
            for (literal.elements) |element| try result.append(try self.lowerBodyNode(element));
            return;
        }
        if (self.tree.choiceLiteral(node)) |literal| if (literal.payload) |payload|
            try result.append(try self.lowerBodyNode(payload));
        if (self.tree.returnStatement(node)) |statement| if (statement.value) |value|
            try result.append(try self.lowerBodyNode(value));
    }

    fn blockAsNode(self: *Context, node: syn.NodeIndex) !ir.TemplateNodeId {
        const block = try self.lowerBlock(node);
        return self.addResolvedNode(node, try self.templateBuiltin(.Any), .{ .code_block = block });
    }

    fn addPending(self: *Context, node: syn.NodeIndex, kind: ir.PendingExpressionKind, operands: []const ir.TemplateNodeId, name: ?primitives.StringRange, expected: ?ir.TemplateTypeId, aux: u32) !ir.TemplateNodeId {
        const start: u32 = @intCast(self.graph.semantic.templates.ir.node_refs.items.len);
        try self.graph.semantic.templates.ir.node_refs.appendSlice(self.allocator, operands);
        const pending_id: ir.TemplatePendingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.pending.items.len)));
        try self.graph.semantic.templates.ir.pending.append(self.allocator, .{ .resolve_expression = .{
            .kind = kind,
            .operands = .{ .start = start, .len = @intCast(operands.len) },
            .name = name,
            .expected_type = expected,
            .source = self.sourceRef(node),
            .aux = aux,
        } });
        const id: ir.TemplateNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.nodes.items.len)));
        try self.graph.semantic.templates.ir.nodes.append(self.allocator, .{ .pending = pending_id });
        return id;
    }

    fn addResolvedNode(self: *Context, node: syn.NodeIndex, ty: ir.TemplateTypeId, content: ir.ResolvedNode.Content) !ir.TemplateNodeId {
        const id: ir.TemplateNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.nodes.items.len)));
        try self.graph.semantic.templates.ir.nodes.append(self.allocator, .{ .resolved = .{
            .source = self.sourceRef(node),
            .ty = ty,
            .content = content,
        } });
        return id;
    }

    fn addType(self: *Context, value: ir.Type) !ir.TemplateTypeId {
        const id: ir.TemplateTypeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.types.items.len)));
        try self.graph.semantic.templates.ir.types.append(self.allocator, value);
        return id;
    }

    fn addInt(self: *Context, value: ir.IntExpression) !ir.TemplateIntExprId {
        const id: ir.TemplateIntExprId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.int_expressions.items.len)));
        try self.graph.semantic.templates.ir.int_expressions.append(self.allocator, value);
        return id;
    }

    fn templateBuiltin(self: *Context, builtin: primitives.BuiltinType) !ir.TemplateTypeId {
        return self.addType(.{ .concrete = try self.moduleBuiltin(builtin) });
    }

    fn moduleBuiltin(self: *Context, builtin: primitives.BuiltinType) !entities.ModuleTypeId {
        for (0..views.typeCount(self.graph)) |raw| {
            const id: entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            switch (try views.typeView(self.graph, id)) {
                .resolved => |resolved| switch (resolved) {
                    .builtin => |value| if (value == builtin) return id,
                    else => {},
                },
                .external => {},
            }
        }
        return self.writer.addResolvedType(.{ .builtin = builtin });
    }

    fn parameter(self: *Context, name: []const u8) ?ParameterBinding {
        var i = self.parameters.items.len;
        while (i != 0) {
            i -= 1;
            if (std.mem.eql(u8, self.parameters.items[i].name, name)) return self.parameters.items[i];
        }
        return null;
    }

    fn templateBinding(self: *Context, name: []const u8) ?ir.TemplateBindingId {
        var i = self.bindings.items.len;
        while (i != 0) {
            i -= 1;
            if (std.mem.eql(u8, self.bindings.items[i].name, name)) return self.bindings.items[i].id;
        }
        return null;
    }

    fn localType(self: *Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |id| switch (self.graph.declarations.items[@intFromEnum(id)].kind) {
            .type, .abstract_type => return id,
            else => {},
        };
        return null;
    }

    fn sourceRef(self: *Context, node: syn.NodeIndex) primitives.SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }
};

fn hasGenericParameters(params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) bool {
    return params.len != 0 or params_struct != null;
}

fn isTypeBuiltin(tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex) bool {
    const ty = tree.syntaxType(node) orelse return false;
    if (ty != .name or ty.name.qualifier_token != null) return false;
    return std.mem.eql(u8, tree.tokenTextFromSource(source, ty.name.name_token), "Type");
}

fn isTypeParameter(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField) bool {
    const type_node = field.type_node orelse return true;
    if (isTypeBuiltin(tree, source, type_node)) return true;

    // Syntaxing validates constrained parameters as `.name: Type: Bound` but
    // stores only `Bound` as the field type. Preserve that distinction from a
    // normal comptime parameter by observing the two validated separators.
    const name_location = tree.tokenLocation(field.name_token);
    const type_location = tree.location(type_node);
    const start = name_location.offset + tree.tokenTextFromSource(source, field.name_token).len;
    if (start > type_location.offset or type_location.offset > source.len) return false;
    return std.mem.count(u8, source[start..type_location.offset], ":") >= 2;
}

fn builtinFromName(name: []const u8) ?primitives.BuiltinType {
    inline for (@typeInfo(primitives.BuiltinType).@"enum".fields) |field|
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    return null;
}

fn templateKindForTag(tag: syn.Node.Tag) ir.PendingExpressionKind {
    return switch (tag) {
        .pipe_expression => .pipe,
        .unwrap_or => .unwrap_or,
        .unwrap_or_do => .unwrap_or_do,
        .nullable_test => .nullable_test,
        .function_call => .generic_call,
        .choice_literal, .choice_some_literal => .choice_literal,
        .struct_field_access => .field_access,
        .choice_payload_access => .choice_payload,
        .error_propagation => .error_propagation,
        .error_context => .error_context,
        .index_access => .index,
        .index_assignment => .index_store,
        .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => .binary,
        .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal => .comparison,
        .logical_and, .logical_or => .logical,
        .if_statement => .if_statement,
        .while_statement => .while_statement,
        .for_value, .for_borrow, .for_mut_borrow => .for_each,
        .match_statement, .match_case_value, .match_case_borrow, .match_case_mut_borrow, .match_case_move => .match,
        .defer_statement => .defer_value,
        .keep_statement => .keep_binding,
        .address_of, .address_of_mut => .address_of,
        .dereference => .dereference,
        .pointer_assignment => .pointer_store,
        .move_expression => .move_value,
        .struct_value_literal => .struct_value,
        .list_literal => .list_value,
        .return_statement => .return_statement,
        else => .other,
    };
}

test "module template lowerer stores dependent shapes without syntax references" {
    try std.testing.expect(@sizeOf(ir.TemplateTypeId) == 4);
    try std.testing.expect(@sizeOf(ir.TemplateNodeId) == 4);
}

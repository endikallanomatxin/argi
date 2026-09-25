const std = @import("std");
const literals = @import("../../semantic_literals.zig");
const syn = @import("../../../3_syntax/syntax_tree.zig");
const tok = @import("../../../2_tokens/token.zig");
const graph_mod = @import("../graph.zig");
const entities = @import("../entities.zig");
const writer_mod = @import("../writer.zig");
const views = @import("../views.zig");
const type_lowerer = @import("../type_lowerer.zig");
const parameterized_storage = @import("storage.zig");
const ir = @import("ir.zig");
const primitives = @import("../../primitives/schema.zig");

pub const Stats = struct {
    generic_types: u32 = 0,
    generic_functions: u32 = 0,
    abstract_definitions: u32 = 0,
};

pub const ParameterBinding = struct {
    name: []const u8,
    id: ir.ComptimeParameterId,
    kind: parameterized_storage.ComptimeParameterKind,
};

pub const QualifiedAbstract = struct {
    qualifier: ?[]const u8,
    name: []const u8,
};

const BindingName = struct {
    name: []const u8,
    id: ir.ParameterizedBindingId,
};

const AbstractParameterBinding = struct {
    node: syn.NodeIndex,
    id: ir.ComptimeParameterId,
};

pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !Stats {
    return lowerLinked(allocator, graph, files, &.{});
}

pub fn lowerLinked(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    abstract_types: []const QualifiedAbstract,
) !Stats {
    var ctx = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .writer = writer_mod.Writer.init(allocator, graph),
        .parameters = std.array_list.Managed(ParameterBinding).init(allocator),
        .abstract_parameters = std.array_list.Managed(AbstractParameterBinding).init(allocator),
        .bindings = std.array_list.Managed(BindingName).init(allocator),
        .abstract_types = abstract_types,
    };
    defer ctx.parameters.deinit();
    defer ctx.abstract_parameters.deinit();
    defer ctx.bindings.deinit();
    return ctx.lowerDeclarations();
}

pub const Context = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    parameters: std.array_list.Managed(ParameterBinding),
    abstract_parameters: std.array_list.Managed(AbstractParameterBinding),
    bindings: std.array_list.Managed(BindingName),
    abstract_types: []const QualifiedAbstract = &.{},
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
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            const decl_id: entities.ModuleDeclId = @enumFromInt(@as(u32, @intCast(raw_decl)));

            switch (declaration.kind) {
                .type => {
                    const payload = self.genericTypePayload(declaration_node) orelse continue;
                    if (!hasGenericParameters(payload.params, payload.params_struct)) continue;
                    self.parameters.clearRetainingCapacity();
                    self.abstract_parameters.clearRetainingCapacity();
                    const params = try self.lowerParameters(payload.params, payload.params_struct);
                    const body = try self.lowerType(payload.value, false);
                    try self.graph.semantic.parameterized_storage.parameterized_types.append(self.allocator, .{
                        .declaration = decl_id,
                        .parameters = params,
                        .body = body,
                    });
                    stats.generic_types += 1;
                },
                .function => {
                    const function = self.tree.functionDeclaration(declaration_node) orelse continue;
                    self.parameters.clearRetainingCapacity();
                    self.abstract_parameters.clearRetainingCapacity();
                    self.bindings.clearRetainingCapacity();
                    const explicit = hasGenericParameters(function.generic_params, function.generic_params_struct);
                    const parameter_start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
                    if (explicit) _ = try self.lowerParameters(function.generic_params, function.generic_params_struct);
                    const explicit_count: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - parameter_start);
                    try self.collectLocalAbstractParameters(function.input);
                    const params: primitives.Range(ir.ComptimeParameterId) = .{
                        .start = parameter_start,
                        .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - parameter_start),
                    };
                    const has_abstract_parameters = params.len > explicit_count;
                    if (params.len == 0) continue;
                    if (has_abstract_parameters) if (declaration.function_id) |function_id| {
                        // The source interface keeps declaration identity;
                        // only concrete instances own an executable body.
                        try self.graph.semantic.function_semantics.append(self.allocator, .{
                            .function = function_id,
                            .flags = .{ .has_declared_body = function.body != null, .is_abstract_dispatch = true },
                        });
                    };
                    const input = try self.lowerType(function.input, false);
                    const output = try self.lowerType(function.output, false);
                    const input_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len);
                    try self.seedFunctionBindings(function.input, .constant);
                    const output_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len);
                    try self.seedFunctionBindings(function.output, .variable);
                    const output_end: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len);
                    const body = if (function.body) |node| try self.lowerBlock(node) else null;
                    try self.graph.semantic.parameterized_storage.parameterized_functions.append(self.allocator, .{
                        .declaration = decl_id,
                        .parameters = params,
                        .input = input,
                        .output = output,
                        .body = body,
                        .input_bindings = .{ .start = input_start, .len = output_start - input_start },
                        .output_bindings = .{ .start = output_start, .len = output_end - output_start },
                        .dispatch_kind = if (has_abstract_parameters) .abstract_contract else .regular,
                    });
                    stats.generic_functions += 1;
                },
                .abstract_type => {
                    const abstract = self.tree.abstractDeclaration(declaration_node) orelse continue;
                    self.parameters.clearRetainingCapacity();
                    self.abstract_parameters.clearRetainingCapacity();
                    const params = try self.lowerParameters(abstract.generic_params, abstract.generic_params_struct);
                    const req_start: u32 = @intCast(self.graph.semantic.parameterized_storage.abstract_requirements.items.len);
                    for (abstract.requires_functions) |requirement_node| {
                        const requirement = self.tree.abstractFunctionRequirement(requirement_node) orelse continue;
                        const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, requirement.name_token));
                        const input = try self.lowerType(requirement.input, true);
                        const output = try self.lowerType(requirement.output, true);
                        try self.graph.semantic.parameterized_storage.abstract_requirements.append(self.allocator, .{
                            .name = name,
                            .input = input,
                            .output = output,
                        });
                    }
                    try self.graph.semantic.parameterized_storage.abstract_definitions.append(self.allocator, .{
                        .declaration = decl_id,
                        .parameters = params,
                        .requirements = .{
                            .start = req_start,
                            .len = @intCast(self.graph.semantic.parameterized_storage.abstract_requirements.items.len - req_start),
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

    fn lowerParameters(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
        if (params_struct) |struct_node| {
            const literal = self.tree.structTypeLiteral(struct_node) orelse return error.InvalidGenericParameters;

            // Register every parameter before lowering bounds. Bounds may refer
            // to associated parameters declared later in the same generic list,
            // e.g. t: Type: FalliblyCopyable#(.reasons: element_reasons).
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                _ = field.type_node orelse return error.InvalidGenericParameter;
                const kind: parameterized_storage.ComptimeParameterKind =
                    if (isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = kind });
            }

            for (literal.fields, 0..) |field_node, offset| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const value_type_node = field.type_node orelse return error.InvalidGenericParameter;
                const parameter_record = &self.graph.semantic.parameterized_storage.comptime_parameters.items[
                    start + @as(u32, @intCast(offset))
                ];
                switch (parameter_record.kind) {
                    .comptime_int => parameter_record.value_type = try self.lowerType(value_type_node, false),
                    .type => {
                        if (!isTypeBuiltin(self.tree, self.source, value_type_node))
                            parameter_record.constraint = try self.lowerAbstractConstraint(value_type_node);
                    },
                }
            }
        } else {
            for (params) |param_node| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param_node));
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = .type,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - start) };
    }

    pub fn lowerAbstractConstraint(self: *Context, node: syn.NodeIndex) !parameterized_storage.AbstractConstraintId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedAbstractType;
        var base_node = node;
        var arguments_node: ?syn.NodeIndex = null;
        switch (syntax_type) {
            .name => {},
            .generic => |generic| {
                base_node = generic.base;
                arguments_node = generic.arguments;
            },
            else => return error.ExpectedAbstractType,
        }

        const base = self.tree.syntaxType(base_node) orelse return error.ExpectedAbstractType;
        if (base != .name) return error.ExpectedAbstractType;
        const name = self.tree.tokenTextFromSource(self.source, base.name.name_token);
        const local_declaration =
            if (base.name.qualifier_token == null) self.localAbstractType(name) else null;
        const abstract_ref: ir.DeclarationRef = if (local_declaration) |declaration|
            .{ .module = declaration }
        else
            .{ .external = try self.writer.addExternalRef(.{
                .kind = .abstract,
                .module_path = if (base.name.qualifier_token) |qualifier|
                    try self.writer.addString(self.tree.tokenTextFromSource(self.source, qualifier))
                else
                    null,
                .name = try self.writer.addString(name),
                .source = self.sourceRef(base_node),
            }) };

        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        if (arguments_node) |args_node| {
            const literal = self.tree.structTypeLiteral(args_node) orelse return error.InvalidAbstractArguments;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidAbstractArgument;
                const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                    .{ .type = try self.lowerType(type_node, false) }
                else if (field.default_value) |value_node|
                    try self.lowerGenericValue(value_node, false)
                else
                    return error.InvalidAbstractArgument;
                try arguments.append(self.allocator, .{
                    .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token)),
                    .value = value,
                });
            }
        }

        const argument_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        const id: parameterized_storage.AbstractConstraintId =
            @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.abstract_constraints.items.len)));
        try self.graph.semantic.parameterized_storage.abstract_constraints.append(self.allocator, .{
            .abstract_ref = abstract_ref,
            .arguments = .{ .start = argument_start, .len = @intCast(arguments.items.len) },
            .source = self.sourceRef(node),
        });
        return id;
    }

    fn lowerLocalAbstractParameters(self: *Context, input: syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
        try self.collectLocalAbstractParameters(input);
        return .{ .start = start, .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - start) };
    }

    fn collectLocalAbstractParameters(self: *Context, node: syn.NodeIndex) !void {
        const syntax_type = self.tree.syntaxType(node) orelse return;
        switch (syntax_type) {
            .name => |name| {
                const text = self.tree.tokenTextFromSource(self.source, name.name_token);
                if (self.parameter(text) != null) return;
                if (!self.syntaxNameIsAbstract(text, name.qualifier_token)) return;
                _ = try self.registerAbstractParameter(node, text);
            },
            .pointer => |pointer| try self.collectLocalAbstractParameters(pointer.child),
            .nullable, .inferred_errable => |child| try self.collectLocalAbstractParameters(child),
            .array => |array| try self.collectLocalAbstractParameters(array.element),
            .struct_literal => |literal| for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse continue;
                if (field.type_node) |ty| try self.collectLocalAbstractParameters(ty);
            },
            .choice_literal => |literal| for (literal.variants) |variant_node| {
                const variant = self.tree.choiceTypeVariant(variant_node) orelse continue;
                if (variant.payload_type) |ty| try self.collectLocalAbstractParameters(ty);
            },
            .generic => |generic| {
                if (type_lowerer.isRuntimeVirtualType(self.tree, self.source, generic)) return;

                // Associated arguments can themselves contain abstract types.
                // Register those first so lowerAbstractConstraint can refer to
                // their hidden parameters while lowering the outer contract.
                const arguments = self.tree.structTypeLiteral(generic.arguments) orelse return;
                for (arguments.fields) |field_node| {
                    const field = self.tree.structTypeField(field_node) orelse continue;
                    if (field.type_node) |ty| try self.collectLocalAbstractParameters(ty);
                }

                const base = self.tree.syntaxType(generic.base) orelse return;
                if (base != .name or self.parameter(self.tree.tokenTextFromSource(self.source, base.name.name_token)) != null) return;
                const base_text = self.tree.tokenTextFromSource(self.source, base.name.name_token);
                if (!self.syntaxNameIsAbstract(base_text, base.name.qualifier_token)) return;
                _ = try self.registerAbstractParameter(node, base_text);
            },
        }
    }

    fn syntaxNameIsAbstract(
        self: *Context,
        text: []const u8,
        qualifier: ?syn.TokenIndex,
    ) bool {
        if (qualifier) |qualifier_token| {
            const qualifier_text = self.tree.tokenTextFromSource(self.source, qualifier_token);
            return self.knownAbstract(qualifier_text, text);
        }
        return self.localAbstractType(text) != null or self.knownAbstract(null, text);
    }

    fn registerAbstractParameter(self: *Context, node: syn.NodeIndex, abstract_name: []const u8) !ir.ComptimeParameterId {
        if (self.abstractParameter(node)) |existing| return existing;

        const constraint = try self.lowerAbstractConstraint(node);
        const parameter_id: ir.ComptimeParameterId =
            @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
        const synthetic_name = try std.fmt.allocPrint(
            self.allocator,
            "__abstract_{s}_{d}",
            .{ abstract_name, @intFromEnum(parameter_id) },
        );
        defer self.allocator.free(synthetic_name);

        try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
            .name = try self.writer.addString(synthetic_name),
            .kind = .type,
            .constraint = constraint,
        });
        try self.abstract_parameters.append(.{ .node = node, .id = parameter_id });
        return parameter_id;
    }

    fn abstractParameter(self: *const Context, node: syn.NodeIndex) ?ir.ComptimeParameterId {
        for (self.abstract_parameters.items) |binding|
            if (binding.node == node) return binding.id;
        return null;
    }

    fn knownAbstract(self: *const Context, qualifier: ?[]const u8, name: []const u8) bool {
        for (self.abstract_types) |candidate| {
            if (candidate.qualifier == null and qualifier == null and std.mem.eql(u8, candidate.name, name)) return true;
            if (candidate.qualifier != null and qualifier != null and
                std.mem.eql(u8, candidate.qualifier.?, qualifier.?) and
                std.mem.eql(u8, candidate.name, name)) return true;
        }
        return false;
    }

    pub fn lowerType(self: *Context, node: syn.NodeIndex, allow_self: bool) anyerror!ir.ParameterizedTypeId {
        if (self.abstractParameter(node)) |abstract_parameter_id|
            return self.addType(.{ .parameter = abstract_parameter_id });
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedParameterizedType;
        return switch (syntax_type) {
            .name => |name| self.lowerNamedType(node, name.name_token, name.qualifier_token, allow_self),
            .pointer => |value| blk: {
                const child = try self.lowerType(value.child, allow_self);
                break :blk try self.addType(.{ .resolved = .{ .pointer = .{ .child = child, .mutability = graph_mod.pointerMutabilityFromSyntax(value.mutability) } } });
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

    fn lowerNamedType(self: *Context, owner: syn.NodeIndex, name_token: syn.TokenIndex, qualifier: ?syn.TokenIndex, allow_self: bool) !ir.ParameterizedTypeId {
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

    fn lowerGenericType(self: *Context, generic: syn.GenericType, allow_self: bool) !ir.ParameterizedTypeId {
        if (type_lowerer.isRuntimeVirtualType(self.tree, self.source, generic)) {
            const literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidVirtualArguments;
            if (literal.fields.len != 1) return error.InvalidVirtualArguments;
            const field = self.tree.structTypeField(literal.fields[0]) orelse return error.InvalidVirtualArguments;
            if (!std.mem.eql(u8, self.tree.tokenTextFromSource(self.source, field.name_token), "abstract")) return error.InvalidVirtualArguments;
            return self.addType(.{ .resolved = .{ .virtual = try self.lowerType(field.type_node orelse return error.InvalidVirtualArguments, allow_self) } });
        }
        const base = self.tree.syntaxType(generic.base) orelse return error.InvalidGenericParameterizedBase;
        if (base != .name) return error.InvalidGenericParameterizedBase;
        const name = base.name;
        const base_text = self.tree.tokenTextFromSource(self.source, name.name_token);
        if (name.qualifier_token == null and std.mem.eql(u8, base_text, "choice_union")) {
            const literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidChoiceUnionArguments;
            if (literal.fields.len != 2) return error.InvalidChoiceUnionArguments;
            var left: ?ir.ParameterizedTypeId = null;
            var right: ?ir.ParameterizedTypeId = null;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidChoiceUnionArguments;
                if (field.default_value != null) return error.InvalidChoiceUnionArguments;
                const ty = try self.lowerType(field.type_node orelse return error.InvalidChoiceUnionArguments, allow_self);
                const argument_name = self.tree.tokenTextFromSource(self.source, field.name_token);
                if (std.mem.eql(u8, argument_name, "a") and left == null) left = ty else if (std.mem.eql(u8, argument_name, "b") and right == null) right = ty else return error.InvalidChoiceUnionArguments;
            }
            return self.addType(.{ .choice_union = .{ .left = left.?, .right = right.? } });
        }
        if (name.qualifier_token == null and std.mem.eql(u8, base_text, "Array")) {
            const literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidArrayArguments;
            var length: ?ir.ParameterizedIntExprId = null;
            var element: ?ir.ParameterizedTypeId = null;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidArrayArguments;
                const argument_name = self.tree.tokenTextFromSource(self.source, field.name_token);
                if (std.mem.eql(u8, argument_name, "n")) {
                    if (length != null or field.default_value == null) return error.InvalidArrayArguments;
                    length = try self.lowerIntExpression(field.default_value.?);
                } else if (std.mem.eql(u8, argument_name, "t")) {
                    if (element != null or field.type_node == null) return error.InvalidArrayArguments;
                    element = try self.lowerType(field.type_node.?, allow_self);
                } else return error.InvalidArrayArguments;
            }
            if (length == null or element == null) return error.InvalidArrayArguments;
            return self.addType(.{ .array = .{ .length = length.?, .element = element.? } });
        }
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
        const parameterized_decl: ir.ParameterizedDeclId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.declarations.items.len)));
        try self.graph.semantic.parameterized_storage.ir.declarations.append(self.allocator, .{ .target = declaration_ref });

        const literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidGenericParameterizedArguments;
        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameterizedArgument;
            const name_range = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
            const arg_value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                .{ .type = try self.lowerType(type_node, allow_self) }
            else if (field.default_value) |value_node|
                try self.lowerGenericValue(value_node, allow_self)
            else
                return error.InvalidGenericParameterizedArgument;
            try arguments.append(self.allocator, .{ .name = name_range, .value = arg_value });
        }
        const arg_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        return self.addType(.{ .resolved = .{ .generic = .{
            .base = parameterized_decl,
            .arguments = .{ .start = arg_start, .len = @intCast(literal.fields.len) },
        } } });
    }

    fn lowerStructType(self: *Context, literal: syn.StructTypeLiteral, allow_self: bool) !ir.ParameterizedTypeId {
        // Recursive types can append to the same pool. Publish immediate fields
        // together only after their children have been lowered.
        var fields: std.ArrayList(ir.Field) = .empty;
        defer fields.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidParameterizedStructField;
            const type_node = field.type_node orelse return error.InvalidParameterizedStructField;
            try fields.append(self.allocator, .{
                .name = try self.writer.addString(if (field.inferred_result) "result" else self.tree.tokenTextFromSource(self.source, field.name_token)),
                .ty = try self.lowerType(type_node, allow_self),
                .source = self.sourceRef(field_node),
                .default_value = if (field.default_value) |value| try self.lowerBodyNode(value) else null,
            });
        }
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.fields.items.len);
        try self.graph.semantic.parameterized_storage.ir.fields.appendSlice(self.allocator, fields.items);
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

    fn lowerChoiceType(self: *Context, literal: syn.ChoiceTypeLiteral, allow_self: bool) !ir.ParameterizedTypeId {
        var variants: std.ArrayList(ir.Variant) = .empty;
        defer variants.deinit(self.allocator);
        for (literal.variants, 0..) |variant_node, index| {
            const variant = self.tree.choiceTypeVariant(variant_node) orelse return error.InvalidParameterizedChoiceVariant;
            try variants.append(self.allocator, .{ .semantic = .{
                .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, variant.name_token)),
                .payload_type = if (variant.payload_type) |payload| try self.lowerType(payload, allow_self) else null,
                .source = self.sourceRef(variant_node),
                .value = @intCast(index),
            } });
        }
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.variants.items.len);
        try self.graph.semantic.parameterized_storage.ir.variants.appendSlice(self.allocator, variants.items);
        return self.addType(.{ .resolved = .{ .structural_choice = .{
            .variants = .{ .start = start, .len = @intCast(literal.variants.len) },
        } } });
    }

    fn lowerIntExpressionFromToken(self: *Context, token_index: syn.TokenIndex) !ir.ParameterizedIntExprId {
        const text = self.tree.tokenTextFromSource(self.source, token_index);
        if (self.parameter(text)) |binding| if (binding.kind == .comptime_int) {
            return self.addInt(.{ .parameter = binding.id });
        };
        const value = std.fmt.parseInt(i64, text, 0) catch return error.InvalidParameterizedComptimeInteger;
        return self.addInt(.{ .literal = value });
    }

    fn lowerIntExpression(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedIntExprId {
        if (self.tree.literal(node)) |literal| {
            const text = self.tree.tokenTextFromSource(self.source, literal.token);
            var value = std.fmt.parseInt(i64, text, 0) catch return error.InvalidParameterizedComptimeInteger;
            if (literal.negative) value = -value;
            return self.addInt(.{ .literal = value });
        }
        if (self.tree.tag(node) == .identifier) {
            const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            const binding = self.parameter(name) orelse return error.UnknownParameterizedComptimeParameter;
            if (binding.kind != .comptime_int) return error.ExpectedParameterizedComptimeParameter;
            return self.addInt(.{ .parameter = binding.id });
        }
        const op = self.tree.binaryOperation(node) orelse return error.InvalidParameterizedComptimeInteger;
        const operator: ir.IntBinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .add,
            .binary_subtract => .subtract,
            .binary_multiply => .multiply,
            .binary_divide => .divide,
            .binary_modulo => .modulo,
            else => return error.InvalidParameterizedComptimeInteger,
        };
        return self.addInt(.{ .binary = .{
            .operator = operator,
            .left = try self.lowerIntExpression(op.lhs),
            .right = try self.lowerIntExpression(op.rhs),
        } });
    }

    fn seedFunctionBindings(self: *Context, struct_node: syn.NodeIndex, mutability: primitives.Mutability) !void {
        const literal = self.tree.structTypeLiteral(struct_node) orelse return;
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse continue;
            const type_node = field.type_node orelse continue;
            const name = if (field.inferred_result) "result" else self.tree.tokenTextFromSource(self.source, field.name_token);
            const initialization = if (field.default_value) |value| try self.lowerBodyNode(value) else null;
            const binding_id: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len)));
            try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                .name = try self.writer.addString(name),
                .source = self.sourceRef(field_node),
                .ty = try self.lowerType(type_node, false),
                .initialization = initialization,
                .mutability = mutability,
            });
            try self.bindings.append(.{ .name = name, .id = binding_id });
        }
    }

    fn lowerBlock(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedBlockId {
        const block = self.tree.codeBlock(node) orelse return error.ExpectedParameterizedBlock;
        const binding_mark = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(binding_mark);
        var statements: std.ArrayList(ir.ParameterizedNodeId) = .empty;
        defer statements.deinit(self.allocator);
        var ret_val: ?ir.ParameterizedNodeId = null;
        for (block.statements) |statement| {
            const lowered = try self.lowerBodyNode(statement);
            try statements.append(self.allocator, lowered);
            ret_val = lowered;
        }
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.node_refs.items.len);
        try self.graph.semantic.parameterized_storage.ir.node_refs.appendSlice(self.allocator, statements.items);
        const id: ir.ParameterizedBlockId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.blocks.items.len)));
        try self.graph.semantic.parameterized_storage.ir.blocks.append(self.allocator, .{
            .nodes = .{ .start = start, .len = @intCast(block.statements.len) },
            .ret_val = ret_val,
        });
        return id;
    }

    fn lowerBodyNode(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedNodeId {
        if (self.tree.tag(node) == .expression_statement)
            return self.lowerBodyNode(self.tree.unaryOperand(node).?);
        if (self.tree.tag(node) == .reach_directive) return self.lowerReach(node);
        if (self.tree.matchStatement(node)) |statement| {
            const value = try self.lowerBodyNode(statement.value);
            var cases: std.ArrayList(ir.MatchCase) = .empty;
            defer cases.deinit(self.allocator);
            for (statement.cases) |case_node| {
                const case = self.tree.matchCase(case_node) orelse return error.InvalidParameterizedMatchCase;
                const binding_mark = self.bindings.items.len;
                defer self.bindings.shrinkRetainingCapacity(binding_mark);
                const payload_binding: ?ir.ParameterizedBindingId = if (case.payload_name) |token| blk: {
                    const name = self.tree.tokenTextFromSource(self.source, token);
                    const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len)));
                    try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                        .name = try self.writer.addString(name),
                        .source = self.sourceRef(case_node),
                        .ty = ir.unresolved_binding_type_poison,
                        .mutability = .constant,
                    });
                    try self.graph.semantic.parameterized_storage.ir.unresolved_binding_types.append(self.allocator, binding);
                    try self.bindings.append(.{ .name = name, .id = binding });
                    break :blk binding;
                } else null;
                try cases.append(self.allocator, .{
                    .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, case.variant_token)),
                    .payload_binding = payload_binding,
                    .body = try self.lowerBlock(case.body),
                    .mode = graph_mod.matchCaseModeFromSyntax(case.mode),
                    .source = self.sourceRef(case_node),
                });
            }
            const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.match_cases.items.len);
            try self.graph.semantic.parameterized_storage.ir.match_cases.appendSlice(self.allocator, cases.items);
            const id = try self.addPending(node, .match, &.{value}, null, null, .none);
            const pending_id = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(id)].pending;
            self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.match_cases = .{ .start = start, .len = @intCast(cases.items.len) };
            return id;
        }
        if (self.tree.functionCall(node)) |call| {
            const input = try self.lowerBodyNode(call.input);
            var arguments: std.ArrayList(ir.GenericArgument) = .empty;
            defer arguments.deinit(self.allocator);
            if (call.type_arguments_struct) |struct_node| {
                const literal = self.tree.structTypeLiteral(struct_node) orelse return error.InvalidParameterizedCallArguments;
                for (literal.fields) |field_node| {
                    const field = self.tree.structTypeField(field_node) orelse return error.InvalidParameterizedCallArgument;
                    const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                        .{ .type = try self.lowerType(type_node, false) }
                    else if (field.default_value) |value_node|
                        try self.lowerGenericValue(value_node, false)
                    else
                        return error.InvalidParameterizedCallArgument;
                    try arguments.append(self.allocator, .{
                        .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token)),
                        .value = value,
                    });
                }
            } else for (call.type_arguments) |type_node| {
                try arguments.append(self.allocator, .{ .name = try self.writer.addString(""), .value = .{ .type = try self.lowerType(type_node, false) } });
            }
            const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
            try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
            const id = try self.addPending(node, .generic_call, &.{input}, try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token)), null, .none);
            const pending_id = self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(id)].pending;
            self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.generic_arguments = .{ .start = start, .len = @intCast(arguments.items.len) };
            self.graph.semantic.parameterized_storage.ir.pending.items[@intFromEnum(pending_id)].resolve_expression.module_path = if (call.module_qualifier) |token| try self.writer.addString(self.tree.tokenTextFromSource(self.source, token)) else null;
            return id;
        }
        if (self.tree.symbolDeclaration(node)) |declaration| {
            const initialization = if (declaration.value) |value| try self.lowerBodyNode(value) else null;
            const inferred_ty: ?ir.ParameterizedTypeId = if (initialization) |value|
                switch (self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(value)]) {
                    .resolved => |resolved_node| resolved_node.ty,
                    .pending => null,
                }
            else
                null;
            const ty: ?ir.ParameterizedTypeId = if (declaration.type_node) |value| try self.lowerType(value, false) else inferred_ty;
            const name = self.tree.tokenTextFromSource(self.source, declaration.name_token);
            const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len)));
            try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                .name = try self.writer.addString(name),
                .source = self.sourceRef(node),
                .ty = ty orelse ir.unresolved_binding_type_poison,
                .initialization = initialization,
                .mutability = graph_mod.mutabilityFromSyntax(declaration.mutability),
            });
            if (ty == null) try self.graph.semantic.parameterized_storage.ir.unresolved_binding_types.append(self.allocator, binding);
            try self.bindings.append(.{ .name = name, .id = binding });
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .binding_declaration = binding });
        }
        if (self.tree.assignment(node)) |assignment| {
            const name = self.tree.tokenTextFromSource(self.source, assignment.name_token);
            const binding = self.parameterizedBinding(name) orelse return error.UnknownParameterizedAssignment;
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .assignment = .{
                .binding = binding,
                .value = try self.lowerBodyNode(assignment.value),
            } });
        }
        if (self.tree.structValueLiteral(node)) |literal| {
            var fields: std.ArrayList(ir.ValueField) = .empty;
            defer fields.deinit(self.allocator);
            for (literal.fields) |field_node| {
                const field = self.tree.valueField(field_node) orelse return error.InvalidParameterizedValueField;
                try fields.append(self.allocator, .{
                    .name = try self.writer.addString(if (field.name_token) |token| self.tree.tokenTextFromSource(self.source, token) else ""),
                    .value = try self.lowerBodyNode(field.value),
                });
            }
            const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.value_fields.items.len);
            try self.graph.semantic.parameterized_storage.ir.value_fields.appendSlice(self.allocator, fields.items);
            return self.addResolvedNode(node, null, .{ .struct_value_literal = .{
                .fields = .{ .start = start, .len = @intCast(fields.items.len) },
                .dispatch_prefix_positional_count = literal.positional_prefix_count,
            } });
        }
        // Keep the few parameter-independent leaves compact and represent every
        // semantic composition uniformly as a syntax-free pending expression.
        if (self.tree.literal(node)) |literal| {
            const token_content = self.tree.tokenContent(literal.token).literal;
            return switch (token_content) {
                .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => blk: {
                    const value = try literals.integer(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                    break :blk self.addResolvedNode(node, try self.parameterizedBuiltin(.Int32), .{ .int_literal = value });
                },
                .regular_float_literal, .scientific_float_literal => blk: {
                    const value = try literals.float(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                    break :blk self.addResolvedNode(node, try self.parameterizedBuiltin(.Float32), .{ .float_literal = value });
                },
                .bool_literal => |value| self.addResolvedNode(node, try self.parameterizedBuiltin(.Bool), .{ .bool_literal = value }),
                .char_literal => |value| self.addResolvedNode(node, try self.parameterizedBuiltin(.Char), .{ .char_literal = value }),
                .string_literal => blk: {
                    const raw = self.tree.tokenTextFromSource(self.source, literal.token);
                    const decoded = try tok.decodeStringLiteral(self.allocator, raw);
                    defer if (std.mem.indexOfScalar(u8, raw, '\\') != null)
                        self.allocator.free(decoded);
                    break :blk self.addResolvedNode(node, null, .{
                        .string_literal = try self.writer.addString(decoded),
                    });
                },
            };
        }
        if (self.tree.tag(node) == .identifier) {
            const name = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            if (self.parameterizedBinding(name)) |binding| {
                const ty = self.graph.semantic.parameterized_storage.ir.bindingType(binding);
                return self.addResolvedNode(node, ty, .{ .binding_use = binding });
            }
            if (self.parameter(name)) |parameter_binding| {
                switch (parameter_binding.kind) {
                    .type => {
                        const value = try self.addType(.{ .parameter = parameter_binding.id });
                        return self.addResolvedNode(node, try self.parameterizedBuiltin(.Type), .{ .type_literal = value });
                    },
                    .comptime_int => {
                        const parameter_record = self.graph.semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter_binding.id)];
                        return self.addPending(
                            node,
                            .comptime_parameter,
                            &.{},
                            null,
                            parameter_record.value_type,
                            .{ .comptime_parameter = parameter_binding.id },
                        );
                    },
                }
            }
            return self.addPending(node, .unknown_identifier, &.{}, try self.writer.addString(name), null, .none);
        }
        if (self.tree.tag(node) == .break_statement)
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .break_statement);
        if (self.tree.tag(node) == .continue_statement)
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .continue_statement);

        var operands = std.array_list.Managed(ir.ParameterizedNodeId).init(self.allocator);
        defer operands.deinit();
        try self.collectBodyOperands(node, &operands);
        const kind = parameterizedKindForTag(self.tree.tag(node));
        const name = switch (self.tree.tag(node)) {
            .function_call => if (self.tree.functionCall(node)) |call| try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token)) else null,
            .struct_field_access => if (self.tree.structFieldAccess(node)) |access| try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)) else null,
            .choice_payload_access => if (self.tree.choicePayloadAccess(node)) |access| try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)) else null,
            .choice_literal, .choice_some_literal => if (self.tree.choiceLiteral(node)) |literal| try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.name_token)) else null,
            .keep_statement => if (self.tree.keepStatement(node)) |keep| try self.writer.addString(self.tree.tokenTextFromSource(self.source, keep.name_token)) else null,
            else => null,
        };
        return self.addPending(node, kind, operands.items, name, null, parameterizedDetailForTag(self.tree.tag(node)));
    }

    fn lowerReach(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const directive = self.tree.reachDirective(node) orelse return error.InvalidParameterizedReach;
        const alt_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.reach_alternatives.items.len);
        for (directive.alternatives) |alt_node| {
            const alternative = self.tree.reachAlternative(alt_node) orelse return error.InvalidParameterizedReachAlternative;
            const segment_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.reach_segments.items.len);
            for (alternative.segments) |segment| {
                try self.graph.semantic.parameterized_storage.ir.reach_segments.append(self.allocator, try self.writer.addString(self.tree.tokenTextFromSource(self.source, self.tree.mainToken(segment))));
            }
            try self.graph.semantic.parameterized_storage.ir.reach_alternatives.append(self.allocator, .{
                .segments = .{ .start = segment_start, .len = @intCast(alternative.segments.len) },
            });
        }
        const reach_id: ir.ParameterizedReachId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.reaches.items.len)));
        try self.graph.semantic.parameterized_storage.ir.reaches.append(self.allocator, .{
            .alternatives = .{ .start = alt_start, .len = @intCast(directive.alternatives.len) },
        });
        return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .reach_directive = reach_id });
    }

    fn collectBodyOperands(self: *Context, node: syn.NodeIndex, result: *std.array_list.Managed(ir.ParameterizedNodeId)) anyerror!void {
        if (self.tree.pointerAssignment(node)) |assignment| {
            const pointer = if (self.tree.tag(assignment.target) == .dereference)
                self.tree.unaryOperand(assignment.target).?
            else
                assignment.target;
            const target = try self.lowerBodyNode(pointer);
            try result.append(if (self.tree.tag(assignment.target) == .dereference)
                target
            else
                try self.addPending(node, .address_of, &.{target}, null, null, .{ .pointer_mutability = .read_write }));
            try result.append(try self.lowerBodyNode(assignment.value));
            return;
        }
        if (self.tree.indexAssignment(node)) |assignment| {
            const target = self.tree.indexAccess(assignment.target) orelse return error.InvalidIndexAssignmentTarget;
            try result.append(try self.lowerBodyNode(target.value));
            try result.append(try self.lowerBodyNode(target.index));
            try result.append(try self.lowerBodyNode(assignment.value));
            return;
        }
        if (self.tree.indexAccess(node)) |access| {
            try result.append(try self.lowerBodyNode(access.value));
            try result.append(try self.lowerBodyNode(access.index));
            return;
        }
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

    fn blockAsNode(self: *Context, node: syn.NodeIndex) !ir.ParameterizedNodeId {
        const block = try self.lowerBlock(node);
        const body = self.graph.semantic.parameterized_storage.ir.blocks.items[@intFromEnum(block)];
        const ty: ?ir.ParameterizedTypeId = if (body.ret_val) |ret_val|
            switch (self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(ret_val)]) {
                .resolved => |resolved_node| resolved_node.ty,
                .pending => null,
            }
        else
            try self.parameterizedBuiltin(.Void);
        return self.addResolvedNode(node, ty, .{ .code_block = block });
    }

    fn addPending(self: *Context, node: syn.NodeIndex, kind: ir.PendingExpressionKind, operands: []const ir.ParameterizedNodeId, name: ?primitives.StringRange, expected: ?ir.ParameterizedTypeId, detail: ir.PendingExpressionDetail) !ir.ParameterizedNodeId {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.node_refs.items.len);
        try self.graph.semantic.parameterized_storage.ir.node_refs.appendSlice(self.allocator, operands);
        const pending_id: ir.ParameterizedPendingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.pending.items.len)));
        try self.graph.semantic.parameterized_storage.ir.pending.append(self.allocator, .{ .resolve_expression = .{
            .kind = kind,
            .operands = .{ .start = start, .len = @intCast(operands.len) },
            .name = name,
            .expected_type = expected,
            .source = self.sourceRef(node),
            .detail = detail,
        } });
        const id: ir.ParameterizedNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.nodes.items.len)));
        try self.graph.semantic.parameterized_storage.ir.nodes.append(self.allocator, .{ .pending = pending_id });
        return id;
    }

    fn addResolvedNode(self: *Context, node: syn.NodeIndex, ty: ?ir.ParameterizedTypeId, content: ir.ResolvedNode.Content) !ir.ParameterizedNodeId {
        const id: ir.ParameterizedNodeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.nodes.items.len)));
        try self.graph.semantic.parameterized_storage.ir.nodes.append(self.allocator, .{ .resolved = .{
            .source = self.sourceRef(node),
            .ty = ty,
            .content = content,
        } });
        return id;
    }

    fn addType(self: *Context, value: ir.Type) !ir.ParameterizedTypeId {
        const id: ir.ParameterizedTypeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.types.items.len)));
        try self.graph.semantic.parameterized_storage.ir.types.append(self.allocator, value);
        return id;
    }

    fn addInt(self: *Context, value: ir.IntExpression) !ir.ParameterizedIntExprId {
        const id: ir.ParameterizedIntExprId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.int_expressions.items.len)));
        try self.graph.semantic.parameterized_storage.ir.int_expressions.append(self.allocator, value);
        return id;
    }

    fn parameterizedBuiltin(self: *Context, builtin: primitives.BuiltinType) !ir.ParameterizedTypeId {
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

    fn parameterizedBinding(self: *Context, name: []const u8) ?ir.ParameterizedBindingId {
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

    fn localAbstractType(self: *Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |id|
            if (self.graph.declarations.items[@intFromEnum(id)].kind == .abstract_type) return id;
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

pub fn isTypeParameter(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField) bool {
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

fn parameterizedDetailForTag(tag: syn.Node.Tag) ir.PendingExpressionDetail {
    return switch (tag) {
        .binary_add => .{ .binary = .addition },
        .binary_subtract => .{ .binary = .subtraction },
        .binary_multiply => .{ .binary = .multiplication },
        .binary_divide => .{ .binary = .division },
        .binary_modulo => .{ .binary = .modulo },
        .compare_equal => .{ .comparison = .equal },
        .compare_not_equal => .{ .comparison = .not_equal },
        .compare_less => .{ .comparison = .less_than },
        .compare_greater => .{ .comparison = .greater_than },
        .compare_less_equal => .{ .comparison = .less_than_or_equal },
        .compare_greater_equal => .{ .comparison = .greater_than_or_equal },
        .logical_and => .{ .logical = .and_ },
        .logical_or => .{ .logical = .or_ },
        .address_of => .{ .pointer_mutability = .read_only },
        .address_of_mut => .{ .pointer_mutability = .read_write },
        else => .none,
    };
}

fn parameterizedKindForTag(tag: syn.Node.Tag) ir.PendingExpressionKind {
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

test "module parameterized lowerer stores dependent shapes without syntax references" {
    try std.testing.expect(@sizeOf(ir.ParameterizedTypeId) == 4);
    try std.testing.expect(@sizeOf(ir.ParameterizedNodeId) == 4);
}

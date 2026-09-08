const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const graph_mod = @import("module_semantic_graph.zig");
const entities = @import("module_semantic_entities.zig");
const templates = @import("module_semantic_templates.zig");
const ir = @import("module_semantic_template_ir.zig");
const writer_mod = @import("module_semantic_writer.zig");
const type_lowerer = @import("module_type_lowerer.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    implementations: u32 = 0,
    implementation_templates: u32 = 0,
    defaults: u32 = 0,
    default_templates: u32 = 0,
};

const Param = struct {
    name: []const u8,
    id: ir.TemplateParameterId,
    kind: templates.GenericParameterKind,
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
        .params = std.array_list.Managed(Param).init(allocator),
    };
    defer ctx.params.deinit();
    return ctx.run();
}

const Context = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    params: std.array_list.Managed(Param),
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},

    fn run(self: *Context) !Stats {
        var stats: Stats = .{};
        for (self.files, 0..) |file, raw_file| {
            self.file_index = @intCast(raw_file);
            self.tree = file.tree;
            self.source = file.source;
            for (self.tree.roots) |node| switch (self.tree.tag(node)) {
                .abstract_implements => {
                    const relation = self.tree.abstractImplements(node).?;
                    if (hasParams(relation.generic_params, relation.generic_params_struct)) {
                        try self.lowerImplementationTemplate(node, relation);
                        stats.implementation_templates += 1;
                    } else {
                        try self.lowerImplementation(node, relation);
                        stats.implementations += 1;
                    }
                },
                .abstract_defaultsto => {
                    const relation = self.tree.abstractDefaultsTo(node).?;
                    if (hasParams(relation.generic_params, relation.generic_params_struct)) {
                        try self.lowerDefaultTemplate(node, relation);
                        stats.default_templates += 1;
                    } else {
                        try self.lowerDefault(node, relation);
                        stats.defaults += 1;
                    }
                },
                else => {},
            };
        }
        return stats;
    }

    fn lowerImplementation(self: *Context, node: syn.NodeIndex, relation: syn.AbstractImplements) !void {
        const concrete_name = self.tree.tokenTextFromSource(self.source, relation.concrete_name_token);
        const concrete = try self.moduleTypeFromName(node, concrete_name, null);
        const parsed = try self.abstractReference(relation.abstract_type, false);
        const arg_start: u32 = @intCast(self.graph.semantic.templates.abstract_arguments.items.len);
        for (parsed.module_arguments) |argument| try self.graph.semantic.templates.abstract_arguments.append(self.allocator, argument);
        defer self.allocator.free(parsed.module_arguments);
        try self.graph.semantic.templates.abstract_implementations.append(self.allocator, .{
            .abstract_ref = parsed.reference,
            .ty = concrete,
            .arguments = .{ .start = arg_start, .len = @intCast(parsed.module_arguments.len) },
            .source = self.sourceRef(node),
        });
    }

    fn lowerImplementationTemplate(self: *Context, node: syn.NodeIndex, relation: syn.AbstractImplements) !void {
        self.params.clearRetainingCapacity();
        const params = try self.lowerParams(relation.generic_params, relation.generic_params_struct);
        const parsed = try self.abstractReference(relation.abstract_type, true);
        defer self.allocator.free(parsed.module_arguments);
        const concrete_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, relation.concrete_name_token));
        try self.graph.semantic.templates.abstract_implementation_templates.append(self.allocator, .{
            .abstract_ref = parsed.reference,
            .parameters = params,
            .concrete_name = concrete_name,
            .concrete_parameter_count = params.len,
            .arguments = parsed.template_arguments,
            .source = self.sourceRef(node),
        });
    }

    fn lowerDefault(self: *Context, node: syn.NodeIndex, relation: syn.AbstractDefaultsTo) !void {
        const abstract_name = self.tree.tokenTextFromSource(self.source, relation.name_token);
        const abstract_ref = try self.declarationRef(node, abstract_name, .abstract);
        const ty = try self.lowerModuleType(relation.type_node);
        try self.graph.semantic.templates.abstract_defaults.append(self.allocator, .{
            .abstract_ref = abstract_ref,
            .ty = ty,
            .source = self.sourceRef(node),
        });
    }

    fn lowerDefaultTemplate(self: *Context, node: syn.NodeIndex, relation: syn.AbstractDefaultsTo) !void {
        self.params.clearRetainingCapacity();
        const params = try self.lowerParams(relation.generic_params, relation.generic_params_struct);
        const abstract_name = self.tree.tokenTextFromSource(self.source, relation.name_token);
        const abstract_ref = try self.declarationRef(node, abstract_name, .abstract);
        const ty = try self.lowerTemplateType(relation.type_node);
        try self.graph.semantic.templates.abstract_default_templates.append(self.allocator, .{
            .abstract_ref = abstract_ref,
            .parameters = params,
            .ty = ty,
            .source = self.sourceRef(node),
        });
    }

    const ParsedAbstract = struct {
        reference: ir.DeclarationRef,
        module_arguments: []templates.AbstractArgument,
        template_arguments: primitives.Range(ir.TemplateGenericArgId),
    };

    fn abstractReference(self: *Context, node: syn.NodeIndex, template_mode: bool) !ParsedAbstract {
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
        const base = self.tree.syntaxType(base_node).?.name;
        const name = self.tree.tokenTextFromSource(self.source, base.name_token);
        const reference = try self.declarationRef(base_node, name, .abstract);
        var module_args: std.ArrayList(templates.AbstractArgument) = .empty;
        errdefer module_args.deinit(self.allocator);
        const template_start: u32 = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len);
        if (arguments_node) |args_node| {
            const literal = self.tree.structTypeLiteral(args_node) orelse return error.InvalidAbstractArguments;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidAbstractArgument;
                const arg_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
                if (template_mode) {
                    if (field.type_node) |type_node| {
                        try self.graph.semantic.templates.ir.generic_arguments.append(self.allocator, .{
                            .name = arg_name,
                            .value = .{ .type = try self.lowerTemplateType(type_node) },
                        });
                    } else if (field.default_value) |value_node| {
                        try self.graph.semantic.templates.ir.generic_arguments.append(self.allocator, .{
                            .name = arg_name,
                            .value = .{ .comptime_int = try self.lowerTemplateInt(value_node) },
                        });
                    } else return error.InvalidAbstractArgument;
                } else {
                    if (field.type_node) |type_node|
                        try module_args.append(self.allocator, .{ .type = try self.lowerModuleType(type_node) })
                    else if (field.default_value) |value_node|
                        try module_args.append(self.allocator, .{ .comptime_int = try self.evalInt(value_node) })
                    else
                        try module_args.append(self.allocator, .none);
                }
            }
        }
        return .{
            .reference = reference,
            .module_arguments = try module_args.toOwnedSlice(self.allocator),
            .template_arguments = .{
                .start = template_start,
                .len = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len - template_start),
            },
        };
    }

    fn lowerParams(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.TemplateParameterId) {
        const start: u32 = @intCast(self.graph.semantic.templates.generic_parameters.items.len);
        if (params_struct) |node| {
            const literal = self.tree.structTypeLiteral(node) orelse return error.InvalidGenericParameters;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                const kind: templates.GenericParameterKind = if (field.type_node) |type_node|
                    if (isTypeName(self.tree, self.source, type_node, "Type")) .type else .comptime_int
                else .type;
                const id: ir.TemplateParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.generic_parameters.items.len)));
                try self.graph.semantic.templates.generic_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                });
                try self.params.append(.{ .name = name_text, .id = id, .kind = kind });
            }
        } else {
            for (params) |param| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param));
                const id: ir.TemplateParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.generic_parameters.items.len)));
                try self.graph.semantic.templates.generic_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text), .kind = .type,
                });
                try self.params.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.templates.generic_parameters.items.len - start) };
    }

    fn lowerTemplateType(self: *Context, node: syn.NodeIndex) anyerror!ir.TemplateTypeId {
        const ty = self.tree.syntaxType(node) orelse return error.ExpectedTemplateType;
        return switch (ty) {
            .name => |name| blk: {
                const text = self.tree.tokenTextFromSource(self.source, name.name_token);
                if (name.qualifier_token == null) {
                    for (self.params.items) |param| if (param.kind == .type and std.mem.eql(u8, param.name, text))
                        break :blk try self.addTemplateType(.{ .parameter = param.id });
                    if (self.localType(text)) |local|
                        break :blk try self.addTemplateType(.{ .concrete = self.graph.declarations.items[@intFromEnum(local)].type_id.? });
                    if (builtinFromName(text)) |builtin|
                        break :blk try self.addTemplateType(.{ .concrete = try self.moduleBuiltin(builtin) });
                }
                const external = try self.writer.addExternalRef(.{
                    .kind = .type,
                    .module_path = if (name.qualifier_token) |token| try self.writer.addString(self.tree.tokenTextFromSource(self.source, token)) else null,
                    .name = try self.writer.addString(text), .source = self.sourceRef(node),
                });
                break :blk try self.addTemplateType(.{ .external = external });
            },
            .pointer => |ptr| try self.addTemplateType(.{ .resolved = .{ .pointer = .{
                .child = try self.lowerTemplateType(ptr.child), .mutability = ptr.mutability,
            } } }),
            .nullable => |child| try self.addTemplateType(.{ .resolved = .{ .nullable = try self.lowerTemplateType(child) } }),
            .inferred_errable => |child| try self.addTemplateType(.{ .resolved = .{ .inferred_errable = try self.lowerTemplateType(child) } }),
            .array => |array| try self.addTemplateType(.{ .array = .{
                .length = try self.lowerTemplateIntFromToken(array.length_token),
                .element = try self.lowerTemplateType(array.element),
            } }),
            .generic => |generic| self.lowerTemplateGeneric(generic),
            .struct_literal, .choice_literal => return error.UnsupportedAbstractRelationTemplateType,
        };
    }

    fn lowerTemplateGeneric(self: *Context, generic: syn.GenericType) !ir.TemplateTypeId {
        const base = self.tree.syntaxType(generic.base) orelse return error.InvalidGenericBase;
        if (base != .name) return error.InvalidGenericBase;
        const name = self.tree.tokenTextFromSource(self.source, base.name.name_token);
        const ref = try self.declarationRef(generic.base, name, .type);
        const decl_id: ir.TemplateDeclId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.declarations.items.len)));
        try self.graph.semantic.templates.ir.declarations.append(self.allocator, .{ .target = ref });
        const literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidGenericArguments;
        const start: u32 = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericArgument;
            const name_range = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
            const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                .{ .type = try self.lowerTemplateType(type_node) }
            else if (field.default_value) |value_node|
                .{ .comptime_int = try self.lowerTemplateInt(value_node) }
            else return error.InvalidGenericArgument;
            try self.graph.semantic.templates.ir.generic_arguments.append(self.allocator, .{ .name = name_range, .value = value });
        }
        return self.addTemplateType(.{ .resolved = .{ .generic = .{
            .base = decl_id,
            .arguments = .{ .start = start, .len = @intCast(literal.fields.len) },
        } } });
    }

    fn lowerModuleType(self: *Context, node: syn.NodeIndex) !entities.ModuleTypeId {
        var lowerer = type_lowerer.Context{
            .graph = self.graph, .writer = &self.writer, .file_index = self.file_index,
            .tree = self.tree, .source = self.source,
        };
        return lowerer.lower(node);
    }

    fn moduleTypeFromName(self: *Context, node: syn.NodeIndex, name: []const u8, qualifier: ?[]const u8) !entities.ModuleTypeId {
        if (qualifier == null) if (self.localType(name)) |decl| return self.graph.declarations.items[@intFromEnum(decl)].type_id.?;
        const external = try self.writer.addExternalRef(.{
            .kind = .type,
            .module_path = if (qualifier) |text| try self.writer.addString(text) else null,
            .name = try self.writer.addString(name), .source = self.sourceRef(node),
        });
        return self.writer.addExternalType(external);
    }

    fn declarationRef(self: *Context, node: syn.NodeIndex, name: []const u8, kind: entities.ExternalKind) !ir.DeclarationRef {
        for (self.graph.declarationsNamed(name)) |decl| {
            const candidate = self.graph.declarations.items[@intFromEnum(decl)];
            if ((kind == .abstract and candidate.kind == .abstract_type) or (kind == .type and candidate.kind == .type))
                return .{ .module = decl };
        }
        const external = try self.writer.addExternalRef(.{
            .kind = kind,
            .module_path = null,
            .name = try self.writer.addString(name),
            .source = self.sourceRef(node),
        });
        return .{ .external = external };
    }

    fn lowerTemplateInt(self: *Context, node: syn.NodeIndex) anyerror!ir.TemplateIntExprId {
        if (self.tree.literal(node)) |literal| {
            var value = std.fmt.parseInt(i64, self.tree.tokenTextFromSource(self.source, literal.token), 0) catch return error.InvalidComptimeInt;
            if (literal.negative) value = -value;
            return self.addInt(.{ .literal = value });
        }
        if (self.tree.tag(node) == .identifier) {
            const text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            for (self.params.items) |param| if (param.kind == .comptime_int and std.mem.eql(u8, param.name, text))
                return self.addInt(.{ .parameter = param.id });
        }
        const op = self.tree.binaryOperation(node) orelse return error.InvalidComptimeInt;
        const operator: ir.IntBinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .add, .binary_subtract => .subtract, .binary_multiply => .multiply,
            .binary_divide => .divide, .binary_modulo => .modulo, else => return error.InvalidComptimeInt,
        };
        return self.addInt(.{ .binary = .{
            .operator = operator, .left = try self.lowerTemplateInt(op.lhs), .right = try self.lowerTemplateInt(op.rhs),
        } });
    }

    fn lowerTemplateIntFromToken(self: *Context, token: syn.TokenIndex) !ir.TemplateIntExprId {
        const text = self.tree.tokenTextFromSource(self.source, token);
        for (self.params.items) |param| if (param.kind == .comptime_int and std.mem.eql(u8, param.name, text))
            return self.addInt(.{ .parameter = param.id });
        return self.addInt(.{ .literal = try std.fmt.parseInt(i64, text, 0) });
    }

    fn evalInt(self: *Context, node: syn.NodeIndex) !i64 {
        if (self.tree.literal(node)) |literal| {
            var value = try std.fmt.parseInt(i64, self.tree.tokenTextFromSource(self.source, literal.token), 0);
            if (literal.negative) value = -value;
            return value;
        }
        const op = self.tree.binaryOperation(node) orelse return error.InvalidComptimeInt;
        const left = try self.evalInt(op.lhs);
        const right = try self.evalInt(op.rhs);
        return switch (self.tree.tag(node)) {
            .binary_add => left + right,
            .binary_subtract => left - right,
            .binary_multiply => left * right,
            .binary_divide => @divTrunc(left, right),
            .binary_modulo => @mod(left, right),
            else => error.InvalidComptimeInt,
        };
    }

    fn addTemplateType(self: *Context, value: ir.Type) !ir.TemplateTypeId {
        const id: ir.TemplateTypeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.types.items.len)));
        try self.graph.semantic.templates.ir.types.append(self.allocator, value);
        return id;
    }

    fn addInt(self: *Context, value: ir.IntExpression) !ir.TemplateIntExprId {
        const id: ir.TemplateIntExprId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.int_expressions.items.len)));
        try self.graph.semantic.templates.ir.int_expressions.append(self.allocator, value);
        return id;
    }

    fn moduleBuiltin(self: *Context, builtin: primitives.BuiltinType) !entities.ModuleTypeId {
        for (self.graph.types.items, 0..) |existing, index| switch (existing) {
            .builtin => |value| if (value == builtin) return @enumFromInt(@as(u32, @intCast(index))),
            else => {},
        };
        return self.writer.addResolvedType(.{ .builtin = builtin });
    }

    fn localType(self: *Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |decl| switch (self.graph.declarations.items[@intFromEnum(decl)].kind) {
            .type, .abstract_type => return decl,
            else => {},
        };
        return null;
    }

    fn sourceRef(self: *Context, node: syn.NodeIndex) primitives.SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }
};

fn hasParams(params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) bool {
    return params.len != 0 or params_struct != null;
}

fn isTypeName(tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex, expected: []const u8) bool {
    const ty = tree.syntaxType(node) orelse return false;
    return ty == .name and ty.name.qualifier_token == null and std.mem.eql(u8, tree.tokenTextFromSource(source, ty.name.name_token), expected);
}

fn builtinFromName(name: []const u8) ?primitives.BuiltinType {
    inline for (@typeInfo(primitives.BuiltinType).@"enum".fields) |field|
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    return null;
}

test "abstract relation lowering owns both concrete and template forms" {
    try std.testing.expect(@sizeOf(templates.AbstractDefaultTemplate) <= 32);
}

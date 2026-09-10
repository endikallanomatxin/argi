const parameterized_lowerer = @import("parameterized/lowerer.zig");
const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const parameterized_storage = @import("parameterized/storage.zig");
const ir = @import("parameterized/ir.zig");
const writer_mod = @import("writer.zig");
const type_lowerer = @import("type_lowerer.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    implementations: u32 = 0,
    implementation_parameterized_forms: u32 = 0,
    defaults: u32 = 0,
    default_parameterized_forms: u32 = 0,
};

const Param = parameterized_lowerer.ParameterBinding;

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
                        try self.lowerImplementationParameterized(node, relation);
                        stats.implementation_parameterized_forms += 1;
                    } else {
                        try self.lowerImplementation(node, relation);
                        stats.implementations += 1;
                    }
                },
                .abstract_defaultsto => {
                    const relation = self.tree.abstractDefaultsTo(node).?;
                    if (hasParams(relation.generic_params, relation.generic_params_struct)) {
                        try self.lowerDefaultParameterized(node, relation);
                        stats.default_parameterized_forms += 1;
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
        const arg_start: u32 = @intCast(self.graph.semantic.parameterized_storage.abstract_arguments.items.len);
        for (parsed.module_arguments) |argument| try self.graph.semantic.parameterized_storage.abstract_arguments.append(self.allocator, argument);
        defer self.allocator.free(parsed.module_arguments);
        try self.graph.semantic.parameterized_storage.abstract_implementations.append(self.allocator, .{
            .abstract_ref = parsed.reference,
            .ty = concrete,
            .arguments = .{ .start = arg_start, .len = @intCast(parsed.module_arguments.len) },
            .source = self.sourceRef(node),
        });
    }

    fn lowerImplementationParameterized(self: *Context, node: syn.NodeIndex, relation: syn.AbstractImplements) !void {
        self.params.clearRetainingCapacity();
        const params = try self.lowerParams(relation.generic_params, relation.generic_params_struct);
        const parsed = try self.abstractReference(relation.abstract_type, true);
        defer self.allocator.free(parsed.module_arguments);
        const concrete_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, relation.concrete_name_token));
        try self.graph.semantic.parameterized_storage.parameterized_abstract_implementations.append(self.allocator, .{
            .abstract_ref = parsed.reference,
            .parameters = params,
            .concrete_name = concrete_name,
            .concrete_parameter_count = params.len,
            .arguments = parsed.parameterized_arguments,
            .source = self.sourceRef(node),
        });
    }

    fn lowerDefault(self: *Context, node: syn.NodeIndex, relation: syn.AbstractDefaultsTo) !void {
        const abstract_name = self.tree.tokenTextFromSource(self.source, relation.name_token);
        const abstract_ref = try self.declarationRef(node, abstract_name, .abstract);
        const ty = try self.lowerModuleType(relation.type_node);
        try self.graph.semantic.parameterized_storage.abstract_defaults.append(self.allocator, .{
            .abstract_ref = abstract_ref,
            .ty = ty,
            .source = self.sourceRef(node),
        });
    }

    fn lowerDefaultParameterized(self: *Context, node: syn.NodeIndex, relation: syn.AbstractDefaultsTo) !void {
        self.params.clearRetainingCapacity();
        const params = try self.lowerParams(relation.generic_params, relation.generic_params_struct);
        const abstract_name = self.tree.tokenTextFromSource(self.source, relation.name_token);
        const abstract_ref = try self.declarationRef(node, abstract_name, .abstract);
        const ty = try self.lowerParameterizedType(relation.type_node);
        try self.graph.semantic.parameterized_storage.parameterized_abstract_defaults.append(self.allocator, .{
            .abstract_ref = abstract_ref,
            .parameters = params,
            .ty = ty,
            .source = self.sourceRef(node),
        });
    }

    const ParsedAbstract = struct {
        reference: ir.DeclarationRef,
        module_arguments: []parameterized_storage.AbstractArgument,
        parameterized_arguments: primitives.Range(ir.ParameterizedGenericArgId),
    };

    fn abstractReference(self: *Context, node: syn.NodeIndex, parameterized_mode: bool) !ParsedAbstract {
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
        var module_args: std.ArrayList(parameterized_storage.AbstractArgument) = .empty;
        errdefer module_args.deinit(self.allocator);
        var parameterized_args: std.ArrayList(ir.GenericArgument) = .empty;
        defer parameterized_args.deinit(self.allocator);
        if (arguments_node) |args_node| {
            const literal = self.tree.structTypeLiteral(args_node) orelse return error.InvalidAbstractArguments;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidAbstractArgument;
                const arg_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
                if (parameterized_mode) {
                    if (field.type_node) |type_node| {
                        try parameterized_args.append(self.allocator, .{
                            .name = arg_name,
                            .value = .{ .type = try self.lowerParameterizedType(type_node) },
                        });
                    } else if (field.default_value) |value_node| {
                        var lowerer = self.parameterizedContext();
                        defer lowerer.bindings.deinit();
                        try parameterized_args.append(self.allocator, .{
                            .name = arg_name,
                            .value = try lowerer.lowerGenericValue(value_node, false),
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
        const parameterized_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, parameterized_args.items);
        return .{
            .reference = reference,
            .module_arguments = try module_args.toOwnedSlice(self.allocator),
            .parameterized_arguments = .{
                .start = parameterized_start,
                .len = @intCast(parameterized_args.items.len),
            },
        };
    }

    fn lowerParams(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
        if (params_struct) |node| {
            const literal = self.tree.structTypeLiteral(node) orelse return error.InvalidGenericParameters;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                const kind: parameterized_storage.ComptimeParameterKind = if (field.type_node) |type_node|
                    if (isTypeName(self.tree, self.source, type_node, "Type")) .type else .comptime_int
                else
                    .type;
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                });
                try self.params.append(.{ .name = name_text, .id = id, .kind = kind });
            }
        } else {
            for (params) |param| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param));
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = .type,
                });
                try self.params.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - start) };
    }

    fn lowerParameterizedType(self: *Context, node: syn.NodeIndex) !ir.ParameterizedTypeId {
        var lowerer = self.parameterizedContext();
        defer lowerer.bindings.deinit();
        return lowerer.lowerType(node, false);
    }

    fn parameterizedContext(self: *Context) parameterized_lowerer.Context {
        return .{
            .allocator = self.allocator,
            .graph = self.graph,
            .files = self.files,
            .writer = self.writer,
            .parameters = self.params,
            .bindings = .init(self.allocator),
            .file_index = self.file_index,
            .tree = self.tree,
            .source = self.source,
        };
    }

    fn lowerModuleType(self: *Context, node: syn.NodeIndex) !entities.ModuleTypeId {
        var lowerer = type_lowerer.Context{
            .graph = self.graph,
            .writer = &self.writer,
            .file_index = self.file_index,
            .tree = self.tree,
            .source = self.source,
        };
        return lowerer.lower(node);
    }

    fn moduleTypeFromName(self: *Context, node: syn.NodeIndex, name: []const u8, qualifier: ?[]const u8) !entities.ModuleTypeId {
        if (qualifier == null) if (self.localType(name)) |decl| return self.graph.declarations.items[@intFromEnum(decl)].type_id.?;
        const external = try self.writer.addExternalRef(.{
            .kind = .type,
            .module_path = if (qualifier) |text| try self.writer.addString(text) else null,
            .name = try self.writer.addString(name),
            .source = self.sourceRef(node),
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

    fn lowerParameterizedInt(self: *Context, node: syn.NodeIndex) anyerror!ir.ParameterizedIntExprId {
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
            .binary_add => .add,
            .binary_subtract => .subtract,
            .binary_multiply => .multiply,
            .binary_divide => .divide,
            .binary_modulo => .modulo,
            else => return error.InvalidComptimeInt,
        };
        return self.addInt(.{ .binary = .{
            .operator = operator,
            .left = try self.lowerParameterizedInt(op.lhs),
            .right = try self.lowerParameterizedInt(op.rhs),
        } });
    }

    fn lowerParameterizedIntFromToken(self: *Context, token: syn.TokenIndex) !ir.ParameterizedIntExprId {
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

    fn addParameterizedType(self: *Context, value: ir.Type) !ir.ParameterizedTypeId {
        const id: ir.ParameterizedTypeId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.types.items.len)));
        try self.graph.semantic.parameterized_storage.ir.types.append(self.allocator, value);
        return id;
    }

    fn addInt(self: *Context, value: ir.IntExpression) !ir.ParameterizedIntExprId {
        const id: ir.ParameterizedIntExprId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.int_expressions.items.len)));
        try self.graph.semantic.parameterized_storage.ir.int_expressions.append(self.allocator, value);
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

test "abstract relation lowering owns both concrete and parameterized forms" {
    try std.testing.expect(@sizeOf(parameterized_storage.ParameterizedAbstractDefault) <= 32);
}

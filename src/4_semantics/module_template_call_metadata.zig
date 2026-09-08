const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const graph_mod = @import("module_semantic_graph.zig");
const entities = @import("module_semantic_entities.zig");
const templates = @import("module_semantic_templates.zig");
const ir = @import("module_semantic_template_ir.zig");
const writer_mod = @import("module_semantic_writer.zig");
const primitives = @import("semantic_primitives.zig");

pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !u32 {
    var ctx = Context{ .allocator = allocator, .graph = graph, .files = files, .writer = writer_mod.Writer.init(allocator, graph) };
    var count: u32 = 0;
    for (graph.semantic.templates.generic_function_templates.items) |template| {
        const decl = graph.declarations.items[@intFromEnum(template.declaration)];
        ctx.file_index = decl.module_file_index;
        ctx.tree = files[decl.module_file_index].tree;
        ctx.source = files[decl.module_file_index].source;
        ctx.parameter_range = template.parameters;
        const end = nextDeclarationOffset(graph, template.declaration);
        for (graph.semantic.templates.ir.pending.items) |*pending| {
            const expression = switch (pending.*) { .resolve_expression => |*value| value, else => continue };
            if (expression.kind != .generic_call) continue;
            if (expression.source.file_index != decl.module_file_index) continue;
            if (expression.source.offset < decl.source_offset or expression.source.offset >= end) continue;
            const call_node = ctx.findCall(expression.source.offset) orelse continue;
            const call = ctx.tree.functionCall(call_node).?;
            expression.module_path = if (call.module_qualifier) |token|
                try ctx.writer.addString(ctx.tree.tokenTextFromSource(ctx.source, token)) else null;
            expression.generic_arguments = try ctx.lowerArguments(call);
            count += 1;
        }
    }
    return count;
}

const Context = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},
    parameter_range: primitives.Range(ir.TemplateParameterId) = .{ .start = 0, .len = 0 },

    fn findCall(self: *Context, offset: u32) ?syn.NodeIndex {
        for (self.tree.nodes.items(.tag), 0..) |tag, raw| {
            if (tag != .function_call) continue;
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            if (self.tree.location(node).offset == offset) return node;
        }
        return null;
    }

    fn lowerArguments(self: *Context, call: syn.FunctionCall) !primitives.Range(ir.TemplateGenericArgId) {
        const start: u32 = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len);
        if (call.type_arguments_struct) |struct_node| {
            const literal = self.tree.structTypeLiteral(struct_node) orelse return error.InvalidTemplateCallArguments;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidTemplateCallArgument;
                const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
                const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                    .{ .type = try self.lowerType(type_node) }
                else if (field.default_value) |value_node|
                    .{ .comptime_int = try self.lowerInt(value_node) }
                else return error.InvalidTemplateCallArgument;
                try self.graph.semantic.templates.ir.generic_arguments.append(self.allocator, .{ .name = name, .value = value });
            }
        } else {
            for (call.type_arguments) |type_node| {
                try self.graph.semantic.templates.ir.generic_arguments.append(self.allocator, .{
                    .name = try self.writer.addString(""), .value = .{ .type = try self.lowerType(type_node) },
                });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len - start) };
    }

    fn lowerType(self: *Context, node: syn.NodeIndex) anyerror!ir.TemplateTypeId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedTemplateType;
        return switch (syntax_type) {
            .name => |name| blk: {
                const text = self.tree.tokenTextFromSource(self.source, name.name_token);
                if (name.qualifier_token == null) {
                    if (self.parameter(text)) |param| if (param.kind == .type)
                        break :blk try self.addType(.{ .parameter = param.id });
                    if (builtinFromName(text)) |builtin|
                        break :blk try self.addType(.{ .concrete = try self.moduleBuiltin(builtin) });
                    for (self.graph.declarationsNamed(text)) |decl| switch (self.graph.declarations.items[@intFromEnum(decl)].kind) {
                        .type, .abstract_type => break :blk try self.addType(.{ .concrete = self.graph.declarations.items[@intFromEnum(decl)].type_id.? }),
                        else => {},
                    };
                }
                const external = try self.writer.addExternalRef(.{
                    .kind = .type,
                    .module_path = if (name.qualifier_token) |token| try self.writer.addString(self.tree.tokenTextFromSource(self.source, token)) else null,
                    .name = try self.writer.addString(text),
                    .source = .{ .file_index = self.file_index, .offset = self.tree.location(node).offset },
                });
                break :blk try self.addType(.{ .external = external });
            },
            .pointer => |ptr| try self.addType(.{ .resolved = .{ .pointer = .{ .child = try self.lowerType(ptr.child), .mutability = ptr.mutability } } }),
            .nullable => |child| try self.addType(.{ .resolved = .{ .nullable = try self.lowerType(child) } }),
            .inferred_errable => |child| try self.addType(.{ .resolved = .{ .inferred_errable = try self.lowerType(child) } }),
            .array => |array| try self.addType(.{ .array = .{
                .length = try self.lowerIntFromToken(array.length_token), .element = try self.lowerType(array.element),
            } }),
            .generic => |generic| self.lowerGeneric(generic),
            .struct_literal, .choice_literal => error.UnsupportedTemplateCallArgumentShape,
        };
    }

    fn lowerGeneric(self: *Context, generic: syn.GenericType) !ir.TemplateTypeId {
        const base = self.tree.syntaxType(generic.base) orelse return error.InvalidGenericBase;
        if (base != .name) return error.InvalidGenericBase;
        const text = self.tree.tokenTextFromSource(self.source, base.name.name_token);
        const target: ir.DeclarationRef = blk: {
            if (base.name.qualifier_token == null) for (self.graph.declarationsNamed(text)) |decl| switch (self.graph.declarations.items[@intFromEnum(decl)].kind) {
                .type => break :blk .{ .module = decl }, else => {},
            };
            const external = try self.writer.addExternalRef(.{
                .kind = .type,
                .module_path = if (base.name.qualifier_token) |token| try self.writer.addString(self.tree.tokenTextFromSource(self.source, token)) else null,
                .name = try self.writer.addString(text),
                .source = .{ .file_index = self.file_index, .offset = self.tree.location(generic.base).offset },
            });
            break :blk .{ .external = external };
        };
        const decl_id: ir.TemplateDeclId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.templates.ir.declarations.items.len)));
        try self.graph.semantic.templates.ir.declarations.append(self.allocator, .{ .target = target });
        const args = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidGenericArguments;
        const start: u32 = @intCast(self.graph.semantic.templates.ir.generic_arguments.items.len);
        for (args.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericArgument;
            const value: ir.GenericArgument.Value = if (field.type_node) |type_node| .{ .type = try self.lowerType(type_node) }
                else if (field.default_value) |value_node| .{ .comptime_int = try self.lowerInt(value_node) }
                else return error.InvalidGenericArgument;
            try self.graph.semantic.templates.ir.generic_arguments.append(self.allocator, .{
                .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token)), .value = value,
            });
        }
        return self.addType(.{ .resolved = .{ .generic = .{ .base = decl_id, .arguments = .{ .start = start, .len = @intCast(args.fields.len) } } } });
    }

    const Parameter = struct { id: ir.TemplateParameterId, kind: templates.GenericParameterKind };
    fn parameter(self: *Context, name: []const u8) ?Parameter {
        for (0..self.parameter_range.len) |offset| {
            const raw = self.parameter_range.start + @as(u32, @intCast(offset));
            const param = self.graph.semantic.templates.generic_parameters.items[raw];
            if (std.mem.eql(u8, self.graph.text(param.name), name)) return .{ .id = @enumFromInt(raw), .kind = param.kind };
        }
        return null;
    }

    fn lowerInt(self: *Context, node: syn.NodeIndex) anyerror!ir.TemplateIntExprId {
        if (self.tree.literal(node)) |literal| {
            var value = std.fmt.parseInt(i64, self.tree.tokenTextFromSource(self.source, literal.token), 0) catch return error.InvalidComptimeInt;
            if (literal.negative) value = -value;
            return self.addInt(.{ .literal = value });
        }
        if (self.tree.tag(node) == .identifier) {
            const text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
            if (self.parameter(text)) |param| if (param.kind == .comptime_int) return self.addInt(.{ .parameter = param.id });
        }
        const op = self.tree.binaryOperation(node) orelse return error.InvalidComptimeInt;
        const operator: ir.IntBinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .add, .binary_subtract => .subtract, .binary_multiply => .multiply,
            .binary_divide => .divide, .binary_modulo => .modulo, else => return error.InvalidComptimeInt,
        };
        return self.addInt(.{ .binary = .{ .operator = operator, .left = try self.lowerInt(op.lhs), .right = try self.lowerInt(op.rhs) } });
    }

    fn lowerIntFromToken(self: *Context, token: syn.TokenIndex) !ir.TemplateIntExprId {
        const text = self.tree.tokenTextFromSource(self.source, token);
        if (self.parameter(text)) |param| if (param.kind == .comptime_int) return self.addInt(.{ .parameter = param.id });
        return self.addInt(.{ .literal = try std.fmt.parseInt(i64, text, 0) });
    }

    fn moduleBuiltin(self: *Context, builtin: primitives.BuiltinType) !entities.ModuleTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == builtin) return @enumFromInt(@as(u32, @intCast(raw))), else => {},
        };
        return self.writer.addResolvedType(.{ .builtin = builtin });
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
};

fn nextDeclarationOffset(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleDeclId) u32 {
    const declaration = graph.declarations.items[@intFromEnum(id)];
    var end: u32 = std.math.maxInt(u32);
    for (graph.declarations.items) |candidate| {
        if (candidate.module_file_index != declaration.module_file_index) continue;
        if (candidate.source_offset > declaration.source_offset and candidate.source_offset < end) end = candidate.source_offset;
    }
    return end;
}

fn builtinFromName(name: []const u8) ?primitives.BuiltinType {
    inline for (@typeInfo(primitives.BuiltinType).@"enum".fields) |field| if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    return null;
}

test "template call metadata is syntax free after normalization" {
    try std.testing.expect(@sizeOf(ir.PendingExpression) <= 48);
}

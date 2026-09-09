const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const graph_mod = @import("module_semantic_graph.zig");
const entities = @import("module_semantic_entities.zig");
const views = @import("module_semantic_views.zig");
const writer_mod = @import("module_semantic_writer.zig");

pub const Context = struct {
    graph: *graph_mod.ModuleSemanticGraph,
    writer: *writer_mod.Writer,
    file_index: u32,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,

    pub fn lower(self: *Context, node: syn.NodeIndex) anyerror!entities.ModuleTypeId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedTypeSyntax;
        return switch (syntax_type) {
            .name => |name| self.lowerName(node, name.name_token, name.qualifier_token, null),
            .pointer => |pointer| blk: {
                const child = try self.lower(pointer.child);
                break :blk try self.writer.addResolvedType(.{ .pointer = .{
                    .child = child,
                    .mutability = pointer.mutability,
                } });
            },
            .array => |array| blk: {
                const length_text = self.tree.tokenTextFromSource(self.source, array.length_token);
                const length = std.fmt.parseInt(u64, length_text, 0) catch return error.InvalidArrayLength;
                const element = try self.lower(array.element);
                break :blk try self.writer.addResolvedType(.{ .array = .{ .length = length, .element = element } });
            },
            .nullable => |child_node| blk: {
                const child = try self.lower(child_node);
                break :blk try self.writer.addResolvedType(.{ .nullable = child });
            },
            .inferred_errable => |child_node| blk: {
                const child = try self.lower(child_node);
                break :blk try self.writer.addResolvedType(.{ .inferred_errable = child });
            },
            .struct_literal => |literal| self.lowerStructural(node, literal),
            .choice_literal => |literal| self.lowerChoice(node, literal),
            .generic => |generic| self.lowerGeneric(node, generic),
        };
    }

    fn lowerName(
        self: *Context,
        node: syn.NodeIndex,
        name_token: syn.TokenIndex,
        qualifier_token: ?syn.TokenIndex,
        generic_arguments: ?entities.GenericArgRange,
    ) !entities.ModuleTypeId {
        const name_text = self.tree.tokenTextFromSource(self.source, name_token);
        if (qualifier_token == null and generic_arguments == null) {
            if (builtinFromName(name_text)) |builtin| return self.internBuiltin(builtin);
            if (self.localTypeDeclaration(name_text)) |declaration| {
                return self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse error.LocalTypeNotPredeclared;
            }
        }

        if (qualifier_token == null) {
            if (self.localTypeDeclaration(name_text)) |declaration| {
                if (generic_arguments) |arguments| {
                    return self.writer.addResolvedType(.{ .generic = .{ .base = declaration, .arguments = arguments } });
                }
                return self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse error.LocalTypeNotPredeclared;
            }
        }

        const name = try self.writer.addString(name_text);
        const module_path = if (qualifier_token) |token_index|
            try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))
        else
            null;
        const external = try self.writer.addExternalRef(.{
            .kind = .type,
            .module_path = module_path,
            .name = name,
            .generic_arguments = generic_arguments,
            .source = self.sourceRef(node),
        });
        return self.writer.addExternalType(external);
    }

    fn lowerStructural(self: *Context, owner: syn.NodeIndex, literal: syn.StructTypeLiteral) anyerror!entities.ModuleTypeId {
        var first: ?entities.ModuleFieldId = null;
        var count: u32 = 0;
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
            const ty_node = field.type_node orelse return error.StructFieldTypeRequired;
            const ty = try self.lower(ty_node);
            const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
            const id = try self.writer.addField(.{
                .name = name,
                .ty = ty,
                .source = self.sourceRef(field_node),
                // Defaults are lowered by the body/default pass; type lowering
                // deliberately does not retain the syntax node.
                .default_value = null,
            });
            if (first == null) first = id;
            count += 1;
        }
        _ = owner;
        return self.writer.addResolvedType(.{ .structural = .{
            .fields = .{ .start = if (first) |id| @intFromEnum(id) else @intCast(views.fieldCount(self.graph)), .len = count },
            .layout = .regular,
        } });
    }

    fn lowerChoice(self: *Context, owner: syn.NodeIndex, literal: syn.ChoiceTypeLiteral) anyerror!entities.ModuleTypeId {
        var first: ?entities.ModuleVariantId = null;
        var count: u32 = 0;
        for (literal.variants) |variant_node| {
            const variant = self.tree.choiceTypeVariant(variant_node) orelse return error.InvalidChoiceVariant;
            const name_text = self.tree.tokenTextFromSource(self.source, variant.name_token);
            const payload_type = if (variant.payload_type) |payload| try self.lower(payload) else null;
            const option_decl = if (variant.module_qualifier == null) self.localChoiceOption(name_text) else null;
            const name = try self.writer.addString(name_text);
            const id = try self.writer.addVariant(.{
                .name = name,
                .payload_type = payload_type,
                .option_decl = option_decl,
                .source = self.sourceRef(variant_node),
                .value = @intCast(count),
            });
            if (first == null) first = id;
            count += 1;
        }
        _ = owner;
        return self.writer.addResolvedType(.{ .structural_choice = .{
            .variants = .{ .start = if (first) |id| @intFromEnum(id) else @intCast(views.variantCount(self.graph)), .len = count },
            .layout = .regular,
        } });
    }

    fn lowerGeneric(self: *Context, owner: syn.NodeIndex, generic: syn.GenericType) anyerror!entities.ModuleTypeId {
        const arguments_literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidGenericArguments;
        const base = self.tree.syntaxType(generic.base) orelse return error.InvalidGenericBase;
        if (base == .name and base.name.qualifier_token == null and
            std.mem.eql(u8, self.tree.tokenTextFromSource(self.source, base.name.name_token), "Virtual"))
        {
            if (arguments_literal.fields.len != 1) return error.InvalidVirtualArguments;
            const field = self.tree.structTypeField(arguments_literal.fields[0]) orelse return error.InvalidVirtualArguments;
            if (!std.mem.eql(u8, self.tree.tokenTextFromSource(self.source, field.name_token), "abstract")) return error.InvalidVirtualArguments;
            const abstract_type = try self.lower(field.type_node orelse return error.InvalidVirtualArguments);
            return self.writer.addResolvedType(.{ .virtual = abstract_type });
        }
        var first: ?entities.ModuleGenericArgId = null;
        var count: u32 = 0;
        for (arguments_literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericArgument;
            const name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token));
            const value: entities.GenericArgument.Value = if (field.type_node) |type_node|
                .{ .type = try self.lower(type_node) }
            else if (field.default_value) |value_node|
                .{ .comptime_int = try self.evalComptimeInt(value_node) }
            else
                return error.InvalidGenericArgument;
            const id = try self.writer.addGenericArgument(.{ .name = name, .value = value });
            if (first == null) first = id;
            count += 1;
        }
        const range = entities.GenericArgRange{
            .start = if (first) |id| @intFromEnum(id) else @intCast(views.genericArgumentCount(self.graph)),
            .len = count,
        };

        return switch (base) {
            .name => |name| self.lowerName(owner, name.name_token, name.qualifier_token, range),
            else => error.InvalidGenericBase,
        };
    }

    fn evalComptimeInt(self: *Context, node: syn.NodeIndex) anyerror!i64 {
        if (self.tree.literal(node)) |literal| {
            const text = self.tree.tokenTextFromSource(self.source, literal.token);
            const parsed = std.fmt.parseInt(i64, text, 0) catch return error.InvalidComptimeInteger;
            return if (literal.negative) -parsed else parsed;
        }
        const operation = self.tree.binaryOperation(node) orelse return error.InvalidComptimeInteger;
        const lhs = try self.evalComptimeInt(operation.lhs);
        const rhs = try self.evalComptimeInt(operation.rhs);
        return switch (self.tree.tag(node)) {
            .binary_add => lhs + rhs,
            .binary_subtract => lhs - rhs,
            .binary_multiply => lhs * rhs,
            .binary_divide => if (rhs == 0) return error.InvalidComptimeInteger else @divTrunc(lhs, rhs),
            .binary_modulo => if (rhs == 0) return error.InvalidComptimeInteger else @mod(lhs, rhs),
            else => error.InvalidComptimeInteger,
        };
    }

    fn internBuiltin(self: *Context, builtin: graph_mod.BuiltinType) !entities.ModuleTypeId {
        for (0..views.typeCount(self.graph)) |index| {
            const id: entities.ModuleTypeId = @enumFromInt(@as(u32, @intCast(index)));
            const candidate = try views.typeView(self.graph, id);
            switch (candidate) {
                .resolved => |resolved| switch (resolved) {
                    .builtin => |value| if (value == builtin) return id,
                    else => {},
                },
                .external => {},
            }
        }
        return self.writer.addResolvedType(.{ .builtin = builtin });
    }

    fn localTypeDeclaration(self: *const Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |declaration| switch (self.graph.declarations.items[@intFromEnum(declaration)].kind) {
            .type, .abstract_type => return declaration,
            else => {},
        };
        return null;
    }

    fn localChoiceOption(self: *const Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |declaration|
            if (self.graph.declarations.items[@intFromEnum(declaration)].kind == .choice_option) return declaration;
        return null;
    }

    fn sourceRef(self: *const Context, node: syn.NodeIndex) @import("semantic_primitives.zig").SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }
};

fn builtinFromName(name: []const u8) ?graph_mod.BuiltinType {
    inline for (@typeInfo(graph_mod.BuiltinType).@"enum".fields) |field|
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    return null;
}

test "module type lowerer preserves imported generic arguments without syntax" {
    const allocator = std.testing.allocator;
    // The parser-facing behavior is covered by module integration tests. This
    // focused test locks the destination representation used by lowerGeneric.
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);
    var writer = writer_mod.Writer.init(allocator, &graph);
    const arg_name = try writer.addString("t");
    const int_ty = try writer.addResolvedType(.{ .builtin = .Int32 });
    const arg = try writer.addGenericArgument(.{ .name = arg_name, .value = .{ .type = int_ty } });
    const ref_name = try writer.addString("Box");
    const module_name = try writer.addString("other");
    const external = try writer.addExternalRef(.{
        .kind = .type,
        .module_path = module_name,
        .name = ref_name,
        .generic_arguments = .{ .start = @intFromEnum(arg), .len = 1 },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    const ty = try writer.addExternalType(external);

    const stored = (try views.typeView(&graph, ty)).external;
    const ext = graph.semantic.external_refs.items[@intFromEnum(stored)];
    try std.testing.expectEqual(@as(u32, 0), ext.generic_arguments.?.start);
    try std.testing.expectEqualStrings("Box", graph.text(ext.name));
}

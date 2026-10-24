const type_arguments = @import("type_arguments.zig");
const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const views = @import("views.zig");
const writer_mod = @import("writer.zig");
const primitives = @import("../primitives/schema.zig");

pub const LexicalModuleAlias = struct {
    name: primitives.StringRange,
    path: primitives.StringRange,
};

// Virtual is a language-level runtime type constructor. Its contract
// argument describes a vtable contract, unlike an ordinary generic argument
// whose type can be specialized from a concrete call input.
pub fn isRuntimeVirtualType(tree: *const syn.FileSyntaxTree, source: []const u8, generic: syn.GenericType) bool {
    const base = tree.syntaxType(generic.base) orelse return false;
    return base == .name and base.name.qualifier_token == null and
        std.mem.eql(u8, tree.tokenTextFromSource(source, base.name.name_token), "Virtual");
}

pub const Context = struct {
    graph: *graph_mod.ModuleSemanticGraph,
    writer: *writer_mod.Writer,
    file_index: u32,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    module_aliases: []const LexicalModuleAlias = &.{},
    generated_source: ?primitives.SourceRef = null,

    pub fn lower(self: *Context, node: syn.NodeIndex) anyerror!entities.ModuleTypeId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedTypeSyntax;
        return switch (syntax_type) {
            .name => |name| self.lowerName(node, name.name_token, name.qualifier_token, null),
            .pointer => |pointer| blk: {
                const child = try self.lower(pointer.child);
                break :blk try self.writer.addResolvedType(.{ .pointer = .{
                    .child = child,
                    .mutability = graph_mod.pointerMutabilityFromSyntax(pointer.mutability),
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
            .projection => |projection| blk: {
                const base = try self.lower(projection.base);
                const external = try self.writer.addExternalRef(.{
                    .kind = .type,
                    .module_path = null,
                    .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, projection.member_token)),
                    .projection_base = base,
                    .source = self.sourceRef(node),
                });
                break :blk try self.writer.addExternalType(external);
            },
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
            if (primitives.builtinTypeNamedForTarget(name_text, self.graph.target.stdTarget())) |builtin| return self.internBuiltin(builtin);
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
            try self.modulePathForQualifier(token_index)
        else
            null;
        const external = try self.writer.addExternalRef(.{
            .kind = .type,
            .module_path = module_path,
            .name = name,
            .generic_arguments = generic_arguments,
            .source = if (qualifier_token) |token_index| .{
                .file_index = self.file_index,
                .offset = self.tree.tokenLocation(token_index).offset,
            } else self.sourceRef(node),
        });
        return self.writer.addExternalType(external);
    }

    fn lowerStructural(self: *Context, owner: syn.NodeIndex, literal: syn.StructTypeLiteral) anyerror!entities.ModuleTypeId {
        // Preserve executable defaults as ordinary deferred type recipes.
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
            if (field.default_value != null) return self.lowerComputedType(owner);
        }
        return self.lowerRecordFields(owner, literal);
    }

    // Entry signatures initialize their output defaults in the function body.
    // Their field types still retain nested record defaults normally.
    pub fn lowerRecordFields(self: *Context, owner: syn.NodeIndex, literal: syn.StructTypeLiteral) anyerror!entities.ModuleTypeId {
        _ = owner;
        // Child types may append their own fields. Publish siblings together
        // only after lowering those children, preserving one contiguous range.
        var fields: std.ArrayList(entities.Field) = .empty;
        defer fields.deinit(self.writer.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
            const ty_node = field.type_node orelse return error.StructFieldTypeRequired;
            try fields.append(self.writer.allocator, .{
                .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token)),
                .ty = try self.lower(ty_node),
                .source = self.sourceRef(field_node),
                .default_value = null,
            });
        }
        const start: u32 = @intCast(views.fieldCount(self.graph));
        for (fields.items) |field| _ = try self.writer.addField(field);
        return self.writer.addResolvedType(.{ .structural = .{
            .fields = .{ .start = start, .len = @intCast(fields.items.len) },
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
                .qualifier = if (variant.module_qualifier) |qualifier| try self.modulePathForQualifier(qualifier) else null,
                .payload_type = payload_type,
                .option_decl = option_decl,
                .source = .{ .file_index = self.file_index, .offset = self.tree.tokenLocation(variant.name_token).offset },
                .value = variant.value orelse @intCast(count),
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

    fn lowerComputedType(self: *Context, owner: syn.NodeIndex) anyerror!entities.ModuleTypeId {
        const external_start = self.graph.semantic.external_refs.items.len;
        const computed = try @import("parameterized/lowerer.zig").lowerConcreteTypeExpression(self.graph, self.writer, self.file_index, self.tree, self.source, owner);
        // Preserve lexical import aliases in the anonymous expression.
        for (self.graph.semantic.external_refs.items[external_start..]) |*external| {
            const path = external.module_path orelse continue;
            var alias_index = self.module_aliases.len;
            while (alias_index != 0) {
                alias_index -= 1;
                const alias = self.module_aliases[alias_index];
                if (std.mem.eql(u8, self.graph.text(path), self.graph.text(alias.name))) {
                    external.module_path = alias.path;
                    break;
                }
            }
        }
        const reference = try self.writer.addExternalRef(.{
            .kind = .type,
            .module_path = null,
            .name = try self.writer.addString("compile-time type"),
            .computed_type = computed,
            .source = self.sourceRef(owner),
        });
        return self.writer.addExternalType(reference);
    }

    fn lowerGeneric(self: *Context, owner: syn.NodeIndex, generic: syn.GenericType) anyerror!entities.ModuleTypeId {
        if (@import("type_arguments.zig").requiresResolution(self.tree, generic.arguments)) {
            return self.lowerComputedType(owner);
        }
        const arguments_literal = self.tree.structTypeLiteral(generic.arguments) orelse return error.InvalidGenericArguments;
        const base = self.tree.syntaxType(generic.base) orelse return error.InvalidGenericBase;
        const base_name = if (base == .name and base.name.qualifier_token == null) self.tree.tokenTextFromSource(self.source, base.name.name_token) else "";
        if (base == .name and base.name.qualifier_token == null and
            std.mem.eql(u8, self.tree.tokenTextFromSource(self.source, base.name.name_token), "Array"))
        {
            var length: ?u64 = null;
            var element: ?entities.ModuleTypeId = null;
            for (arguments_literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidArrayArguments;
                const name = type_arguments.name(self.tree, self.source, field, base_name);
                if (std.mem.eql(u8, name, "n")) {
                    if (length != null or field.default_value == null) return error.InvalidArrayArguments;
                    length = std.math.cast(u64, try self.evalComptimeInt(field.default_value.?)) orelse return error.InvalidArrayLength;
                } else if (std.mem.eql(u8, name, "t")) {
                    if (element != null or field.type_node == null) return error.InvalidArrayArguments;
                    element = try self.lower(field.type_node.?);
                } else return error.InvalidArrayArguments;
            }
            if (length == null or element == null) return error.InvalidArrayArguments;
            return self.writer.addResolvedType(.{ .array = .{ .length = length.?, .element = element.? } });
        }
        if (base == .name and base.name.qualifier_token == null and
            std.mem.eql(u8, self.tree.tokenTextFromSource(self.source, base.name.name_token), "Errable"))
        {
            // Only a lone value type requests inferred reasons. Other argument
            // lists go through ordinary binding, which diagnoses duplicates,
            // unknown names and kind mismatches consistently for every family.
            if (arguments_literal.fields.len == 1) {
                const field = self.tree.structTypeField(arguments_literal.fields[0]) orelse return error.InvalidGenericArgument;
                if (std.mem.eql(u8, type_arguments.name(self.tree, self.source, field, base_name), "t")) {
                    const child = try self.lower(field.type_node orelse return error.InvalidGenericArgument);
                    return self.writer.addResolvedType(.{ .inferred_errable = child });
                }
            }
        }
        if (isRuntimeVirtualType(self.tree, self.source, generic)) {
            if (arguments_literal.fields.len != 1) return error.InvalidVirtualArguments;
            const field = self.tree.structTypeField(arguments_literal.fields[0]) orelse return error.InvalidVirtualArguments;
            if (!type_arguments.isVirtualContractParameter(type_arguments.name(self.tree, self.source, field, base_name))) return error.InvalidVirtualArguments;
            const contract_type = try self.lower(field.type_node orelse return error.InvalidVirtualArguments);
            return self.writer.addResolvedType(.{ .virtual = contract_type });
        }
        // Nested generic types may append to the same argument pool. Buffer
        // this level until their complete ranges have been published.
        var arguments = std.array_list.Managed(entities.GenericArgument).init(self.writer.allocator);
        defer arguments.deinit();
        for (arguments_literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericArgument;
            const name = try self.writer.addString(type_arguments.name(self.tree, self.source, field, base_name));
            const value: entities.GenericArgument.Value = if (field.type_node) |type_node|
                .{ .type = try self.lower(type_node) }
            else if (field.default_value) |value_node|
                .{ .comptime_int = try self.evalComptimeInt(value_node) }
            else
                return error.InvalidGenericArgument;
            try arguments.append(.{ .name = name, .value = value });
        }
        const start: u32 = @intCast(views.genericArgumentCount(self.graph));
        for (arguments.items) |argument| _ = try self.writer.addGenericArgument(argument);
        const range = entities.GenericArgRange{ .start = start, .len = @intCast(arguments.items.len) };

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
            .type, .contract_type => return declaration,
            else => {},
        };
        return null;
    }

    fn localChoiceOption(self: *const Context, name: []const u8) ?entities.ModuleDeclId {
        for (self.graph.declarationsNamed(name)) |declaration|
            if (self.graph.declarations.items[@intFromEnum(declaration)].kind == .choice_option) return declaration;
        return null;
    }

    fn modulePathForQualifier(self: *Context, token: syn.TokenIndex) !primitives.StringRange {
        const spelling = self.tree.tokenTextFromSource(self.source, token);
        var index = self.module_aliases.len;
        while (index != 0) {
            index -= 1;
            const alias = self.module_aliases[index];
            if (std.mem.eql(u8, self.graph.text(alias.name), spelling)) return alias.path;
        }
        return self.writer.addString(spelling);
    }

    fn sourceRef(self: *const Context, node: syn.NodeIndex) @import("../primitives/schema.zig").SourceRef {
        return self.generated_source orelse .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }
};

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

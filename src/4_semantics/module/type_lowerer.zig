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
    const base = tree.typeReference(generic.base) orelse return false;
    return base == .name and base.name.qualifier_token == null and
        std.mem.eql(u8, tree.tokenTextFromSource(source, base.name.name_token), "Virtual");
}

/// Payload/value declarations define closed variants. Bare option references
/// retain the compositional set representation used by error reasons.
pub fn definesChoiceVariants(tree: *const syn.FileSyntaxTree, literal: syn.ChoiceTypeLiteral) bool {
    for (literal.variants) |node| {
        const variant = tree.choiceTypeVariant(node) orelse continue;
        if (variant.payload_type != null or variant.value != null) return true;
    }
    return false;
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
        const syntax_type = self.tree.typeReference(node) orelse return error.ExpectedTypeSyntax;
        return switch (syntax_type) {
            .name => |name| self.lowerName(node, name.name_token, name.qualifier_token, null),
            .pointer => |pointer| blk: {
                const child = try self.lower(pointer.child);
                break :blk try self.internDerived(.{ .pointer = .{
                    .child = child,
                    .mutability = graph_mod.pointerMutabilityFromSyntax(pointer.mutability),
                } });
            },
            .array => |array| blk: {
                if (self.tree.tokens.items(.content)[@intFromEnum(array.length_token)] == .identifier)
                    break :blk try self.lowerComputedType(node);
                const length_text = self.tree.tokenTextFromSource(self.source, array.length_token);
                const length = std.fmt.parseInt(u64, length_text, 0) catch return error.InvalidArrayLength;
                const element = try self.lower(array.element);
                break :blk try self.internDerived(.{ .array = .{ .length = length, .element = element } });
            },
            .nullable => |child_node| blk: {
                const child = try self.lower(child_node);
                break :blk try self.internDerived(.{ .nullable = child });
            },
            .inferred_errable => |child_node| blk: {
                const child = try self.lower(child_node);
                break :blk try self.internDerived(.{ .inferred_errable = child });
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
                    return self.writer.addResolvedType(.{ .generic = .{ .base = self.graph.declaration(declaration).family_definition orelse return error.ExpectedParameterizedDefinition, .arguments = arguments } });
                }
                return self.graph.declarations.items[@intFromEnum(declaration)].type_id orelse error.LocalTypeNotPredeclared;
            }
        }

        const name = try self.writer.addString(name_text);
        const module_path = if (qualifier_token) |token_index|
            try self.modulePathForQualifier(token_index, name_token)
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
        const definition = try self.writer.typeDefinitionAt(.{ .file_index = self.file_index, .offset = self.tree.location(owner).offset });
        if (self.graph.semantic.type_definitions.items[@intFromEnum(definition)].struct_fields == null) {
            const fields = try self.lowerFields(literal);
            self.graph.semantic.type_definitions.items[@intFromEnum(definition)].struct_fields = fields;
        }
        return self.internDerived(.{ .nominal = definition });
    }

    pub fn lowerFields(self: *Context, literal: syn.StructTypeLiteral) anyerror!entities.FieldRange {
        // Publish siblings only after children: nested types append to these
        // same pools, so reserving a range before recursion is incorrect.
        var fields: std.ArrayList(entities.Field) = .empty;
        defer fields.deinit(self.writer.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
            const ty_node = field.type_node orelse return error.StructFieldTypeRequired;
            try fields.append(self.writer.allocator, .{
                .name = try self.writer.addString(if (field.inferred_result) "result" else self.tree.tokenTextFromSource(self.source, field.name_token)),
                .ty = try self.lower(ty_node),
                .source = self.sourceRef(field_node),
            });
        }
        const start: u32 = @intCast(views.fieldCount(self.graph));
        for (fields.items) |field| _ = try self.writer.addField(field);
        return .{ .start = start, .len = @intCast(fields.items.len) };
    }

    fn lowerChoice(self: *Context, owner: syn.NodeIndex, literal: syn.ChoiceTypeLiteral) anyerror!entities.ModuleTypeId {
        if (definesChoiceVariants(self.tree, literal)) {
            const definition = try self.writer.typeDefinitionAt(.{ .file_index = self.file_index, .offset = self.tree.location(owner).offset });
            if (self.graph.semantic.type_definitions.items[@intFromEnum(definition)].choice_variants == null) {
                const variants = try self.lowerVariants(literal);
                self.graph.semantic.type_definitions.items[@intFromEnum(definition)].choice_variants = variants;
            }
            return self.internDerived(.{ .nominal = definition });
        }
        return self.writer.addResolvedType(.{ .structural_choice = .{
            .variants = try self.lowerVariants(literal),
            .layout = .regular,
        } });
    }

    pub fn lowerVariants(self: *Context, literal: syn.ChoiceTypeLiteral) anyerror!entities.VariantRange {
        var variants: std.ArrayList(entities.ChoiceVariant) = .empty;
        defer variants.deinit(self.writer.allocator);
        for (literal.variants, 0..) |variant_node, index| {
            const variant = self.tree.choiceTypeVariant(variant_node) orelse return error.InvalidChoiceVariant;
            const name_text = self.tree.tokenTextFromSource(self.source, variant.name_token);
            const payload_type = if (variant.payload_type) |payload| try self.lower(payload) else null;
            try variants.append(self.writer.allocator, .{
                .name = try self.writer.addString(name_text),
                .qualifier = if (variant.module_qualifier) |qualifier| try self.modulePathForQualifier(qualifier, variant.name_token) else null,
                .payload_type = payload_type,
                .option_decl = if (variant.module_qualifier == null) self.localChoiceOption(name_text) else null,
                .source = .{ .file_index = self.file_index, .offset = self.tree.tokenLocation(variant.name_token).offset },
                .value = variant.value orelse @intCast(index),
            });
        }
        const start: u32 = @intCast(views.variantCount(self.graph));
        for (variants.items) |variant| _ = try self.writer.addVariant(variant);
        return .{ .start = start, .len = @intCast(variants.items.len) };
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
        const base = self.tree.typeReference(generic.base) orelse return error.InvalidGenericBase;
        const base_name = if (base == .name and base.name.qualifier_token == null) self.tree.tokenTextFromSource(self.source, base.name.name_token) else "";
        if (base == .projection or @import("type_arguments.zig").requiresResolution(self.tree, generic.arguments) or std.mem.eql(u8, base_name, "choice_union")) {
            return self.lowerComputedType(owner);
        }
        const arguments_literal = self.tree.specializationArguments(generic.arguments) orelse return error.InvalidGenericArguments;
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
            return self.internDerived(.{ .array = .{ .length = length.?, .element = element.? } });
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
                    return self.internDerived(.{ .inferred_errable = child });
                }
            }
        }
        if (isRuntimeVirtualType(self.tree, self.source, generic)) {
            if (arguments_literal.fields.len != 1) return error.InvalidVirtualArguments;
            const field = self.tree.structTypeField(arguments_literal.fields[0]) orelse return error.InvalidVirtualArguments;
            if (!type_arguments.isVirtualContractParameter(type_arguments.name(self.tree, self.source, field, base_name))) return error.InvalidVirtualArguments;
            const contract_type = try self.lower(field.type_node orelse return error.InvalidVirtualArguments);
            return self.internDerived(.{ .virtual = contract_type });
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

    fn internDerived(self: *Context, ty: entities.ResolvedType) !entities.ModuleTypeId {
        for (self.graph.semantic.types.items, 0..) |candidate, raw| {
            if (candidate != .resolved or std.meta.activeTag(candidate.resolved) != std.meta.activeTag(ty)) continue;
            const same = switch (ty) {
                .nominal => |value| candidate.resolved.nominal == value,
                .pointer => |value| candidate.resolved.pointer.child == value.child and candidate.resolved.pointer.mutability == value.mutability,
                .array => |value| candidate.resolved.array.element == value.element and candidate.resolved.array.length == value.length,
                .nullable => |value| candidate.resolved.nullable == value,
                .inferred_errable => |value| candidate.resolved.inferred_errable == value,
                .virtual => |value| candidate.resolved.virtual == value,
                else => unreachable,
            };
            if (same) return @enumFromInt(@as(u32, @intCast(raw)));
        }
        return self.writer.addResolvedType(ty);
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

    fn modulePathForQualifier(self: *Context, token: syn.TokenIndex, member: syn.TokenIndex) !primitives.StringRange {
        const spelling = self.tree.tokenTextFromSource(self.source, token);
        var root: ?[]const u8 = null;
        var index = self.module_aliases.len;
        while (index != 0) {
            index -= 1;
            const alias = self.module_aliases[index];
            if (std.mem.eql(u8, self.graph.text(alias.name), spelling)) {
                root = self.graph.text(alias.path);
                break;
            }
        }
        const path = if (root) |path|
            try @import("qualified_path.zig").build(self.writer.allocator, self.tree, self.source, token, member, path)
        else
            try @import("qualified_path.zig").symbolic(self.writer.allocator, self.tree, self.source, token, member);
        defer self.writer.allocator.free(path);
        return self.writer.addString(path);
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

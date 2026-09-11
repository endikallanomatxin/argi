const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const graph_mod = @import("graph.zig");
const body_lowerer = @import("body_lowerer.zig");
const entities = @import("entities.zig");
const writer_mod = @import("writer.zig");
const type_lowerer = @import("type_lowerer.zig");
const views = @import("views.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    global_bindings: u32 = 0,
    field_defaults: u32 = 0,
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
    };
    var stats: Stats = .{};
    try ctx.lowerDeferredStructDefinitions();
    try ctx.lowerDeferredChoiceDefinitions();
    try ctx.lowerDeferredFunctionInterfaces();
    try ctx.predeclareGlobals(&stats);
    try ctx.lowerGlobalInitializers();
    try ctx.lowerFieldDefaults(&stats);
    return stats;
}

const Context = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    writer: writer_mod.Writer,
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},

    fn selectFile(self: *Context, index: u32) void {
        self.file_index = index;
        self.tree = self.files[@intCast(index)].tree;
        self.source = self.files[@intCast(index)].source;
    }

    /// The compact graph's early interface pass can only materialize fields
    /// whose types are entirely module-local. Finish declarations containing
    /// imported or generic types here, where unresolved names have a durable
    /// ExternalRef representation. Immediate fields are buffered because
    /// lowering a field type may itself append fields for a structural type.
    fn lowerDeferredStructDefinitions(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or declaration.struct_fields != null) continue;
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            const type_declaration = switch (self.tree.tag(declaration_node)) {
                .type_declaration => self.tree.typeDeclaration(declaration_node).?,
                .c_union_declaration => blk: {
                    const value = self.tree.cUnionDeclaration(declaration_node).?;
                    break :blk syn.TypeDeclaration{
                        .name_token = value.name_token,
                        .generic_params = value.generic_params,
                        .generic_params_struct = value.generic_params_struct,
                        .value = value.value,
                    };
                },
                else => continue,
            };
            if (type_declaration.generic_params.len != 0 or type_declaration.generic_params_struct != null) continue;
            const literal = self.tree.structTypeLiteral(type_declaration.value) orelse continue;

            var fields: std.ArrayList(entities.Field) = .empty;
            defer fields.deinit(self.allocator);
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
                const type_node = field.type_node orelse return error.StructFieldTypeRequired;
                try fields.append(self.allocator, .{
                    .name = try self.writer.addString(if (field.inferred_result)
                        "result"
                    else
                        self.tree.tokenTextFromSource(self.source, field.name_token)),
                    .ty = try self.lowerType(type_node),
                    .source = self.sourceRef(field_node),
                });
            }

            const start: u32 = @intCast(views.fieldCount(self.graph));
            for (fields.items) |field| _ = try self.writer.addField(field);
            self.graph.declarations.items[raw].struct_fields = .{
                .start = start,
                .len = @intCast(fields.items.len),
            };
        }
    }

    /// Finish non-generic choice declarations whose payload types could not
    /// be represented by the compatibility builder because they cross a
    /// module boundary. Canonical ModuleSema can retain those types as
    /// ExternalRef-backed slots, so the declared choice shape stays complete.
    fn lowerDeferredChoiceDefinitions(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or declaration.choice_variants != null) continue;
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            const type_declaration = self.tree.typeDeclaration(declaration_node) orelse continue;
            if (type_declaration.generic_params.len != 0 or type_declaration.generic_params_struct != null) continue;
            const literal = self.tree.choiceTypeLiteral(type_declaration.value) orelse continue;
            const start: u32 = @intCast(views.variantCount(self.graph));
            for (literal.variants, 0..) |variant_node, index| {
                const variant = self.tree.choiceTypeVariant(variant_node) orelse return error.InvalidChoiceVariant;
                const name_text = self.tree.tokenTextFromSource(self.source, variant.name_token);
                var option_decl: ?entities.ModuleDeclId = null;
                if (variant.module_qualifier == null) {
                    for (self.graph.declarationsNamed(name_text)) |candidate| {
                        if (self.graph.declarations.items[@intFromEnum(candidate)].kind != .choice_option) continue;
                        option_decl = candidate;
                        break;
                    }
                }
                _ = try self.writer.addVariant(.{
                    .name = try self.writer.addString(name_text),
                    .payload_type = if (variant.payload_type) |payload| try self.lowerType(payload) else null,
                    .option_decl = option_decl,
                    .source = self.sourceRef(variant_node),
                    .value = @intCast(index),
                });
            }
            self.graph.declarations.items[raw].choice_variants = .{ .start = start, .len = @intCast(literal.variants.len) };
        }
    }

    fn lowerDeferredFunctionInterfaces(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if ((declaration.kind != .function and declaration.kind != .test_function) or declaration.function_id != null) continue;
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            const function = if (declaration.kind == .test_function)
                self.tree.testDeclaration(declaration_node).?.function
            else
                self.tree.functionDeclaration(declaration_node).?;
            if (function.generic_params.len != 0 or function.generic_params_struct != null) continue;

            const input = try self.lowerInterfaceFields(function.input);
            const output = try self.lowerInterfaceFields(function.output);
            const function_id: entities.ModuleFunctionId = @enumFromInt(@as(u32, @intCast(self.graph.functions.items.len)));
            try self.graph.functions.append(self.allocator, .{
                .declaration = @enumFromInt(@as(u32, @intCast(raw))),
                .input = .{ .start = input.start, .len = input.len },
                .output = .{ .start = output.start, .len = output.len },
            });
            self.graph.declarations.items[raw].function_id = function_id;
        }
    }

    fn lowerInterfaceFields(self: *Context, struct_node: syn.NodeIndex) !entities.FieldRange {
        const literal = self.tree.structTypeLiteral(struct_node) orelse return error.ExpectedStructType;
        var fields: std.ArrayList(entities.Field) = .empty;
        defer fields.deinit(self.allocator);
        for (literal.fields) |field_node| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
            const type_node = field.type_node orelse return error.StructFieldTypeRequired;
            try fields.append(self.allocator, .{
                .name = try self.writer.addString(if (field.inferred_result)
                    "result"
                else
                    self.tree.tokenTextFromSource(self.source, field.name_token)),
                .ty = try self.lowerType(type_node),
                .source = self.sourceRef(field_node),
            });
        }
        const start: u32 = @intCast(views.fieldCount(self.graph));
        for (fields.items) |field| _ = try self.writer.addField(field);
        return .{ .start = start, .len = @intCast(fields.items.len) };
    }

    fn predeclareGlobals(self: *Context, stats: *Stats) !void {
        for (self.graph.declarations.items, 0..) |decl, raw| {
            if (decl.kind != .binding) continue;
            self.selectFile(decl.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, decl) orelse continue;
            const syntax_decl = self.tree.symbolDeclaration(declaration_node) orelse continue;
            const declared_ty = if (syntax_decl.type_node) |node| try self.lowerType(node) else try self.builtin(.Any);
            const binding = try self.writer.addBinding(.{
                .name = decl.name,
                .source = self.sourceRef(declaration_node),
                .ty = declared_ty,
                .mutability = graph_mod.mutabilityFromSyntax(syntax_decl.mutability),
            });
            const decl_id: entities.ModuleDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            try self.graph.semantic.declaration_bindings.append(self.allocator, .{
                .declaration = decl_id,
                .binding = binding,
            });
            stats.global_bindings += 1;
        }
    }

    fn lowerGlobalInitializers(self: *Context) !void {
        for (self.graph.semantic.declaration_bindings.items) |relation| {
            const decl = self.graph.declarations.items[@intFromEnum(relation.declaration)];
            self.selectFile(decl.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, decl) orelse continue;
            const syntax_decl = self.tree.symbolDeclaration(declaration_node) orelse continue;
            const value_node = syntax_decl.value orelse continue;
            if (self.tree.tag(value_node) == .import_statement) continue;
            const expected = self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty;
            const value = try body_lowerer.lowerInitializerExpression(
                self.allocator,
                self.graph,
                self.files,
                self.file_index,
                value_node,
                expected,
            );
            self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].initialization = value.node;
            if (self.isAny(expected)) {
                if (value.ty) |value_ty| {
                    if (!self.isAny(value_ty))
                        self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty = value_ty;
                }
            }
            try self.writer.addRoot(value.node);
        }
    }

    fn lowerFieldDefaults(self: *Context, stats: *Stats) !void {
        for (self.graph.declarations.items) |declaration| {
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            switch (declaration.kind) {
                .type => if (declaration.struct_fields) |range| {
                    const type_declaration = self.tree.typeDeclaration(declaration_node) orelse continue;
                    try self.lowerDeferredDefaults(range.start, range.len, type_declaration.value, stats);
                },
                .function, .test_function => if (declaration.function_id) |function_id| {
                    const syntax_function = if (declaration.kind == .test_function)
                        self.tree.testDeclaration(declaration_node).?.function
                    else
                        self.tree.functionDeclaration(declaration_node).?;
                    const function = self.graph.functions.items[@intFromEnum(function_id)];
                    try self.lowerDeferredDefaults(function.input.start, function.input.len, syntax_function.input, stats);
                    try self.lowerDeferredDefaults(function.output.start, function.output.len, syntax_function.output, stats);
                },
                else => {},
            }
        }
    }

    fn lowerDeferredDefaults(self: *Context, range_start: u32, range_len: u32, struct_node: syn.NodeIndex, stats: *Stats) !void {
        const semantic_field_base = self.graph.fields.items.len + self.graph.structural_fields.items.len;
        const literal = self.tree.structTypeLiteral(struct_node) orelse return error.ExpectedStructType;
        if (literal.fields.len != range_len) return error.InterfaceFieldCountMismatch;
        for (literal.fields, 0..) |field_node, offset| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
            const default_node = field.default_value orelse continue;
            const raw_field: usize = @intCast(range_start + @as(u32, @intCast(offset)));
            const field_id: entities.ModuleFieldId = @enumFromInt(@as(u32, @intCast(raw_field)));
            const field_ty = if (raw_field < self.graph.fields.items.len)
                self.graph.fields.items[raw_field].ty
            else if (raw_field < semantic_field_base)
                self.graph.structural_fields.items[raw_field - self.graph.fields.items.len].ty
            else
                self.graph.semantic.fields.items[raw_field - semantic_field_base].ty;
            const value = try body_lowerer.lowerInitializerExpression(
                self.allocator,
                self.graph,
                self.files,
                self.file_index,
                default_node,
                field_ty,
            );
            if (raw_field < semantic_field_base) {
                try self.graph.semantic.field_semantics.append(self.allocator, .{
                    .field = field_id,
                    .default_value = value.node,
                });
            } else {
                self.graph.semantic.fields.items[raw_field - semantic_field_base].default_value = value.node;
            }
            stats.field_defaults += 1;
        }
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

    fn isAny(self: *Context, id: entities.ModuleTypeId) bool {
        const value = views.typeView(self.graph, id) catch return false;
        return switch (value) {
            .resolved => |resolved_type| switch (resolved_type) {
                .builtin => |builtin_value| builtin_value == .Any,
                else => false,
            },
            .external => false,
        };
    }

    fn sourceRef(self: *const Context, node: syn.NodeIndex) primitives.SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }

};

test "module initializer lowering is syntax-free after construction" {
    try std.testing.expect(@sizeOf(entities.DeclarationBinding) <= 8);
}

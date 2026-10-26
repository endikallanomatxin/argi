const std = @import("std");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
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
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !Stats {
    var ctx = Context{
        .allocator = allocator,
        .graph = graph,
        .files = files,
        .diagnostics = diagnostics,
        .writer = writer_mod.Writer.init(allocator, graph),
    };
    var stats: Stats = .{};
    try ctx.lowerUnderlyingTypes();
    try ctx.lowerStructDefinitions();
    try ctx.lowerChoiceDefinitions();
    try ctx.lowerFunctionInterfaces();
    try ctx.predeclareGlobals(&stats);
    try ctx.lowerGlobalInitializers();
    try ctx.lowerFieldDefaults(&stats);
    return stats;
}

/// Closed anonymous types in associated definitions are lowered after the
/// ordinary default pass. Reuse that same expression lowering for their fields.
pub fn lowerAnonymousFieldDefaults(allocator: std.mem.Allocator, graph: *graph_mod.ModuleSemanticGraph, files: []const graph_mod.FileInput, file_index: u32, syntax: syn.NodeIndex, ty: entities.ModuleTypeId, diagnostics: ?*diagnostics_mod.Diagnostics) !void {
    var context = Context{ .allocator = allocator, .graph = graph, .files = files, .diagnostics = diagnostics, .writer = writer_mod.Writer.init(allocator, graph) };
    context.selectFile(file_index);
    if (context.tree.structTypeLiteral(syntax) == null) return;
    const semantic = try views.typeView(graph, ty);
    if (semantic != .resolved or semantic.resolved != .structural) return;
    const fields = semantic.resolved.structural.fields;
    var stats: Stats = .{};
    try context.lowerDefaults(fields.start, fields.len, syntax, &stats);
}

const Context = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
    diagnostics: ?*diagnostics_mod.Diagnostics,
    writer: writer_mod.Writer,
    file_index: u32 = 0,
    tree: *const syn.FileSyntaxTree = undefined,
    source: []const u8 = &.{},

    fn selectFile(self: *Context, index: u32) void {
        self.file_index = index;
        self.tree = self.files[@intCast(index)].tree;
        self.source = self.files[@intCast(index)].source;
    }

    fn lowerUnderlyingTypes(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type) continue;
            self.selectFile(declaration.module_file_index);
            const node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            if (self.tree.tag(node) != .type_declaration) continue;
            const value = self.tree.typeDeclaration(node).?;
            if (value.generic_params.len != 0 or value.generic_params_struct != null) continue;
            switch (self.tree.tag(value.value)) {
                .struct_type_literal, .choice_type_literal => continue,
                else => {},
            }
            const underlying = try self.lowerType(value.value);
            self.graph.declarations.items[raw].underlying_type = underlying;
        }
    }

    /// One constructor handles local, imported and generic field types. Buffer
    /// siblings because lowering nested types can append to the same pools.
    fn lowerStructDefinitions(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or declaration.struct_fields != null) continue;
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            const type_declaration = self.tree.typeDeclaration(declaration_node) orelse continue;
            if (type_declaration.generic_params.len != 0 or type_declaration.generic_params_struct != null) continue;
            const literal = self.tree.structTypeLiteral(type_declaration.value) orelse continue;

            var lowerer = self.typeContext();
            const fields = try lowerer.lowerFields(literal);
            self.graph.declarations.items[raw].struct_fields = .{ .start = fields.start, .len = fields.len };
        }
    }

    fn lowerChoiceDefinitions(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or declaration.choice_variants != null) continue;
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            const type_declaration = self.tree.typeDeclaration(declaration_node) orelse continue;
            if (type_declaration.generic_params.len != 0 or type_declaration.generic_params_struct != null) continue;
            const literal = self.tree.choiceTypeLiteral(type_declaration.value) orelse continue;
            var lowerer = self.typeContext();
            const variants = try lowerer.lowerVariants(literal);
            self.graph.declarations.items[raw].choice_variants = .{ .start = variants.start, .len = variants.len };
        }
    }

    fn lowerFunctionInterfaces(self: *Context) !void {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.function_id != null) continue;
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            if (declaration.kind != .function and declaration.kind != .test_function and self.tree.tag(declaration_node) != .c_function_pointer_declaration) continue;
            const function = if (declaration.kind == .test_function)
                self.tree.testDeclaration(declaration_node).?.function
            else
                self.tree.functionDeclaration(declaration_node).?;
            if (function.contract_member or function.generic_params.len != 0 or function.generic_params_struct != null) continue;

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
        var lowerer = self.typeContext();
        const fields = try lowerer.lowerFields(literal);
        return .{ .start = fields.start, .len = fields.len };
    }

    fn predeclareGlobals(self: *Context, stats: *Stats) !void {
        for (self.graph.declarations.items, 0..) |decl, raw| {
            if (decl.kind != .binding) continue;
            self.selectFile(decl.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, decl) orelse continue;
            const syntax_decl = self.tree.symbolDeclaration(declaration_node) orelse continue;
            const binding = if (syntax_decl.type_node) |node|
                try self.writer.addBinding(.{
                    .name = decl.name,
                    .source = self.sourceRef(declaration_node),
                    .ty = try self.lowerType(node),
                    .mutability = graph_mod.mutabilityFromSyntax(syntax_decl.mutability),
                })
            else
                try self.writer.addUnresolvedBinding(
                    decl.name,
                    self.sourceRef(declaration_node),
                    null,
                    graph_mod.mutabilityFromSyntax(syntax_decl.mutability),
                );
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
            const unresolved = views.bindingTypeUnresolved(self.graph, relation.binding);
            const expected: ?entities.ModuleTypeId = if (unresolved)
                null
            else
                self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty;
            const value = try body_lowerer.lowerInitializerExpression(
                self.allocator,
                self.graph,
                self.files,
                self.file_index,
                value_node,
                expected,
                self.diagnostics,
            );
            self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].initialization = value.node;
            if (unresolved) if (value.ty) |value_ty| {
                self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty = value_ty;
                var index: usize = 0;
                while (index < self.graph.semantic.unresolved_binding_types.items.len) : (index += 1) {
                    if (self.graph.semantic.unresolved_binding_types.items[index] != relation.binding) continue;
                    _ = self.graph.semantic.unresolved_binding_types.orderedRemove(index);
                    break;
                }
            };
            try self.writer.addRoot(value.node);
        }
    }

    fn lowerFieldDefaults(self: *Context, stats: *Stats) !void {
        var index: usize = 0;
        // A default expression can register a generated compile-time entry.
        while (index < self.graph.declarations.items.len) : (index += 1) {
            const declaration = self.graph.declarations.items[index];
            self.selectFile(declaration.module_file_index);
            const declaration_node = graph_mod.declarationSyntaxNode(self.files, declaration) orelse continue;
            switch (declaration.kind) {
                .type => if (declaration.struct_fields) |range| {
                    const type_declaration = self.tree.typeDeclaration(declaration_node) orelse continue;
                    try self.lowerDefaults(range.start, range.len, type_declaration.value, stats);
                },
                .function, .test_function => if (declaration.function_id) |function_id| {
                    const syntax_function = if (declaration.kind == .test_function)
                        self.tree.testDeclaration(declaration_node).?.function
                    else
                        self.tree.functionDeclaration(declaration_node).?;
                    const function = self.graph.functions.items[@intFromEnum(function_id)];
                    try self.lowerDefaults(function.input.start, function.input.len, syntax_function.input, stats);
                    // Executable output defaults belong to the function entry scope.
                    if (syntax_function.body == null) {
                        try self.lowerDefaults(function.output.start, function.output.len, syntax_function.output, stats);
                    }
                },
                else => {},
            }
        }
    }

    fn lowerDefaults(self: *Context, range_start: u32, range_len: u32, struct_node: syn.NodeIndex, stats: *Stats) !void {
        const literal = self.tree.structTypeLiteral(struct_node) orelse return error.ExpectedStructType;
        if (literal.fields.len != range_len) return error.InterfaceFieldCountMismatch;
        for (literal.fields, 0..) |field_node, offset| {
            const field = self.tree.structTypeField(field_node) orelse return error.InvalidStructField;
            const default_node = field.default_value orelse continue;
            const raw_field: usize = @intCast(range_start + @as(u32, @intCast(offset)));
            const field_ty = self.graph.semantic.fields.items[raw_field].ty;
            const value = try body_lowerer.lowerInitializerExpression(
                self.allocator,
                self.graph,
                self.files,
                self.file_index,
                default_node,
                field_ty,
                self.diagnostics,
            );
            self.graph.semantic.fields.items[raw_field].default_value = value.node;
            stats.field_defaults += 1;
        }
    }

    fn lowerType(self: *Context, node: syn.NodeIndex) !entities.ModuleTypeId {
        var lowerer = self.typeContext();
        return lowerer.lower(node);
    }

    fn typeContext(self: *Context) type_lowerer.Context {
        return .{
            .graph = self.graph,
            .writer = &self.writer,
            .file_index = self.file_index,
            .tree = self.tree,
            .source = self.source,
        };
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

    fn sourceRef(self: *const Context, node: syn.NodeIndex) primitives.SourceRef {
        return .{ .file_index = self.file_index, .offset = self.tree.location(node).offset };
    }
};

test "module initializer lowering is syntax-free after construction" {
    try std.testing.expect(@sizeOf(entities.DeclarationBinding) <= 8);
}

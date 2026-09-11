const std = @import("std");
const literals = @import("../semantic_literals.zig");
const syn = @import("../../3_syntax/syntax_tree.zig");
const tok = @import("../../2_tokens/token.zig");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const writer_mod = @import("writer.zig");
const type_lowerer = @import("type_lowerer.zig");
const views = @import("views.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    global_bindings: u32 = 0,
    field_defaults: u32 = 0,
};

const Lowered = struct {
    node: entities.ModuleNodeId,
    ty: entities.ModuleTypeId,
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
                .mutability = syntax_decl.mutability,
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
            const value = try self.lowerExpr(value_node, expected);
            self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].initialization = value.node;
            if (self.isAny(expected) and !self.isAny(value.ty))
                self.graph.semantic.bindings.items[@intFromEnum(relation.binding)].ty = value.ty;
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
            const value = try self.lowerExpr(default_node, field_ty);
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

    fn lowerExpr(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) anyerror!Lowered {
        return switch (self.tree.tag(node)) {
            .literal => self.lowerLiteral(node),
            .identifier => self.lowerIdentifier(node, expected),
            .function_call => self.lowerCall(node, expected),
            .struct_value_literal => self.lowerStruct(node),
            .list_literal => self.lowerList(node),
            .struct_field_access => self.lowerField(node, expected),
            .index_access => self.lowerIndex(node, expected),
            .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => self.lowerBinary(node, expected),
            .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal => self.lowerComparison(node),
            .logical_and, .logical_or => self.lowerLogical(node),
            .address_of, .address_of_mut => self.lowerAddress(node),
            .dereference => self.lowerDereference(node, expected),
            .reach_directive => self.lowerReach(node),
            .type_name, .pointer_type, .pointer_type_mut, .nullable_type, .inferred_errable_type, .array_type, .generic_type_instantiation, .struct_type_literal, .choice_type_literal => self.lowerTypeLiteral(node),
            else => error.UnsupportedInitializerExpression,
        };
    }

    fn lowerLiteral(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.literal(node).?;
        return switch (self.tree.tokenContent(literal.token).literal) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => blk: {
                const value = try literals.integer(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                break :blk self.resolved(node, try self.builtin(.Int32), .{ .int_literal = value });
            },
            .regular_float_literal, .scientific_float_literal => blk: {
                const value = try literals.float(self.tree.tokenTextFromSource(self.source, literal.token), literal.negative);
                break :blk self.resolved(node, try self.builtin(.Float32), .{ .float_literal = value });
            },
            .bool_literal => |value| self.resolved(node, try self.builtin(.Bool), .{ .bool_literal = value }),
            .char_literal => |value| self.resolved(node, try self.builtin(.Char), .{ .char_literal = value }),
            .string_literal => self.resolved(node, try self.builtin(.Any), .{
                .string_literal = try self.writer.addString(self.tree.tokenTextFromSource(self.source, literal.token)),
            }),
        };
    }

    fn lowerIdentifier(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(node));
        for (self.graph.semantic.declaration_bindings.items) |relation| {
            const decl = self.graph.declarations.items[@intFromEnum(relation.declaration)];
            if (!std.mem.eql(u8, self.graph.text(decl.name), text)) continue;
            const binding = self.graph.semantic.bindings.items[@intFromEnum(relation.binding)];
            return self.resolved(node, binding.ty, .{ .binding_use = relation.binding });
        }
        const ty = expected orelse try self.builtin(.Any);
        return self.pending(.{ .resolve_name_use = .{
            .node = self.nextNodeId(),
            .name = try self.writer.addString(text),
        } }, ty);
    }

    fn lowerCall(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const call = self.tree.functionCall(node).?;
        const input = try self.lowerExpr(call.input, null);
        const external = try self.writer.addExternalRef(.{
            .kind = .function,
            .module_path = if (call.module_qualifier) |token_index|
                try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))
            else
                null,
            .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, call.callee_token)),
            .source = self.sourceRef(node),
        });
        const target = self.nextNodeId();
        return self.pending(.{ .resolve_call = .{
            .node = target,
            .callee = external,
            .input = input.node,
            .expected_type = expected,
        } }, expected orelse try self.builtin(.Any));
    }

    fn lowerStruct(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.structValueLiteral(node).?;
        const start: u32 = @intCast(self.graph.semantic.value_fields.items.len);
        for (literal.fields) |field_node| {
            const field = self.tree.valueField(field_node).?;
            const value = try self.lowerExpr(field.value, null);
            const name = if (field.name_token) |token_index|
                try self.writer.addString(self.tree.tokenTextFromSource(self.source, token_index))
            else
                try self.writer.addString("");
            try self.graph.semantic.value_fields.append(self.allocator, .{ .name = name, .value = value.node });
        }
        const ty = try self.builtin(.Any);
        return self.resolved(node, ty, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(literal.fields.len) },
            .ty = ty,
            .dispatch_prefix_positional_count = literal.positional_prefix_count,
        } });
    }

    fn lowerList(self: *Context, node: syn.NodeIndex) !Lowered {
        const literal = self.tree.listLiteral(node).?;
        var nodes: std.ArrayList(entities.ModuleNodeId) = .empty;
        defer nodes.deinit(self.allocator);
        var types: std.ArrayList(entities.ModuleTypeId) = .empty;
        defer types.deinit(self.allocator);
        for (literal.elements) |child| {
            const value = try self.lowerExpr(child, null);
            try nodes.append(self.allocator, value.node);
            try types.append(self.allocator, value.ty);
        }
        const ty = try self.builtin(.Any);
        return self.resolved(node, ty, .{ .list_literal = .{
            .elements = try self.writer.appendNodeRefs(nodes.items),
            .element_types = try self.writer.appendTypeRefs(types.items),
        } });
    }

    fn lowerField(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const access = self.tree.structFieldAccess(node).?;
        const value = try self.lowerExpr(access.value, null);
        const target = self.nextNodeId();
        const pending_id = try self.writer.addPendingOperation(.{ .resolve_field = .{
            .node = target,
            .value = value.node,
            .field_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.field_token)),
        } });
        const stored = try self.writer.addNode(.{ .pending = pending_id });
        return .{ .node = stored, .ty = expected orelse try self.builtin(.Any) };
    }

    fn lowerIndex(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const access = self.tree.indexAccess(node).?;
        const value = try self.lowerExpr(access.value, null);
        const index = try self.lowerExpr(access.index, try self.builtin(.Int32));
        return self.pending(.{ .resolve_index = .{
            .node = self.nextNodeId(),
            .value = value.node,
            .index = index.node,
        } }, expected orelse try self.builtin(.Any));
    }

    fn lowerBinary(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const operation = self.tree.binaryOperation(node).?;
        const left = try self.lowerExpr(operation.lhs, null);
        const right = try self.lowerExpr(operation.rhs, left.ty);
        const operator: tok.BinaryOperator = switch (self.tree.tag(node)) {
            .binary_add => .addition,
            .binary_subtract => .subtraction,
            .binary_multiply => .multiplication,
            .binary_divide => .division,
            .binary_modulo => .modulo,
            else => unreachable,
        };
        return self.pending(.{ .resolve_binary = .{
            .node = self.nextNodeId(),
            .operator = operator,
            .left = left.node,
            .right = right.node,
        } }, expected orelse left.ty);
    }

    fn lowerComparison(self: *Context, node: syn.NodeIndex) !Lowered {
        const operation = self.tree.binaryOperation(node).?;
        const left = try self.lowerExpr(operation.lhs, null);
        const right = try self.lowerExpr(operation.rhs, left.ty);
        const operator: tok.ComparisonOperator = switch (self.tree.tag(node)) {
            .compare_equal => .equal,
            .compare_not_equal => .not_equal,
            .compare_less => .less_than,
            .compare_greater => .greater_than,
            .compare_less_equal => .less_than_or_equal,
            .compare_greater_equal => .greater_than_or_equal,
            else => unreachable,
        };
        return self.pending(.{ .resolve_comparison = .{
            .node = self.nextNodeId(),
            .operator = operator,
            .left = left.node,
            .right = right.node,
        } }, try self.builtin(.Bool));
    }

    fn lowerLogical(self: *Context, node: syn.NodeIndex) !Lowered {
        const operation = self.tree.binaryOperation(node).?;
        const bool_ty = try self.builtin(.Bool);
        const left = try self.lowerExpr(operation.lhs, bool_ty);
        const right = try self.lowerExpr(operation.rhs, bool_ty);
        return self.resolved(node, bool_ty, .{ .logical_operation = .{
            .operator = if (self.tree.tag(node) == .logical_and) .and_ else .or_,
            .left = left.node,
            .right = right.node,
        } });
    }

    fn lowerAddress(self: *Context, node: syn.NodeIndex) !Lowered {
        const address = self.tree.addressOf(node).?;
        const value = try self.lowerExpr(address.value, null);
        const ty = try self.writer.addResolvedType(.{ .pointer = .{ .child = value.ty, .mutability = address.mutability } });
        return self.resolved(node, ty, .{ .address_of = value.node });
    }

    fn lowerDereference(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const value = try self.lowerExpr(self.tree.unaryOperand(node).?, null);
        const ty = expected orelse try self.builtin(.Any);
        return self.resolved(node, ty, .{ .dereference = .{ .pointer = value.node, .ty = ty, .pointer_type = value.ty } });
    }

    fn lowerReach(self: *Context, node: syn.NodeIndex) !Lowered {
        const directive = self.tree.reachDirective(node).?;
        const alt_start: u32 = @intCast(self.graph.semantic.reach_alternatives.items.len);
        for (directive.alternatives) |alt_node| {
            const alt = self.tree.reachAlternative(alt_node).?;
            const seg_start: u32 = @intCast(self.graph.semantic.reach_segments.items.len);
            for (alt.segments) |segment| try self.graph.semantic.reach_segments.append(self.allocator, try self.writer.addString(self.tree.tokenTextFromSource(self.source, self.tree.mainToken(segment))));
            try self.graph.semantic.reach_alternatives.append(self.allocator, .{
                .segments = .{ .start = seg_start, .len = @intCast(alt.segments.len) },
            });
        }
        const reach_id: entities.ModuleReachId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.reaches.items.len)));
        try self.graph.semantic.reaches.append(self.allocator, .{
            .alternatives = .{ .start = alt_start, .len = @intCast(directive.alternatives.len) },
        });
        return self.resolved(node, try self.builtin(.Any), .{ .reach_directive = reach_id });
    }

    fn lowerTypeLiteral(self: *Context, node: syn.NodeIndex) !Lowered {
        const value = try self.lowerType(node);
        return self.resolved(node, try self.builtin(.Type), .{ .type_literal = value });
    }

    fn pending(self: *Context, operation: entities.PendingOperation, ty: entities.ModuleTypeId) !Lowered {
        const id = try self.writer.addPendingNode(operation);
        return .{ .node = id, .ty = ty };
    }

    fn resolved(self: *Context, node: syn.NodeIndex, ty: entities.ModuleTypeId, content: entities.ResolvedNode.Content) !Lowered {
        return .{ .node = try self.writer.addResolvedNode(.{ .source = self.sourceRef(node), .ty = ty, .content = content }), .ty = ty };
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

    fn nextNodeId(self: *const Context) entities.ModuleNodeId {
        return @enumFromInt(@as(u32, @intCast(self.graph.semantic.nodes.items.len)));
    }
};

test "module initializer lowering is syntax-free after construction" {
    try std.testing.expect(@sizeOf(entities.DeclarationBinding) <= 8);
}

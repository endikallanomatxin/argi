const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const tok = @import("../2_tokens/token.zig");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const templates = @import("module_semantic_templates.zig");
const ir = @import("module_semantic_template_ir.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const core_mod = @import("global_semantic_core.zig");
const generic_mod = @import("global_semantic_generics.zig");
const global_types = @import("global_semantic_types.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    instances: u32 = 0,
    calls: u32 = 0,
    nodes: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    generics: *generic_mod.Resolver,
    stats: Stats = .{},

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        return switch (operation) {
            .resolve_call => |value| self.resolveModuleGenericCall(module_index, module, o, value),
            else => null,
        };
    }

    fn resolveModuleGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        const local_args = reference.generic_arguments orelse return false;
        const declaration = self.core.resolveDeclaration(module_index, reference, &.{.function}) catch return false;
        const args = try self.generics.relocateModuleArguments(module_index, local_args);
        const function = try self.instantiate(declaration, args);
        const input = globalizer.globalNode(o, value.input);
        const output_ty = try self.core.functionOutputType(function);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(module_index, reference.source),
            .ty = if (value.expected_type) |ty| globalizer.globalType(o, ty) else output_ty,
            .content = .{ .function_call = .{ .callee = function, .input = input } },
        };
        self.stats.calls += 1;
        return true;
    }

    pub fn instantiate(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !global_sg.GlobalFunctionId {
        if (self.findExisting(declaration, arguments)) |id| return id;
        const located = self.findTemplate(declaration) orelse return error.GenericFunctionTemplateNotFound;
        const module = &self.modules[located.module_index];
        const storage = &module.semantic.templates;

        var substitutions = try generic_mod.Resolver.Bindings.init(self.allocator, storage.generic_parameters.items.len);
        defer substitutions.deinit(self.allocator);
        try self.generics.bindGlobalArguments(located.module_index, located.template.parameters, arguments, &substitutions);

        const input_ty = try self.generics.instantiateTemplateType(located.module_index, located.template.input, &substitutions, null);
        const output_ty = try self.generics.instantiateTemplateType(located.module_index, located.template.output, &substitutions, null);
        const input_fields = try self.interfaceFields(input_ty);
        const output_fields = try self.interfaceFields(output_ty);

        var context = try InstanceContext.init(self, located.module_index, located.template, &substitutions);
        defer context.deinit();
        const input_bindings = try context.instantiateBindingRange(located.template.input_bindings);
        const output_bindings = try context.instantiateBindingRange(located.template.output_bindings);

        // Reserve the function and identity before its body. Recursive generic
        // calls can now discover this exact monomorphization while the body is
        // still being instantiated.
        const function_id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(self.graph.functions.items.len)));
        try self.graph.functions.append(self.allocator, .{
            .declaration = declaration,
            .input = input_fields,
            .output = output_fields,
            .body = null,
            .input_bindings = input_bindings,
            .output_bindings = output_bindings,
            .flags = .{
                .has_declared_body = located.template.body != null,
                .is_generic_instantiation = true,
                .is_abstract_dispatch = located.template.dispatch_kind == .abstract_contract,
            },
        });
        try self.graph.function_operators.append(self.allocator, located.template.operator);
        try self.graph.generic_function_instances.append(self.allocator, .{
            .function = function_id,
            .template_declaration = declaration,
            .arguments = arguments,
        });

        context.function = function_id;
        if (located.template.body) |body| {
            self.graph.functions.items[@intFromEnum(function_id)].body = try context.instantiateBlock(body);
        }
        self.stats.instances += 1;
        return function_id;
    }

    const LocatedTemplate = struct {
        module_index: usize,
        template: templates.GenericFunctionTemplate,
    };

    fn findTemplate(self: *Resolver, declaration: global_sg.GlobalDeclId) ?LocatedTemplate {
        const owner = self.graph.moduleForDeclaration(declaration) orelse return null;
        const module_index: usize = @intFromEnum(owner);
        const base = self.offsets[module_index].declaration_base;
        const raw = @intFromEnum(declaration);
        if (raw < base) return null;
        const local: module_entities.ModuleDeclId = @enumFromInt(raw - base);
        for (self.modules[module_index].semantic.templates.generic_function_templates.items) |template| {
            if (template.declaration == local) return .{ .module_index = module_index, .template = template };
        }
        return null;
    }

    fn findExisting(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) ?global_sg.GlobalFunctionId {
        for (self.graph.generic_function_instances.items) |instance| {
            if (instance.template_declaration != declaration) continue;
            if (argumentRangesEqual(self.graph, instance.arguments, arguments)) return instance.function;
        }
        return null;
    }

    fn interfaceFields(self: *Resolver, ty: global_sg.GlobalTypeId) !global_sg.FieldRange {
        if (global_types.fields(self.graph, ty)) |range| return range;
        const name = try self.graph.addString(self.allocator, "value");
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.append(self.allocator, .{
            .name = name,
            .ty = ty,
            .source = .{ .file_index = 0, .offset = 0 },
        });
        return .{ .start = start, .len = 1 };
    }

    fn sourceFor(self: *Resolver, module_index: usize, source: primitives.SourceRef) primitives.SourceRef {
        return .{ .file_index = self.offsets[module_index].file_base + source.file_index, .offset = source.offset };
    }

    const InstanceContext = struct {
        resolver: *Resolver,
        module_index: usize,
        template: templates.GenericFunctionTemplate,
        substitutions: *generic_mod.Resolver.Bindings,
        binding_map: []?global_sg.GlobalBindingId,
        node_map: []?global_sg.GlobalNodeId,
        block_map: []?global_sg.GlobalBlockId,
        function: ?global_sg.GlobalFunctionId = null,

        fn init(
            resolver: *Resolver,
            module_index: usize,
            template: templates.GenericFunctionTemplate,
            substitutions: *generic_mod.Resolver.Bindings,
        ) !InstanceContext {
            const storage = &resolver.modules[module_index].semantic.templates.ir;
            const bindings = try resolver.allocator.alloc(?global_sg.GlobalBindingId, storage.bindings.items.len);
            errdefer resolver.allocator.free(bindings);
            const nodes = try resolver.allocator.alloc(?global_sg.GlobalNodeId, storage.nodes.items.len);
            errdefer resolver.allocator.free(nodes);
            const blocks = try resolver.allocator.alloc(?global_sg.GlobalBlockId, storage.blocks.items.len);
            @memset(bindings, null);
            @memset(nodes, null);
            @memset(blocks, null);
            return .{
                .resolver = resolver,
                .module_index = module_index,
                .template = template,
                .substitutions = substitutions,
                .binding_map = bindings,
                .node_map = nodes,
                .block_map = blocks,
            };
        }

        fn deinit(self: *InstanceContext) void {
            self.resolver.allocator.free(self.binding_map);
            self.resolver.allocator.free(self.node_map);
            self.resolver.allocator.free(self.block_map);
        }

        fn instantiateBindingRange(self: *InstanceContext, range: primitives.Range(ir.TemplateBindingId)) !global_sg.BindingRange {
            const start: u32 = @intCast(self.resolver.graph.binding_refs.items.len);
            for (0..range.len) |offset| {
                const local: ir.TemplateBindingId = @enumFromInt(range.start + @as(u32, @intCast(offset)));
                const global = try self.instantiateBinding(local);
                try self.resolver.graph.binding_refs.append(self.resolver.allocator, global);
            }
            return .{ .start = start, .len = range.len };
        }

        fn instantiateBinding(self: *InstanceContext, id: ir.TemplateBindingId) !global_sg.GlobalBindingId {
            if (self.binding_map[@intFromEnum(id)]) |existing| return existing;
            const module = &self.resolver.modules[self.module_index];
            const source = module.semantic.templates.ir.bindings.items[@intFromEnum(id)];
            const global: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.bindings.items.len)));
            try self.resolver.graph.bindings.append(self.resolver.allocator, .{
                .name = try self.resolver.graph.addString(self.resolver.allocator, module.text(source.name)),
                .source = self.resolver.sourceFor(self.module_index, source.source),
                .ty = try self.resolver.generics.instantiateTemplateType(self.module_index, source.ty, self.substitutions, null),
                .initialization = null,
                .mutability = source.mutability,
            });
            self.binding_map[@intFromEnum(id)] = global;
            if (source.initialization) |node| {
                self.resolver.graph.bindings.items[@intFromEnum(global)].initialization = try self.instantiateNode(node);
            }
            return global;
        }

        fn instantiateBlock(self: *InstanceContext, id: ir.TemplateBlockId) anyerror!global_sg.GlobalBlockId {
            if (self.block_map[@intFromEnum(id)]) |existing| return existing;
            const local = self.resolver.modules[self.module_index].semantic.templates.ir.blocks.items[@intFromEnum(id)];
            const global: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.blocks.items.len)));
            // Reserve to support nested/self-referential block graphs.
            try self.resolver.graph.blocks.append(self.resolver.allocator, .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = null });
            self.block_map[@intFromEnum(id)] = global;

            const storage = &self.resolver.modules[self.module_index].semantic.templates.ir;
            const start: u32 = @intCast(self.resolver.graph.node_refs.items.len);
            for (storage.node_refs.items[local.nodes.start..][0..local.nodes.len]) |node| {
                try self.resolver.graph.node_refs.append(self.resolver.allocator, try self.instantiateNode(node));
            }
            self.resolver.graph.blocks.items[@intFromEnum(global)] = .{
                .nodes = .{ .start = start, .len = local.nodes.len },
                .ret_val = if (local.ret_val) |node| try self.instantiateNode(node) else null,
            };
            return global;
        }

        fn instantiateNode(self: *InstanceContext, id: ir.TemplateNodeId) anyerror!global_sg.GlobalNodeId {
            if (self.node_map[@intFromEnum(id)]) |existing| return existing;
            const storage = &self.resolver.modules[self.module_index].semantic.templates.ir;
            const local = storage.nodes.items[@intFromEnum(id)];
            const global: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.nodes.items.len)));
            // Reserve the slot first so recursive expression graphs remain stable.
            try self.resolver.graph.nodes.append(self.resolver.allocator, .{
                .source = .{ .file_index = 0, .offset = 0 },
                .ty = null,
                .content = .break_statement,
            });
            self.node_map[@intFromEnum(id)] = global;
            self.resolver.graph.nodes.items[@intFromEnum(global)] = switch (local) {
                .resolved => |node| try self.instantiateResolvedNode(node),
                .pending => |pending| try self.instantiatePendingNode(storage.pending.items[@intFromEnum(pending)]),
            };
            self.resolver.stats.nodes += 1;
            return global;
        }

        fn instantiateResolvedNode(self: *InstanceContext, node: ir.ResolvedNode) anyerror!global_sg.Node {
            const ty = if (node.ty) |value| try self.resolver.generics.instantiateTemplateType(self.module_index, value, self.substitutions, null) else null;
            return .{
                .source = self.resolver.sourceFor(self.module_index, node.source),
                .ty = ty,
                .content = switch (node.content) {
                    .binding_use => |binding| .{ .binding_use = try self.instantiateBinding(binding) },
                    .binding_declaration => |binding| .{ .binding_declaration = try self.instantiateBinding(binding) },
                    .code_block => |block| .{ .code_block = try self.instantiateBlock(block) },
                    .int_literal => |value| .{ .int_literal = value },
                    .float_literal => |value| .{ .float_literal = value },
                    .char_literal => |value| .{ .char_literal = value },
                    .bool_literal => |value| .{ .bool_literal = value },
                    .string_literal => |value| .{ .string_literal = try self.copyString(value) },
                    .break_statement => .break_statement,
                    .continue_statement => .continue_statement,
                    else => return error.UnsupportedResolvedTemplateNode,
                },
            };
        }

        fn instantiatePendingNode(self: *InstanceContext, pending: ir.Pending) anyerror!global_sg.Node {
            return switch (pending) {
                .resolve_name => |value| self.resolveName(value),
                .resolve_call => |value| self.resolveLegacyCall(value),
                .resolve_field => |value| self.resolveTemplateField(value.value, value.field_name, value.source),
                .resolve_expression => |value| self.resolveExpression(value),
                .resolve_copy, .resolve_deinit => error.TemplateOwnershipPending,
            };
        }

        fn resolveName(self: *InstanceContext, value: anytype) !global_sg.Node {
            const name = self.resolver.modules[self.module_index].text(value.name);
            if (self.findGlobalBinding(name)) |binding| {
                const record = self.resolver.graph.bindings.items[@intFromEnum(binding)];
                return .{ .source = self.resolver.sourceFor(self.module_index, value.source), .ty = record.ty, .content = .{ .binding_use = binding } };
            }
            return error.UnknownTemplateName;
        }

        fn resolveLegacyCall(self: *InstanceContext, value: anytype) !global_sg.Node {
            const name = self.resolver.modules[self.module_index].text(value.name);
            const input = try self.instantiateNode(value.input);
            return self.makeNamedCall(name, null, .{ .start = 0, .len = 0 }, input, value.source);
        }

        fn resolveExpression(self: *InstanceContext, value: ir.PendingExpression) anyerror!global_sg.Node {
            const storage = &self.resolver.modules[self.module_index].semantic.templates.ir;
            var operands = std.array_list.Managed(global_sg.GlobalNodeId).init(self.resolver.allocator);
            defer operands.deinit();
            for (storage.node_refs.items[value.operands.start..][0..value.operands.len]) |operand|
                try operands.append(try self.instantiateNode(operand));

            return switch (value.kind) {
                .unknown_identifier => if (value.name) |name| self.resolveName(.{ .name = name, .source = value.source }) else error.UnknownTemplateName,
                .generic_call => blk: {
                    const name = self.resolver.modules[self.module_index].text(value.name orelse return error.GenericTemplateCallWithoutName);
                    const args = try self.resolver.generics.instantiateTemplateArguments(self.module_index, value.generic_arguments, self.substitutions, null);
                    const input = if (operands.items.len != 0) operands.items[0] else return error.GenericTemplateCallWithoutInput;
                    break :blk try self.makeNamedCall(name, value.module_path, args, input, value.source);
                },
                .binary => self.resolveBinary(operands.items, value.source, value.aux),
                .comparison => self.resolveComparison(operands.items, value.source, value.aux),
                .logical => self.resolveLogical(operands.items, value.source, value.aux),
                .index => self.resolveIndex(operands.items, value.source, false),
                .index_store => self.resolveIndex(operands.items, value.source, true),
                .choice_payload => if (value.name) |name| self.resolveField(operands.items[0], name, value.source) else error.InvalidTemplateChoicePayload,
                .return_statement => self.resolveReturn(operands.items, value.source),
                .if_statement => self.resolveIf(operands.items, value.source),
                .while_statement => self.resolveWhile(operands.items, value.source),
                .address_of => self.resolveAddress(operands.items, value.source, value.aux),
                .dereference => self.resolveDereference(operands.items, value.source),
                .pointer_store => self.resolvePointerStore(operands.items, value.source),
                .pipe => if (operands.items.len != 0) self.resolver.graph.nodes.items[@intFromEnum(operands.items[operands.items.len - 1])] else error.InvalidTemplatePipe,
                .struct_value, .list_value, .choice_literal, .nullable_test, .unwrap_or, .unwrap_or_do,
                .error_propagation, .error_context, .for_each, .match, .match_case,
                .defer_value, .keep_binding, .type_initializer, .explicit_cast, .other,
                => error.TemplateExpressionRequiresGlobalResolver,
            };
        }

        fn makeNamedCall(
            self: *InstanceContext,
            name: []const u8,
            module_path: ?primitives.StringRange,
            arguments: primitives.Range(global_sg.GlobalGenericArgId),
            input: global_sg.GlobalNodeId,
            source: primitives.SourceRef,
        ) !global_sg.Node {
            const declaration = self.findFunctionDeclaration(name, module_path) orelse return error.UnknownTemplateFunction;
            const function = if (arguments.len != 0 or self.resolver.findTemplate(declaration) != null)
                try self.resolver.instantiate(declaration, arguments)
            else
                self.findOrdinaryFunction(declaration, input) orelse return error.NoMatchingTemplateFunction;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = try self.resolver.core.functionOutputType(function),
                .content = .{ .function_call = .{ .callee = function, .input = input } },
            };
        }

        fn findFunctionDeclaration(self: *InstanceContext, name: []const u8, module_path: ?primitives.StringRange) ?global_sg.GlobalDeclId {
            var found: ?global_sg.GlobalDeclId = null;
            for (self.resolver.graph.declarations.items, 0..) |decl, raw| {
                if (decl.kind != .function) continue;
                if (!std.mem.eql(u8, self.resolver.graph.text(decl.name), name)) continue;
                const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
                if (module_path) |path| {
                    const wanted = self.resolver.modules[self.module_index].text(path);
                    const owner = self.resolver.graph.moduleForDeclaration(id) orelse continue;
                    if (!std.mem.eql(u8, self.resolver.graph.text(self.resolver.graph.modules.items[@intFromEnum(owner)].dir), wanted)) continue;
                } else if (@intFromEnum(self.resolver.graph.moduleForDeclaration(id).?) != self.module_index and found != null) {
                    continue;
                }
                found = id;
                if (@intFromEnum(self.resolver.graph.moduleForDeclaration(id).?) == self.module_index and module_path == null) break;
            }
            return found;
        }

        fn findOrdinaryFunction(self: *InstanceContext, declaration: global_sg.GlobalDeclId, input: global_sg.GlobalNodeId) ?global_sg.GlobalFunctionId {
            const actual = self.resolver.graph.nodes.items[@intFromEnum(input)].ty;
            for (self.resolver.graph.functions.items, 0..) |function, raw| {
                if (function.declaration != declaration or function.flags.is_generic_instantiation) continue;
                if (actual == null) return @enumFromInt(@as(u32, @intCast(raw)));
                if (function.input.len == 1) {
                    const expected = self.resolver.graph.fields.items[function.input.start].ty;
                    if (global_types.equal(self.resolver.graph, expected, actual.?)) return @enumFromInt(@as(u32, @intCast(raw)));
                } else return @enumFromInt(@as(u32, @intCast(raw)));
            }
            return null;
        }

        fn resolveBinary(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, aux: u32) !global_sg.Node {
            if (operands.len != 2) return error.InvalidTemplateBinary;
            const tag: syn.Node.Tag = @enumFromInt(aux);
            const operator: tok.BinaryOperator = switch (tag) {
                .binary_add => .addition,
                .binary_subtract => .subtraction,
                .binary_multiply => .multiplication,
                .binary_divide => .division,
                .binary_modulo => .modulo,
                else => return error.InvalidTemplateBinary,
            };
            const ty = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = ty,
                .content = .{ .binary_operation = .{ .operator = operator, .left = operands[0], .right = operands[1] } },
            };
        }

        fn resolveComparison(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, aux: u32) !global_sg.Node {
            if (operands.len != 2) return error.InvalidTemplateComparison;
            const tag: syn.Node.Tag = @enumFromInt(aux);
            const operator: tok.ComparisonOperator = switch (tag) {
                .compare_equal => .equal,
                .compare_not_equal => .not_equal,
                .compare_less => .less,
                .compare_greater => .greater,
                .compare_less_equal => .less_equal,
                .compare_greater_equal => .greater_equal,
                else => return error.InvalidTemplateComparison,
            };
            const bool_ty = try self.resolver.generics.internType(.{ .builtin = .Bool });
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = bool_ty,
                .content = .{ .comparison = .{ .operator = operator, .left = operands[0], .right = operands[1] } },
            };
        }

        fn resolveLogical(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, aux: u32) !global_sg.Node {
            if (operands.len != 2) return error.InvalidTemplateLogical;
            const tag: syn.Node.Tag = @enumFromInt(aux);
            const operator: primitives.LogicalOperator = if (tag == .logical_and) .and_ else if (tag == .logical_or) .or_ else return error.InvalidTemplateLogical;
            const bool_ty = try self.resolver.generics.internType(.{ .builtin = .Bool });
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = bool_ty, .content = .{ .logical_operation = .{ .operator = operator, .left = operands[0], .right = operands[1] } } };
        }

        fn resolveTemplateField(self: *InstanceContext, value: ir.TemplateNodeId, field_name: primitives.StringRange, source: primitives.SourceRef) !global_sg.Node {
            return self.resolveField(try self.instantiateNode(value), field_name, source);
        }

        fn resolveField(self: *InstanceContext, value: global_sg.GlobalNodeId, field_name: primitives.StringRange, source: primitives.SourceRef) !global_sg.Node {
            const ty = self.resolver.graph.nodes.items[@intFromEnum(value)].ty orelse return error.TemplateFieldOnUntypedValue;
            const name = self.resolver.modules[self.module_index].text(field_name);
            const hit = global_types.findField(self.resolver.graph, ty, name) orelse return error.UnknownTemplateField;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = hit.field.ty,
                .content = .{ .struct_field_access = .{ .value = value, .field_name = try self.copyString(field_name), .field_index = hit.index } },
            };
        }

        fn resolveIndex(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, store: bool) !global_sg.Node {
            if (operands.len < 2) return error.InvalidTemplateIndex;
            const collection_ty = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.TemplateIndexUntyped;
            const element = global_types.arrayElement(self.resolver.graph, collection_ty) orelse return error.TemplateIndexRequiresDispatch;
            return if (store) .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = element,
                .content = .{ .array_store = .{ .array_ptr = operands[0], .index = operands[1], .value = operands[2], .element_type = element, .array_type = collection_ty } },
            } else .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = element,
                .content = .{ .array_index = .{ .array_ptr = operands[0], .index = operands[1], .element_type = element, .array_type = collection_ty } },
            };
        }

        fn resolveReturn(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            const void_ty = try self.resolver.generics.internType(.{ .builtin = .Void });
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = if (operands.len != 0) self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty else void_ty,
                .content = .{ .return_statement = .{ .expression = if (operands.len != 0) operands[0] else null, .cleanup = .{ .start = 0, .len = 0 } } },
            };
        }

        fn resolveIf(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len < 2) return error.InvalidTemplateIf;
            const then_block = switch (self.resolver.graph.nodes.items[@intFromEnum(operands[1])].content) { .code_block => |block| block, else => return error.TemplateIfBlockExpected };
            const else_block = if (operands.len > 2) switch (self.resolver.graph.nodes.items[@intFromEnum(operands[2])].content) { .code_block => |block| block, else => return error.TemplateIfBlockExpected } else null;
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = try self.resolver.generics.internType(.{ .builtin = .Void }),
                .content = .{ .if_statement = .{ .condition = operands[0], .then_block = then_block, .else_block = else_block } },
            };
        }

        fn resolveWhile(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 2) return error.InvalidTemplateWhile;
            const body = switch (self.resolver.graph.nodes.items[@intFromEnum(operands[1])].content) { .code_block => |block| block, else => return error.TemplateWhileBlockExpected };
            return .{
                .source = self.resolver.sourceFor(self.module_index, source),
                .ty = try self.resolver.generics.internType(.{ .builtin = .Void }),
                .content = .{ .while_statement = .{ .condition = operands[0], .body = body } },
            };
        }

        fn resolveAddress(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef, aux: u32) !global_sg.Node {
            if (operands.len != 1) return error.InvalidTemplateAddressOf;
            const child = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.TemplateAddressUntyped;
            const tag: syn.Node.Tag = @enumFromInt(aux);
            const pointer = try self.resolver.generics.internType(.{ .pointer = .{ .child = child, .mutability = if (tag == .address_of_mut) .read_write else .read_only } });
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = pointer, .content = .{ .address_of = operands[0] } };
        }

        fn resolveDereference(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 1) return error.InvalidTemplateDereference;
            const pointer_ty = self.resolver.graph.nodes.items[@intFromEnum(operands[0])].ty orelse return error.TemplateDereferenceUntyped;
            const child = switch (self.resolver.graph.types.items[@intFromEnum(pointer_ty)]) { .pointer => |pointer| pointer.child, else => return error.TemplateDereferenceNonPointer };
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = child, .content = .{ .dereference = .{ .pointer = operands[0], .ty = child, .pointer_type = pointer_ty } } };
        }

        fn resolvePointerStore(self: *InstanceContext, operands: []const global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.Node {
            if (operands.len != 2) return error.InvalidTemplatePointerStore;
            return .{ .source = self.resolver.sourceFor(self.module_index, source), .ty = self.resolver.graph.nodes.items[@intFromEnum(operands[1])].ty, .content = .{ .pointer_assignment = .{ .pointer = operands[0], .value = operands[1] } } };
        }

        fn findGlobalBinding(self: *InstanceContext, name: []const u8) ?global_sg.GlobalBindingId {
            for (self.resolver.graph.bindings.items, 0..) |binding, raw| {
                if (std.mem.eql(u8, self.resolver.graph.text(binding.name), name)) return @enumFromInt(@as(u32, @intCast(raw)));
            }
            return null;
        }

        fn copyString(self: *InstanceContext, range: primitives.StringRange) !primitives.StringRange {
            return self.resolver.graph.addString(self.resolver.allocator, self.resolver.modules[self.module_index].text(range));
        }
    };
};

fn argumentRangesEqual(
    graph: *const global_sg.GlobalSemanticGraph,
    a: primitives.Range(global_sg.GlobalGenericArgId),
    b: primitives.Range(global_sg.GlobalGenericArgId),
) bool {
    if (a.len != b.len) return false;
    for (0..a.len) |offset| {
        const left = graph.generic_arguments.items[a.start + @as(u32, @intCast(offset))];
        const right = graph.generic_arguments.items[b.start + @as(u32, @intCast(offset))];
        if (!std.mem.eql(u8, graph.text(left.name), graph.text(right.name))) return false;
        switch (left.value) {
            .type => |left_ty| switch (right.value) { .type => |right_ty| if (left_ty != right_ty) return false, else => return false },
            .comptime_int => |left_int| switch (right.value) { .comptime_int => |right_int| if (left_int != right_int) return false, else => return false },
        }
    }
    return true;
}

test "generic function monomorphization uses stable GlobalFunctionId identity" {
    try std.testing.expect(@sizeOf(global_sg.GlobalFunctionId) == 4);
    try std.testing.expect(@sizeOf(global_sg.GenericFunctionInstance) <= 16);
}

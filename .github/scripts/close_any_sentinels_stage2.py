from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old in text:
        p.write_text(text.replace(old, new, 1))
        return
    if new in text:
        return
    raise SystemExit(f"expected anchor not found in {path}: {old[:160]!r}")


# A string literal is contextual while a call is being matched, but when no
# context claims it the language-level default is the bundled core StringView.
# This keeps `Any` out of inference while still allowing explicit contextual
# coercions such as the low-level C-string boundary.
replace_once(
    "src/4_semantics/global/core.zig",
    """    pub fn tryResolve(
""",
    """    pub fn defaultStringLiteralType(self: *const Resolver) ?global_sg.GlobalTypeId {
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or !std.mem.eql(u8, self.graph.text(declaration.name), "StringView")) continue;
            const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            const owner = self.graph.moduleForDeclaration(id) orelse continue;
            if (!self.graph.modules.items[@intFromEnum(owner)].is_bundled_core) continue;
            const ty = declaration.type_id orelse continue;
            if (self.graph.isTypeUnresolved(ty)) continue;
            return ty;
        }
        return null;
    }

    pub fn materializeStringLiteralTypes(self: *Resolver) bool {
        const default_ty = self.defaultStringLiteralType() orelse return false;
        var changed = false;
        for (self.graph.nodes.items) |*node| {
            if (node.ty != null or node.content != .string_literal) continue;
            node.ty = default_ty;
            changed = true;
        }
        return changed;
    }

    pub fn tryResolve(
""",
)

replace_once(
    "src/4_semantics/global/semantizer.zig",
    """        if (relocation.graph.reconcileTypeResolution()) changed = true;
        if (relocation.graph.reconcileBindingTypeResolution()) changed = true;
        if (core.materializeBindingTypes()) changed = true;
""",
    """        if (relocation.graph.reconcileTypeResolution()) changed = true;
        if (relocation.graph.reconcileBindingTypeResolution()) changed = true;
        if (core.materializeStringLiteralTypes()) changed = true;
        if (core.materializeBindingTypes()) changed = true;
""",
)

# Preserve the syntax-level positional prefix in parameterized struct values;
# call matching needs the same representation as ordinary ModuleSG lowering.
replace_once(
    "src/4_semantics/module/parameterized/lowerer.zig",
    """            return self.addResolvedNode(node, null, .{ .struct_value_literal = .{
                .fields = .{ .start = start, .len = @intCast(fields.items.len) },
            } });
""",
    """            return self.addResolvedNode(node, null, .{ .struct_value_literal = .{
                .fields = .{ .start = start, .len = @intCast(fields.items.len) },
                .dispatch_prefix_positional_count = literal.positional_prefix_count,
            } });
""",
)

# Expected-context instantiation must be able to retag string literals after
# their ordinary StringView default has been materialized.
replace_once(
    "src/4_semantics/global/generic_functions.zig",
    """            } else if (local.resolved.content == .struct_value_literal) {
                return self.instantiateStructValueWithExpected(id, local.resolved, expected);
            }
            return self.instantiateNode(id);
""",
    """            } else if (local.resolved.content == .struct_value_literal) {
                return self.instantiateStructValueWithExpected(id, local.resolved, expected);
            } else if (local.resolved.content == .string_literal) {
                const global = try self.instantiateNode(id);
                const current = self.resolver.graph.nodes.items[@intFromEnum(global)].ty;
                if (current == null or !global_types.equal(self.resolver.graph, current.?, expected))
                    _ = self.resolver.core.coerceContextualValue(global, expected);
                return global;
            }
            return self.instantiateNode(id);
""",
)

# A parameterized code-block node may have been lowered before its final
# expression had a type. Recompute its type from the instantiated block rather
# than freezing the earlier null construction state.
replace_once(
    "src/4_semantics/global/generic_functions.zig",
    """        fn instantiateResolvedNode(self: *InstanceContext, node: ir.ResolvedNode) anyerror!global_sg.Node {
            if (node.content == .struct_value_literal) return self.instantiateStructValue(node);
            if (node.content == .binding_use or node.content == .binding_declaration) {
""",
    """        fn instantiateResolvedNode(self: *InstanceContext, node: ir.ResolvedNode) anyerror!global_sg.Node {
            if (node.content == .struct_value_literal) return self.instantiateStructValue(node);
            if (node.content == .code_block) {
                const block = try self.instantiateBlock(node.content.code_block);
                const body = self.resolver.graph.blocks.items[@intFromEnum(block)];
                const ty: ?global_sg.GlobalTypeId = if (body.ret_val) |ret_val|
                    self.resolver.graph.nodes.items[@intFromEnum(ret_val)].ty
                else
                    try self.resolver.generics.internType(.{ .builtin = .Void });
                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = ty,
                    .content = .{ .code_block = block },
                };
            }
            if (node.content == .binding_use or node.content == .binding_declaration) {
""",
)

replace_once(
    "src/4_semantics/global/generic_functions.zig",
    """            const ty = if (node.ty) |value| try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions, null) else null;
""",
    """            const ty = if (node.ty) |value|
                try self.resolver.generics.instantiateParameterizedType(self.module_index, value, self.substitutions, null)
            else if (node.content == .string_literal)
                self.resolver.core.defaultStringLiteralType()
            else
                null;
""",
)

# Untyped contextual fields are valid construction state for a struct literal.
# Publish a structural type only when every child has a real type; otherwise
# keep the parent untyped so call matching can supply the expected shape.
replace_once(
    "src/4_semantics/global/generic_functions.zig",
    """        fn instantiateStructValue(self: *InstanceContext, node: ir.ResolvedNode) !global_sg.Node {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const range = node.content.struct_value_literal.fields;
            var values: std.ArrayList(global_sg.ValueField) = .empty;
            defer values.deinit(self.resolver.allocator);
            var fields: std.ArrayList(global_sg.Field) = .empty;
            defer fields.deinit(self.resolver.allocator);
            var choice_context: ?global_sg.GlobalTypeId = null;
            for (storage.value_fields.items[range.start..][0..range.len]) |field| {
                if (!std.mem.eql(u8, self.resolver.modules[self.module_index].text(field.name), "value")) continue;
                const value = try self.instantiateNode(field.value);
                choice_context = self.resolver.graph.nodes.items[@intFromEnum(value)].ty;
                break;
            }
            for (storage.value_fields.items[range.start..][0..range.len]) |field| {
                const local = storage.nodes.items[@intFromEnum(field.value)];
                const contextual_choice = local == .pending and storage.pending.items[@intFromEnum(local.pending)] == .resolve_expression and
                    storage.pending.items[@intFromEnum(local.pending)].resolve_expression.kind == .choice_literal;
                const value = if (contextual_choice and choice_context != null)
                    try self.instantiateChoiceTag(field.value, choice_context.?)
                else
                    try self.instantiateNode(field.value);
                const name = try self.copyString(field.name);
                try values.append(self.resolver.allocator, .{ .name = name, .value = value });
                try fields.append(self.resolver.allocator, .{
                    .name = name,
                    .ty = self.resolver.graph.nodes.items[@intFromEnum(value)].ty orelse return error.MissingParameterizedValueType,
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                });
            }
            const field_start: u32 = @intCast(self.resolver.graph.fields.items.len);
            try self.resolver.graph.fields.appendSlice(self.resolver.allocator, fields.items);
            const ty: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.types.items.len)));
            try self.resolver.graph.types.append(self.resolver.allocator, .{ .structural = .{
                .fields = .{ .start = field_start, .len = @intCast(fields.items.len) },
            } });
            const start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, values.items);
            return .{ .source = self.resolver.sourceFor(self.module_index, node.source), .ty = ty, .content = .{
                .struct_value_literal = .{ .fields = .{ .start = start, .len = @intCast(values.items.len) } },
            } };
        }
""",
    """        fn instantiateStructValue(self: *InstanceContext, node: ir.ResolvedNode) !global_sg.Node {
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage.ir;
            const literal = node.content.struct_value_literal;
            const range = literal.fields;
            var values: std.ArrayList(global_sg.ValueField) = .empty;
            defer values.deinit(self.resolver.allocator);
            var fields: std.ArrayList(global_sg.Field) = .empty;
            defer fields.deinit(self.resolver.allocator);
            var complete_type = true;
            var choice_context: ?global_sg.GlobalTypeId = null;
            for (storage.value_fields.items[range.start..][0..range.len]) |field| {
                if (!std.mem.eql(u8, self.resolver.modules[self.module_index].text(field.name), "value")) continue;
                const value = try self.instantiateNode(field.value);
                choice_context = self.resolver.graph.nodes.items[@intFromEnum(value)].ty;
                break;
            }
            for (storage.value_fields.items[range.start..][0..range.len]) |field| {
                const local = storage.nodes.items[@intFromEnum(field.value)];
                const contextual_choice = local == .pending and storage.pending.items[@intFromEnum(local.pending)] == .resolve_expression and
                    storage.pending.items[@intFromEnum(local.pending)].resolve_expression.kind == .choice_literal;
                const value = if (contextual_choice and choice_context != null)
                    try self.instantiateChoiceTag(field.value, choice_context.?)
                else
                    try self.instantiateNode(field.value);
                const name = try self.copyString(field.name);
                try values.append(self.resolver.allocator, .{ .name = name, .value = value });
                if (self.resolver.graph.nodes.items[@intFromEnum(value)].ty) |field_ty| {
                    try fields.append(self.resolver.allocator, .{
                        .name = name,
                        .ty = field_ty,
                        .source = self.resolver.sourceFor(self.module_index, node.source),
                    });
                } else {
                    complete_type = false;
                }
            }
            var ty: ?global_sg.GlobalTypeId = null;
            if (complete_type) {
                const field_start: u32 = @intCast(self.resolver.graph.fields.items.len);
                try self.resolver.graph.fields.appendSlice(self.resolver.allocator, fields.items);
                const structural: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.types.items.len)));
                try self.resolver.graph.types.append(self.resolver.allocator, .{ .structural = .{
                    .fields = .{ .start = field_start, .len = @intCast(fields.items.len) },
                } });
                ty = structural;
            }
            const start: u32 = @intCast(self.resolver.graph.value_fields.items.len);
            try self.resolver.graph.value_fields.appendSlice(self.resolver.allocator, values.items);
            return .{ .source = self.resolver.sourceFor(self.module_index, node.source), .ty = ty, .content = .{
                .struct_value_literal = .{
                    .fields = .{ .start = start, .len = @intCast(values.items.len) },
                    .dispatch_prefix_positional_count = literal.dispatch_prefix_positional_count,
                },
            } };
        }
""",
)

replace_once(
    "src/4_semantics/global/generic_functions.zig",
    """                .content = .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = local_fields.len } } },
""",
    """                .content = .{ .struct_value_literal = .{
                    .fields = .{ .start = start, .len = local_fields.len },
                    .dispatch_prefix_positional_count = node.content.struct_value_literal.dispatch_prefix_positional_count,
                } },
""",
)

from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"expected anchor not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


# Parameterized IR gets the same sparse construction state as ordinary ModuleSG.
replace(
    "src/4_semantics/module/parameterized/ir.zig",
    "pub const Binding = primitives.Binding(Ids);\n",
    """pub const Binding = primitives.Binding(Ids);
/// Construction-only poison carried only by bindings listed in
/// `Storage.unresolved_binding_types`. It is never a semantic type.
pub const unresolved_binding_type_poison: ParameterizedTypeId = @enumFromInt(std.math.maxInt(u32));
""",
)
replace(
    "src/4_semantics/module/parameterized/ir.zig",
    "    bindings: std.ArrayList(Binding) = .empty,\n    nodes: std.ArrayList(Node) = .empty,\n",
    """    bindings: std.ArrayList(Binding) = .empty,
    /// Sparse construction state for bindings whose type depends on generic
    /// body resolution. Unknown is metadata, never the language `Any` type.
    unresolved_binding_types: std.ArrayList(ParameterizedBindingId) = .empty,
    nodes: std.ArrayList(Node) = .empty,
""",
)
replace(
    "src/4_semantics/module/parameterized/ir.zig",
    """    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
""",
    """    pub fn bindingType(self: *const Storage, id: ParameterizedBindingId) ?ParameterizedTypeId {
        for (self.unresolved_binding_types.items) |pending| if (pending == id) return null;
        return self.bindings.items[@intFromEnum(id)].ty;
    }

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
""",
)
replace(
    "src/4_semantics/module/parameterized/ir.zig",
    """            &self.variants,        &self.fields,             &self.generic_arguments,     &self.bindings,
            &self.nodes,           &self.blocks,             &self.value_fields,          &self.switch_cases,
""",
    """            &self.variants,        &self.fields,             &self.generic_arguments,     &self.bindings,
            &self.unresolved_binding_types,
            &self.nodes,           &self.blocks,             &self.value_fields,          &self.switch_cases,
""",
)
replace(
    "src/4_semantics/module/parameterized/ir.zig",
    """            self.bindings.items.len * @sizeOf(Binding) +
            self.nodes.items.len * @sizeOf(Node) +
""",
    """            self.bindings.items.len * @sizeOf(Binding) +
            self.unresolved_binding_types.items.len * @sizeOf(ParameterizedBindingId) +
            self.nodes.items.len * @sizeOf(Node) +
""",
)

# Match payload type is selected only after the matched choice is known.
replace(
    "src/4_semantics/module/parameterized/lowerer.zig",
    """                    try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                        .name = try self.writer.addString(name),
                        .source = self.sourceRef(case_node),
                        .ty = try self.parameterizedBuiltin(.Any),
                        .mutability = .constant,
                    });
                    try self.bindings.append(.{ .name = name, .id = binding });
""",
    """                    try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                        .name = try self.writer.addString(name),
                        .source = self.sourceRef(case_node),
                        .ty = ir.unresolved_binding_type_poison,
                        .mutability = .constant,
                    });
                    try self.graph.semantic.parameterized_storage.ir.unresolved_binding_types.append(self.allocator, binding);
                    try self.bindings.append(.{ .name = name, .id = binding });
""",
)

# Locals infer immediately only when the lowered initializer already has a real
# type. Otherwise the sparse unresolved marker owns the incomplete state.
replace(
    "src/4_semantics/module/parameterized/lowerer.zig",
    """        if (self.tree.symbolDeclaration(node)) |declaration| {
            const initialization = if (declaration.value) |value| try self.lowerBodyNode(value) else null;
            const ty = if (declaration.type_node) |value| try self.lowerType(value, false) else try self.parameterizedBuiltin(.Any);
            const name = self.tree.tokenTextFromSource(self.source, declaration.name_token);
            const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len)));
            try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                .name = try self.writer.addString(name),
                .source = self.sourceRef(node),
                .ty = ty,
                .initialization = initialization,
                .mutability = graph_mod.mutabilityFromSyntax(declaration.mutability),
            });
            try self.bindings.append(.{ .name = name, .id = binding });
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .binding_declaration = binding });
        }
""",
    """        if (self.tree.symbolDeclaration(node)) |declaration| {
            const initialization = if (declaration.value) |value| try self.lowerBodyNode(value) else null;
            const inferred_ty: ?ir.ParameterizedTypeId = if (initialization) |value|
                switch (self.graph.semantic.parameterized_storage.ir.nodes.items[@intFromEnum(value)]) {
                    .resolved => |resolved_node| resolved_node.ty,
                    .pending => null,
                }
            else
                null;
            const ty: ?ir.ParameterizedTypeId = if (declaration.type_node) |value| try self.lowerType(value, false) else inferred_ty;
            const name = self.tree.tokenTextFromSource(self.source, declaration.name_token);
            const binding: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.ir.bindings.items.len)));
            try self.graph.semantic.parameterized_storage.ir.bindings.append(self.allocator, .{
                .name = try self.writer.addString(name),
                .source = self.sourceRef(node),
                .ty = ty orelse ir.unresolved_binding_type_poison,
                .initialization = initialization,
                .mutability = graph_mod.mutabilityFromSyntax(declaration.mutability),
            });
            if (ty == null) try self.graph.semantic.parameterized_storage.ir.unresolved_binding_types.append(self.allocator, binding);
            try self.bindings.append(.{ .name = name, .id = binding });
            return self.addResolvedNode(node, try self.parameterizedBuiltin(.Void), .{ .binding_declaration = binding });
        }
""",
)
replace(
    "src/4_semantics/module/parameterized/lowerer.zig",
    """            if (self.parameterizedBinding(name)) |binding| {
                const ty = self.graph.semantic.parameterized_storage.ir.bindings.items[@intFromEnum(binding)].ty;
                return self.addResolvedNode(node, ty, .{ .binding_use = binding });
            }
""",
    """            if (self.parameterizedBinding(name)) |binding| {
                const ty = self.graph.semantic.parameterized_storage.ir.bindingType(binding);
                return self.addResolvedNode(node, ty, .{ .binding_use = binding });
            }
""",
)

# Monomorphization preserves unresolved state explicitly and never instantiates
# the poison as if it were a type.
replace(
    "src/4_semantics/global/generic_functions.zig",
    """            const module = &self.resolver.modules[self.module_index];
            const source = module.semantic.parameterized_storage.ir.bindings.items[@intFromEnum(id)];
            const global: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.bindings.items.len)));
            try self.resolver.graph.bindings.append(self.resolver.allocator, .{
                .name = try self.resolver.graph.addString(self.resolver.allocator, module.text(source.name)),
                .source = self.resolver.sourceFor(self.module_index, source.source),
                .ty = try self.resolver.generics.instantiateParameterizedType(self.module_index, source.ty, self.substitutions, null),
                .initialization = null,
                .mutability = source.mutability,
            });
            self.binding_map[@intFromEnum(id)] = global;
            if (source.initialization) |node| {
                const initialization = try self.instantiateNodeAs(node, source.ty);
                self.resolver.graph.bindings.items[@intFromEnum(global)].initialization = initialization;
                const binding = &self.resolver.graph.bindings.items[@intFromEnum(global)];
                if (global_types.isBuiltin(self.resolver.graph, binding.ty, .Any)) {
                    binding.ty = self.resolver.graph.nodes.items[@intFromEnum(initialization)].ty orelse binding.ty;
                }
            }
            return global;
""",
    """            const module = &self.resolver.modules[self.module_index];
            const storage = &module.semantic.parameterized_storage.ir;
            const source = storage.bindings.items[@intFromEnum(id)];
            const source_ty = storage.bindingType(id);
            const global: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.resolver.graph.bindings.items.len)));
            try self.resolver.graph.bindings.append(self.resolver.allocator, .{
                .name = try self.resolver.graph.addString(self.resolver.allocator, module.text(source.name)),
                .source = self.resolver.sourceFor(self.module_index, source.source),
                .ty = if (source_ty) |ty|
                    try self.resolver.generics.instantiateParameterizedType(self.module_index, ty, self.substitutions, null)
                else
                    @enumFromInt(0),
                .initialization = null,
                .mutability = source.mutability,
            });
            self.binding_map[@intFromEnum(id)] = global;
            if (source_ty == null) try self.resolver.graph.markBindingTypeUnresolved(self.resolver.allocator, global);
            if (source.initialization) |node| {
                const initialization = if (source_ty) |ty|
                    try self.instantiateNodeAs(node, ty)
                else
                    try self.instantiateNode(node);
                self.resolver.graph.bindings.items[@intFromEnum(global)].initialization = initialization;
                if (source_ty == null) {
                    if (self.resolver.graph.nodes.items[@intFromEnum(initialization)].ty) |inferred| {
                        if (!self.resolver.graph.isTypeUnresolved(inferred)) {
                            self.resolver.graph.bindings.items[@intFromEnum(global)].ty = inferred;
                            _ = self.resolver.graph.reconcileBindingTypeResolution();
                        }
                    }
                }
            }
            return global;
""",
)

replace(
    "src/4_semantics/global/generic_functions.zig",
    """                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = self.resolver.graph.bindings.items[@intFromEnum(binding)].ty,
                    .content = if (declaration) .{ .binding_declaration = binding } else .{ .binding_use = binding },
                };
""",
    """                return .{
                    .source = self.resolver.sourceFor(self.module_index, node.source),
                    .ty = if (self.resolver.graph.isBindingTypeUnresolved(binding)) null else self.resolver.graph.bindings.items[@intFromEnum(binding)].ty,
                    .content = if (declaration) .{ .binding_declaration = binding } else .{ .binding_use = binding },
                };
""",
)

replace(
    "src/4_semantics/global/generic_functions.zig",
    """                    .assignment => |assignment| .{ .assignment = .{
                        .binding = try self.instantiateBinding(assignment.binding),
                        .value = try self.instantiateNodeAs(assignment.value, self.resolver.modules[self.module_index].semantic.parameterized_storage.ir.bindings.items[@intFromEnum(assignment.binding)].ty),
                    } },
""",
    """                    .assignment => |assignment| .{ .assignment = .{
                        .binding = try self.instantiateBinding(assignment.binding),
                        .value = if (self.resolver.modules[self.module_index].semantic.parameterized_storage.ir.bindingType(assignment.binding)) |binding_ty|
                            try self.instantiateNodeAs(assignment.value, binding_ty)
                        else
                            try self.instantiateNode(assignment.value),
                    } },
""",
)

replace(
    "src/4_semantics/global/generic_functions.zig",
    """                    const binding = try self.instantiateBinding(local_binding);
                    self.resolver.graph.bindings.items[@intFromEnum(binding)].ty = try self.matchBindingType(payload, case.mode);
                }
                const body = try self.instantiateBlock(case.body);
""",
    """                    const binding = try self.instantiateBinding(local_binding);
                    self.resolver.graph.bindings.items[@intFromEnum(binding)].ty = try self.matchBindingType(payload, case.mode);
                    _ = self.resolver.graph.reconcileBindingTypeResolution();
                }
                const body = try self.instantiateBlock(case.body);
""",
)

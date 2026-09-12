from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    assert old in text, f"missing anchor in {path}: {old[:80]!r}"
    p.write_text(text.replace(old, new, 1))


# Module construction state: unknown binding types are explicit, never Any.
replace_once(
    'src/4_semantics/module/entities.zig',
    'pub const PendingOperationId = enum(u32) { _ };\n',
    'pub const PendingOperationId = enum(u32) { _ };\n\n/// Construction-only poison carried only by bindings listed in\n/// `Storage.unresolved_binding_types`. It is never a language type.\npub const unresolved_binding_type_poison: ModuleTypeId = @enumFromInt(std.math.maxInt(u32));\n',
)

replace_once(
    'src/4_semantics/module/storage.zig',
    '    bindings: std.ArrayList(entities.Binding) = .empty,\n',
    '    bindings: std.ArrayList(entities.Binding) = .empty,\n    /// Sparse construction state: bindings whose semantic type is not known\n    /// until GlobalSema resolves an initializer/control-flow dependency.\n    unresolved_binding_types: std.ArrayList(entities.ModuleBindingId) = .empty,\n',
)
replace_once(
    'src/4_semantics/module/storage.zig',
    '        self.bindings.deinit(allocator);\n',
    '        self.bindings.deinit(allocator);\n        self.unresolved_binding_types.deinit(allocator);\n',
)
replace_once(
    'src/4_semantics/module/storage.zig',
    '            self.bindings.items.len * @sizeOf(entities.Binding) +\n',
    '            self.bindings.items.len * @sizeOf(entities.Binding) +\n            self.unresolved_binding_types.items.len * @sizeOf(entities.ModuleBindingId) +\n',
)

replace_once(
    'src/4_semantics/module/views.zig',
    'pub fn genericArgumentCount(graph: *const graph_mod.ModuleSemanticGraph) usize {\n    return graph.generic_type_arguments.items.len + graph.semantic.generic_arguments.items.len;\n}\n',
    'pub fn genericArgumentCount(graph: *const graph_mod.ModuleSemanticGraph) usize {\n    return graph.generic_type_arguments.items.len + graph.semantic.generic_arguments.items.len;\n}\n\npub fn bindingTypeUnresolved(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleBindingId) bool {\n    for (graph.semantic.unresolved_binding_types.items) |candidate|\n        if (candidate == id) return true;\n    return false;\n}\n',
)

replace_once(
    'src/4_semantics/module/writer.zig',
    'const strings = @import("../primitives/strings.zig");\n',
    'const strings = @import("../primitives/strings.zig");\nconst primitives = @import("../primitives/schema.zig");\n',
)
replace_once(
    'src/4_semantics/module/writer.zig',
    '''    pub fn addBinding(self: *Writer, binding: entities.Binding) !entities.ModuleBindingId {
        const id = try directId(entities.ModuleBindingId, self.graph.semantic.bindings.items.len);
        try self.graph.semantic.bindings.append(self.allocator, binding);
        return id;
    }
''',
    '''    pub fn addBinding(self: *Writer, binding: entities.Binding) !entities.ModuleBindingId {
        const id = try directId(entities.ModuleBindingId, self.graph.semantic.bindings.items.len);
        try self.graph.semantic.bindings.append(self.allocator, binding);
        return id;
    }

    pub fn addUnresolvedBinding(
        self: *Writer,
        name: primitives.StringRange,
        source: primitives.SourceRef,
        initialization: ?entities.ModuleNodeId,
        mutability: primitives.Mutability,
    ) !entities.ModuleBindingId {
        const id = try directId(entities.ModuleBindingId, self.graph.semantic.bindings.items.len);
        const old_len = self.graph.semantic.bindings.items.len;
        errdefer self.graph.semantic.bindings.shrinkRetainingCapacity(old_len);
        try self.graph.semantic.bindings.append(self.allocator, .{
            .name = name,
            .source = source,
            .ty = entities.unresolved_binding_type_poison,
            .initialization = initialization,
            .mutability = mutability,
        });
        try self.graph.semantic.unresolved_binding_types.append(self.allocator, id);
        return id;
    }
''',
)

# Body lowering marks only bindings whose type really depends on later semantics.
p = Path('src/4_semantics/module/body_lowerer.zig')
text = p.read_text()
old = '''        const stored_ty = try self.compatibilityType(semantic_ty);
        const name_text = self.tree.tokenTextFromSource(self.source, declaration.name_token);
        const binding = try self.writer.addBinding(.{
            .name = try self.writer.addString(name_text),
            .source = self.sourceRef(node),
            .ty = stored_ty,
            .initialization = if (value) |item| item.node else null,
            .mutability = graph_mod.mutabilityFromSyntax(declaration.mutability),
        });'''
new = '''        const name_text = self.tree.tokenTextFromSource(self.source, declaration.name_token);
        const name_range = try self.writer.addString(name_text);
        const source = self.sourceRef(node);
        const initialization = if (value) |item| item.node else null;
        const mutability = graph_mod.mutabilityFromSyntax(declaration.mutability);
        const binding = if (semantic_ty) |stored_ty|
            try self.writer.addBinding(.{
                .name = name_range,
                .source = source,
                .ty = stored_ty,
                .initialization = initialization,
                .mutability = mutability,
            })
        else
            try self.writer.addUnresolvedBinding(name_range, source, initialization, mutability);'''
assert old in text
text = text.replace(old, new, 1)
old = '''        const binding = try self.writer.addBinding(.{
            .name = try self.writer.addString(name_text),
            .source = self.sourceRef(node),
            .ty = try self.builtin(.Any),
            .mutability = if (statement.mode == .mut_borrow) .variable else .constant,
        });'''
new = '''        const binding = try self.writer.addUnresolvedBinding(
            try self.writer.addString(name_text),
            self.sourceRef(node),
            null,
            if (statement.mode == .mut_borrow) .variable else .constant,
        );'''
assert old in text
text = text.replace(old, new, 1)
old = '''                const id = try self.writer.addBinding(.{
                    .name = try self.writer.addString(text),
                    .source = self.sourceRef(case_node),
                    .ty = try self.builtin(.Any),
                    .mutability = if (case.mode == .mut_borrow) .variable else .constant,
                });'''
new = '''                const id = try self.writer.addUnresolvedBinding(
                    try self.writer.addString(text),
                    self.sourceRef(case_node),
                    null,
                    if (case.mode == .mut_borrow) .variable else .constant,
                );'''
assert old in text
text = text.replace(old, new, 1)
old = '''                .name = declaration.name,
                .id = relation.binding,
                .ty = binding.ty,
'''
new = '''                .name = declaration.name,
                .id = relation.binding,
                .ty = if (views.bindingTypeUnresolved(self.graph, relation.binding)) null else binding.ty,
'''
assert old in text
text = text.replace(old, new, 1)
p.write_text(text)

# Module verifier understands the sparse construction state without accepting a
# semantically valid type as a sentinel.
p = Path('src/4_semantics/module/verify.zig')
text = p.read_text()
old = '    for (semantic.bindings.items) |value| try payload.binding(entities.Ids, value, bounds);\n'
new = '''    for (semantic.unresolved_binding_types.items, 0..) |id, index| {
        try require(verify.idFits(id, semantic.bindings.items.len));
        for (semantic.unresolved_binding_types.items[0..index]) |previous| try require(previous != id);
        try require(semantic.bindings.items[@intFromEnum(id)].ty == entities.unresolved_binding_type_poison);
    }
    for (semantic.bindings.items, 0..) |value, raw| {
        const id: entities.ModuleBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        if (views.bindingTypeUnresolved(graph, id)) {
            try require(verify.stringFits(value.name, graph.strings.items));
            try require(verify.sourceFits(value.source, graph.file_offsets.items.len));
            try require(verify.optionalIdFits(value.initialization, semantic.nodes.items.len));
        } else try payload.binding(entities.Ids, value, bounds);
    }
'''
assert old in text
p.write_text(text.replace(old, new, 1))

# Global construction state mirrors the module marker and uses an invalid poison
# ID that cannot be mistaken for Any or another real semantic type.
p = Path('src/4_semantics/global/graph.zig')
text = p.read_text()
old = 'const unresolved_type_poison_decl: GlobalDeclId = @enumFromInt(std.math.maxInt(u32));\n'
new = '''const unresolved_type_poison_decl: GlobalDeclId = @enumFromInt(std.math.maxInt(u32));
const unresolved_binding_type_poison: GlobalTypeId = @enumFromInt(std.math.maxInt(u32));
'''
assert old in text
text = text.replace(old, new, 1)
old = '    bindings: std.ArrayList(Binding) = .empty,\n'
new = '''    bindings: std.ArrayList(Binding) = .empty,
    /// Present only while GlobalSema is inferring bindings whose type was not
    /// available in ModuleSema. Final graphs always leave this list empty.
    binding_type_resolution: std.ArrayList(TypeResolutionState) = .empty,
'''
assert old in text
text = text.replace(old, new, 1)
old = '            &self.functions,             &self.function_operators,    &self.generic_function_instances, &self.bindings,\n'
new = '            &self.functions,             &self.function_operators,    &self.generic_function_instances, &self.bindings,\n            &self.binding_type_resolution,\n'
assert old in text
text = text.replace(old, new, 1)
anchor = '''    pub fn binding(self: *const GlobalSemanticGraph, id: GlobalBindingId) Binding {
        return self.bindings.items[@intFromEnum(id)];
    }
'''
addition = anchor + '''
    pub fn isBindingTypeUnresolved(self: *const GlobalSemanticGraph, id: GlobalBindingId) bool {
        const raw: usize = @intFromEnum(id);
        return raw < self.binding_type_resolution.items.len and self.binding_type_resolution.items[raw] == .unresolved;
    }

    pub fn markBindingTypeUnresolved(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, id: GlobalBindingId) !void {
        const raw: usize = @intFromEnum(id);
        if (raw >= self.bindings.items.len) return error.InvalidGlobalBindingId;
        try self.ensureBindingTypeResolutionCovers(allocator, self.bindings.items.len);
        self.binding_type_resolution.items[raw] = .unresolved;
        self.bindings.items[raw].ty = unresolved_binding_type_poison;
    }

    pub fn reconcileBindingTypeResolution(self: *GlobalSemanticGraph) bool {
        var changed = false;
        const limit = @min(self.binding_type_resolution.items.len, self.bindings.items.len);
        for (self.binding_type_resolution.items[0..limit], 0..) |*state, raw| {
            if (state.* != .unresolved or self.bindings.items[raw].ty == unresolved_binding_type_poison) continue;
            state.* = .resolved;
            changed = true;
        }
        return changed;
    }

    pub fn hasUnresolvedBindingTypes(self: *const GlobalSemanticGraph) bool {
        for (self.binding_type_resolution.items) |state| if (state == .unresolved) return true;
        return false;
    }

    pub fn finishBindingTypeResolution(self: *GlobalSemanticGraph, allocator: std.mem.Allocator) !void {
        if (self.hasUnresolvedBindingTypes()) return error.UnresolvedGlobalBindingTypes;
        self.binding_type_resolution.deinit(allocator);
        self.binding_type_resolution = .empty;
    }

    fn ensureBindingTypeResolutionCovers(self: *GlobalSemanticGraph, allocator: std.mem.Allocator, count: usize) !void {
        if (self.binding_type_resolution.items.len >= count) return;
        try self.binding_type_resolution.ensureTotalCapacity(allocator, count);
        while (self.binding_type_resolution.items.len < count) self.binding_type_resolution.appendAssumeCapacity(.resolved);
    }
'''
assert anchor in text
text = text.replace(anchor, addition, 1)
old = '            self.bindings.items.len * @sizeOf(Binding) +\n'
new = '            self.bindings.items.len * @sizeOf(Binding) +\n            self.binding_type_resolution.items.len * @sizeOf(TypeResolutionState) +\n'
assert old in text
text = text.replace(old, new, 1)
p.write_text(text)

# Globalization transfers the explicit unresolved marker; strict globalization
# refuses it, while GlobalSema mode records construction state.
p = Path('src/4_semantics/global/globalizer.zig')
text = p.read_text()
old = '''    if (semantic.parameterized_storage.storageBytes() != 0) return error.ModuleParameterizedSemanticsNotConsumed;
'''
new = '''    if (semantic.parameterized_storage.storageBytes() != 0) return error.ModuleParameterizedSemanticsNotConsumed;
    if (semantic.unresolved_binding_types.items.len != 0) return error.UnresolvedModuleSemantics;
'''
assert old in text
text = text.replace(old, new, 1)
old = '''    for (storage.bindings.items) |value| try result.bindings.append(allocator, .{
        .name = try relocateString(module, value.name, o.string_base),
        .source = globalSource(o, value.source),
        .ty = globalType(o, value.ty),
        .initialization = if (value.initialization) |id| globalNode(o, id) else null,
        .mutability = value.mutability,
    });'''
new = '''    for (storage.bindings.items, 0..) |value, raw| {
        const local_id: module_entities.ModuleBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        const unresolved = module_views.bindingTypeUnresolved(module, local_id);
        if (unresolved and mode == .strict) return error.UnresolvedModuleSemantics;
        const global_id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(result.bindings.items.len)));
        try result.bindings.append(allocator, .{
            .name = try relocateString(module, value.name, o.string_base),
            .source = globalSource(o, value.source),
            .ty = if (unresolved) @enumFromInt(0) else globalType(o, value.ty),
            .initialization = if (value.initialization) |id| globalNode(o, id) else null,
            .mutability = value.mutability,
        });
        if (unresolved) try result.markBindingTypeUnresolved(allocator, global_id);
    }'''
assert old in text
p.write_text(text.replace(old, new, 1))

# Resolvers never read the poison. Uses/assignments wait until their binding type
# owner has resolved the binding.
p = Path('src/4_semantics/global/expressions.zig')
text = p.read_text()
old = '        const target = globalizer.globalNode(o, value.node);\n        const source = self.graph.nodes.items[@intFromEnum(target)].source;\n        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;\n'
new = '        if (self.graph.isBindingTypeUnresolved(binding)) return false;\n        const target = globalizer.globalNode(o, value.node);\n        const source = self.graph.nodes.items[@intFromEnum(target)].source;\n        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;\n'
assert text.count(old) == 1
text = text.replace(old, new, 1)
old2 = '        const target = globalizer.globalNode(o, node);\n        const source = self.graph.nodes.items[@intFromEnum(target)].source;\n        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;\n'
new2 = '        if (self.graph.isBindingTypeUnresolved(binding)) return false;\n        const target = globalizer.globalNode(o, node);\n        const source = self.graph.nodes.items[@intFromEnum(target)].source;\n        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;\n'
assert old2 in text
p.write_text(text.replace(old2, new2, 1))

# Binding inference now keys exclusively off construction metadata, not Any.
p = Path('src/4_semantics/global/core.zig')
text = p.read_text()
old = '''        for (self.graph.bindings.items) |*binding| {
            if (!types.isBuiltin(self.graph, binding.ty, .Any)) continue;
            const initialization = binding.initialization orelse continue;
            const inferred = self.graph.nodes.items[@intFromEnum(initialization)].ty orelse continue;
            if (types.isBuiltin(self.graph, inferred, .Any)) continue;
            binding.ty = inferred;
            self.stats.binding_types += 1;
            changed = true;
        }
'''
new = '''        for (self.graph.bindings.items, 0..) |*binding, raw| {
            const id: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(raw)));
            if (!self.graph.isBindingTypeUnresolved(id)) continue;
            const initialization = binding.initialization orelse continue;
            const inferred = self.graph.nodes.items[@intFromEnum(initialization)].ty orelse continue;
            if (self.graph.isTypeUnresolved(inferred)) continue;
            binding.ty = inferred;
            self.stats.binding_types += 1;
            changed = true;
        }
'''
assert old in text
text = text.replace(old, new, 1)
old = '''            .binding_use => |binding_id| {
                const inferred = self.graph.bindings.items[@intFromEnum(binding_id)].ty;
'''
new = '''            .binding_use => |binding_id| {
                if (self.graph.isBindingTypeUnresolved(binding_id)) continue;
                const inferred = self.graph.bindings.items[@intFromEnum(binding_id)].ty;
'''
assert old in text
p.write_text(text.replace(old, new, 1))

# Fixed-point bookkeeping resolves direct writes made by control/other owners and
# strips construction metadata before exposing the final graph.
p = Path('src/4_semantics/global/semantizer.zig')
text = p.read_text()
old = '''        if (relocation.graph.reconcileTypeResolution()) changed = true;
        if (core.materializeBindingTypes()) changed = true;
'''
new = '''        if (relocation.graph.reconcileTypeResolution()) changed = true;
        if (relocation.graph.reconcileBindingTypeResolution()) changed = true;
        if (core.materializeBindingTypes()) changed = true;
'''
assert old in text
text = text.replace(old, new, 1)
old = '''    _ = relocation.graph.reconcileTypeResolution();
    if (relocation.graph.hasUnresolvedTypes()) {
        std.debug.print("global sema unresolved global type slots remain\\n", .{});
        return error.UnsupportedGlobalSemantic;
    }

    // Construction-only resolution metadata must disappear before the graph is
    // exposed to Safety, Codegen or editor consumers.
    try relocation.graph.finishTypeResolution(allocator);
'''
new = '''    _ = relocation.graph.reconcileTypeResolution();
    _ = relocation.graph.reconcileBindingTypeResolution();
    if (relocation.graph.hasUnresolvedTypes()) {
        std.debug.print("global sema unresolved global type slots remain\\n", .{});
        return error.UnsupportedGlobalSemantic;
    }
    if (relocation.graph.hasUnresolvedBindingTypes()) {
        std.debug.print("global sema unresolved binding types remain\\n", .{});
        return error.UnsupportedGlobalSemantic;
    }

    // Construction-only resolution metadata must disappear before the graph is
    // exposed to Safety, Codegen or editor consumers.
    try relocation.graph.finishTypeResolution(allocator);
    try relocation.graph.finishBindingTypeResolution(allocator);
'''
assert old in text
p.write_text(text.replace(old, new, 1))

# Final graph verifier rejects leaked construction metadata.
p = Path('src/4_semantics/global/verify.zig')
text = p.read_text()
old = '''pub fn verifyGlobal(graph: *const graph_mod.GlobalSemanticGraph) !void {
    const bounds = makeBounds(graph);
'''
new = '''pub fn verifyGlobal(graph: *const graph_mod.GlobalSemanticGraph) !void {
    try require(graph.type_resolution.items.len == 0);
    try require(graph.binding_type_resolution.items.len == 0);
    const bounds = makeBounds(graph);
'''
assert old in text
p.write_text(text.replace(old, new, 1))

print('binding type construction state is explicit')

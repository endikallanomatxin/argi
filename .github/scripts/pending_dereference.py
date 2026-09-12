from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    assert old in text, f"missing anchor in {path}: {old[:100]!r}"
    p.write_text(text.replace(old, new, 1))


# A dereference whose pointer type is not locally known is semantic construction
# state. Do not encode that state as the valid language type Any.
replace_once(
    'src/4_semantics/module/entities.zig',
    '''    resolve_index: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        index: ModuleNodeId,
        store_value: ?ModuleNodeId = null,
    },
''',
    '''    resolve_index: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        index: ModuleNodeId,
        store_value: ?ModuleNodeId = null,
    },
    resolve_dereference: struct {
        node: ModuleNodeId,
        pointer: ModuleNodeId,
    },
''',
)

replace_once(
    'src/4_semantics/module/body_lowerer.zig',
    '''    fn lowerDereference(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const value = try self.lowerNode(self.tree.unaryOperand(node).?, null);
        const pointer_ty = try self.compatibilityType(value.ty);
        const child_ty = if (value.ty) |known| try self.pointerChild(known) else null;
        const ty = child_ty orelse expected orelse try self.builtin(.Any);
        return self.resolved(node, ty, .{ .dereference = .{ .pointer = value.node, .ty = ty, .pointer_type = pointer_ty } });
    }
''',
    '''    fn lowerDereference(self: *Context, node: syn.NodeIndex, expected: ?entities.ModuleTypeId) !Lowered {
        const value = try self.lowerNode(self.tree.unaryOperand(node).?, null);
        if (value.ty) |pointer_ty| {
            if (try self.pointerChild(pointer_ty)) |child_ty| {
                return self.resolved(node, child_ty, .{ .dereference = .{
                    .pointer = value.node,
                    .ty = child_ty,
                    .pointer_type = pointer_ty,
                } });
            }
        }
        return self.pending(node, .{ .resolve_dereference = .{
            .node = self.nextNodeId(),
            .pointer = value.node,
        } }, expected);
    }
''',
)

replace_once(
    'src/4_semantics/module/verify.zig',
    '''        .resolve_index => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
            try require(verify.idFits(value.index, semantic.nodes.items.len));
            try require(verify.optionalIdFits(value.store_value, semantic.nodes.items.len));
        },
''',
    '''        .resolve_index => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
            try require(verify.idFits(value.index, semantic.nodes.items.len));
            try require(verify.optionalIdFits(value.store_value, semantic.nodes.items.len));
        },
        .resolve_dereference => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.pointer, semantic.nodes.items.len));
        },
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
    '''            .resolve_index => |value| try self.resolveIndex(module_index, o, value),
            else => .not_applicable,
''',
    '''            .resolve_index => |value| try self.resolveIndex(module_index, o, value),
            .resolve_dereference => |value| try self.resolveDereference(o, value),
            else => .not_applicable,
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
    '''    fn resolveBinary(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
''',
    '''    fn resolveDereference(self: *Resolver, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const pointer = globalizer.globalNode(o, value.pointer);
        const pointer_type = self.graph.nodes.items[@intFromEnum(pointer)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(pointer_type)) return .deferred;
        const child = switch (self.graph.types.items[@intFromEnum(pointer_type)]) {
            .pointer => |pointer_value| pointer_value.child,
            else => return .deferred,
        };
        if (self.graph.isTypeUnresolved(child)) return .deferred;
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(pointer)].source,
            .ty = child,
            .content = .{ .dereference = .{
                .pointer = pointer,
                .ty = child,
                .pointer_type = pointer_type,
            } },
        };
        self.stats.dereferences += 1;
        return .resolved;
    }

    fn resolveBinary(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
''',
)

replace_once(
    'src/4_semantics/global/semantizer.zig',
    '''        .resolve_index,
        .resolve_name_use,
''',
    '''        .resolve_index,
        .resolve_dereference,
        .resolve_name_use,
''',
)

replace_once(
    'src/4_semantics/global/semantizer.zig',
    '''        .resolve_field,
        .resolve_binary,
        .resolve_comparison,
        => try core.tryResolve(module_index, module, o, operation),
''',
    '''        .resolve_field,
        .resolve_binary,
        .resolve_comparison,
        .resolve_dereference,
        => try core.tryResolve(module_index, module, o, operation),
''',
)

print('unknown dereferences are explicit pending operations')

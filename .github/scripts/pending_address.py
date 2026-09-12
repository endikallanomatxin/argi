from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    assert old in text, f"missing anchor in {path}: {old[:120]!r}"
    p.write_text(text.replace(old, new, 1))


replace_once(
    'src/4_semantics/module/entities.zig',
    '''    resolve_dereference: struct {
        node: ModuleNodeId,
        pointer: ModuleNodeId,
    },
''',
    '''    resolve_dereference: struct {
        node: ModuleNodeId,
        pointer: ModuleNodeId,
    },
    resolve_address: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        mutability: primitives.PointerMutability,
    },
''',
)

replace_once(
    'src/4_semantics/module/body_lowerer.zig',
    '''    fn lowerAddress(self: *Context, node: syn.NodeIndex) !Lowered {
        const address = self.tree.addressOf(node).?;
        const value = try self.lowerNode(address.value, null);
        const child_ty = try self.compatibilityType(value.ty);
        const ty = try self.writer.addResolvedType(.{ .pointer = .{ .child = child_ty, .mutability = graph_mod.pointerMutabilityFromSyntax(address.mutability) } });
        return self.resolved(node, ty, .{ .address_of = value.node });
    }
''',
    '''    fn lowerAddress(self: *Context, node: syn.NodeIndex) !Lowered {
        const address = self.tree.addressOf(node).?;
        const value = try self.lowerNode(address.value, null);
        const mutability = graph_mod.pointerMutabilityFromSyntax(address.mutability);
        if (value.ty) |child_ty| {
            const ty = try self.writer.addResolvedType(.{ .pointer = .{ .child = child_ty, .mutability = mutability } });
            return self.resolved(node, ty, .{ .address_of = value.node });
        }
        return self.pending(node, .{ .resolve_address = .{
            .node = self.nextNodeId(),
            .value = value.node,
            .mutability = mutability,
        } }, null);
    }
''',
)

replace_once(
    'src/4_semantics/module/verify.zig',
    '''        .resolve_dereference => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.pointer, semantic.nodes.items.len));
        },
''',
    '''        .resolve_dereference => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.pointer, semantic.nodes.items.len));
        },
        .resolve_address => |value| {
            try require(verify.idFits(value.node, semantic.nodes.items.len));
            try require(verify.idFits(value.value, semantic.nodes.items.len));
        },
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
    '''            .resolve_index => |value| try self.resolveIndex(module_index, o, value),
            .resolve_dereference => |value| try self.resolveDereference(o, value),
            else => .not_applicable,
''',
    '''            .resolve_index => |value| try self.resolveIndex(module_index, o, value),
            .resolve_dereference => |value| try self.resolveDereference(o, value),
            .resolve_address => |value| try self.resolveAddress(o, value),
            else => .not_applicable,
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
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

    fn resolveAddress(self: *Resolver, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const child_node = globalizer.globalNode(o, value.value);
        const child = self.graph.nodes.items[@intFromEnum(child_node)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(child)) return .deferred;
        const pointer_type = try self.pointerType(child, value.mutability);
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(child_node)].source,
            .ty = pointer_type,
            .content = .{ .address_of = child_node },
        };
        return .resolved;
    }
''',
)

replace_once(
    'src/4_semantics/global/semantizer.zig',
    '''        .resolve_index,
        .resolve_dereference,
        .resolve_name_use,
''',
    '''        .resolve_index,
        .resolve_dereference,
        .resolve_address,
        .resolve_name_use,
''',
)

replace_once(
    'src/4_semantics/global/semantizer.zig',
    '''        .resolve_comparison,
        .resolve_dereference,
        => try core.tryResolve(module_index, module, o, operation),
''',
    '''        .resolve_comparison,
        .resolve_dereference,
        .resolve_address,
        => try core.tryResolve(module_index, module, o, operation),
''',
)

print('unknown address-of expressions are explicit pending operations')

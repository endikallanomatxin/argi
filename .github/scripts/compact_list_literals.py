from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    assert old in text, f"missing anchor in {path}: {old[:140]!r}"
    p.write_text(text.replace(old, new, 1))


replace_once(
    'src/4_semantics/primitives/schema.zig',
    '''            list_literal: struct {
                elements: Range(Ids.NodeId),
                element_types: Range(Ids.TypeId),
            },
''',
    '''            list_literal: struct {
                elements: Range(Ids.NodeId),
            },
''',
)

replace_once(
    'src/4_semantics/module/body_lowerer.zig',
    '''    fn lowerList(self: *Context, node: syn.NodeIndex) !Lowered {
        const list = self.tree.listLiteral(node).?;
        var nodes = std.array_list.Managed(entities.ModuleNodeId).init(self.allocator);
        defer nodes.deinit();
        var types = std.array_list.Managed(entities.ModuleTypeId).init(self.allocator);
        defer types.deinit();
        for (list.elements) |child| {
            const value = try self.lowerNode(child, null);
            try nodes.append(value.node);
            try types.append(try self.compatibilityType(value.ty));
        }
        return self.resolved(node, try self.builtin(.Any), .{ .list_literal = .{
            .elements = try self.writer.appendNodeRefs(nodes.items),
            .element_types = try self.writer.appendTypeRefs(types.items),
        } });
    }
''',
    '''    fn lowerList(self: *Context, node: syn.NodeIndex) !Lowered {
        const list = self.tree.listLiteral(node).?;
        var nodes = std.array_list.Managed(entities.ModuleNodeId).init(self.allocator);
        defer nodes.deinit();
        for (list.elements) |child| {
            const value = try self.lowerNode(child, null);
            try nodes.append(value.node);
        }
        return self.resolved(node, null, .{ .list_literal = .{
            .elements = try self.writer.appendNodeRefs(nodes.items),
        } });
    }
''',
)

# The only remaining caller was list lowering. Unknown semantic state must never
# be materialized as the valid language type Any.
p = Path('src/4_semantics/module/body_lowerer.zig')
text = p.read_text()
helper = '''    /// Temporary boundary for semantic payloads that still require a concrete
    /// ModuleTypeId during local lowering. Unknown expression types themselves
    /// are represented as `null`; every remaining `Any` introduced here is a
    /// compatibility bridge to be removed as those payloads become pending-aware.
    fn compatibilityType(self: *Context, ty: ?entities.ModuleTypeId) !entities.ModuleTypeId {
        return ty orelse self.builtin(.Any);
    }

'''
if helper in text:
    text = text.replace(helper, '', 1)
p.write_text(text)
assert 'compatibilityType(' not in text

replace_once(
    'src/4_semantics/semantic_payload_verify.zig',
    '''        .list_literal => |item| {
            try require(verify.rangeFits(item.elements, bounds.node_refs));
            try require(verify.rangeFits(item.element_types, bounds.type_refs));
        },
''',
    '''        .list_literal => |item| {
            try require(verify.rangeFits(item.elements, bounds.node_refs));
        },
''',
)

replace_once(
    'src/4_semantics/global/globalizer.zig',
    '''            .list_literal => |value| .{ .list_literal = .{
                .elements = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.elements),
                .element_types = relocatePoolRange(global_sg.GlobalTypeId, o.type_ref_base, value.element_types),
            } },
''',
    '''            .list_literal => |value| .{ .list_literal = .{
                .elements = relocatePoolRange(global_sg.GlobalNodeId, o.node_ref_base, value.elements),
            } },
''',
)

replace_once(
    'src/5_codegen/global_codegen.zig',
    '''    fn listLiteral(self: *CodeGenerator, literal: anytype, ty: ?graph_mod.GlobalTypeId) !TypedValue {
        const element_types = self.graph.type_refs.items[literal.element_types.start..][0..literal.element_types.len];
        const llvm_fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, element_types.len);
        defer self.allocator.free(llvm_fields);
        for (element_types, 0..) |element, index| llvm_fields[index] = try self.toLLVMType(element);
        const type_ref = c.LLVMStructType(if (llvm_fields.len == 0) null else llvm_fields.ptr, @intCast(llvm_fields.len), 0);
        var aggregate = c.LLVMGetUndef(type_ref);
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len], 0..) |node, index| {
            const value = (try self.visitNode(node)) orelse return CodegenError.ValueNotFound;
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, @intCast(index), "list.elem");
        }
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = ty };
    }
''',
    '''    fn listLiteral(self: *CodeGenerator, literal: anytype, ty: ?graph_mod.GlobalTypeId) !TypedValue {
        const elements = self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len];
        const values = try self.allocator.alloc(TypedValue, elements.len);
        defer self.allocator.free(values);
        const llvm_fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, elements.len);
        defer self.allocator.free(llvm_fields);
        for (elements, 0..) |node, index| {
            values[index] = (try self.visitNode(node)) orelse return CodegenError.ValueNotFound;
            llvm_fields[index] = values[index].type_ref;
        }
        const type_ref = c.LLVMStructType(if (llvm_fields.len == 0) null else llvm_fields.ptr, @intCast(llvm_fields.len), 0);
        var aggregate = c.LLVMGetUndef(type_ref);
        for (values, 0..) |value, index|
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, @intCast(index), "list.elem");
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = ty };
    }
''',
)

print('list literals no longer duplicate or invent element types')

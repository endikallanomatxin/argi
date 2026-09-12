from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    assert old in text, f"missing anchor in {path}: {old[:160]!r}"
    p.write_text(text.replace(old, new, 1))


replace_once(
    'src/4_semantics/primitives/schema.zig',
    '''            struct_value_literal: struct {
                fields: Range(Ids.ValueFieldId),
                ty: Ids.TypeId,
                dispatch_prefix_positional_count: u32 = 0,
            },
''',
    '''            struct_value_literal: struct {
                fields: Range(Ids.ValueFieldId),
                dispatch_prefix_positional_count: u32 = 0,
            },
''',
)

replace_once(
    'src/4_semantics/module/body_lowerer.zig',
    '''        const ty = try self.builtin(.Any);
        return self.resolved(node, ty, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(literal.fields.len) },
            .ty = ty,
            .dispatch_prefix_positional_count = literal.positional_prefix_count,
        } });
''',
    '''        return self.resolved(node, null, .{ .struct_value_literal = .{
            .fields = .{ .start = start, .len = @intCast(literal.fields.len) },
            .dispatch_prefix_positional_count = literal.positional_prefix_count,
        } });
''',
)

replace_once(
    'src/4_semantics/semantic_payload_verify.zig',
    '''        .struct_value_literal => |item| {
            try require(verify.rangeFits(item.fields, bounds.value_fields));
            try require(verify.idFits(item.ty, bounds.types));
        },
''',
    '''        .struct_value_literal => |item| {
            try require(verify.rangeFits(item.fields, bounds.value_fields));
        },
''',
)

replace_once(
    'src/4_semantics/global/globalizer.zig',
    '''            .struct_value_literal => |value| .{ .struct_value_literal = .{
                .fields = relocateEntityRange(global_sg.GlobalValueFieldId, o.value_field_base, value.fields),
                .ty = globalType(o, value.ty),
                .dispatch_prefix_positional_count = value.dispatch_prefix_positional_count,
            } },
''',
    '''            .struct_value_literal => |value| .{ .struct_value_literal = .{
                .fields = relocateEntityRange(global_sg.GlobalValueFieldId, o.value_field_base, value.fields),
                .dispatch_prefix_positional_count = value.dispatch_prefix_positional_count,
            } },
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
    '''        self.graph.nodes.items[@intFromEnum(input_node)].content.struct_value_literal = .{
            .fields = .{ .start = start, .len = expected_fields.len },
            .ty = ty,
        };
''',
    '''        self.graph.nodes.items[@intFromEnum(input_node)].content.struct_value_literal = .{
            .fields = .{ .start = start, .len = expected_fields.len },
        };
''',
)

replace_once(
    'src/4_semantics/global/core.zig',
    '''        self.graph.nodes.items[@intFromEnum(node)].ty = target;
        self.graph.nodes.items[@intFromEnum(node)].content.struct_value_literal.ty = target;
        return true;
''',
    '''        self.graph.nodes.items[@intFromEnum(node)].ty = target;
        return true;
''',
)

replace_once(
    'src/4_semantics/global/constructors.zig',
    '''        self.graph.nodes.items[@intFromEnum(input)].ty = ty;
        self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.ty = ty;
        const target = globalizer.globalNode(o, value.node);
''',
    '''        self.graph.nodes.items[@intFromEnum(input)].ty = ty;
        const target = globalizer.globalNode(o, value.node);
''',
)

p = Path('src/4_semantics/global/constructors.zig')
text = p.read_text()
text = text.replace('''    try std.testing.expectEqual(fixture.declared_type, result.ty.?);
    try std.testing.expectEqual(fixture.declared_type, result.content.struct_value_literal.ty);
''', '''    try std.testing.expectEqual(fixture.declared_type, result.ty.?);
''', 1)
p.write_text(text)

replace_once(
    'src/5_codegen/global_codegen.zig',
    '''            .struct_value_literal => |literal| try self.structLiteral(literal),
''',
    '''            .struct_value_literal => |literal| try self.structLiteral(literal, node.ty),
''',
)

replace_once(
    'src/5_codegen/global_codegen.zig',
    '''    fn structLiteral(self: *CodeGenerator, literal: anytype) !TypedValue {
        const type_ref = try self.toLLVMType(literal.ty);
        const range = types.fields(self.graph, literal.ty) orelse return CodegenError.InvalidType;
        if (self.isCUnion(literal.ty)) {
            const temp = c.LLVMBuildAlloca(self.builder, type_ref, "union.literal");
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
                const name = self.graph.text(value_field.name);
                const hit = types.findField(self.graph, literal.ty, name) orelse return CodegenError.InvalidType;
                const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
                var lowerer = self.typeLowerer();
                const pointer = try lowerer.buildUnionFieldPointer(self.builder, temp, types.effectiveFieldType(hit.field), "union.literal.field");
                _ = c.LLVMBuildStore(self.builder, value.value_ref, pointer);
            }
            return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, temp, "union.literal.value"), .type_ref = type_ref, .ty = literal.ty };
        }
        var aggregate = c.LLVMGetUndef(type_ref);
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
            const name = self.graph.text(value_field.name);
            const hit = types.findField(self.graph, literal.ty, name) orelse return CodegenError.InvalidType;
            const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, hit.index, "struct.field");
        }
        _ = range;
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = literal.ty };
    }
''',
    '''    fn structLiteral(self: *CodeGenerator, literal: anytype, maybe_ty: ?graph_mod.GlobalTypeId) !TypedValue {
        const ty = maybe_ty orelse return CodegenError.InvalidType;
        const type_ref = try self.toLLVMType(ty);
        const range = types.fields(self.graph, ty) orelse return CodegenError.InvalidType;
        if (self.isCUnion(ty)) {
            const temp = c.LLVMBuildAlloca(self.builder, type_ref, "union.literal");
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
                const name = self.graph.text(value_field.name);
                const hit = types.findField(self.graph, ty, name) orelse return CodegenError.InvalidType;
                const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
                var lowerer = self.typeLowerer();
                const pointer = try lowerer.buildUnionFieldPointer(self.builder, temp, types.effectiveFieldType(hit.field), "union.literal.field");
                _ = c.LLVMBuildStore(self.builder, value.value_ref, pointer);
            }
            return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, temp, "union.literal.value"), .type_ref = type_ref, .ty = ty };
        }
        var aggregate = c.LLVMGetUndef(type_ref);
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
            const name = self.graph.text(value_field.name);
            const hit = types.findField(self.graph, ty, name) orelse return CodegenError.InvalidType;
            const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, hit.index, "struct.field");
        }
        _ = range;
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = ty };
    }
''',
)

print('struct literal type is authoritative on Node.ty only')

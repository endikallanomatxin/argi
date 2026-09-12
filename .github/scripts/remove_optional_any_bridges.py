from pathlib import Path

path = Path('src/4_semantics/module/body_lowerer.zig')
text = path.read_text()

old = '''        const ty = if (value) |item| try self.compatibilityType(item.ty) else try self.builtin(.Void);
        return self.resolved(node, ty, .{ .return_statement = .{
'''
new = '''        const ty: ?entities.ModuleTypeId = if (value) |item| item.ty else try self.builtin(.Void);
        return self.resolved(node, ty, .{ .return_statement = .{
'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise AssertionError('return Any bridge anchor missing')

old = '''        const ty = expected orelse try self.compatibilityType(value.ty);
        return self.resolved(node, ty, .{ .pointer_assignment = .{ .pointer = pointer.node, .value = value.node } });
'''
new = '''        const ty: ?entities.ModuleTypeId = expected orelse value.ty;
        return self.resolved(node, ty, .{ .pointer_assignment = .{ .pointer = pointer.node, .value = value.node } });
'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise AssertionError('pointer assignment Any bridge anchor missing')

old = '''        const value = try self.lowerNode(self.tree.unaryOperand(node).?, expected);
        const ty = try self.compatibilityType(value.ty);
        return self.resolved(node, ty, @unionInit(entities.ResolvedNode.Content, @tagName(tag), value.node));
'''
new = '''        const value = try self.lowerNode(self.tree.unaryOperand(node).?, expected);
        return self.resolved(node, value.ty, @unionInit(entities.ResolvedNode.Content, @tagName(tag), value.node));
'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise AssertionError('unary Any bridge anchor missing')

path.write_text(text)
print('optional node types no longer round-trip through Any')

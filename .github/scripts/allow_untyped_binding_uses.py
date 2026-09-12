from pathlib import Path

path = Path('src/4_semantics/global/expressions.zig')
text = path.read_text()

old = '''        if (self.graph.isBindingTypeUnresolved(binding)) return false;
        const target = globalizer.globalNode(o, value.node);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;
'''
new = '''        const target = globalizer.globalNode(o, value.node);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const ty = if (self.graph.isBindingTypeUnresolved(binding)) null else self.graph.bindings.items[@intFromEnum(binding)].ty;
'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise AssertionError('assignment binding-use anchor missing')

old = '''        if (self.graph.isBindingTypeUnresolved(binding)) return false;
        const target = globalizer.globalNode(o, node);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;
'''
new = '''        const target = globalizer.globalNode(o, node);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const ty = if (self.graph.isBindingTypeUnresolved(binding)) null else self.graph.bindings.items[@intFromEnum(binding)].ty;
'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise AssertionError('read binding-use anchor missing')

path.write_text(text)
print('untyped binding identities resolve before their types')

from pathlib import Path

path = Path('src/4_semantics/global/semantizer.zig')
text = path.read_text()
text = text.replace('''    if (remaining != 0) {
        dumpUnresolved(modules, resolved);
        debugUnresolvedBindingTypes(&relocation.graph);
        return error.UnsupportedGlobalSemantic;
    }
''', '''    if (remaining != 0) {
        dumpUnresolved(modules, resolved);
        return error.UnsupportedGlobalSemantic;
    }
''', 1)
start = text.find('\nfn debugUnresolvedBindingTypes(')
if start != -1:
    end = text.find('\nfn dumpUnresolved(', start)
    assert end != -1
    text = text[:start] + '\n' + text[end:]
assert 'debugUnresolvedBindingTypes' not in text
path.write_text(text)
print('temporary binding diagnostics removed')

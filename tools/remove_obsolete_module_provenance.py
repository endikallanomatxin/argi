from pathlib import Path
import re


def replace_all(path: str, old: str, new: str, min_count: int = 1) -> None:
    p = Path(path)
    s = p.read_text()
    count = s.count(old)
    if count < min_count:
        raise RuntimeError(f"{path}: expected at least {min_count} occurrences, got {count}")
    p.write_text(s.replace(old, new))

p = Path("src/4_semantics/module/graph.zig")
s = p.read_text()

# Import aliases are now represented by semantic.module_aliases and linked once
# to GlobalModuleId. The old syntax-discovery import table is redundant.
s, n = re.subn(
    r'''/// The spelling of an import is file-local; locating its module is global work\.\npub const ImportReference = struct \{\n    path: StringRange,\n    source_offset: u32,\n    syntax_node: syn\.NodeIndex,\n\};\n\n''',
    '',
    s,
    count=1,
)
if n != 1:
    raise RuntimeError("graph.zig: ImportReference definition not found")

# TypeReference only needs semantic spelling/source position. The AST node was
# never part of resolution identity and no completed ModuleSG consumer needs it.
s = s.replace('''    source_offset: u32,\n    syntax_node: syn.NodeIndex,\n    resolution: TypeReferenceResolution = .external,''',
              '''    source_offset: u32,\n    resolution: TypeReferenceResolution = .external,''', 1)

s = s.replace('''    type_reference_base: u32,\n    type_reference_count: u32,\n    import_reference_base: u32,\n    import_reference_count: u32,''',
              '''    type_reference_base: u32,\n    type_reference_count: u32,''', 1)

s = s.replace('''    type_references: std.ArrayList(TypeReference) = .empty,\n    import_references: std.ArrayList(ImportReference) = .empty,\n    file_offsets: std.ArrayList(FileOffsets) = .empty,''',
              '''    type_references: std.ArrayList(TypeReference) = .empty,\n    file_offsets: std.ArrayList(FileOffsets) = .empty,''', 1)
s = s.replace('''        self.type_references.deinit(allocator);\n        self.import_references.deinit(allocator);\n        self.file_offsets.deinit(allocator);''',
              '''        self.type_references.deinit(allocator);\n        self.file_offsets.deinit(allocator);''', 1)
s = s.replace('''            self.type_references.items.len * @sizeOf(TypeReference) +\n            self.import_references.items.len * @sizeOf(ImportReference) +\n            self.file_offsets.items.len * @sizeOf(FileOffsets) +''',
              '''            self.type_references.items.len * @sizeOf(TypeReference) +\n            self.file_offsets.items.len * @sizeOf(FileOffsets) +''', 1)

s = s.replace('''            const type_reference_base: u32 = @intCast(self.graph.type_references.items.len);\n            const import_reference_base: u32 = @intCast(self.graph.import_references.items.len);\n            try discoverFile''',
              '''            const type_reference_base: u32 = @intCast(self.graph.type_references.items.len);\n            try discoverFile''', 1)
s = s.replace('''                .type_reference_base = type_reference_base,\n                .type_reference_count = @intCast(self.graph.type_references.items.len - type_reference_base),\n                .import_reference_base = import_reference_base,\n                .import_reference_count = @intCast(self.graph.import_references.items.len - import_reference_base),''',
              '''                .type_reference_base = type_reference_base,\n                .type_reference_count = @intCast(self.graph.type_references.items.len - type_reference_base),''', 1)

# Remove the discovery-only import scan. module_alias_lowerer consumes the
# import statement through its owning declaration during ModuleSema instead.
pattern = re.compile(r'''\n    for \(tree\.nodes\.items\(\.tag\), 0\.\.\) \|tag, index\| \{\n        if \(tag == \.import_statement\) \{\n            const node: syn\.NodeIndex = @enumFromInt\(@as\(u32, @intCast\(index\)\)\);\n            const path_token = tree\.importStatement\(node\)\.\?\.path_token;\n            const path = try graph\.addString\(allocator, tree\.tokenTextFromSource\(source, path_token\)\);\n            try graph\.import_references\.append\(allocator, \.\{\n                \.path = path,\n                \.source_offset = tree\.tokenLocation\(path_token\)\.offset,\n                \.syntax_node = node,\n            \}\);\n        \}\n    \}\n''')
s, n = pattern.subn('\n', s, count=1)
if n != 1:
    raise RuntimeError("graph.zig: import discovery scan not found")

# Remove only TypeReference.syntax_node initializers, not declaration provenance.
pattern = re.compile(r'''(graph\.type_references\.append\(allocator, \.\{.*?\.source_offset = tree\.tokenLocation\(name\.qualifier_token orelse name\.name_token\)\.offset,\n)            \.syntax_node = node,\n(        \}\);)''', re.S)
s, n = pattern.subn(r'\1\2', s)
if n < 1:
    raise RuntimeError("graph.zig: TypeReference syntax initializer not found")
p.write_text(s)

p = Path("src/4_semantics/module/verify.zig")
s = p.read_text()
s = s.replace('''    for (graph.import_references.items) |reference| try require(verify.stringFits(reference.path, graph.strings.items));\n\n''', '', 1)
s = s.replace('''    var type_reference_cursor: usize = 0;\n    var import_reference_cursor: usize = 0;''',
              '''    var type_reference_cursor: usize = 0;''', 1)
s = s.replace('''        try require(file.type_reference_base == type_reference_cursor);\n        try require(file.import_reference_base == import_reference_cursor);\n        try require(rangeFitsRaw(file.declaration_base, file.declaration_count, graph.declarations.items.len));\n        try require(rangeFitsRaw(file.type_reference_base, file.type_reference_count, graph.type_references.items.len));\n        try require(rangeFitsRaw(file.import_reference_base, file.import_reference_count, graph.import_references.items.len));\n        declaration_cursor += file.declaration_count;\n        type_reference_cursor += file.type_reference_count;\n        import_reference_cursor += file.import_reference_count;''',
              '''        try require(file.type_reference_base == type_reference_cursor);\n        try require(rangeFitsRaw(file.declaration_base, file.declaration_count, graph.declarations.items.len));\n        try require(rangeFitsRaw(file.type_reference_base, file.type_reference_count, graph.type_references.items.len));\n        declaration_cursor += file.declaration_count;\n        type_reference_cursor += file.type_reference_count;''', 1)
s = s.replace('''    try require(type_reference_cursor == graph.type_references.items.len);\n    try require(import_reference_cursor == graph.import_references.items.len);''',
              '''    try require(type_reference_cursor == graph.type_references.items.len);''', 1)
p.write_text(s)

Path(__file__).unlink()

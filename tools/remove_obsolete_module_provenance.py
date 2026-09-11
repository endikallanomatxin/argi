from pathlib import Path
import re

p = Path("src/4_semantics/module/graph.zig")
s = p.read_text()

# Import aliases are now represented by semantic.module_aliases and linked once
# to GlobalModuleId. The old syntax-discovery import table is redundant.
old = '''/// The spelling of an import is file-local; locating its module is global work.
pub const ImportReference = struct {
    path: StringRange,
    source_offset: u32,
    syntax_node: syn.NodeIndex,
};

'''
if s.count(old) != 1:
    raise RuntimeError(f"graph.zig: expected one ImportReference definition, got {s.count(old)}")
s = s.replace(old, '', 1)

old = '''    source_offset: u32,
    syntax_node: syn.NodeIndex,
    resolution: TypeReferenceResolution = .external,'''
new = '''    source_offset: u32,
    resolution: TypeReferenceResolution = .external,'''
if s.count(old) != 1:
    raise RuntimeError("graph.zig: TypeReference syntax field not found")
s = s.replace(old, new, 1)

for old, new in [
    ('''    type_reference_base: u32,
    type_reference_count: u32,
    import_reference_base: u32,
    import_reference_count: u32,''', '''    type_reference_base: u32,
    type_reference_count: u32,'''),
    ('''    type_references: std.ArrayList(TypeReference) = .empty,
    import_references: std.ArrayList(ImportReference) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,''', '''    type_references: std.ArrayList(TypeReference) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,'''),
    ('''        self.type_references.deinit(allocator);
        self.import_references.deinit(allocator);
        self.file_offsets.deinit(allocator);''', '''        self.type_references.deinit(allocator);
        self.file_offsets.deinit(allocator);'''),
    ('''            self.type_references.items.len * @sizeOf(TypeReference) +
            self.import_references.items.len * @sizeOf(ImportReference) +
            self.file_offsets.items.len * @sizeOf(FileOffsets) +''', '''            self.type_references.items.len * @sizeOf(TypeReference) +
            self.file_offsets.items.len * @sizeOf(FileOffsets) +'''),
    ('''            const type_reference_base: u32 = @intCast(self.graph.type_references.items.len);
            const import_reference_base: u32 = @intCast(self.graph.import_references.items.len);
            try discoverFile''', '''            const type_reference_base: u32 = @intCast(self.graph.type_references.items.len);
            try discoverFile'''),
    ('''                .type_reference_base = type_reference_base,
                .type_reference_count = @intCast(self.graph.type_references.items.len - type_reference_base),
                .import_reference_base = import_reference_base,
                .import_reference_count = @intCast(self.graph.import_references.items.len - import_reference_base),''', '''                .type_reference_base = type_reference_base,
                .type_reference_count = @intCast(self.graph.type_references.items.len - type_reference_base),'''),
]:
    if s.count(old) != 1:
        raise RuntimeError(f"graph.zig: expected one storage fragment, got {s.count(old)}")
    s = s.replace(old, new, 1)

# Remove the discovery-only scan without depending on incidental whitespace in
# the statements inside it.
start_marker = '    for (tree.nodes.items(.tag), 0..) |tag, index| {\n        if (tag == .import_statement) {'
start = s.find(start_marker)
if start < 0:
    raise RuntimeError("graph.zig: import discovery scan start not found")
end_marker = '        }\n    }\n'
end = s.find(end_marker, start)
if end < 0:
    raise RuntimeError("graph.zig: import discovery scan end not found")
s = s[:start] + s[end + len(end_marker):]

# Remove only TypeReference.syntax_node initializers, not declaration provenance.
pattern = re.compile(r'''(graph\.type_references\.append\(allocator, \.\{.*?\.source_offset = tree\.tokenLocation\(name\.qualifier_token orelse name\.name_token\)\.offset,\n)            \.syntax_node = node,\n(        \}\);)''', re.S)
s, n = pattern.subn(r'\1\2', s)
if n < 1:
    raise RuntimeError("graph.zig: TypeReference syntax initializer not found")
p.write_text(s)

p = Path("src/4_semantics/module/verify.zig")
s = p.read_text()
for old, new in [
    ('    for (graph.import_references.items) |reference| try require(verify.stringFits(reference.path, graph.strings.items));\n\n', ''),
    ('''    var type_reference_cursor: usize = 0;
    var import_reference_cursor: usize = 0;''', '''    var type_reference_cursor: usize = 0;'''),
    ('''        try require(file.type_reference_base == type_reference_cursor);
        try require(file.import_reference_base == import_reference_cursor);
        try require(rangeFitsRaw(file.declaration_base, file.declaration_count, graph.declarations.items.len));
        try require(rangeFitsRaw(file.type_reference_base, file.type_reference_count, graph.type_references.items.len));
        try require(rangeFitsRaw(file.import_reference_base, file.import_reference_count, graph.import_references.items.len));
        declaration_cursor += file.declaration_count;
        type_reference_cursor += file.type_reference_count;
        import_reference_cursor += file.import_reference_count;''', '''        try require(file.type_reference_base == type_reference_cursor);
        try require(rangeFitsRaw(file.declaration_base, file.declaration_count, graph.declarations.items.len));
        try require(rangeFitsRaw(file.type_reference_base, file.type_reference_count, graph.type_references.items.len));
        declaration_cursor += file.declaration_count;
        type_reference_cursor += file.type_reference_count;'''),
    ('''    try require(type_reference_cursor == graph.type_references.items.len);
    try require(import_reference_cursor == graph.import_references.items.len);''', '''    try require(type_reference_cursor == graph.type_references.items.len);'''),
]:
    if s.count(old) != 1:
        raise RuntimeError(f"verify.zig: expected one provenance fragment, got {s.count(old)}")
    s = s.replace(old, new, 1)
p.write_text(s)

Path(__file__).unlink()

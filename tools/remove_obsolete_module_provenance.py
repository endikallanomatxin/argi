from pathlib import Path

p = Path("src/4_semantics/module/graph.zig")
s = p.read_text()

# Import aliases are represented semantically and linked once to GlobalModuleId.
# The old syntax-discovery ImportReference table is therefore redundant.
replacements = [
    ('''/// The spelling of an import is file-local; locating its module is global work.
pub const ImportReference = struct {
    path: StringRange,
    source_offset: u32,
    syntax_node: syn.NodeIndex,
};

''', ''),
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
    ('''        if (tag == .import_statement) {
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(index)));
            const path_token = tree.importStatement(node).?.path_token;
            const path = try graph.addString(allocator, tree.tokenTextFromSource(source, path_token));
            try graph.import_references.append(allocator, .{
                .path = path,
                .source_offset = tree.tokenLocation(path_token).offset,
                .syntax_node = node,
            });
        }
''', ''),
]
for old, new in replacements:
    count = s.count(old)
    if count != 1:
        raise RuntimeError(f"graph.zig: expected one obsolete import fragment, got {count}")
    s = s.replace(old, new, 1)
p.write_text(s)

p = Path("src/4_semantics/module/verify.zig")
s = p.read_text()
replacements = [
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
]
for old, new in replacements:
    count = s.count(old)
    if count != 1:
        raise RuntimeError(f"verify.zig: expected one obsolete import fragment, got {count}")
    s = s.replace(old, new, 1)
p.write_text(s)

Path(__file__).unlink()

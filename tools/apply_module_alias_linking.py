from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if s.count(old) != 1:
        raise RuntimeError(f"{path}: expected one occurrence, got {s.count(old)}")
    p.write_text(s.replace(old, new, 1))

# ModuleSG owns an explicit alias -> import path relation.
replace_once(
    "src/4_semantics/module/entities.zig",
    '''pub const DeclarationBinding = struct {\n    declaration: ModuleDeclId,\n    binding: ModuleBindingId,\n};\n\npub const FunctionSemantic = struct {''',
    '''pub const DeclarationBinding = struct {\n    declaration: ModuleDeclId,\n    binding: ModuleBindingId,\n};\n\n/// Durable semantic relation for a named module import. Syntax is consumed in\n/// ModuleSema; global consumers link this path once to a GlobalModuleId.\npub const ModuleAlias = struct {\n    declaration: ModuleDeclId,\n    path: primitives.StringRange,\n    source: primitives.SourceRef,\n};\n\npub const FunctionSemantic = struct {''',
)

replace_once(
    "src/4_semantics/module/storage.zig",
    '''    declaration_semantics: std.ArrayList(entities.DeclarationSemantic) = .empty,\n    declaration_bindings: std.ArrayList(entities.DeclarationBinding) = .empty,\n    function_semantics: std.ArrayList(entities.FunctionSemantic) = .empty,''',
    '''    declaration_semantics: std.ArrayList(entities.DeclarationSemantic) = .empty,\n    declaration_bindings: std.ArrayList(entities.DeclarationBinding) = .empty,\n    module_aliases: std.ArrayList(entities.ModuleAlias) = .empty,\n    function_semantics: std.ArrayList(entities.FunctionSemantic) = .empty,''',
)
replace_once(
    "src/4_semantics/module/storage.zig",
    '''        self.declaration_semantics.deinit(allocator);\n        self.declaration_bindings.deinit(allocator);\n        self.function_semantics.deinit(allocator);''',
    '''        self.declaration_semantics.deinit(allocator);\n        self.declaration_bindings.deinit(allocator);\n        self.module_aliases.deinit(allocator);\n        self.function_semantics.deinit(allocator);''',
)
replace_once(
    "src/4_semantics/module/storage.zig",
    '''            self.declaration_semantics.items.len * @sizeOf(entities.DeclarationSemantic) +\n            self.declaration_bindings.items.len * @sizeOf(entities.DeclarationBinding) +\n            self.function_semantics.items.len * @sizeOf(entities.FunctionSemantic) +''',
    '''            self.declaration_semantics.items.len * @sizeOf(entities.DeclarationSemantic) +\n            self.declaration_bindings.items.len * @sizeOf(entities.DeclarationBinding) +\n            self.module_aliases.items.len * @sizeOf(entities.ModuleAlias) +\n            self.function_semantics.items.len * @sizeOf(entities.FunctionSemantic) +''',
)

Path("src/4_semantics/module/module_alias_lowerer.zig").write_text(r'''const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const writer_mod = @import("writer.zig");

/// Consume import syntax at the ModuleSema boundary and retain only the
/// semantic alias relation plus source provenance. GlobalSema never needs to
/// recover an alias by comparing syntax-node/source-offset windows again.
pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !u32 {
    var writer = writer_mod.Writer.init(allocator, graph);
    var count: u32 = 0;
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .import_alias) continue;
        if (declaration.module_file_index >= files.len) return error.InvalidModuleFileIndex;
        const file = files[declaration.module_file_index];
        const symbol = file.tree.symbolDeclaration(declaration.syntax_node) orelse return error.InvalidImportAlias;
        const value_node = symbol.value orelse return error.InvalidImportAlias;
        const import_statement = file.tree.importStatement(value_node) orelse return error.InvalidImportAlias;
        const path_text = file.tree.tokenTextFromSource(file.source, import_statement.path_token);
        try graph.semantic.module_aliases.append(allocator, .{
            .declaration = @enumFromInt(@as(u32, @intCast(raw))),
            .path = try writer.addString(path_text),
            .source = .{
                .file_index = declaration.module_file_index,
                .offset = file.tree.tokenLocation(import_statement.path_token).offset,
            },
        });
        count += 1;
    }
    return count;
}

test "module alias relation is an indexed semantic entity" {
    try std.testing.expect(@sizeOf(entities.ModuleAlias) <= 20);
}
''')

replace_once(
    "src/4_semantics/module/semantizer.zig",
    '''const initializer_lowerer = @import("initializer_lowerer.zig");\nconst global_roots_lowerer = @import("global_roots_lowerer.zig");''',
    '''const initializer_lowerer = @import("initializer_lowerer.zig");\nconst module_alias_lowerer = @import("module_alias_lowerer.zig");\nconst global_roots_lowerer = @import("global_roots_lowerer.zig");''',
)
replace_once(
    "src/4_semantics/module/semantizer.zig",
    '''    global_bindings: u32 = 0,\n    global_roots: u32 = 0,''',
    '''    global_bindings: u32 = 0,\n    module_aliases: u32 = 0,\n    global_roots: u32 = 0,''',
)
replace_once(
    "src/4_semantics/module/semantizer.zig",
    '''    var graph = try module_sg.build(allocator, module_dir, files);\n    errdefer graph.deinit(allocator);\n\n    const initializers = try initializer_lowerer.lower(allocator, &graph, files);''',
    '''    var graph = try module_sg.build(allocator, module_dir, files);\n    errdefer graph.deinit(allocator);\n\n    const module_aliases = try module_alias_lowerer.lower(allocator, &graph, files);\n    const initializers = try initializer_lowerer.lower(allocator, &graph, files);''',
)
replace_once(
    "src/4_semantics/module/semantizer.zig",
    '''            .global_bindings = initializers.global_bindings,\n            .global_roots = global_roots,''',
    '''            .global_bindings = initializers.global_bindings,\n            .module_aliases = module_aliases,\n            .global_roots = global_roots,''',
)

# Final GlobalSG stores aliases already linked to dense module identity.
replace_once(
    "src/4_semantics/global/graph.zig",
    '''pub const Module = struct {\n    dir: StringRange,\n    is_bundled_core: bool = false,\n    files: primitives.Range(GlobalFileId),\n    declarations: DeclRange,\n};\n\npub const Symbol = struct {''',
    '''pub const Module = struct {\n    dir: StringRange,\n    is_bundled_core: bool = false,\n    files: primitives.Range(GlobalFileId),\n    declarations: DeclRange,\n};\n\n/// A source alias linked once to semantic module identity. `dir` remains\n/// loader metadata; lookup and dispatch consume `target`, never path strings.\npub const ModuleAlias = struct {\n    owner: GlobalModuleId,\n    declaration: GlobalDeclId,\n    target: GlobalModuleId,\n    source: primitives.SourceRef,\n};\n\npub const Symbol = struct {''',
)
replace_once(
    "src/4_semantics/global/graph.zig",
    '''pub const GlobalSemanticGraph = struct {\n    modules: std.ArrayList(Module) = .empty,\n    files: std.ArrayList(File) = .empty,''',
    '''pub const GlobalSemanticGraph = struct {\n    modules: std.ArrayList(Module) = .empty,\n    module_aliases: std.ArrayList(ModuleAlias) = .empty,\n    files: std.ArrayList(File) = .empty,''',
)
replace_once(
    "src/4_semantics/global/graph.zig",
    '''            &self.modules,               &self.files,                 &self.declarations,               &self.symbols,''',
    '''            &self.modules,               &self.module_aliases,        &self.files,                      &self.declarations,\n            &self.symbols,''',
)
replace_once(
    "src/4_semantics/global/graph.zig",
    '''        return self.modules.items.len * @sizeOf(Module) +\n            self.files.items.len * @sizeOf(File) +''',
    '''        return self.modules.items.len * @sizeOf(Module) +\n            self.module_aliases.items.len * @sizeOf(ModuleAlias) +\n            self.files.items.len * @sizeOf(File) +''',
)

Path("src/4_semantics/global/module_linker.zig").write_text(r'''const std = @import("std");
const module_sg = @import("../module/graph.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");

/// Link every source-level import exactly once. Path spelling belongs to the
/// loader/link boundary; after this pass semantic lookup uses GlobalModuleId.
pub fn link(
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
) !void {
    graph.module_aliases.clearRetainingCapacity();
    for (modules, 0..) |*module, module_index| {
        const owner: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(module_index)));
        for (module.semantic.module_aliases.items) |alias| {
            const target = try resolveImportPath(allocator, graph, modules, module_index, module.text(alias.path));
            try graph.module_aliases.append(allocator, .{
                .owner = owner,
                .declaration = globalizer.globalDecl(offsets[module_index], alias.declaration),
                .target = target,
                .source = .{
                    .file_index = offsets[module_index].file_base + alias.source.file_index,
                    .offset = alias.source.offset,
                },
            });
        }
    }
}

fn resolveImportPath(
    allocator: std.mem.Allocator,
    graph: *const global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    current_module: usize,
    spelling: []const u8,
) !global_sg.GlobalModuleId {
    const import_path = std.mem.trim(u8, spelling, "\"'");
    if (std.mem.startsWith(u8, import_path, "./") or std.mem.startsWith(u8, import_path, "../")) {
        const resolved = try std.fs.path.resolve(allocator, &.{ modules[current_module].module_dir, import_path });
        defer allocator.free(resolved);
        var found: ?global_sg.GlobalModuleId = null;
        for (graph.modules.items, 0..) |module, index| {
            const dir = graph.text(module.dir);
            if (!std.mem.eql(u8, dir, resolved)) continue;
            if (found != null) return error.AmbiguousModuleReference;
            found = @enumFromInt(@as(u32, @intCast(index)));
        }
        return found orelse error.UnknownModuleReference;
    }

    // `.../foo` is project/dependency-root syntax. The loader has already
    // discovered concrete module directories; linking accepts only a unique
    // path suffix and converts it immediately to GlobalModuleId.
    const suffix = if (std.mem.startsWith(u8, import_path, ".../")) import_path[4..] else import_path;
    var found: ?global_sg.GlobalModuleId = null;
    for (graph.modules.items, 0..) |module, index| {
        const dir = graph.text(module.dir);
        if (!pathEndsWith(dir, suffix)) continue;
        if (found != null) return error.AmbiguousModuleReference;
        found = @enumFromInt(@as(u32, @intCast(index)));
    }
    return found orelse error.UnknownModuleReference;
}

fn pathEndsWith(path: []const u8, suffix: []const u8) bool {
    if (std.mem.eql(u8, path, suffix)) return true;
    if (!std.mem.endsWith(u8, path, suffix) or path.len <= suffix.len) return false;
    const boundary = path[path.len - suffix.len - 1];
    return boundary == '/' or boundary == '\\';
}
''')

replace_once(
    "src/4_semantics/global/semantizer.zig",
    '''const globalizer = @import("globalizer.zig");\nconst global_verify = @import("verify.zig");''',
    '''const globalizer = @import("globalizer.zig");\nconst module_linker = @import("module_linker.zig");\nconst global_verify = @import("verify.zig");''',
)
replace_once(
    "src/4_semantics/global/semantizer.zig",
    '''    var relocation = try globalizer.relocate(allocator, modules, .allow_holes);\n    errdefer relocation.deinit(allocator);\n\n    // The globalizer preallocates stable GlobalTypeId slots.''',
    '''    var relocation = try globalizer.relocate(allocator, modules, .allow_holes);\n    errdefer relocation.deinit(allocator);\n    try module_linker.link(allocator, &relocation.graph, modules, relocation.offsets.items);\n\n    // The globalizer preallocates stable GlobalTypeId slots.''',
)

# Verify linked aliases as part of the final graph invariant.
replace_once(
    "src/4_semantics/global/verify.zig",
    '''    const bounds = makeBounds(graph);\n    try verifyModulePartitions(graph);\n\n    for (graph.declarations.items)''',
    '''    const bounds = makeBounds(graph);\n    try verifyModulePartitions(graph);\n    for (graph.module_aliases.items) |alias| {\n        try require(verify.idFits(alias.owner, graph.modules.items.len));\n        try require(verify.idFits(alias.target, graph.modules.items.len));\n        try require(verify.idFits(alias.declaration, graph.declarations.items.len));\n        try require(graph.moduleForDeclaration(alias.declaration) == alias.owner);\n        try require(alias.source.file_index < graph.files.items.len);\n        try require(graph.declarations.items[@intFromEnum(alias.declaration)].kind == .import_alias);\n    }\n\n    for (graph.declarations.items)''',
)

# Qualified lookup now consumes the linked semantic relation. Remove the old
# declaration-window/source-offset reconstruction and path resolver from core.
p = Path("src/4_semantics/global/core.zig")
s = p.read_text()
pattern = re.compile(
    r'''    /// Resolve a qualifier through the import binding in the calling module\.\n.*?\n    fn findModuleBySpelling\(self: \*Resolver, spelling: \[\]const u8\) !global_sg\.GlobalModuleId \{''',
    re.S,
)
replacement = r'''    /// Resolve a source qualifier through the module aliases linked before
    /// semantic resolution. Paths are no longer semantic identity here.
    pub fn findModuleForQualifier(self: *Resolver, current_module: usize, qualifier: []const u8) !global_sg.GlobalModuleId {
        var found: ?global_sg.GlobalModuleId = null;
        const current: global_sg.GlobalModuleId = @enumFromInt(@as(u32, @intCast(current_module)));
        for (self.graph.module_aliases.items) |alias| {
            if (alias.owner != current) continue;
            const declaration = self.graph.declarations.items[@intFromEnum(alias.declaration)];
            if (!std.mem.eql(u8, self.graph.text(declaration.name), qualifier)) continue;
            if (found) |previous| {
                if (previous != alias.target) return error.AmbiguousModuleReference;
            } else found = alias.target;
        }
        if (found) |target| return target;
        // Transitional/compiler-generated qualifiers may still spell a module
        // directly; source import aliases never take this fallback.
        return self.findModuleBySpelling(qualifier);
    }

    fn findModuleBySpelling(self: *Resolver, spelling: []const u8) !global_sg.GlobalModuleId {'''
new_s, n = pattern.subn(replacement, s, count=1)
if n != 1:
    raise RuntimeError(f"core.zig: failed to replace import lookup block ({n})")
s = new_s

# Update the focused core test to construct the semantic relation directly.
test_pattern = re.compile(r'''test "qualified lookup follows import alias binding" \{.*?\n\}\n\ntest "''', re.S)
new_test = r'''test "qualified lookup follows linked module alias" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "/workspace/app") };
    defer module.deinit(allocator);

    const app_dir = try graph.addString(allocator, "/workspace/app");
    const target_dir = try graph.addString(allocator, "/tool/more/_test_support/basic");
    const alias_name = try graph.addString(allocator, "support");
    try graph.declarations.append(allocator, .{
        .kind = .import_alias,
        .name = alias_name,
        .source = .{ .file_index = 0, .offset = 10 },
    });
    try graph.modules.append(allocator, .{ .dir = app_dir, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 1 } });
    try graph.modules.append(allocator, .{ .dir = target_dir, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 1, .len = 0 } });
    try graph.module_aliases.append(allocator, .{
        .owner = @enumFromInt(0),
        .declaration = @enumFromInt(0),
        .target = @enumFromInt(1),
        .source = .{ .file_index = 0, .offset = 24 },
    });

    var resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{module}, .offsets = &.{} };
    try std.testing.expectEqual(@as(global_sg.GlobalModuleId, @enumFromInt(1)), try resolver.findModuleForQualifier(0, "support"));
}

test "'''
s, n = test_pattern.subn(new_test, s, count=1)
if n != 1:
    raise RuntimeError(f"core.zig: failed to replace alias test ({n})")
p.write_text(s)

Path(__file__).unlink()

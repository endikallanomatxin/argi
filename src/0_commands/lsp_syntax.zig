const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const st = @import("../3_syntax/syntax_tree.zig");

pub const File = struct {
    source: sf.SourceFile,
    tree: st.FileSyntaxTree,
    tokens: token.View,
    scope_end: []usize,
    scope_start: []usize,
    paren_depth: []usize,
};
// Editor syntax is prepared per file and survives failures in other files.
// The caller owns all artifacts through its request arena.
pub fn load_files(work: std.mem.Allocator, sources: []const sf.SourceFile) ![]File {
    var work_copy = work;
    var diagnostics = diag.Diagnostics.init(&work_copy, sources);
    defer diagnostics.deinit();
    const files = try work.alloc(File, sources.len);
    for (sources, files, 0..) |source, *file, index| {
        var lexer = tokenizer.Tokenizer.init(work, &diagnostics, source.code, diagnostics.source_db.fileId(index));
        _ = lexer.tokenize() catch {};
        var tree = st.FileSyntaxTree.initOwnedTokens(lexer.location.file, lexer.takeTokens());
        var parser = syntaxer.Syntaxer.initFile(work, tree, source.code, &diagnostics);
        tree = parser.parse() catch parser.file;
        file.* = .{
            .source = source,
            .tree = tree,
            .tokens = token.View.init(tree.tokens),
            .scope_start = try work.alloc(usize, tree.tokens.len),
            .scope_end = try work.alloc(usize, tree.tokens.len),
            .paren_depth = try work.alloc(usize, tree.tokens.len),
        };
        try compute_scopes(work, file);
        if (file.tree.roots.len == 0) {
            var roots: std.ArrayList(st.NodeIndex) = .empty;
            for (0..file.tree.nodes.len) |raw| {
                const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
                switch (file.tree.tag(node)) {
                    .function_declaration, .function_declaration_once, .c_function_pointer_declaration, .type_declaration, .abstract_declaration, .symbol_declaration_constant, .symbol_declaration_variable, .c_enum_declaration, .c_union_declaration, .c_struct_declaration, .c_incomplete_declaration, .choice_option_declaration => {
                        if (file.scope_start[@intFromEnum(file.tree.mainToken(node))] == 0)
                            try roots.append(work, node);
                    },
                    else => {},
                }
            }
            file.tree.roots = roots.items;
        }
    }
    return files;
}

fn compute_scopes(allocator: std.mem.Allocator, file: *File) !void {
    var stack: std.ArrayList(usize) = .empty;
    var parens: usize = 0;
    for (file.tokens.contents, file.tokens.locations, 0..) |content, location, index| {
        file.paren_depth[index] = parens;
        if (content == .open_parenthesis) parens += 1;
        if (content == .close_parenthesis and parens > 0) parens -= 1;
        file.scope_start[index] = if (stack.items.len > 0) stack.items[stack.items.len - 1] + 1 else 0;
        file.scope_end[index] = file.source.code.len + 1;
        if (content == .open_brace) try stack.append(allocator, index);
        if (content == .close_brace and stack.items.len > 0) {
            const open = stack.pop().?;
            for (open + 1..index) |inner| {
                if (file.scope_start[inner] == open + 1) file.scope_end[inner] = location.offset;
            }
        }
    }
}

pub const Declaration = struct { path: []const u8, offset: u32, len: u32 };

fn name_token(file: *const File, node: st.NodeIndex) ?st.TokenIndex {
    if (file.tree.functionDeclaration(node)) |value| return value.name_token;
    if (file.tree.typeDeclaration(node)) |value| return value.name_token;
    if (file.tree.abstractDeclaration(node)) |value| return value.name_token;
    if (file.tree.cEnumDeclaration(node)) |value| return value.name_token;
    if (file.tree.cUnionDeclaration(node)) |value| return value.name_token;
    if (file.tree.symbolDeclaration(node)) |value| return value.name_token;
    return null;
}

fn declaration(file: *const File, index: st.TokenIndex) Declaration {
    return .{ .path = file.source.path, .offset = file.tree.tokenLocation(index).offset, .len = @intCast(file.tree.tokenTextFromSource(file.source.code, index).len) };
}

fn previous_token(file: *const File, index: usize) ?usize {
    var cursor = index;
    while (cursor > 0) {
        cursor -= 1;
        if (file.tokens.contents[cursor] != .new_line and file.tokens.contents[cursor] != .comment) return cursor;
    }
    return null;
}

/// Syntax navigation only resolves lexical bindings and unambiguous visible
/// declarations. Overload selection and inferred receiver types require GlobalSG;
/// an unresolved expression must never turn into a guess across unrelated modules.
pub fn find_declaration(work: std.mem.Allocator, io: std.Io, sources: []const sf.SourceFile, path: []const u8, offset: usize) !?Declaration {
    const files = try load_files(work, sources);
    var current: ?*const File = null;
    for (files) |*file| if (std.mem.eql(u8, file.source.path, path)) {
        current = file;
        break;
    };
    const file = current orelse return null;
    var selected: ?usize = null;
    for (file.tokens.contents, file.tokens.locations, 0..) |content, location, index| {
        if (content != .identifier) continue;
        const text = file.tree.tokenTextFromSource(file.source.code, @enumFromInt(@as(u32, @intCast(index))));
        if (location.offset <= offset and offset < location.offset + text.len) {
            selected = index;
            break;
        }
    }
    const index = selected orelse return null;
    const name = file.tree.tokenTextFromSource(file.source.code, @enumFromInt(@as(u32, @intCast(index))));
    var module_dir: ?[]const u8 = null;
    if (previous_token(file, index)) |previous| {
        if (file.tokens.contents[previous] == .double_dot) return null;
        if (file.tokens.contents[previous] == .dot) {
            const alias_index = previous_token(file, previous) orelse return null;
            if (file.tokens.contents[alias_index] != .identifier) return null;
            const alias = file.tree.tokenTextFromSource(file.source.code, @enumFromInt(@as(u32, @intCast(alias_index))));
            for (file.tree.roots) |node| {
                const binding = file.tree.symbolDeclaration(node) orelse continue;
                if (!std.mem.eql(u8, file.tree.tokenTextFromSource(file.source.code, binding.name_token), alias)) continue;
                const import = file.tree.importStatement(binding.value orelse continue) orelse continue;
                const literal = file.tree.tokenTextFromSource(file.source.code, import.path_token);
                const import_path = try token.decodeStringLiteral(work, literal);
                var allocator = work;
                module_dir = sf.resolveImportDir(&allocator, io, path, import_path) catch null;
            }
            if (module_dir == null) return null;
        }
    }
    if (module_dir == null) {
        var local: ?Declaration = null;
        for (0..file.tree.nodes.len) |raw| {
            const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            const binding = file.tree.symbolDeclaration(node) orelse continue;
            const token_index = @intFromEnum(binding.name_token);
            const location = file.tree.tokenLocation(binding.name_token).offset;
            if (location > offset or file.scope_start[token_index] == 0 or offset > file.scope_end[token_index]) continue;
            if (!std.mem.eql(u8, file.tree.tokenTextFromSource(file.source.code, binding.name_token), name)) continue;
            if (local == null or location > local.?.offset) local = declaration(file, binding.name_token);
        }
        if (local) |value| return value;
        for (file.tree.roots) |node| {
            const function = file.tree.functionDeclaration(node) orelse continue;
            const body = function.body orelse continue;
            const body_index = @intFromEnum(file.tree.mainToken(body));
            if (file.tokens.locations[body_index].offset > offset) continue;
            // The body opening token and its following tokens carry its end.
            if (body_index + 1 >= file.tokens.len or offset > file.scope_end[body_index + 1]) continue;
            for ([_]st.NodeIndex{ function.input, function.output }) |signature| {
                const fields = file.tree.structTypeLiteral(signature) orelse continue;
                for (fields.fields) |field_node| {
                    const field = file.tree.structTypeField(field_node) orelse continue;
                    if (std.mem.eql(u8, file.tree.tokenTextFromSource(file.source.code, field.name_token), name)) return declaration(file, field.name_token);
                }
            }
        }
    }
    // Module declarations take precedence over the implicitly visible core.
    for ([_]bool{ false, true }) |core| {
        var found: ?Declaration = null;
        for (files) |*candidate| {
            const same_module = std.mem.eql(u8, std.fs.path.dirname(candidate.source.path) orelse ".", std.fs.path.dirname(path) orelse ".");
            if (module_dir) |dir| {
                if (core or !std.mem.eql(u8, std.fs.path.dirname(candidate.source.path) orelse ".", dir)) continue;
            } else if (core) {
                if (same_module or candidate.source.origin != .bundled_core) continue;
            } else if (!same_module) continue;
            if ((core or module_dir != null) and std.mem.startsWith(u8, name, "_")) continue;
            for (candidate.tree.roots) |node| {
                const name_index = name_token(candidate, node) orelse continue;
                if (!std.mem.eql(u8, candidate.tree.tokenTextFromSource(candidate.source.code, name_index), name)) continue;
                if (found != null) return null;
                found = declaration(candidate, name_index);
            }
        }
        if (found) |value| return value;
    }
    return null;
}

fn test_definition(sources: []const sf.SourceFile, needle: []const u8) !?Declaration {
    const offset = std.mem.indexOf(u8, sources[0].code, needle).?;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    return try find_declaration(arena.allocator(), std.testing.io, sources, sources[0].path, offset);
}

test "syntax navigation preserves lexical scopes and ignores member guesses" {
    const code =
        \\main(.input: Int32) -> (.result: Int32) := {
        \\    value := input
        \\    if true { hidden := 1 }
        \\    result = value
        \\    hidden
        \\    object.value
        \\    -- value
        \\    "value"
        \\}
    ;
    const sources = [_]sf.SourceFile{.{ .path = "/app/main.rg", .code = code }};
    const local = (try test_definition(&sources, "value\n")).?;
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, code, "value :=").?)), local.offset);
    const parameter = (try test_definition(&sources, "input\n")).?;
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, code, "input:").?)), parameter.offset);
    try std.testing.expect((try test_definition(&sources, "hidden\n")) == null);
    try std.testing.expect((try test_definition(&sources, "value\n    --")) == null);
    try std.testing.expect((try test_definition(&sources, "value\n    \"")) == null);
    try std.testing.expect((try test_definition(&sources, "value\"")) == null);
}

test "syntax navigation respects visibility and refuses unresolved overloads" {
    const sources = [_]sf.SourceFile{
        .{ .path = "/app/main.rg", .code = "main() -> () := { local()\n unique()\n overload()\n foreign()\n _private()\n }" },
        .{ .path = "/app/helper.rg", .code = "local() -> () := {}" },
        .{ .path = "/core/library.rg", .origin = .bundled_core, .code = "local() -> () := {}\nunique() -> () := {}\noverload() -> () := {}\noverload(.a: Int32) -> () := {}\n_private() -> () := {}" },
        .{ .path = "/other/foreign.rg", .code = "foreign() -> () := {}" },
    };
    const local = (try test_definition(&sources, "local()")).?;
    try std.testing.expectEqualStrings("/app/helper.rg", local.path);
    const core = (try test_definition(&sources, "unique()")).?;
    try std.testing.expectEqualStrings("/core/library.rg", core.path);
    try std.testing.expect((try test_definition(&sources, "overload()")) == null);
    try std.testing.expect((try test_definition(&sources, "foreign()")) == null);
    try std.testing.expect((try test_definition(&sources, "_private()")) == null);
}

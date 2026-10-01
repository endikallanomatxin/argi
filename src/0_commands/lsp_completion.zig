const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const primitives = @import("../4_semantics/primitives/schema.zig");

pub const Kind = enum(u8) { function = 3, field = 5, variable = 6, type_ = 7, module = 9, keyword = 14 };
pub const Item = struct { label: []const u8, kind: Kind, detail: []const u8, insert_text: []const u8 };
pub const Result = struct {
    arena: std.heap.ArenaAllocator,
    items: []const Item,
    start: usize,
    end: usize,

    pub fn deinit(self: *Result) void {
        self.arena.deinit();
    }
};

const File = struct {
    source: sf.SourceFile,
    tree: st.FileSyntaxTree,
    tokens: token.View,
    scope_end: []usize,
    scope_start: []usize,
    paren_depth: []usize,
};
const TypeRef = struct { file: *const File, node: st.NodeIndex };

// Completion deliberately uses syntax artifacts rather than requiring a
// successful whole-program graph. Each file is syntaxed independently so an
// unfinished call in the editor does not hide core or sibling declarations.
pub fn complete(allocator: std.mem.Allocator, io: std.Io, sources: []const sf.SourceFile, path: []const u8, offset: usize) !Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const work = arena.allocator();
    var work_copy = work;
    var diagnostics = diag.Diagnostics.init(&work_copy, sources);
    defer diagnostics.deinit();
    const files = try work.alloc(File, sources.len);
    var current: ?*File = null;
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
                    .function_declaration, .function_declaration_once, .type_declaration, .abstract_declaration, .symbol_declaration_constant, .symbol_declaration_variable, .c_enum_declaration, .c_union_declaration, .choice_option_declaration => {
                        if (file.scope_start[@intFromEnum(file.tree.mainToken(node))] == 0)
                            try roots.append(work, node);
                    },
                    else => {},
                }
            }
            file.tree.roots = roots.items;
        }
        if (std.mem.eql(u8, source.path, path)) current = file;
    }
    const file = current orelse return error.FileNotFound;
    if (offset > file.source.code.len) return error.InvalidPosition;
    var start = offset;
    while (start > 0 and identifier_byte(file.source.code[start - 1])) start -= 1;
    var end = offset;
    while (end < file.source.code.len and identifier_byte(file.source.code[end])) end += 1;
    var builder = Builder{ .allocator = work, .prefix = file.source.code[start..offset] };
    for (file.tokens.contents, file.tokens.locations) |content, location| {
        if (location.offset > offset) break;
        const length: usize = switch (content) {
            .comment => |range| range.len,
            .literal => |literal| switch (literal) {
                .string_literal => |range| range.len + 2,
                .char_literal => 3,
                else => 0,
            },
            else => 0,
        };
        if (length > 0 and offset > location.offset and (offset < location.offset + length or (content == .comment and offset == location.offset + length)))
            return .{ .arena = arena, .items = &.{}, .start = start, .end = end };
    }
    const previous = previous_token(file, start);
    if (previous) |dot| {
        if (file.tokens.contents[dot] == .dot) {
            const before_dot = previous_token(file, file.tokens.locations[dot].offset);
            if (before_dot) |before| {
                if (file.tokens.contents[before] == .open_parenthesis or file.tokens.contents[before] == .comma) {
                    try add_arguments(&builder, io, files, file, dot);
                    const rest = std.mem.trimStart(u8, file.source.code[end..], " \t");
                    if (std.mem.startsWith(u8, rest, "=")) {
                        for (builder.items.items) |*item| item.insert_text = item.label;
                    }
                } else {
                    try add_members(&builder, io, files, file, dot, offset);
                }
            }
            return finish(arena, &builder, start, end);
        }
    }
    try add_locals(&builder, file, offset);
    for (files) |*candidate| {
        if (same_module(candidate.source.path, path)) try add_declarations(&builder, candidate, true);
    }
    for (files) |*candidate| {
        if (candidate.source.origin == .bundled_core and !same_module(candidate.source.path, path))
            try add_declarations(&builder, candidate, false);
    }
    inline for (@typeInfo(primitives.BuiltinType).@"enum".fields) |field|
        try builder.add(field.name, .type_, "builtin type", field.name);
    for ([_][]const u8{ "if", "else", "while", "for", "in", "match", "return", "break", "continue", "assume", "reach", "once", "test", "import", "abort", "and", "or", "true", "false" }) |keyword|
        try builder.add(keyword, .keyword, "keyword", keyword);
    return finish(arena, &builder, start, end);
}

const Builder = struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,
    items: std.ArrayList(Item) = .empty,
    seen: std.StringHashMapUnmanaged(void) = .empty,

    fn add(self: *Builder, label: []const u8, kind: Kind, detail: []const u8, insert_text: []const u8) !void {
        if (label.len == 0 or !std.mem.startsWith(u8, label, self.prefix)) return;
        const entry = try self.seen.getOrPut(self.allocator, label);
        if (entry.found_existing) return;
        try self.items.append(self.allocator, .{
            .label = try self.allocator.dupe(u8, label),
            .kind = kind,
            .detail = try self.allocator.dupe(u8, detail),
            .insert_text = try self.allocator.dupe(u8, insert_text),
        });
    }
};

fn finish(arena: std.heap.ArenaAllocator, builder: *Builder, start: usize, end: usize) Result {
    std.mem.sort(Item, builder.items.items, {}, struct {
        fn less(_: void, a: Item, b: Item) bool {
            return std.mem.lessThan(u8, a.label, b.label);
        }
    }.less);
    return .{ .arena = arena, .items = builder.items.items, .start = start, .end = end };
}

fn identifier_byte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn same_module(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.dirname(a) orelse ".", std.fs.path.dirname(b) orelse ".");
}

fn spelling(file: *const File, index: usize) []const u8 {
    return file.tree.tokenTextFromSource(file.source.code, @enumFromInt(@as(u32, @intCast(index))));
}

fn previous_token(file: *const File, offset: usize) ?usize {
    var found: ?usize = null;
    for (file.tokens.contents, file.tokens.locations, 0..) |content, location, index| {
        if (location.offset >= offset) break;
        if (content == .new_line or content == .comment) continue;
        found = index;
    }
    return found;
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

fn in_scope(file: *const File, index: usize, offset: usize) bool {
    if (file.tokens.locations[index].offset >= offset) return false;
    const start = file.scope_start[index];
    return (start == 0 or file.tokens.locations[start - 1].offset < offset) and offset <= file.scope_end[index];
}

fn signature_begin(file: *const File, open: usize) ?usize {
    var index = open;
    var arrow = false;
    while (index > 0) {
        index -= 1;
        if (file.tokens.contents[index] == .close_brace) break;
        if (file.paren_depth[index] != 0) continue;
        if (file.tokens.contents[index] == .arrow) arrow = true;
        if (arrow and file.tokens.contents[index] == .identifier and index + 1 < open and
            (file.tokens.contents[index + 1] == .open_parenthesis or file.tokens.contents[index + 1] == .hash)) return index;
    }
    return null;
}

fn add_locals(builder: *Builder, file: *const File, offset: usize) !void {
    // Walk backwards so the nearest visible binding wins over shadowed names.
    var index = file.tokens.len;
    while (index > 0) {
        index -= 1;
        if (file.tokens.contents[index] != .identifier or !in_scope(file, index, offset)) continue;
        if (index + 1 >= file.tokens.len) continue;
        const next = file.tokens.contents[index + 1];
        if (next != .colon and next != .double_colon) continue;
        if (index > 0 and (file.tokens.contents[index - 1] == .dot or file.tokens.contents[index - 1] == .double_dot)) continue;
        if (file.scope_start[index] == 0) continue;
        try builder.add(spelling(file, index), .variable, "local binding", spelling(file, index));
    }
    // Signature fields precede the body scope. They remain available even
    // when an incomplete statement prevents the function node being finished.
    var body: ?usize = null;
    for (file.tokens.contents, file.tokens.locations, 0..) |content, location, i| {
        if (location.offset >= offset) break;
        if (content == .open_brace and file.scope_start[i] == 0 and offset <= scope_close(file, i)) body = i;
    }
    if (body) |open| {
        const begin = signature_begin(file, open) orelse return;
        for (begin..open) |i| {
            if (i > 0 and i + 1 < open and file.tokens.contents[i] == .identifier and
                file.tokens.contents[i - 1] == .dot and file.tokens.contents[i + 1] == .colon)
                try builder.add(spelling(file, i), .variable, "parameter", spelling(file, i));
        }
    }
}

fn scope_close(file: *const File, open: usize) usize {
    var depth: usize = 1;
    for (open + 1..file.tokens.len) |index| {
        if (file.tokens.contents[index] == .open_brace) depth += 1;
        if (file.tokens.contents[index] == .close_brace) {
            depth -= 1;
            if (depth == 0) return file.tokens.locations[index].offset;
        }
    }
    return file.source.code.len;
}

fn add_declarations(builder: *Builder, file: *const File, private: bool) !void {
    for (file.tree.roots) |node| {
        const name_token: st.TokenIndex = if (file.tree.functionDeclaration(node)) |function| function.name_token else if (file.tree.typeDeclaration(node)) |ty| ty.name_token else if (file.tree.abstractDeclaration(node)) |abstract| abstract.name_token else if (file.tree.cEnumDeclaration(node)) |ty| ty.name_token else if (file.tree.cUnionDeclaration(node)) |ty| ty.name_token else if (file.tree.symbolDeclaration(node)) |binding| binding.name_token else continue;
        const name = file.tree.tokenTextFromSource(file.source.code, name_token);
        if (!private and std.mem.startsWith(u8, name, "_")) continue;
        const kind: Kind = if (file.tree.functionDeclaration(node) != null) .function else if (file.tree.typeDeclaration(node) != null or file.tree.abstractDeclaration(node) != null or
            file.tree.cEnumDeclaration(node) != null or file.tree.cUnionDeclaration(node) != null) .type_ else blk: {
            const binding = file.tree.symbolDeclaration(node) orelse break :blk .variable;
            const value = binding.value orelse break :blk .variable;
            break :blk if (file.tree.importStatement(value) != null) .module else .variable;
        };
        var detail: []const u8 = switch (kind) {
            .type_ => "type",
            .variable => "module binding",
            else => @tagName(kind),
        };
        if (file.tree.functionDeclaration(node)) |function| {
            const start = file.tree.tokenLocation(name_token).offset;
            const end = if (function.body) |body| file.tree.location(body).offset else signature_end(file, start);
            if (end > start) detail = std.mem.trim(u8, file.source.code[start..end], " \t\r\n:=");
        }
        try builder.add(name, kind, detail, name);
    }
}

fn signature_end(file: *const File, start: usize) usize {
    return std.mem.indexOfScalarPos(u8, file.source.code, start, '\n') orelse file.source.code.len;
}

fn find_type(files: []const File, name: []const u8, context: *const File) ?TypeRef {
    var core: ?TypeRef = null;
    for (files) |*file| {
        if (!same_module(file.source.path, context.source.path) and file.source.origin != .bundled_core) continue;
        for (file.tree.roots) |node| {
            const ty = file.tree.typeDeclaration(node) orelse continue;
            if (!std.mem.eql(u8, file.tree.tokenTextFromSource(file.source.code, ty.name_token), name)) continue;
            if (same_module(file.source.path, context.source.path)) return .{ .file = file, .node = ty.value };
            if (!std.mem.startsWith(u8, name, "_")) core = .{ .file = file, .node = ty.value };
        }
    }
    return core;
}

fn fields_of(files: []const File, value: TypeRef, depth: usize) ?TypeRef {
    if (depth > 16) return null;
    const ty = value.file.tree.syntaxType(value.node) orelse return null;
    return switch (ty) {
        .struct_literal => value,
        .pointer => |pointer| fields_of(files, .{ .file = value.file, .node = pointer.child }, depth + 1),
        .name => |name| if (name.qualifier_token == null) blk: {
            const target = find_type(files, value.file.tree.tokenTextFromSource(value.file.source.code, name.name_token), value.file) orelse break :blk null;
            break :blk fields_of(files, target, depth + 1);
        } else null,
        else => null,
    };
}

fn binding_type(files: []const File, file: *const File, name: []const u8, offset: usize) ?TypeRef {
    var best: ?TypeRef = null;
    var best_offset: usize = 0;
    for (0..file.tree.nodes.len) |raw| {
        const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
        if (file.tree.symbolDeclaration(node)) |binding| {
            const location = file.tree.tokenLocation(binding.name_token).offset;
            const index = @intFromEnum(binding.name_token);
            if (location >= offset or location < best_offset or !in_scope(file, index, offset)) continue;
            if (!std.mem.eql(u8, file.tree.tokenTextFromSource(file.source.code, binding.name_token), name)) continue;
            best = null;
            best_offset = location;
            if (binding.type_node) |ty| {
                best = .{ .file = file, .node = ty };
            } else if (binding.value) |value| {
                const call = file.tree.functionCall(value) orelse continue;
                if (call.module_qualifier != null) continue;
                best = find_type(files, file.tree.tokenTextFromSource(file.source.code, call.callee_token), file);
            }
        }
    }
    if (best_offset != 0 or best != null) return best;
    // Locate a parameter's type within the current top-level function body.
    var body: ?usize = null;
    for (file.tokens.contents, file.tokens.locations, 0..) |content, location, i| {
        if (location.offset >= offset) break;
        if (content == .open_brace and file.scope_start[i] == 0 and offset <= scope_close(file, i)) body = i;
    }
    const open = body orelse return null;
    const begin = signature_begin(file, open) orelse return null;
    for (0..file.tree.nodes.len) |raw| {
        const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
        const field = file.tree.structTypeField(node) orelse continue;
        const index = @intFromEnum(field.name_token);
        if (index < begin or index >= open) continue;
        if (!std.mem.eql(u8, file.tree.tokenTextFromSource(file.source.code, field.name_token), name)) continue;
        return .{ .file = file, .node = field.type_node orelse return null };
    }
    return null;
}

fn add_fields(builder: *Builder, files: []const File, value: TypeRef, caller: *const File, arguments: bool) !void {
    const resolved = fields_of(files, value, 0) orelse return;
    const fields = resolved.file.tree.structTypeLiteral(resolved.node) orelse return;
    for (fields.fields) |node| {
        const field = resolved.file.tree.structTypeField(node) orelse continue;
        const name = resolved.file.tree.tokenTextFromSource(resolved.file.source.code, field.name_token);
        if (!same_module(resolved.file.source.path, caller.source.path) and std.mem.startsWith(u8, name, "_")) continue;
        const insertion = if (arguments) try std.fmt.allocPrint(builder.allocator, "{s} = ", .{name}) else name;
        try builder.add(name, .field, if (arguments) "named argument" else "field", insertion);
    }
}

fn add_arguments(builder: *Builder, io: std.Io, files: []const File, file: *const File, dot: usize) !void {
    var index = dot;
    var depth: usize = 0;
    var open: ?usize = null;
    while (index > 0) {
        index -= 1;
        if (file.tokens.contents[index] == .close_parenthesis) depth += 1;
        if (file.tokens.contents[index] == .open_parenthesis) {
            if (depth == 0) {
                open = index;
                break;
            }
            depth -= 1;
        }
    }
    const paren = open orelse return;
    if (paren == 0 or file.tokens.contents[paren - 1] != .identifier) return;
    const callee = spelling(file, paren - 1);
    const qualified = paren >= 3 and file.tokens.contents[paren - 2] == .dot and file.tokens.contents[paren - 3] == .identifier;
    const module_dir = if (qualified) try imported_module(builder, io, file, spelling(file, paren - 3)) else null;
    if (qualified and module_dir == null) return;
    for (files) |*candidate| {
        if (module_dir) |dir| {
            if (!std.mem.eql(u8, std.fs.path.dirname(candidate.source.path) orelse ".", dir)) continue;
        } else if (!same_module(candidate.source.path, file.source.path) and candidate.source.origin != .bundled_core) continue;
        for (candidate.tree.roots) |node| {
            const function = candidate.tree.functionDeclaration(node) orelse continue;
            if (!std.mem.eql(u8, candidate.tree.tokenTextFromSource(candidate.source.code, function.name_token), callee)) continue;
            try add_fields(builder, files, .{ .file = candidate, .node = function.input }, file, true);
        }
    }
    if (!qualified) {
        if (find_type(files, callee, file)) |ty| try add_fields(builder, files, ty, file, true);
    }
    // Arguments already supplied at this call level should not be suggested.
    var nested: usize = 0;
    for (paren + 1..dot) |i| {
        if (file.tokens.contents[i] == .open_parenthesis) nested += 1;
        if (file.tokens.contents[i] == .close_parenthesis and nested > 0) nested -= 1;
        if (nested == 0 and file.tokens.contents[i] == .dot and i + 2 < dot and
            file.tokens.contents[i + 1] == .identifier and file.tokens.contents[i + 2] == .equal)
        {
            const name = spelling(file, i + 1);
            var item: usize = 0;
            while (item < builder.items.items.len) {
                if (std.mem.eql(u8, builder.items.items[item].label, name)) {
                    _ = builder.items.orderedRemove(item);
                } else item += 1;
            }
        }
    }
}

fn imported_module(builder: *Builder, io: std.Io, file: *const File, alias: []const u8) !?[]const u8 {
    for (file.tree.roots) |node| {
        const binding = file.tree.symbolDeclaration(node) orelse continue;
        if (!std.mem.eql(u8, file.tree.tokenTextFromSource(file.source.code, binding.name_token), alias)) continue;
        const import = file.tree.importStatement(binding.value orelse continue) orelse continue;
        const path_literal = file.tree.tokenTextFromSource(file.source.code, import.path_token);
        const import_path = try token.decodeStringLiteral(builder.allocator, path_literal);
        var work = builder.allocator;
        return sf.resolveImportDir(&work, io, file.source.path, import_path) catch null;
    }
    return null;
}

fn add_members(builder: *Builder, io: std.Io, files: []const File, file: *const File, dot: usize, offset: usize) !void {
    var chain: std.ArrayList([]const u8) = .empty;
    var cursor = dot;
    while (cursor > 0) {
        cursor -= 1;
        const content = file.tokens.contents[cursor];
        if (content == .ampersand) continue;
        if (content != .identifier) break;
        try chain.append(builder.allocator, spelling(file, cursor));
        if (cursor == 0 or file.tokens.contents[cursor - 1] != .dot) break;
        cursor -= 1;
    }
    if (chain.items.len == 0) return;
    const root = chain.items[chain.items.len - 1];
    if (chain.items.len == 1) {
        if (try imported_module(builder, io, file, root)) |dir| {
            for (files) |*candidate| if (std.mem.eql(u8, std.fs.path.dirname(candidate.source.path) orelse ".", dir))
                try add_declarations(builder, candidate, false);
            return;
        }
    }
    var value = binding_type(files, file, root, offset) orelse return;
    var remaining = chain.items.len - 1;
    while (remaining > 0) {
        remaining -= 1;
        const resolved = fields_of(files, value, 0) orelse return;
        const fields = resolved.file.tree.structTypeLiteral(resolved.node) orelse return;
        var next: ?TypeRef = null;
        for (fields.fields) |node| {
            const field = resolved.file.tree.structTypeField(node) orelse continue;
            const name = resolved.file.tree.tokenTextFromSource(resolved.file.source.code, field.name_token);
            if (std.mem.eql(u8, name, chain.items[remaining])) {
                if (!same_module(resolved.file.source.path, file.source.path) and std.mem.startsWith(u8, name, "_")) return;
                next = .{ .file = resolved.file, .node = field.type_node orelse continue };
            }
        }
        value = next orelse return;
    }
    try add_fields(builder, files, value, file, false);
}

fn test_completion(marked: []const u8, dependencies: []const sf.SourceFile) !Result {
    const offset = std.mem.indexOfScalar(u8, marked, '|') orelse return error.TestExpectedEqual;
    const text = try std.mem.concat(std.testing.allocator, u8, &.{ marked[0..offset], marked[offset + 1 ..] });
    defer std.testing.allocator.free(text);
    var sources: std.array_list.Managed(sf.SourceFile) = .init(std.testing.allocator);
    defer sources.deinit();
    try sources.append(.{ .path = "/project/main.rg", .code = text });
    try sources.appendSlice(dependencies);
    return complete(std.testing.allocator, std.testing.io, sources.items, "/project/main.rg", offset);
}

fn item_named(result: Result, name: []const u8) ?Item {
    for (result.items) |item| if (std.mem.eql(u8, item.label, name)) return item;
    return null;
}

test "LSP completion filters names and preserves scopes in unfinished code" {
    const source =
        \\Point : Type = (.unrelated: Int32)
        \\other(.foreign: Int32) -> () := { hidden := 1 }
        \\main(.system: System) -> () := {
        \\    visible := 1
        \\    if true { closed := 2 }
        \\    |
        \\    later := 3
        \\}
    ;
    var result = try test_completion(source, &.{
        .{ .path = "/bundle/core/print.rg", .origin = .bundled_core, .code =
        \\print(.value: Int32) -> () := {}
        \\_secret() -> () := {}
        },
        .{ .path = "/project/sibling.rg", .code = "sibling() -> () := {}" },
        .{ .path = "/project/lib/foreign.rg", .code = "unqualified() -> () := {}" },
    });
    defer result.deinit();
    try std.testing.expect(item_named(result, "visible") != null);
    try std.testing.expect(item_named(result, "system") != null);
    try std.testing.expect(item_named(result, "other") != null);
    try std.testing.expect(item_named(result, "sibling") != null);
    try std.testing.expect(item_named(result, "print") != null);
    try std.testing.expect(item_named(result, "Int32") != null);
    try std.testing.expect(item_named(result, "assume") != null);
    for ([_][]const u8{ "hidden", "closed", "later", "foreign", "unrelated", "_secret", "unqualified" }) |name|
        try std.testing.expect(item_named(result, name) == null);
}

test "LSP completion replaces whole identifier and deduplicates overloads" {
    var result = try test_completion("main() -> () := { pri|nt }", &.{.{ .path = "/bundle/core/print.rg", .origin = .bundled_core, .code =
        \\print(.value: Int32) -> () := {}
        \\print(.value: Bool) -> () := {}
        \\print_error(.value: Int32) -> () := {}
    }});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    const item = item_named(result, "print").?;
    try std.testing.expectEqual(Kind.function, item.kind);
    try std.testing.expect(std.mem.indexOf(u8, item.detail, ".value: Int32") != null);
    try std.testing.expectEqual(@as(usize, 5), result.end - result.start);
}

test "LSP completion offers known fields and respects private boundaries" {
    const dependencies = [_]sf.SourceFile{.{ .path = "/bundle/core/system.rg", .origin = .bundled_core, .code =
        \\System : Type = (.terminal: $&Terminal, ._private: Int32)
        \\Terminal : Type = (.stdout_writer: Int32)
    }};
    var result = try test_completion("main(.system: System) -> () := { system.te| }", &dependencies);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqual(Kind.field, item_named(result, "terminal").?.kind);
    var chained = try test_completion("main(.system: System) -> () := { system.terminal&.| }", &dependencies);
    defer chained.deinit();
    try std.testing.expect(item_named(chained, "stdout_writer") != null);
    var local = try test_completion("Point : Type = (.x: Int32, ._private: Int32)\nmain() -> () := { point := Point(.x = 1, ._private = 2)\npoint.| }", &.{});
    defer local.deinit();
    try std.testing.expect(item_named(local, "x") != null);
    try std.testing.expect(item_named(local, "_private") != null);
    var public = try test_completion("main(.system: System) -> () := { system.| }", &dependencies);
    defer public.deinit();
    try std.testing.expect(item_named(public, "_private") == null);
    var shadow = try test_completion("Point : Type = (.x: Int32)\nmain() -> () := { point := Point(.x = 1)\nif true { point := 1\npoint.| } }", &.{});
    defer shadow.deinit();
    try std.testing.expectEqual(@as(usize, 0), shadow.items.len);
}

test "LSP completion offers unused named arguments and avoids duplicate equals" {
    const dependencies = [_]sf.SourceFile{.{ .path = "/bundle/core/print.rg", .origin = .bundled_core, .code =
        \\print(.value: Int32, .stdout: Int32) -> () := {}
    }};
    var result = try test_completion("main() -> () := { print(.|", &dependencies);
    defer result.deinit();
    try std.testing.expectEqualStrings("value = ", item_named(result, "value").?.insert_text);
    var supplied = try test_completion("main() -> () := { print(.value = 1, .|", &dependencies);
    defer supplied.deinit();
    try std.testing.expect(item_named(supplied, "value") == null);
    try std.testing.expect(item_named(supplied, "stdout") != null);
    var existing = try test_completion("main() -> () := { print(.va|lue = 1)", &dependencies);
    defer existing.deinit();
    try std.testing.expectEqualStrings("value", item_named(existing, "value").?.insert_text);
}

test "LSP completion supports imported names without exposing private declarations" {
    const dependencies = [_]sf.SourceFile{.{ .path = "/project/lib/main.rg", .code =
        \\public(.input: Int32) -> () := {}
        \\_private() -> () := {}
    }};
    var result = try test_completion("lib ::= import(\"./lib\")\nmain() -> () := { lib.|", &dependencies);
    defer result.deinit();
    try std.testing.expect(item_named(result, "public") != null);
    try std.testing.expect(item_named(result, "_private") == null);
    var arguments = try test_completion("lib ::= import(\"./lib\")\nmain() -> () := { lib.public(.|", &dependencies);
    defer arguments.deinit();
    try std.testing.expect(item_named(arguments, "input") != null);
}

test "LSP completion does not suggest names in comments or strings" {
    var comment = try test_completion("main() -> () := {\n-- pri|", &.{});
    defer comment.deinit();
    try std.testing.expectEqual(@as(usize, 0), comment.items.len);
    var string = try test_completion("main() -> () := { text := \"pri|nt\" }", &.{});
    defer string.deinit();
    try std.testing.expectEqual(@as(usize, 0), string.items.len);
}

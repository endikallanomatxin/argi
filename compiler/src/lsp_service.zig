const std = @import("std");

const sf = @import("source_files.zig");
const diag = @import("diagnostic.zig");
const token = @import("token.zig");
const tokenizer = @import("tokenizer.zig");
const st = @import("syntax_tree.zig");
const syntaxer = @import("syntaxer.zig");
const semantizer = @import("semantizer.zig");

// Índices fijos del legend que anuncias en initialize.semanticTokensProvider.legend.tokenTypes
const TOKEN_INDEX = struct {
    pub const namespace: u32 = 0;
    pub const type_: u32 = 1; // 'type' es keyword en Zig
    pub const function: u32 = 2;
    pub const method: u32 = 3;
    pub const variable: u32 = 4;
    pub const property: u32 = 5;
    pub const keyword: u32 = 6;
    pub const number: u32 = 7;
    pub const string: u32 = 8;
    pub const comment: u32 = 9;
    pub const operator: u32 = 10;
};

pub const Severity = enum(u8) {
    err = 1,
    warn = 2,
    info = 3,
    hint = 4,
};

pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Diagnostic = struct {
    range: Range,
    severity: Severity,
    message: []const u8,
};

pub const DiagnosticsResult = struct {
    allocator: std.mem.Allocator,
    items: []Diagnostic,
    owned: bool,

    pub fn empty(allocator: std.mem.Allocator) DiagnosticsResult {
        return .{ .allocator = allocator, .items = &[_]Diagnostic{}, .owned = false };
    }

    pub fn deinit(self: DiagnosticsResult) void {
        if (!self.owned) return;
        for (self.items) |d| self.allocator.free(d.message);
        self.allocator.free(self.items);
    }
};

const Document = struct {
    uri: []u8,
    path: []u8,
    version: ?i64,
    text: []u8,

    fn init(
        allocator: std.mem.Allocator,
        uri: []const u8,
        path: []const u8,
        text: []const u8,
        version: ?i64,
    ) !Document {
        return .{
            .uri = try allocator.dupe(u8, uri),
            .path = try allocator.dupe(u8, path),
            .version = version,
            .text = try allocator.dupe(u8, text),
        };
    }

    fn update(self: *Document, allocator: std.mem.Allocator, text: []const u8, version: ?i64) !void {
        allocator.free(self.text);
        self.text = try allocator.dupe(u8, text);
        self.version = version;
    }

    fn updatePath(self: *Document, allocator: std.mem.Allocator, path: []const u8) !void {
        allocator.free(self.path);
        self.path = try allocator.dupe(u8, path);
    }

    fn deinit(self: *Document, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
        allocator.free(self.path);
        allocator.free(self.text);
    }
};

pub const LanguageService = struct {
    allocator: std.mem.Allocator,
    documents: std.ArrayList(Document),
    root_path: ?[]u8 = null,
    core_files: std.ArrayList(sf.SourceFile),
    core_loaded: bool = false,

    pub fn init(allocator: std.mem.Allocator) LanguageService {
        return .{
            .allocator = allocator,
            .documents = std.ArrayList(Document).init(allocator),
            .core_files = std.ArrayList(sf.SourceFile).init(allocator),
        };
    }

    pub fn deinit(self: *LanguageService) void {
        for (self.documents.items) |*doc| doc.deinit(self.allocator);
        self.documents.deinit();

        if (self.root_path) |path| self.allocator.free(path);

        for (self.core_files.items) |core_file| {
            self.allocator.free(core_file.path);
            self.allocator.free(core_file.code);
        }
        self.core_files.deinit();
    }

    pub fn initialize(self: *LanguageService, root_uri: ?[]const u8) !void {
        if (root_uri) |uri| {
            if (try decodeFileUri(self.allocator, uri)) |path| {
                if (self.root_path) |existing| self.allocator.free(existing);
                self.root_path = path;
            }
        }
    }

    pub fn openDocument(
        self: *LanguageService,
        uri: []const u8,
        path: []const u8,
        version: ?i64,
        text: []const u8,
    ) !DiagnosticsResult {
        try self.storeDocument(uri, path, version, text);
        const idx = self.findDocument(uri) orelse return DiagnosticsResult.empty(self.allocator);
        return try self.analyzeDocument(&self.documents.items[idx]);
    }

    pub fn changeDocument(
        self: *LanguageService,
        uri: []const u8,
        path: []const u8,
        version: ?i64,
        text: []const u8,
    ) !DiagnosticsResult {
        const idx = self.findDocument(uri) orelse return DiagnosticsResult.empty(self.allocator);
        try self.documents.items[idx].updatePath(self.allocator, path);
        try self.documents.items[idx].update(self.allocator, text, version);
        return try self.analyzeDocument(&self.documents.items[idx]);
    }

    pub fn closeDocument(self: *LanguageService, uri: []const u8) void {
        if (self.findDocument(uri)) |idx| {
            self.documents.items[idx].deinit(self.allocator);
            _ = self.documents.swapRemove(idx);
        }
    }

    fn storeDocument(
        self: *LanguageService,
        uri: []const u8,
        path: []const u8,
        version: ?i64,
        text: []const u8,
    ) !void {
        if (self.findDocument(uri)) |idx| {
            try self.documents.items[idx].updatePath(self.allocator, path);
            try self.documents.items[idx].update(self.allocator, text, version);
            return;
        }

        const doc = try Document.init(self.allocator, uri, path, text, version);
        try self.documents.append(doc);
    }

    fn findDocument(self: *LanguageService, uri: []const u8) ?usize {
        for (self.documents.items, 0..) |doc, idx| {
            if (std.mem.eql(u8, doc.uri, uri)) return idx;
        }
        return null;
    }

    pub fn getDoc(self: *LanguageService, uri: []const u8) !*Document {
        if (self.findDocument(uri)) |idx| {
            return &self.documents.items[idx];
        }
        return error.DocumentNotOpen;
    }

    fn analyzeDocument(self: *LanguageService, doc: *Document) !DiagnosticsResult {
        try self.ensureCoreFiles();

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var analysis_allocator = arena.allocator();

        const total_files = self.core_files.items.len + 1;
        const files = try analysis_allocator.alloc(sf.SourceFile, total_files);
        for (self.core_files.items, 0..) |core_file, idx| {
            files[idx] = core_file;
        }
        files[total_files - 1] = .{ .path = doc.path, .code = doc.text };

        var diagnostics = diag.Diagnostics.init(&analysis_allocator, files);
        defer diagnostics.deinit();

        var tokens = std.ArrayList(token.Token).init(analysis_allocator);
        defer tokens.deinit();

        var pipeline_failed = false;

        for (files, 0..) |source_file, idx| {
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                &analysis_allocator,
                &diagnostics,
                source_file.code,
                source_file.path,
            );
            const token_slice = tokenizer_ctx.tokenize() catch {
                pipeline_failed = true;
                break;
            };

            const slice = if (idx == total_files - 1)
                token_slice
            else
                token_slice[0 .. token_slice.len - 1];
            tokens.appendSlice(slice) catch {
                pipeline_failed = true;
                break;
            };
        }

        if (!pipeline_failed) analysis: {
            var syntax_ctx = syntaxer.Syntaxer.init(&analysis_allocator, tokens.items, &diagnostics);
            const st_nodes = syntax_ctx.parse() catch {
                pipeline_failed = true;
                break :analysis;
            };

            var sem_ctx = semantizer.Semantizer.init(&analysis_allocator, st_nodes, &diagnostics);
            _ = sem_ctx.analyze() catch {
                pipeline_failed = true;
            };
        }

        var out = std.ArrayList(Diagnostic).init(self.allocator);
        errdefer {
            for (out.items) |d| self.allocator.free(d.message);
            out.deinit();
        }

        for (diagnostics.list.items) |entry| {
            const msg_copy = self.allocator.dupe(u8, entry.msg) catch |err| {
                return err;
            };
            const range = locationToRange(entry.loc);
            const severity = mapSeverity(entry.kind);
            out.append(.{ .range = range, .severity = severity, .message = msg_copy }) catch |err| {
                self.allocator.free(msg_copy);
                return err;
            };
        }

        const diag_slice = out.toOwnedSlice() catch |err| {
            for (out.items) |d| self.allocator.free(d.message);
            out.deinit();
            return err;
        };
        out.deinit();

        return DiagnosticsResult{
            .allocator = self.allocator,
            .items = diag_slice,
            .owned = true,
        };
    }

    fn ensureCoreFiles(self: *LanguageService) !void {
        if (self.core_loaded) return;

        var owned_candidates = std.ArrayList([]u8).init(self.allocator);
        defer {
            for (owned_candidates.items) |p| self.allocator.free(p);
            owned_candidates.deinit();
        }

        var candidates = std.ArrayList([]const u8).init(self.allocator);
        defer candidates.deinit();

        try candidates.append("core");

        if (self.root_path) |root| {
            const root_core = std.fs.path.join(self.allocator, &.{ root, "core" }) catch null;
            if (root_core) |joined| {
                try owned_candidates.append(joined);
                try candidates.append(joined);
            }
            const root_compiler_core = std.fs.path.join(self.allocator, &.{ root, "compiler", "core" }) catch null;
            if (root_compiler_core) |joined| {
                try owned_candidates.append(joined);
                try candidates.append(joined);
            }
        }

        for (candidates.items) |candidate| {
            if (try self.loadCoreDir(candidate)) {
                self.core_loaded = true;
                return;
            }
        }

        self.core_loaded = true;
    }

    fn loadCoreDir(self: *LanguageService, dir_path: []const u8) !bool {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return false;
        defer dir.close();

        var walker = dir.walk(self.allocator) catch return false;
        defer walker.deinit();

        var any_loaded = false;
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.path, ".rg")) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.path });
            defer self.allocator.free(full_path);

            const file = sf.readFile(&self.allocator, full_path) catch continue;
            self.core_files.append(file) catch {
                self.allocator.free(file.path);
                self.allocator.free(file.code);
                continue;
            };
            any_loaded = true;
        }

        return any_loaded;
    }

    pub fn semanticTokensFull(self: *LanguageService, uri: []const u8) !std.ArrayList(u32) {
        const gpa = self.allocator;
        var out = std.ArrayList(u32).init(gpa);

        const doc = try self.getDoc(uri);
        const text = doc.text;

        // Arena temporal
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var work = arena.allocator();

        // Diagnósticos dummy para tokenizer/syntaxer
        const one_file = [_]sf.SourceFile{.{ .path = doc.path, .code = doc.text }};
        var diagnostics = diag.Diagnostics.init(&work, &one_file);
        defer diagnostics.deinit();

        // 1) Tokeniza
        var tz = tokenizer.Tokenizer.init(&work, &diagnostics, text, doc.path);
        const toks = try tz.tokenize();
        if (toks.len == 0) return out;

        // 2) Parsea; si falla, devolvemos solo léxico rápido
        var syn_ctx = syntaxer.Syntaxer.init(&work, toks, &diagnostics);
        const st_nodes = syn_ctx.parse() catch {
            try emitLexical(&out, gpa, text, toks);
            return out;
        };

        // 3) Mapa offset -> índice de token (para longitudes de identificadores)
        var off2ix = std.AutoHashMap(usize, usize).init(work);
        defer off2ix.deinit();
        for (toks, 0..) |tk, i| {
            try off2ix.put(tk.location.offset, i);
        }

        // 4) Recolectamos TODO en 'collected' (luego ordenamos y codificamos)
        var collected = std.ArrayList(SemanticToken).init(work);
        defer collected.deinit();

        // 4.a) Léxico con split por '\n' (NO añadimos identificadores aquí)
        for (toks) |tk| {
            const ty_opt = classify_lex_only(tk.content) orelse continue;

            const start_off: usize = tk.location.offset;
            const len_u: usize = tokenLenBytes(tk);
            const end_off: usize = start_off + len_u;

            var line0: u32 = if (tk.location.line == 0) 0 else tk.location.line - 1;
            var col0: u32 = if (tk.location.column == 0) 0 else tk.location.column - 1;

            var off: usize = start_off;
            while (off < end_off) {
                const rest = text[off..end_off];
                if (std.mem.indexOfScalar(u8, rest, '\n')) |r| {
                    if (r > 0) {
                        try collected.append(.{
                            .line = line0,
                            .start = col0,
                            .len = @intCast(@min(r, @as(usize, std.math.maxInt(u32)))),
                            .type_index = ty_opt,
                            .mods = 0,
                        });
                        col0 += @intCast(r);
                    }
                    off += r + 1; // saltar '\n'
                    line0 += 1;
                    col0 = 0;
                } else {
                    const seg = rest.len;
                    if (seg > 0) {
                        try collected.append(.{
                            .line = line0,
                            .start = col0,
                            .len = @intCast(@min(seg, @as(usize, std.math.maxInt(u32)))),
                            .type_index = ty_opt,
                            .mods = 0,
                        });
                    }
                    break;
                }
            }
        }

        // 4.b) Overlay del AST: sólo identificadores con su rol
        const Emitter = struct {
            sink: *std.ArrayList(SemanticToken),
            toks: []const token.Token,
            off2ix: *std.AutoHashMap(usize, usize),

            fn identAt(this: *@This(), loc: token.Location, ty_idx: u32, mods: u32) !void {
                const start_off = loc.offset;
                const maybe_ix = this.off2ix.get(start_off) orelse return;
                const tk = this.toks[maybe_ix];
                if (tk.content != .identifier) return;

                const len_bytes: u32 = @intCast(@min(tokenLenBytes(tk), @as(usize, std.math.maxInt(u32))));
                const line0: u32 = if (loc.line == 0) 0 else loc.line - 1;
                const col0: u32 = if (loc.column == 0) 0 else loc.column - 1;

                try this.sink.append(.{
                    .line = line0,
                    .start = col0,
                    .len = len_bytes,
                    .type_index = ty_idx,
                    .mods = mods,
                });
            }
        };

        var em = Emitter{
            .sink = &collected,
            .toks = toks,
            .off2ix = &off2ix,
        };

        // Recorrido del AST (iterativo con pila)
        var stack = std.ArrayList(*const st.STNode).init(work);
        defer stack.deinit();
        for (st_nodes) |n| try stack.append(n);

        while (popOrNull(*const st.STNode, &stack)) |n| {
            switch (n.content) {
                .function_declaration => |fd| {
                    try em.identAt(fd.name_loc, TOKEN_INDEX.function, 0);
                    for (fd.input.fields) |f| {
                        try em.identAt(f.name_loc, TOKEN_INDEX.property, 0);
                        if (f.default_value) |dv| try stack.append(dv);
                    }
                    for (fd.output.fields) |f| {
                        try em.identAt(f.name_loc, TOKEN_INDEX.property, 0);
                        if (f.default_value) |dv| try stack.append(dv);
                    }
                    if (fd.body) |b| try stack.append(b);
                },
                .symbol_declaration => |sd| {
                    // (si añades modifiers: p.ej. readonly para const)
                    try em.identAt(sd.name_loc, TOKEN_INDEX.variable, 0);
                    if (sd.value) |v| try stack.append(v);
                },
                .type_declaration => |td| {
                    try em.identAt(td.name_loc, TOKEN_INDEX.type_, 0);
                    try stack.append(td.value);
                },
                .function_call => |fc| {
                    try em.identAt(fc.callee_loc, TOKEN_INDEX.function, 0);
                    try stack.append(fc.input);
                },
                .struct_field_access => |sfa| {
                    try em.identAt(sfa.field_loc, TOKEN_INDEX.property, 0);
                    try stack.append(sfa.struct_value);
                },
                .struct_value_literal => |sv| {
                    for (sv.fields) |f| {
                        try em.identAt(f.name_loc, TOKEN_INDEX.property, 0);
                        try stack.append(f.value);
                    }
                },
                .struct_type_literal => |stl| {
                    for (stl.fields) |f| {
                        try em.identAt(f.name_loc, TOKEN_INDEX.property, 0);
                        if (f.default_value) |dv| try stack.append(dv);
                    }
                },
                .code_block => |cb| {
                    for (cb.items) |sub| try stack.append(sub);
                },
                .binary_operation => |bo| {
                    try stack.append(bo.left);
                    try stack.append(bo.right);
                },
                .comparison => |c| {
                    try stack.append(c.left);
                    try stack.append(c.right);
                },
                .return_statement => |r| if (r.expression) |e| try stack.append(e),
                .if_statement => |ifs| {
                    try stack.append(ifs.condition);
                    try stack.append(ifs.then_block);
                    if (ifs.else_block) |e| try stack.append(e);
                },
                .list_literal => |ll| for (ll.elements) |e| try stack.append(e),
                .index_access => |ia| {
                    try stack.append(ia.value);
                    try stack.append(ia.index);
                },
                .index_assignment => |ia| {
                    try stack.append(ia.target);
                    try stack.append(ia.value);
                },
                .address_of => |p| try stack.append(p.value),
                .dereference => |p| try stack.append(p),
                .pointer_assignment => |pa| {
                    try stack.append(pa.target);
                    try stack.append(pa.value);
                },
                else => {},
            }
        }

        // 5) Ordenar y delta-codificar
        std.sort.block(SemanticToken, collected.items, {}, struct {
            fn lessThan(_: void, a: SemanticToken, b: SemanticToken) bool {
                return if (a.line == b.line) a.start < b.start else a.line < b.line;
            }
        }.lessThan);

        var prev_line: u32 = 0;
        var prev_char: u32 = 0;
        for (collected.items) |t| {
            try pushEncoded(&out, &prev_line, &prev_char, t.line, t.start, t.len, t.type_index, t.mods);
        }

        return out;
    }
};

fn locationToRange(loc: token.Location) Range {
    const start_line = if (loc.line == 0) 0 else loc.line - 1;
    const start_char = if (loc.column == 0) 0 else loc.column - 1;
    return .{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = start_line, .character = start_char + 1 },
    };
}

fn mapSeverity(kind: diag.Kind) Severity {
    return switch (kind) {
        .syntax, .semantic, .codegen, .internal => .err,
    };
}

pub fn decodeFileUri(allocator: std.mem.Allocator, uri: []const u8) !?[]u8 {
    const prefix = "file://";
    if (!std.mem.startsWith(u8, uri, prefix)) return null;

    var builder = std.ArrayList(u8).init(allocator);
    errdefer builder.deinit();

    var i: usize = prefix.len;
    while (i < uri.len) : (i += 1) {
        const c = uri[i];
        if (c == '%') {
            if (i + 2 >= uri.len) break;
            const hi = std.fmt.charToDigit(uri[i + 1], 16) catch break;
            const lo = std.fmt.charToDigit(uri[i + 2], 16) catch break;
            const decoded: u8 = @intCast(hi * 16 + lo);
            try builder.append(decoded);
            i += 2;
            continue;
        }
        try builder.append(c);
    }

    const slice = try builder.toOwnedSlice();
    builder.deinit();
    return slice;
}

inline fn pushEncoded(
    outp: *std.ArrayList(u32),
    prev_linep: *u32,
    prev_charp: *u32,
    line: u32,
    start_col: u32,
    len: u32,
    ty_index: u32,
    mods: u32,
) !void {
    const d_line = line - prev_linep.*;
    const d_char = if (d_line == 0) (start_col - prev_charp.*) else start_col;
    try outp.append(d_line);
    try outp.append(d_char);
    try outp.append(len);
    try outp.append(ty_index);
    try outp.append(mods);
    prev_linep.* = line;
    prev_charp.* = start_col;
}

inline fn classify(c: token.Content) ?u32 {
    return switch (c) {
        .comment => TOKEN_INDEX.comment,
        .identifier => TOKEN_INDEX.variable,

        .literal => |lit| switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal, .regular_float_literal, .scientific_float_literal => TOKEN_INDEX.number,

            .string_literal, .char_literal => TOKEN_INDEX.string,

            else => TOKEN_INDEX.number, // por si amplías Literal
        },

        // Keywords que ya emites (añade más si tu token.zig los incluye)
        .keyword_return, .keyword_if, .keyword_else => TOKEN_INDEX.keyword,

        // Operadores / puntuación
        .comparison_operator, .binary_operator, .equal, .arrow, .colon, .double_colon, .dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar => TOKEN_INDEX.operator,

        // No coloreamos
        .new_line, .eof => null,
    };
}

fn emitLexical(
    out: *std.ArrayList(u32),
    gpa: std.mem.Allocator,
    text: []const u8,
    toks: []const token.Token,
) !void {
    _ = gpa; // por ahora no lo necesitamos

    var prev_line: u32 = 0;
    var prev_char: u32 = 0;

    for (toks) |tk| {
        // Sólo categorías léxicas (identificadores los pinta el AST)
        const ty_opt = classify_lex_only(tk.content) orelse continue;

        const start_off: usize = tk.location.offset;
        const len_bytes: usize = tokenLenBytes(tk);
        const end_off: usize = start_off + len_bytes;

        var line0: u32 = if (tk.location.line == 0) 0 else tk.location.line - 1;
        var col0: u32 = if (tk.location.column == 0) 0 else tk.location.column - 1;

        // Partir en segmentos por si el token contiene '\n' (p.ej. string o comment multilínea)
        var off = start_off;
        while (off < end_off) {
            const rest = text[off..end_off];
            const nl_rel = std.mem.indexOfScalar(u8, rest, '\n');

            if (nl_rel) |r| {
                if (r > 0) {
                    try pushEncoded(out, &prev_line, &prev_char, line0, col0, @intCast(r), ty_opt, 0);
                    col0 += @intCast(r);
                }
                off += r + 1; // saltar '\n'
                line0 += 1;
                col0 = 0;
            } else {
                const seg = rest.len;
                if (seg > 0) {
                    try pushEncoded(out, &prev_line, &prev_char, line0, col0, @intCast(seg), ty_opt, 0);
                }
                break;
            }
        }
    }
}

const SemanticToken = struct { line: u32, start: u32, len: u32, type_index: u32, mods: u32 };

fn tokenLenBytes(tk: token.Token) usize {
    return switch (tk.content) {
        .identifier => |s| s.len,
        .comment => |s| s.len,

        .literal => |lit| switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal, .regular_float_literal, .scientific_float_literal, .string_literal => |s| s.len,
            .char_literal => 3, // 'x' mínimo (ajusta si soportas escapes)
            .bool_literal => |b| if (b) 4 else 5, // true/false
        },

        // ← añade aquí TODAS tus keywords
        .keyword_return => "return".len, // 6
        .keyword_if => "if".len, // 2
        .keyword_else => "else".len, // 4
        // .keyword_while => "while".len,
        // .keyword_for => "for".len,
        // ...etc si las tienes

        // Puntuación / operadores
        .double_colon => 2,
        .arrow => 2,

        // Si en tu lexer estos **siempre** son de 2 chars, deja 2;
        // si no, cámbialo a 1 o computa según el enum que uses.
        .comparison_operator => 2,
        .binary_operator => 2,

        .new_line => 1,

        // Paréntesis, corchetes, llaves, unarios, etc., 1 char:
        .equal, .colon, .dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar, .eof => 1,
    };
}

inline fn classify_lex_only(c: token.Content) ?u32 {
    return switch (c) {
        .comment => TOKEN_INDEX.comment,
        .literal => |lit| switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal, .regular_float_literal, .scientific_float_literal => TOKEN_INDEX.number,
            .string_literal, .char_literal => TOKEN_INDEX.string,
            .bool_literal => TOKEN_INDEX.keyword, // si prefieres, cámbialo a .number o .type_
        },
        .keyword_return, .keyword_if, .keyword_else => TOKEN_INDEX.keyword,
        .comparison_operator, .binary_operator, .equal, .arrow, .colon, .double_colon, .dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar => TOKEN_INDEX.operator,
        .identifier => null, // ident los pinta el pase sintáctico
        .new_line, .eof => null,
    };
}
inline fn popOrNull(comptime T: type, list: *std.ArrayList(T)) ?T {
    if (list.items.len == 0) return null;
    return list.pop();
}

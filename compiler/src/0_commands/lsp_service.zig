const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const sg = @import("../4_semantics/semantic_graph.zig");
const semantizer = @import("../4_semantics/semantizer.zig");
const typ = @import("../4_semantics/types.zig");

// Token types legend indices
const TOKEN_INDEX = struct {
    pub const namespace: u32 = 0;
    pub const type_: u32 = 1;
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

// Token modifier indices
const MOD_INDEX = struct {
    pub const declaration: u32 = 0;
    pub const readonly: u32 = 1;
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

pub const InlayHint = struct {
    position: Position,
    label: []const u8,
};

pub const Hover = struct {
    range: Range,
    contents: []const u8,
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

pub const InlayHintsResult = struct {
    allocator: std.mem.Allocator,
    items: []InlayHint,
    owned: bool,

    pub fn empty(allocator: std.mem.Allocator) InlayHintsResult {
        return .{ .allocator = allocator, .items = &[_]InlayHint{}, .owned = false };
    }

    pub fn deinit(self: InlayHintsResult) void {
        if (!self.owned) return;
        for (self.items) |hint| self.allocator.free(hint.label);
        self.allocator.free(self.items);
    }
};

const SyntaxFunctionDeclRef = struct {
    node: *const st.STNode,
    decl: st.FunctionDeclaration,
};

const SyntaxFunctionCallRef = struct {
    node: *const st.STNode,
    call: st.FunctionCall,
};

const SemanticFunctionDeclRef = struct {
    node: *const sg.SGNode,
    decl: *const sg.FunctionDeclaration,
};

const SemanticFunctionCallRef = struct {
    node: *const sg.SGNode,
    call: *const sg.FunctionCall,
};

const SemanticTypeDeclRef = struct {
    decl: *const sg.TypeDeclaration,
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
    documents: std.array_list.Managed(Document),
    root_path: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) LanguageService {
        return .{
            .allocator = allocator,
            .documents = std.array_list.Managed(Document).init(allocator),
        };
    }

    pub fn deinit(self: *LanguageService) void {
        for (self.documents.items) |*doc| doc.deinit(self.allocator);
        self.documents.deinit();

        if (self.root_path) |path| self.allocator.free(path);
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
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var analysis_allocator = arena.allocator();

        const files_list = sf.collectWithEntrySource(&analysis_allocator, "core", doc.path, doc.text) catch |err| {
            return try self.collectLoadFailureDiagnostics(doc, err);
        };
        const files = files_list.items;

        for (files_list.items) |*source_file| {
            for (self.documents.items) |open_doc| {
                if (std.mem.eql(u8, source_file.path, open_doc.path)) {
                    source_file.code = open_doc.text;
                    break;
                }
            }
        }

        return try self.analyzeFiles(&analysis_allocator, files, doc.path);
    }

    fn analyzeFiles(
        self: *LanguageService,
        analysis_allocator: *std.mem.Allocator,
        files: []const sf.SourceFile,
        primary_path: []const u8,
    ) !DiagnosticsResult {
        var diagnostics = diag.Diagnostics.init(analysis_allocator, files);
        defer diagnostics.deinit();

        var tokens = std.array_list.Managed(token.Token).init(analysis_allocator.*);
        defer tokens.deinit();

        var pipeline_failed = false;

        for (files, 0..) |source_file, idx| {
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                analysis_allocator,
                &diagnostics,
                source_file.code,
                source_file.path,
            );
            const token_slice = tokenizer_ctx.tokenize() catch {
                pipeline_failed = true;
                break;
            };

            const slice = if (idx == files.len - 1)
                token_slice
            else
                token_slice[0 .. token_slice.len - 1];
            tokens.appendSlice(slice) catch {
                pipeline_failed = true;
                break;
            };
        }

        if (!pipeline_failed) analysis: {
            var syntax_ctx = syntaxer.Syntaxer.init(analysis_allocator, tokens.items, &diagnostics);
            const st_nodes = syntax_ctx.parse() catch {
                pipeline_failed = true;
                break :analysis;
            };

            var sem_ctx = semantizer.Semantizer.init(analysis_allocator, st_nodes, &diagnostics);
            _ = sem_ctx.analyze() catch {
                pipeline_failed = true;
            };
        }

        var out = std.array_list.Managed(Diagnostic).init(self.allocator);
        errdefer {
            for (out.items) |d| self.allocator.free(d.message);
            out.deinit();
        }

        for (diagnostics.list.items) |entry| {
            if (!std.mem.eql(u8, entry.loc.file, primary_path)) continue;
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

    fn collectLoadFailureDiagnostics(
        self: *LanguageService,
        doc: *Document,
        err: anyerror,
    ) !DiagnosticsResult {
        const range = firstImportRange(doc.text);
        const message = switch (err) {
            error.FileNotFound => "failed to load an imported module",
            error.ImportCycle => "import cycle detected",
            else => "failed to load module graph",
        };

        const msg_copy = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(msg_copy);

        const items = try self.allocator.alloc(Diagnostic, 1);
        items[0] = .{
            .range = range,
            .severity = .err,
            .message = msg_copy,
        };

        return .{
            .allocator = self.allocator,
            .items = items,
            .owned = true,
        };
    }

    pub fn semanticTokensFull(self: *LanguageService, uri: []const u8) !std.array_list.Managed(u32) {
        const gpa = self.allocator;
        var out = std.array_list.Managed(u32).init(gpa);

        const doc = try self.getDoc(uri);
        const text = doc.text;

        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var work = arena.allocator();

        const one_file = [_]sf.SourceFile{.{ .path = doc.path, .code = doc.text }};
        var diagnostics = diag.Diagnostics.init(&work, &one_file);
        defer diagnostics.deinit();

        var tz = tokenizer.Tokenizer.init(&work, &diagnostics, text, doc.path);
        const toks = try tz.tokenize();
        if (toks.len == 0) return out;

        var syn_ctx = syntaxer.Syntaxer.init(&work, toks, &diagnostics);
        const st_nodes = syn_ctx.parse() catch {
            try emitLexical(&out, gpa, text, toks);
            return out;
        };

        var off2ix = std.AutoHashMap(usize, usize).init(work);
        defer off2ix.deinit();
        for (toks, 0..) |tk, i| {
            try off2ix.put(tk.location.offset, i);
        }

        var collected = std.array_list.Managed(SemanticToken).init(work);
        defer collected.deinit();

        // Lexical layer (no identifiers)
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
                    off += r + 1;
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

        // AST overlay
        const DECL: u32 = (1 << MOD_INDEX.declaration);
        const RO: u32 = (1 << MOD_INDEX.readonly);

        const Emitter = struct {
            sink: *std.array_list.Managed(SemanticToken),
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

            fn colorType(this: *@This(), ty: st.Type, decl_mods: u32) !void {
                switch (ty) {
                    .type_name => |tn| {
                        try this.identAt(tn.location, TOKEN_INDEX.type_, 0);
                    },
                    .generic_type_instantiation => |g| {
                        try this.identAt(g.base_name.location, TOKEN_INDEX.type_, 0);
                        for (g.args.fields) |af| {
                            try this.identAt(af.name.location, TOKEN_INDEX.property, decl_mods);
                            if (af.type) |child_t| try this.colorType(child_t, decl_mods);
                        }
                    },
                    .struct_type_literal => |stl| {
                        for (stl.fields) |f| {
                            try this.identAt(f.name.location, TOKEN_INDEX.property, decl_mods);
                            if (f.type) |child_t| try this.colorType(child_t, decl_mods);
                        }
                    },
                    .array_type => |arr_ptr| {
                        try this.colorType(arr_ptr.element.*, decl_mods);
                    },
                    .pointer_type => |ptr_ptr| {
                        try this.colorType(ptr_ptr.child.*, decl_mods);
                    },
                }
            }
        };

        var em = Emitter{
            .sink = &collected,
            .toks = toks,
            .off2ix = &off2ix,
        };

        var stack = std.array_list.Managed(*const st.STNode).init(work);
        defer stack.deinit();
        for (st_nodes) |n| try stack.append(n);

        while (popOrNull(*const st.STNode, &stack)) |n| {
            switch (n.content) {
                .function_declaration => |fd| {
                    try em.identAt(fd.name.location, TOKEN_INDEX.function, DECL);

                    for (fd.input.fields) |f| {
                        try em.identAt(f.name.location, TOKEN_INDEX.property, DECL);
                        if (f.type) |ty| try em.colorType(ty, DECL);
                        if (f.default_value) |dv| try stack.append(dv);
                    }
                    for (fd.output.fields) |f| {
                        try em.identAt(f.name.location, TOKEN_INDEX.property, DECL);
                        if (f.type) |ty| try em.colorType(ty, DECL);
                        if (f.default_value) |dv| try stack.append(dv);
                    }

                    if (fd.body) |b| try stack.append(b);
                },
                .symbol_declaration => |sd| {
                    const mods: u32 = DECL | (if (sd.mutability == .constant) RO else 0);
                    try em.identAt(sd.name.location, TOKEN_INDEX.variable, mods);
                    if (sd.type) |ty| try em.colorType(ty, DECL);
                    if (sd.value) |v| try stack.append(v);
                },
                .type_declaration => |td| {
                    try em.identAt(td.name.location, TOKEN_INDEX.type_, DECL);
                    try stack.append(td.value);
                },
                .function_call => |fc| {
                    try em.identAt(fc.callee_loc, TOKEN_INDEX.function, 0);
                    if (fc.type_arguments) |tas| {
                        for (tas) |t| try em.colorType(t, 0);
                    }
                    if (fc.type_arguments_struct) |tas_struct| {
                        for (tas_struct.fields) |f| {
                            try em.identAt(f.name.location, TOKEN_INDEX.property, 0);
                            if (f.type) |ty| try em.colorType(ty, 0);
                        }
                    }
                    try stack.append(fc.input);
                },
                .struct_field_access => |sfa| {
                    try em.identAt(sfa.field_name.location, TOKEN_INDEX.property, 0);
                    try stack.append(sfa.struct_value);
                },
                .struct_value_literal => |sv| {
                    for (sv.fields) |f| {
                        try em.identAt(f.name.location, TOKEN_INDEX.property, 0);
                        try stack.append(f.value);
                    }
                },
                .struct_type_literal => |stl| {
                    for (stl.fields) |f| {
                        try em.identAt(f.name.location, TOKEN_INDEX.property, DECL);
                        if (f.type) |ty| try em.colorType(ty, DECL);
                        if (f.default_value) |dv| try stack.append(dv);
                    }
                },
                .choice_type_literal => |ctl| {
                    for (ctl.variants) |v| {
                        try em.identAt(v.name.location, TOKEN_INDEX.property, DECL);
                        if (v.payload_type) |stl| {
                            for (stl.fields) |f| {
                                try em.identAt(f.name.location, TOKEN_INDEX.property, DECL);
                                if (f.type) |ty| try em.colorType(ty, DECL);
                                if (f.default_value) |dv| try stack.append(dv);
                            }
                        }
                    }
                },
                .choice_literal => |lit| {
                    try em.identAt(lit.name.location, TOKEN_INDEX.property, 0);
                    if (lit.payload) |payload| try stack.append(payload);
                },
                .choice_payload_access => |acc| {
                    try em.identAt(acc.variant_name.location, TOKEN_INDEX.property, 0);
                    try stack.append(acc.choice_value);
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
                .for_statement => |f| {
                    try em.identAt(f.item_name.location, TOKEN_INDEX.variable, DECL);
                    try stack.append(f.iterable);
                    try stack.append(f.body);
                },
                .while_statement => |w| {
                    try stack.append(w.condition);
                    try stack.append(w.body);
                },
                .match_statement => |m| {
                    try stack.append(m.value);
                    for (m.cases) |c| {
                        try em.identAt(c.variant_name.location, TOKEN_INDEX.property, 0);
                        if (c.payload_binding) |pb| try em.identAt(pb.location, TOKEN_INDEX.variable, DECL);
                        try stack.append(c.body);
                    }
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
                .reach_directive => |reach| {
                    for (reach.alternatives) |alt| {
                        for (alt.segments, 0..) |segment, idx| {
                            try em.identAt(
                                segment.location,
                                if (idx == 0) TOKEN_INDEX.variable else TOKEN_INDEX.property,
                                0,
                            );
                        }
                    }
                },
                else => {},
            }
        }

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

    pub fn hover(self: *LanguageService, uri: []const u8, position: Position) !?Hover {
        const doc = try self.getDoc(uri);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var analysis_allocator = arena.allocator();

        const files_list = sf.collectWithEntrySource(&analysis_allocator, "core", doc.path, doc.text) catch {
            return null;
        };
        const files = files_list.items;

        for (files_list.items) |*source_file| {
            for (self.documents.items) |open_doc| {
                if (std.mem.eql(u8, source_file.path, open_doc.path)) {
                    source_file.code = open_doc.text;
                    break;
                }
            }
        }

        const one_primary = [_]sf.SourceFile{.{ .path = doc.path, .code = doc.text }};
        var diagnostics = diag.Diagnostics.init(&analysis_allocator, &one_primary);
        defer diagnostics.deinit();

        var tokens = std.array_list.Managed(token.Token).init(analysis_allocator);
        defer tokens.deinit();

        for (files, 0..) |source_file, idx| {
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                &analysis_allocator,
                &diagnostics,
                source_file.code,
                source_file.path,
            );
            const token_slice = tokenizer_ctx.tokenize() catch {
                return null;
            };

            const slice = if (idx == files.len - 1)
                token_slice
            else
                token_slice[0 .. token_slice.len - 1];
            try tokens.appendSlice(slice);
        }

        var syntax_ctx = syntaxer.Syntaxer.init(&analysis_allocator, tokens.items, &diagnostics);
        const st_nodes = syntax_ctx.parse() catch {
            return null;
        };

        var sem_ctx = semantizer.Semantizer.init(&analysis_allocator, st_nodes, &diagnostics);
        const sg_nodes = sem_ctx.analyze() catch {
            return null;
        };

        var syntax_functions = std.array_list.Managed(SyntaxFunctionDeclRef).init(analysis_allocator);
        defer syntax_functions.deinit();
        var syntax_calls = std.array_list.Managed(SyntaxFunctionCallRef).init(analysis_allocator);
        defer syntax_calls.deinit();
        try collectSyntaxRefs(st_nodes, &syntax_functions, &syntax_calls);

        var semantic_functions = std.array_list.Managed(SemanticFunctionDeclRef).init(analysis_allocator);
        defer semantic_functions.deinit();
        var semantic_calls = std.array_list.Managed(SemanticFunctionCallRef).init(analysis_allocator);
        defer semantic_calls.deinit();
        var semantic_types = std.array_list.Managed(SemanticTypeDeclRef).init(analysis_allocator);
        defer semantic_types.deinit();
        try collectSemanticRefs(sg_nodes, &semantic_functions, &semantic_calls, &semantic_types);

        for (syntax_functions.items) |syntax_fn| {
            if (!std.mem.eql(u8, syntax_fn.decl.name.location.file, doc.path)) continue;
            if (!positionWithinName(position, syntax_fn.decl.name.location, syntax_fn.decl.name.string.len)) continue;
            const semantic_fn = findSemanticFunctionDecl(semantic_functions.items, syntax_fn.decl.name.location, syntax_fn.decl.name.string) orelse continue;
            const contents = try buildFunctionHoverMarkdown(
                self.allocator,
                semantic_fn.decl,
                syntax_fn.decl,
                semantic_types.items,
                doc.text,
                tokens.items,
            );
            return .{
                .range = nameRange(syntax_fn.decl.name.location, syntax_fn.decl.name.string.len),
                .contents = contents,
            };
        }

        for (syntax_calls.items) |syntax_call| {
            if (!std.mem.eql(u8, syntax_call.call.callee_loc.file, doc.path)) continue;
            if (!positionWithinName(position, syntax_call.call.callee_loc, syntax_call.call.callee.len)) continue;
            const semantic_call = findSemanticFunctionCall(semantic_calls.items, syntax_call.call.callee_loc, syntax_call.call.callee) orelse continue;
            const syntax_decl = findSyntaxFunctionDecl(syntax_functions.items, semantic_call.call.callee.location, semantic_call.call.callee.name);
            const contents = try buildFunctionHoverMarkdown(
                self.allocator,
                semantic_call.call.callee,
                if (syntax_decl) |decl_ref| decl_ref.decl else null,
                semantic_types.items,
                doc.text,
                tokens.items,
            );
            return .{
                .range = nameRange(syntax_call.call.callee_loc, syntax_call.call.callee.len),
                .contents = contents,
            };
        }

        return null;
    }

    pub fn inlayHints(self: *LanguageService, uri: []const u8, range: ?Range) !InlayHintsResult {
        const doc = try self.getDoc(uri);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var analysis_allocator = arena.allocator();

        const files_list = sf.collectWithEntrySource(&analysis_allocator, "core", doc.path, doc.text) catch {
            return InlayHintsResult.empty(self.allocator);
        };
        const files = files_list.items;

        for (files_list.items) |*source_file| {
            for (self.documents.items) |open_doc| {
                if (std.mem.eql(u8, source_file.path, open_doc.path)) {
                    source_file.code = open_doc.text;
                    break;
                }
            }
        }

        const one_primary = [_]sf.SourceFile{.{ .path = doc.path, .code = doc.text }};
        var diagnostics = diag.Diagnostics.init(&analysis_allocator, &one_primary);
        defer diagnostics.deinit();

        var tokens = std.array_list.Managed(token.Token).init(analysis_allocator);
        defer tokens.deinit();

        for (files, 0..) |source_file, idx| {
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                &analysis_allocator,
                &diagnostics,
                source_file.code,
                source_file.path,
            );
            const token_slice = tokenizer_ctx.tokenize() catch {
                return InlayHintsResult.empty(self.allocator);
            };

            const slice = if (idx == files.len - 1)
                token_slice
            else
                token_slice[0 .. token_slice.len - 1];
            try tokens.appendSlice(slice);
        }

        var syntax_ctx = syntaxer.Syntaxer.init(&analysis_allocator, tokens.items, &diagnostics);
        const st_nodes = syntax_ctx.parse() catch {
            return InlayHintsResult.empty(self.allocator);
        };

        var sem_ctx = semantizer.Semantizer.init(&analysis_allocator, st_nodes, &diagnostics);
        const sg_nodes = sem_ctx.analyze() catch {
            return InlayHintsResult.empty(self.allocator);
        };

        var syntax_functions = std.array_list.Managed(SyntaxFunctionDeclRef).init(analysis_allocator);
        defer syntax_functions.deinit();
        var syntax_calls = std.array_list.Managed(SyntaxFunctionCallRef).init(analysis_allocator);
        defer syntax_calls.deinit();

        try collectSyntaxRefs(st_nodes, &syntax_functions, &syntax_calls);

        var hints = std.array_list.Managed(InlayHint).init(self.allocator);
        errdefer {
            for (hints.items) |hint| self.allocator.free(hint.label);
            hints.deinit();
        }

        try collectFunctionInlayHints(
            self,
            doc.path,
            range,
            sg_nodes,
            syntax_functions.items,
            &hints,
        );
        try collectCallInlayHints(
            self,
            doc.path,
            range,
            sg_nodes,
            syntax_calls.items,
            tokens.items,
            &hints,
        );

        std.sort.block(InlayHint, hints.items, {}, struct {
            fn lessThan(_: void, a: InlayHint, b: InlayHint) bool {
                return if (a.position.line == b.position.line)
                    a.position.character < b.position.character
                else
                    a.position.line < b.position.line;
            }
        }.lessThan);

        const slice = try hints.toOwnedSlice();
        hints.deinit();
        return .{
            .allocator = self.allocator,
            .items = slice,
            .owned = true,
        };
    }
};

fn collectSyntaxRefs(
    st_nodes: []const *st.STNode,
    function_refs: *std.array_list.Managed(SyntaxFunctionDeclRef),
    call_refs: *std.array_list.Managed(SyntaxFunctionCallRef),
) !void {
    var stack = std.array_list.Managed(*const st.STNode).init(function_refs.allocator);
    defer stack.deinit();
    for (st_nodes) |node| try stack.append(node);

    while (popOrNull(*const st.STNode, &stack)) |node| {
        switch (node.content) {
            .function_declaration => |decl| {
                try function_refs.append(.{ .node = node, .decl = decl });
                if (decl.body) |body| try stack.append(body);
                for (decl.input.fields) |field| if (field.default_value) |dv| try stack.append(dv);
                for (decl.output.fields) |field| if (field.default_value) |dv| try stack.append(dv);
            },
            .function_call => |call| {
                try call_refs.append(.{ .node = node, .call = call });
                try stack.append(call.input);
            },
            .symbol_declaration => |sd| {
                if (sd.value) |value| try stack.append(value);
            },
            .assignment => |assign| try stack.append(assign.value),
            .expression_statement => |expr| try stack.append(expr),
            .pipe_expression => |pipe_expr| {
                try stack.append(pipe_expr.left);
                try stack.append(pipe_expr.right);
            },
            .code_block => |block| for (block.items) |item| try stack.append(item),
            .struct_value_literal => |sv| for (sv.fields) |field| try stack.append(field.value),
            .struct_type_literal => |stl| for (stl.fields) |field| if (field.default_value) |dv| try stack.append(dv),
            .choice_type_literal => |ctl| {
                for (ctl.variants) |variant| {
                    if (variant.payload_type) |payload| {
                        for (payload.fields) |field| if (field.default_value) |dv| try stack.append(dv);
                    }
                }
            },
            .choice_literal => |lit| if (lit.payload) |payload| try stack.append(payload),
            .struct_field_access => |sfa| try stack.append(sfa.struct_value),
            .choice_payload_access => |acc| try stack.append(acc.choice_value),
            .index_access => |ia| {
                try stack.append(ia.value);
                try stack.append(ia.index);
            },
            .index_assignment => |ia| {
                try stack.append(ia.target);
                try stack.append(ia.value);
            },
            .binary_operation => |bo| {
                try stack.append(bo.left);
                try stack.append(bo.right);
            },
            .comparison => |cmp| {
                try stack.append(cmp.left);
                try stack.append(cmp.right);
            },
            .return_statement => |ret| if (ret.expression) |expr| try stack.append(expr),
            .if_statement => |ifs| {
                try stack.append(ifs.condition);
                try stack.append(ifs.then_block);
                if (ifs.else_block) |else_block| try stack.append(else_block);
            },
            .for_statement => |for_stmt| {
                try stack.append(for_stmt.iterable);
                try stack.append(for_stmt.body);
            },
            .while_statement => |while_stmt| {
                try stack.append(while_stmt.condition);
                try stack.append(while_stmt.body);
            },
            .match_statement => |match_stmt| {
                try stack.append(match_stmt.value);
                for (match_stmt.cases) |case| try stack.append(case.body);
            },
            .list_literal => |list| for (list.elements) |elem| try stack.append(elem),
            .defer_statement => |expr| try stack.append(expr),
            .address_of => |addr| try stack.append(addr.value),
            .dereference => |expr| try stack.append(expr),
            .pointer_assignment => |pa| {
                try stack.append(pa.target);
                try stack.append(pa.value);
            },
            else => {},
        }
    }
}

fn collectSemanticRefs(
    sg_nodes: []const *sg.SGNode,
    function_refs: *std.array_list.Managed(SemanticFunctionDeclRef),
    call_refs: *std.array_list.Managed(SemanticFunctionCallRef),
    type_refs: *std.array_list.Managed(SemanticTypeDeclRef),
) !void {
    var stack = std.array_list.Managed(*const sg.SGNode).init(function_refs.allocator);
    defer stack.deinit();
    for (sg_nodes) |node| try stack.append(node);

    while (popOrNull(*const sg.SGNode, &stack)) |node| {
        switch (node.content) {
            .function_declaration => |decl| {
                try function_refs.append(.{ .node = node, .decl = decl });
                try appendSgChildren(&stack, node);
            },
            .function_call => |call| {
                try call_refs.append(.{ .node = node, .call = call });
                try appendSgChildren(&stack, node);
            },
            .type_declaration => |decl| try type_refs.append(.{ .decl = decl }),
            else => try appendSgChildren(&stack, node),
        }
    }
}

fn buildFunctionHoverMarkdown(
    allocator: std.mem.Allocator,
    decl: *const sg.FunctionDeclaration,
    syntax_decl_opt: ?st.FunctionDeclaration,
    type_refs: []const SemanticTypeDeclRef,
    source_text: []const u8,
    toks: []const token.Token,
) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    if (syntax_decl_opt) |syntax_decl| {
        if (try collectLeadingCommentBlock(source_text, syntax_decl.name.location)) |comments| {
            try out.appendSlice(comments);
            try out.appendSlice("\n");
        }
        if (!functionHasInferredReachedFields(decl, syntax_decl)) {
            if (try extractFunctionHeaderSource(source_text, toks, syntax_decl)) |header| {
                try out.appendSlice(header);
                return try out.toOwnedSlice();
            }
        }
    }

    try appendGeneratedSignatureText(&out, decl, syntax_decl_opt, type_refs);

    return try out.toOwnedSlice();
}

fn appendGeneratedSignatureText(
    out: *std.array_list.Managed(u8),
    decl: *const sg.FunctionDeclaration,
    syntax_decl_opt: ?st.FunctionDeclaration,
    type_refs: []const SemanticTypeDeclRef,
) !void {
    try out.appendSlice(decl.name);
    try out.appendSlice("(\n");

    for (decl.input.fields, 0..) |field, idx| {
        if (idx != 0) try out.appendSlice(",\n");
        try out.appendSlice("    ");

        const syntax_field = if (syntax_decl_opt) |syntax_decl|
            findSyntaxStructField(syntax_decl.input, field.name)
        else
            null;
        const is_inferred_reach = syntax_field == null and field.default_value != null and field.default_value.?.content == .reach_directive;
        if (is_inferred_reach) try out.appendSlice("*");
        try appendSignatureFieldText(out, field, syntax_field, type_refs);
        if (is_inferred_reach) try out.appendSlice("*");
    }

    if (decl.input.fields.len > 0) try out.appendSlice("\n");
    try out.appendSlice(") -> (");
    for (decl.output.fields, 0..) |field, idx| {
        if (idx != 0) try out.appendSlice(", ");
        try appendSignatureFieldText(out, field, null, type_refs);
    }
    try out.appendSlice(")");
}

fn appendSignatureFieldText(
    out: *std.array_list.Managed(u8),
    field: sg.StructTypeField,
    syntax_field_opt: ?st.StructTypeLiteralField,
    type_refs: []const SemanticTypeDeclRef,
) !void {
    try out.appendSlice(".");
    try out.appendSlice(field.name);
    try out.appendSlice(": ");
    try appendHoverType(out, field.ty, type_refs);

    if (syntax_field_opt) |syntax_field| {
        if (syntax_field.default_value) |dv| {
            if (dv.content == .reach_directive) {
                try out.appendSlice(" = #reach ");
                try appendSyntaxReachDirective(out, dv.content.reach_directive);
                return;
            }
        }
    }

    if (field.default_value) |default_value| {
        if (default_value.content == .reach_directive) {
            try out.appendSlice(" = #reach ");
            try appendReachDirective(out, default_value.content.reach_directive);
        }
    }
}

fn appendHoverType(
    out: *std.array_list.Managed(u8),
    ty: sg.Type,
    type_refs: []const SemanticTypeDeclRef,
) !void {
    if (hoverTypeNameFor(ty, type_refs)) |name| {
        try out.appendSlice(name);
        return;
    }

    if (typ.genericIdentityOf(ty)) |identity| {
        try out.appendSlice(identity.base_name);
        try out.appendSlice("#(");
        for (identity.arg_names, identity.arg_values, 0..) |arg_name, arg_value, idx| {
            if (idx != 0) try out.appendSlice(", ");
            try out.appendSlice(".");
            try out.appendSlice(arg_name);
            try out.appendSlice(": ");
            switch (arg_value) {
                .type => |arg_ty| try appendHoverType(out, arg_ty, type_refs),
                .comptime_int => |value| try out.writer().print("{d}", .{value}),
            }
        }
        try out.appendSlice(")");
        return;
    }

    switch (ty) {
        .builtin => |builtin| try out.appendSlice(@tagName(builtin)),
        .abstract_type => |abstract_ty| try out.appendSlice(abstract_ty.name),
        .pointer_type => |ptr| {
            try out.appendSlice(if (ptr.mutability == .read_write) "$&" else "&");
            try appendHoverType(out, ptr.child.*, type_refs);
        },
        .array_type => |arr| {
            try out.writer().print("[{d}]", .{arr.length});
            try appendHoverType(out, arr.element_type.*, type_refs);
        },
        .struct_type => |_| try out.appendSlice("{...}"),
        .choice_type => |_| try out.appendSlice("choice"),
    }
}

fn hoverTypeNameFor(ty: sg.Type, type_refs: []const SemanticTypeDeclRef) ?[]const u8 {
    for (type_refs) |ref| {
        if (typ.typesExactlyEqual(ref.decl.ty, ty)) return ref.decl.name;
    }
    return null;
}

fn functionHasInferredReachedFields(decl: *const sg.FunctionDeclaration, syntax_decl: st.FunctionDeclaration) bool {
    for (decl.input.fields) |field| {
        if (findSyntaxStructField(syntax_decl.input, field.name) != null) continue;
        if (field.default_value) |default_value| {
            if (default_value.content == .reach_directive) return true;
        }
    }
    return false;
}

fn extractFunctionHeaderSource(
    source_text: []const u8,
    toks: []const token.Token,
    syntax_decl: st.FunctionDeclaration,
) !?[]const u8 {
    const start_idx = findTokenIndexAtOffset(toks, syntax_decl.name.location) orelse return null;
    var paren_depth: usize = 0;
    var idx = start_idx;
    while (idx < toks.len) : (idx += 1) {
        const tk = toks[idx];
        if (!std.mem.eql(u8, tk.location.file, syntax_decl.name.location.file)) continue;
        switch (tk.content) {
            .open_parenthesis => paren_depth += 1,
            .close_parenthesis => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            .equal => if (paren_depth == 0) {
                const raw = source_text[syntax_decl.name.location.offset .. tk.location.offset + 1];
                return std.mem.trimRight(u8, raw, " \t\r\n");
            },
            .new_line => if (paren_depth == 0 and syntax_decl.body == null) {
                const raw = source_text[syntax_decl.name.location.offset..tk.location.offset];
                return std.mem.trimRight(u8, raw, " \t\r\n");
            },
            else => {},
        }
    }
    return null;
}

fn findTokenIndexAtOffset(toks: []const token.Token, loc: token.Location) ?usize {
    for (toks, 0..) |tk, idx| {
        if (!std.mem.eql(u8, tk.location.file, loc.file)) continue;
        if (tk.location.offset == loc.offset) return idx;
    }
    return null;
}

fn collectLeadingCommentBlock(source_text: []const u8, name_loc: token.Location) !?[]const u8 {
    if (name_loc.line <= 1) return null;
    const line_starts = try computeLineStarts(std.heap.page_allocator, source_text);
    defer std.heap.page_allocator.free(line_starts);

    const name_line_idx: usize = @intCast(name_loc.line - 1);
    var current = name_line_idx;
    var first_comment_line: ?usize = null;

    while (current > 0) {
        const prev_line_idx = current - 1;
        const line = lineSlice(source_text, line_starts, prev_line_idx);
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) break;
        if (!std.mem.startsWith(u8, trimmed, "//")) break;
        first_comment_line = prev_line_idx;
        current = prev_line_idx;
    }

    const first = first_comment_line orelse return null;
    const start = line_starts[first];
    const end = line_starts[name_line_idx];
    return std.mem.trimRight(u8, source_text[start..end], "\r\n");
}

fn computeLineStarts(allocator: std.mem.Allocator, text: []const u8) ![]usize {
    var starts = std.array_list.Managed(usize).init(allocator);
    errdefer starts.deinit();
    try starts.append(0);
    for (text, 0..) |ch, idx| {
        if (ch == '\n' and idx + 1 <= text.len) {
            try starts.append(idx + 1);
        }
    }
    return try starts.toOwnedSlice();
}

fn lineSlice(text: []const u8, starts: []const usize, line_idx: usize) []const u8 {
    const start = starts[line_idx];
    const end = if (line_idx + 1 < starts.len) starts[line_idx + 1] else text.len;
    return std.mem.trimRight(u8, text[start..end], "\n");
}

fn collectFunctionInlayHints(
    svc: *LanguageService,
    primary_path: []const u8,
    range: ?Range,
    sg_nodes: []const *sg.SGNode,
    syntax_functions: []const SyntaxFunctionDeclRef,
    out: *std.array_list.Managed(InlayHint),
) !void {
    var stack = std.array_list.Managed(*const sg.SGNode).init(svc.allocator);
    defer stack.deinit();
    for (sg_nodes) |node| try stack.append(node);

    while (popOrNull(*const sg.SGNode, &stack)) |node| {
        switch (node.content) {
            .function_declaration => |fd| {
                if (!std.mem.eql(u8, fd.location.file, primary_path)) {
                    if (fd.body) |body| for (body.nodes) |sub| try stack.append(sub);
                    continue;
                }

                const syntax_fn = findSyntaxFunctionDecl(syntax_functions, fd.location, fd.name) orelse {
                    if (fd.body) |body| for (body.nodes) |sub| try stack.append(sub);
                    continue;
                };
                const hint_pos = positionAfterName(syntax_fn.decl.name.location, syntax_fn.decl.name.string.len);
                if (range) |hint_range| {
                    if (!rangeContainsPosition(hint_range, hint_pos)) {
                        if (fd.body) |body| for (body.nodes) |sub| try stack.append(sub);
                        continue;
                    }
                }

                for (fd.input.fields) |field| {
                    if (syntaxStructTypeHasField(syntax_fn.decl.input, field.name)) continue;
                    const default_node = field.default_value orelse continue;
                    if (default_node.content != .reach_directive) continue;
                    const label = try formatReachedFieldLabel(svc.allocator, field.name, default_node.content.reach_directive);
                    try out.append(.{ .position = hint_pos, .label = label });
                }

                if (fd.body) |body| for (body.nodes) |sub| try stack.append(sub);
            },
            .code_block => |block| {
                for (block.nodes) |sub| try stack.append(sub);
                if (block.ret_val) |ret_val| try stack.append(ret_val);
            },
            .if_statement => |ifs| {
                try stack.append(ifs.condition);
                for (ifs.then_block.nodes) |sub| try stack.append(sub);
                if (ifs.then_block.ret_val) |ret_val| try stack.append(ret_val);
                if (ifs.else_block) |else_block| {
                    for (else_block.nodes) |sub| try stack.append(sub);
                    if (else_block.ret_val) |ret_val| try stack.append(ret_val);
                }
            },
            .while_statement => |while_stmt| {
                try stack.append(while_stmt.condition);
                for (while_stmt.body.nodes) |sub| try stack.append(sub);
                if (while_stmt.body.ret_val) |ret_val| try stack.append(ret_val);
            },
            .for_statement => |for_stmt| {
                if (for_stmt.init) |init| try stack.append(init);
                try stack.append(for_stmt.condition);
                if (for_stmt.increment) |inc| try stack.append(inc);
                for (for_stmt.body.nodes) |sub| try stack.append(sub);
                if (for_stmt.body.ret_val) |ret_val| try stack.append(ret_val);
            },
            .switch_statement => |switch_stmt| {
                try stack.append(switch_stmt.expression);
                for (switch_stmt.cases) |case| {
                    try stack.append(case.value);
                    for (case.body.nodes) |sub| try stack.append(sub);
                    if (case.body.ret_val) |ret_val| try stack.append(ret_val);
                }
                if (switch_stmt.default_case) |default_case| {
                    for (default_case.nodes) |sub| try stack.append(sub);
                    if (default_case.ret_val) |ret_val| try stack.append(ret_val);
                }
            },
            else => appendSgChildren(&stack, node) catch {},
        }
    }
}

fn collectCallInlayHints(
    svc: *LanguageService,
    primary_path: []const u8,
    range: ?Range,
    sg_nodes: []const *sg.SGNode,
    syntax_calls: []const SyntaxFunctionCallRef,
    toks: []const token.Token,
    out: *std.array_list.Managed(InlayHint),
) !void {
    var stack = std.array_list.Managed(*const sg.SGNode).init(svc.allocator);
    defer stack.deinit();
    for (sg_nodes) |node| try stack.append(node);

    while (popOrNull(*const sg.SGNode, &stack)) |node| {
        switch (node.content) {
            .function_call => |call| {
                if (!std.mem.eql(u8, node.location.file, primary_path)) continue;
                const syntax_call = findSyntaxFunctionCall(syntax_calls, node.location, call.callee.name) orelse continue;
                const hint_pos = positionAfterCallInput(toks, syntax_call.call.input.location) orelse
                    positionAfterName(syntax_call.call.callee_loc, syntax_call.call.callee.len);
                if (range) |hint_range| {
                    if (!rangeContainsPosition(hint_range, hint_pos)) continue;
                }
                if (call.input.content != .struct_value_literal) continue;
                const actual_input = call.input.content.struct_value_literal;
                for (call.callee.input.fields) |field| {
                    const default_node = field.default_value orelse continue;
                    if (default_node.content != .reach_directive) continue;
                    if (syntaxCallHasExplicitField(syntax_call.call, field.name)) continue;
                    if (findStructValueField(actual_input.fields, field.name) == null) continue;
                    const label = try formatReachedFieldLabel(svc.allocator, field.name, default_node.content.reach_directive);
                    try out.append(.{ .position = hint_pos, .label = label });
                }
            },
            else => try appendSgChildren(&stack, node),
        }
    }
}

fn appendSgChildren(stack: *std.array_list.Managed(*const sg.SGNode), node: *const sg.SGNode) !void {
    switch (node.content) {
        .function_declaration => |fd| {
            if (fd.body) |body| {
                for (body.nodes) |sub| try stack.append(sub);
                if (body.ret_val) |ret_val| try stack.append(ret_val);
            }
        },
        .binding_declaration => |binding| if (binding.initialization) |init| try stack.append(init),
        .binding_assignment => |assign| try stack.append(assign.value),
        .auto_deinit_binding => {},
        .function_call => |call| try stack.append(call.input),
        .code_block => |block| {
            for (block.nodes) |sub| try stack.append(sub);
            if (block.ret_val) |ret_val| try stack.append(ret_val);
        },
        .choice_literal => |lit| if (lit.payload) |payload| try stack.append(payload),
        .list_literal => |list| for (list.elements) |elem| try stack.append(elem),
        .struct_value_literal => |sv| for (sv.fields) |field| try stack.append(field.value),
        .struct_field_access => |sfa| try stack.append(sfa.struct_value),
        .choice_payload_access => |acc| try stack.append(acc.choice_value),
        .array_literal => |arr| for (arr.elements) |elem| try stack.append(elem),
        .array_index => |idx| {
            try stack.append(idx.array_ptr);
            try stack.append(idx.index);
        },
        .array_store => |store| {
            try stack.append(store.array_ptr);
            try stack.append(store.index);
            try stack.append(store.value);
        },
        .struct_field_store => |store| {
            try stack.append(store.struct_ptr);
            try stack.append(store.value);
        },
        .binary_operation => |bo| {
            try stack.append(bo.left);
            try stack.append(bo.right);
        },
        .comparison => |cmp| {
            try stack.append(cmp.left);
            try stack.append(cmp.right);
        },
        .return_statement => |ret| if (ret.expression) |expr| try stack.append(expr),
        .if_statement => |ifs| {
            try stack.append(ifs.condition);
            for (ifs.then_block.nodes) |sub| try stack.append(sub);
            if (ifs.then_block.ret_val) |ret_val| try stack.append(ret_val);
            if (ifs.else_block) |else_block| {
                for (else_block.nodes) |sub| try stack.append(sub);
                if (else_block.ret_val) |ret_val| try stack.append(ret_val);
            }
        },
        .while_statement => |while_stmt| {
            try stack.append(while_stmt.condition);
            for (while_stmt.body.nodes) |sub| try stack.append(sub);
            if (while_stmt.body.ret_val) |ret_val| try stack.append(ret_val);
        },
        .for_statement => |for_stmt| {
            if (for_stmt.init) |init| try stack.append(init);
            try stack.append(for_stmt.condition);
            if (for_stmt.increment) |inc| try stack.append(inc);
            for (for_stmt.body.nodes) |sub| try stack.append(sub);
            if (for_stmt.body.ret_val) |ret_val| try stack.append(ret_val);
        },
        .switch_statement => |switch_stmt| {
            try stack.append(switch_stmt.expression);
            for (switch_stmt.cases) |case| {
                try stack.append(case.value);
                for (case.body.nodes) |sub| try stack.append(sub);
                if (case.body.ret_val) |ret_val| try stack.append(ret_val);
            }
            if (switch_stmt.default_case) |default_case| {
                for (default_case.nodes) |sub| try stack.append(sub);
                if (default_case.ret_val) |ret_val| try stack.append(ret_val);
            }
        },
        .address_of => |inner| try stack.append(inner),
        .dereference => |deref| try stack.append(deref.pointer),
        .pointer_assignment => |pa| {
            try stack.append(pa.pointer);
            try stack.append(pa.value);
        },
        .type_initializer => |init| try stack.append(init.args),
        .explicit_cast => |cast| try stack.append(cast.value),
        .move_value => |inner| try stack.append(inner),
        else => {},
    }
}

fn findSyntaxFunctionDecl(
    refs: []const SyntaxFunctionDeclRef,
    loc: token.Location,
    name: []const u8,
) ?SyntaxFunctionDeclRef {
    for (refs) |ref| {
        if (!sameLocation(ref.node.location, loc)) continue;
        if (!std.mem.eql(u8, ref.decl.name.string, name)) continue;
        return ref;
    }
    return null;
}

fn findSyntaxFunctionCall(
    refs: []const SyntaxFunctionCallRef,
    loc: token.Location,
    callee: []const u8,
) ?SyntaxFunctionCallRef {
    for (refs) |ref| {
        if (!sameLocation(ref.node.location, loc)) continue;
        if (!std.mem.eql(u8, ref.call.callee, callee)) continue;
        return ref;
    }
    return null;
}

fn findSemanticFunctionDecl(
    refs: []const SemanticFunctionDeclRef,
    loc: token.Location,
    name: []const u8,
) ?SemanticFunctionDeclRef {
    for (refs) |ref| {
        if (!sameLocation(ref.decl.location, loc)) continue;
        if (!std.mem.eql(u8, ref.decl.name, name)) continue;
        return ref;
    }
    return null;
}

fn findSemanticFunctionCall(
    refs: []const SemanticFunctionCallRef,
    loc: token.Location,
    callee: []const u8,
) ?SemanticFunctionCallRef {
    for (refs) |ref| {
        if (!sameLocation(ref.node.location, loc)) continue;
        if (!std.mem.eql(u8, ref.call.callee.name, callee)) continue;
        return ref;
    }
    return null;
}

fn sameLocation(a: token.Location, b: token.Location) bool {
    return std.mem.eql(u8, a.file, b.file) and a.offset == b.offset;
}

fn nameRange(loc: token.Location, byte_len: usize) Range {
    const line = if (loc.line == 0) 0 else loc.line - 1;
    const start_char = if (loc.column == 0) 0 else loc.column - 1;
    return .{
        .start = .{ .line = line, .character = start_char },
        .end = .{ .line = line, .character = start_char + @as(u32, @intCast(byte_len)) },
    };
}

fn positionWithinName(pos: Position, loc: token.Location, byte_len: usize) bool {
    const range = nameRange(loc, byte_len);
    return positionLessOrEqual(range.start, pos) and positionLessOrEqual(pos, range.end);
}

fn findSyntaxStructField(stl: st.StructTypeLiteral, field_name: []const u8) ?st.StructTypeLiteralField {
    for (stl.fields) |field| {
        if (std.mem.eql(u8, field.name.string, field_name)) return field;
    }
    return null;
}

fn syntaxStructTypeHasField(stl: st.StructTypeLiteral, field_name: []const u8) bool {
    for (stl.fields) |field| {
        if (std.mem.eql(u8, field.name.string, field_name)) return true;
    }
    return false;
}

fn syntaxCallHasExplicitField(call: st.FunctionCall, field_name: []const u8) bool {
    return switch (call.input.content) {
        .struct_value_literal => |sv| blk: {
            for (sv.fields) |field| {
                if (std.mem.eql(u8, field.name.string, field_name)) break :blk true;
            }
            break :blk false;
        },
        .struct_type_literal => |stl| blk: {
            for (stl.fields) |field| {
                if (std.mem.eql(u8, field.name.string, field_name)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn findStructValueField(fields: []const sg.StructValueLiteralField, field_name: []const u8) ?*const sg.StructValueLiteralField {
    for (fields) |*field| {
        if (std.mem.eql(u8, field.name, field_name)) return field;
    }
    return null;
}

fn formatReachedFieldLabel(
    allocator: std.mem.Allocator,
    field_name: []const u8,
    reach: *const sg.ReachDirective,
) ![]u8 {
    var text = std.array_list.Managed(u8).init(allocator);
    errdefer text.deinit();

    try text.appendSlice(".");
    try text.appendSlice(field_name);
    try text.appendSlice(" = #reach ");

    for (reach.alternatives, 0..) |alt, alt_idx| {
        if (alt_idx != 0) try text.appendSlice(", ");
        for (alt.segments, 0..) |segment, seg_idx| {
            if (seg_idx != 0) try text.appendSlice(".");
            try text.appendSlice(segment);
        }
    }

    return try text.toOwnedSlice();
}

fn appendSyntaxReachDirective(out: *std.array_list.Managed(u8), reach: st.ReachDirective) !void {
    for (reach.alternatives, 0..) |alt, alt_idx| {
        if (alt_idx != 0) try out.appendSlice(", ");
        for (alt.segments, 0..) |segment, seg_idx| {
            if (seg_idx != 0) try out.appendSlice(".");
            try out.appendSlice(segment.string);
        }
    }
}

fn appendReachDirective(out: *std.array_list.Managed(u8), reach: *const sg.ReachDirective) !void {
    for (reach.alternatives, 0..) |alt, alt_idx| {
        if (alt_idx != 0) try out.appendSlice(", ");
        for (alt.segments, 0..) |segment, seg_idx| {
            if (seg_idx != 0) try out.appendSlice(".");
            try out.appendSlice(segment);
        }
    }
}

fn positionAfterName(loc: token.Location, byte_len: usize) Position {
    const line = if (loc.line == 0) 0 else loc.line - 1;
    const start_char = if (loc.column == 0) 0 else loc.column - 1;
    return .{
        .line = line,
        .character = start_char + @as(u32, @intCast(byte_len)),
    };
}

fn positionAfterCallInput(toks: []const token.Token, input_loc: token.Location) ?Position {
    var start_idx: ?usize = null;
    for (toks, 0..) |tk, idx| {
        if (!std.mem.eql(u8, tk.location.file, input_loc.file)) continue;
        if (tk.location.offset != input_loc.offset) continue;
        if (tk.content != .open_parenthesis) continue;
        start_idx = idx;
        break;
    }

    const idx0 = start_idx orelse return null;
    var depth: usize = 0;
    var idx = idx0;
    while (idx < toks.len) : (idx += 1) {
        const tk = toks[idx];
        if (!std.mem.eql(u8, tk.location.file, input_loc.file)) continue;
        switch (tk.content) {
            .open_parenthesis => depth += 1,
            .close_parenthesis => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) {
                    const line = if (tk.location.line == 0) 0 else tk.location.line - 1;
                    const start_char = if (tk.location.column == 0) 0 else tk.location.column - 1;
                    return .{
                        .line = line,
                        .character = start_char + 1,
                    };
                }
            },
            else => {},
        }
    }

    return null;
}

fn rangeContainsPosition(range: Range, pos: Position) bool {
    return positionLessOrEqual(range.start, pos) and positionLessOrEqual(pos, range.end);
}

fn positionLessOrEqual(lhs: Position, rhs: Position) bool {
    return if (lhs.line == rhs.line)
        lhs.character <= rhs.character
    else
        lhs.line < rhs.line;
}

fn locationToRange(loc: token.Location) Range {
    const start_line = if (loc.line == 0) 0 else loc.line - 1;
    const start_char = if (loc.column == 0) 0 else loc.column - 1;
    return .{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = start_line, .character = start_char + 1 },
    };
}

fn firstImportRange(text: []const u8) Range {
    if (std.mem.indexOf(u8, text, "#import(\"")) |offset| {
        var line: u32 = 0;
        var col: u32 = 0;
        var idx: usize = 0;
        while (idx < offset) : (idx += 1) {
            if (text[idx] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return .{
            .start = .{ .line = line, .character = col },
            .end = .{ .line = line, .character = col + 1 },
        };
    }
    return .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 1 },
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

    var builder = std.array_list.Managed(u8).init(allocator);
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
    outp: *std.array_list.Managed(u32),
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
            else => TOKEN_INDEX.number,
        },

        .keyword_return, .keyword_if, .keyword_else, .keyword_match, .keyword_for, .keyword_in, .keyword_while => TOKEN_INDEX.keyword,

        .comparison_operator, .binary_operator, .equal, .arrow, .colon, .double_colon, .dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar => TOKEN_INDEX.operator,

        .new_line, .eof => null,
    };
}

fn emitLexical(
    out: *std.array_list.Managed(u32),
    gpa: std.mem.Allocator,
    text: []const u8,
    toks: []const token.Token,
) !void {
    _ = gpa;

    var prev_line: u32 = 0;
    var prev_char: u32 = 0;

    for (toks) |tk| {
        const ty_opt = classify_lex_only(tk.content) orelse continue;

        const start_off: usize = tk.location.offset;
        const len_bytes: usize = tokenLenBytes(tk);
        const end_off: usize = start_off + len_bytes;

        var line0: u32 = if (tk.location.line == 0) 0 else tk.location.line - 1;
        var col0: u32 = if (tk.location.column == 0) 0 else tk.location.column - 1;

        var off = start_off;
        while (off < end_off) {
            const rest = text[off..end_off];
            const nl_rel = std.mem.indexOfScalar(u8, rest, '\n');

            if (nl_rel) |r| {
                if (r > 0) {
                    try pushEncoded(out, &prev_line, &prev_char, line0, col0, @intCast(r), ty_opt, 0);
                    col0 += @intCast(r);
                }
                off += r + 1;
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
            .char_literal => 3,
            .bool_literal => |b| if (b) 4 else 5,
        },

        .keyword_return => "return".len,
        .keyword_if => "if".len,
        .keyword_else => "else".len,
        .keyword_match => "match".len,
        .keyword_for => "for".len,
        .keyword_in => "in".len,
        .keyword_while => "while".len,

        .double_colon => 2,
        .arrow => 2,
        .comparison_operator => 2,
        .binary_operator => 2,

        .new_line => 1,

        .equal, .colon, .dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar, .tilde, .eof => 1,
        .double_dot => 2,
    };
}

inline fn classify_lex_only(c: token.Content) ?u32 {
    return switch (c) {
        .comment => TOKEN_INDEX.comment,
        .literal => |lit| switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal, .regular_float_literal, .scientific_float_literal => TOKEN_INDEX.number,
            .string_literal, .char_literal => TOKEN_INDEX.string,
            .bool_literal => TOKEN_INDEX.keyword,
        },
        .keyword_return, .keyword_if, .keyword_else, .keyword_match, .keyword_for, .keyword_in, .keyword_while => TOKEN_INDEX.keyword,
        .comparison_operator, .binary_operator, .equal, .arrow, .colon, .double_colon, .dot, .double_dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar, .tilde => TOKEN_INDEX.operator,
        .identifier => null,
        .new_line, .eof => null,
    };
}

inline fn popOrNull(comptime T: type, list: *std.array_list.Managed(T)) ?T {
    if (list.items.len == 0) return null;
    return list.pop();
}

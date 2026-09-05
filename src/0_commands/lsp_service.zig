const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const sg = @import("../4_semantics/semantic_graph.zig");
const typ = @import("../4_semantics/types.zig");
const frontend = @import("frontend_pipeline.zig");
const test_support = @import("../test_support.zig");

const log = std.log.scoped(.lsp_service);
const tmpRootPath = test_support.tmpRootPath;
const tmpFilePath = test_support.tmpFilePath;

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

pub const Definition = struct {
    path: []u8,
    range: Range,

    pub fn deinit(self: Definition, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

pub const PrepareRename = struct {
    range: Range,
    placeholder: []u8,

    pub fn deinit(self: PrepareRename, allocator: std.mem.Allocator) void {
        allocator.free(self.placeholder);
    }
};

pub const Location = struct {
    path: []u8,
    range: Range,

    pub fn deinit(self: Location, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

pub const LocationsResult = struct {
    allocator: std.mem.Allocator,
    items: []Location,
    owned: bool,

    pub fn empty(allocator: std.mem.Allocator) LocationsResult {
        return .{ .allocator = allocator, .items = &[_]Location{}, .owned = false };
    }

    pub fn deinit(self: LocationsResult) void {
        if (!self.owned) return;
        for (self.items) |item| item.deinit(self.allocator);
        self.allocator.free(self.items);
    }
};

pub const TextEdit = struct {
    path: []u8,
    range: Range,
    new_text: []u8,

    pub fn deinit(self: TextEdit, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.new_text);
    }
};

pub const TextEditsResult = struct {
    allocator: std.mem.Allocator,
    items: []TextEdit,
    owned: bool,

    pub fn empty(allocator: std.mem.Allocator) TextEditsResult {
        return .{ .allocator = allocator, .items = &[_]TextEdit{}, .owned = false };
    }

    pub fn deinit(self: TextEditsResult) void {
        if (!self.owned) return;
        for (self.items) |item| item.deinit(self.allocator);
        self.allocator.free(self.items);
    }
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

const SyntaxName = struct {
    location: token.Location,
    string: []const u8,
};

const SyntaxStructShape = struct {
    field_names: []const []const u8,
};

const SyntaxFunctionShape = struct {
    name: SyntaxName,
    input: SyntaxStructShape,
    has_body: bool,
};

const SyntaxCallShape = struct {
    callee: []const u8,
    callee_loc: token.Location,
    input_location: token.Location,
    field_names: []const []const u8,
};

const SyntaxFunctionDeclRef = struct {
    node: st.SyntaxRef,
    decl: SyntaxFunctionShape,
};

const SyntaxFunctionCallRef = struct {
    node: st.SyntaxRef,
    call: SyntaxCallShape,
};

const SyntaxOperatorRef = struct {
    location: token.Location,
    name: []const u8,
    len: usize,
};

const SemanticFunctionDeclRef = struct {
    node: *const sg.SGNode,
    decl: *const sg.FunctionDeclaration,
};

const SemanticFunctionCallRef = struct {
    node: *const sg.SGNode,
    call: *const sg.FunctionCall,
};

const SemanticTypeInitializerRef = struct {
    node: *const sg.SGNode,
    init: sg.TypeInitializer,
};

const SemanticTypeDeclRef = struct {
    decl: *const sg.TypeDeclaration,
};

const SyntaxBindingDeclRef = struct {
    location: token.Location,
    name: []const u8,
};

const SemanticBindingDeclRef = struct {
    node: *const sg.SGNode,
    decl: *const sg.BindingDeclaration,
};

const SemanticBindingUseRef = struct {
    node: *const sg.SGNode,
    binding: *const sg.BindingDeclaration,
};

const SemanticFieldAccessRef = struct {
    node: *const sg.SGNode,
    access: *const sg.StructFieldAccess,
};

const SyntaxTypeDeclRef = struct {
    node: st.SyntaxRef,
    name: SyntaxName,
    fields: []const SyntaxName,
};

const SyntaxTypeRef = struct {
    location: token.Location,
    name: []const u8,
};

const SymbolTargetTag = enum {
    function_decl,
    binding_decl,
    type_decl,
};

const SymbolTarget = union(SymbolTargetTag) {
    function_decl: *const sg.FunctionDeclaration,
    binding_decl: *const sg.BindingDeclaration,
    type_decl: *const sg.TypeDeclaration,
};

const ModuleAnalysis = struct {
    source_db: source_db.SourceDb,
    tokens: token.View,
    sg_nodes: []const *sg.SGNode,
    syntax_functions: []const SyntaxFunctionDeclRef,
    syntax_calls: []const SyntaxFunctionCallRef,
    syntax_operators: []const SyntaxOperatorRef,
    syntax_type_decls: []const SyntaxTypeDeclRef,
    syntax_type_refs: []const SyntaxTypeRef,
    syntax_binding_decls: []const SyntaxBindingDeclRef,
    semantic_functions: []const SemanticFunctionDeclRef,
    semantic_calls: []const SemanticFunctionCallRef,
    semantic_type_inits: []const SemanticTypeInitializerRef,
    semantic_types: []const SemanticTypeDeclRef,
    semantic_binding_decls: []const SemanticBindingDeclRef,
    semantic_binding_uses: []const SemanticBindingUseRef,
    semantic_field_accesses: []const SemanticFieldAccessRef,

    fn path(self: *const ModuleAnalysis, loc: token.Location) []const u8 {
        return self.source_db.path(loc.file);
    }

    fn isPath(self: *const ModuleAnalysis, loc: token.Location, wanted_path: []const u8) bool {
        return std.mem.eql(u8, self.path(loc), wanted_path);
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
    io: std.Io,
    documents: std.array_list.Managed(Document),
    root_path: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) LanguageService {
        return .{
            .allocator = allocator,
            .io = io,
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

    fn ownedDefinitionPath(self: *LanguageService, raw_path: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(raw_path)) {
            return try self.allocator.dupe(u8, raw_path);
        }
        if (self.root_path) |root_path| {
            return try std.fs.path.join(self.allocator, &.{ root_path, raw_path });
        }
        return try self.allocator.dupe(u8, raw_path);
    }

    fn preferredCoreDir(self: *LanguageService, allocator: std.mem.Allocator) ![]u8 {
        if (self.root_path) |root_path| {
            return try std.fs.path.join(allocator, &.{ root_path, "core" });
        }
        return try allocator.dupe(u8, "core");
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
        if (!documentShouldAcceptVersion(self.documents.items[idx], version)) {
            return try self.analyzeDocument(&self.documents.items[idx]);
        }
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
        const core_dir = try self.preferredCoreDir(analysis_allocator);

        const files_list = sf.collectWithEntrySource(&analysis_allocator, self.io, core_dir, doc.path, doc.text) catch |err| {
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

        var pipeline_failed = false;
        var pipeline = frontend.FrontendPipeline.init(analysis_allocator.*, self.io, &diagnostics, .{});
        defer pipeline.deinit();

        _ = pipeline.semantizeFiles(files) catch {
            pipeline_failed = true;
        };

        var out = std.array_list.Managed(Diagnostic).init(self.allocator);
        errdefer {
            for (out.items) |d| self.allocator.free(d.message);
            out.deinit();
        }

        for (diagnostics.list.items) |entry| {
            if (!std.mem.eql(u8, pipeline.source_db.path(entry.loc.file), primary_path)) continue;
            const msg_copy = self.allocator.dupe(u8, entry.msg) catch |err| {
                return err;
            };
            const range = locationToRange(pipeline.source_db, entry.loc);
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

    fn collectModuleFilesForDocument(
        self: *LanguageService,
        analysis_allocator: *std.mem.Allocator,
        doc: *Document,
    ) ![]const sf.SourceFile {
        const core_dir = try self.preferredCoreDir(analysis_allocator.*);
        const files_list = try sf.collectWithEntrySource(analysis_allocator, self.io, core_dir, doc.path, doc.text);

        for (files_list.items) |*source_file| {
            for (self.documents.items) |open_doc| {
                if (std.mem.eql(u8, source_file.path, open_doc.path)) {
                    source_file.code = open_doc.text;
                    break;
                }
            }
        }

        return files_list.items;
    }

    fn collectModuleAnalysis(
        self: *LanguageService,
        analysis_allocator: *std.mem.Allocator,
        doc: *Document,
    ) !?ModuleAnalysis {
        const files = self.collectModuleFilesForDocument(analysis_allocator, doc) catch |err| {
            log.err("collectModuleFilesForDocument failed for '{s}': {s}", .{ doc.path, @errorName(err) });
            return null;
        };

        // The semantizing pipeline also uses compiler-owned SourceFile origin
        // metadata to bind safety primitives. Keep the complete module here;
        // consumers can still filter diagnostics to the primary document.
        var diagnostics = diag.Diagnostics.init(analysis_allocator, files);
        defer diagnostics.deinit();

        var pipeline = frontend.FrontendPipeline.init(analysis_allocator.*, self.io, &diagnostics, .{});
        defer pipeline.deinit();

        const sg_nodes = pipeline.semantizeFiles(files) catch |err| {
            if (pipeline.syntax_ctx == null) {
                log.err("syntaxing failed for '{s}': {s}", .{ doc.path, @errorName(err) });
            } else {
                log.err("semantizing failed for '{s}': {s}", .{ doc.path, @errorName(err) });
            }
            return null;
        };
        const syntax_roots = pipeline.syntax_roots;
        var syntax_functions = std.array_list.Managed(SyntaxFunctionDeclRef).init(analysis_allocator.*);
        defer syntax_functions.deinit();
        var syntax_calls = std.array_list.Managed(SyntaxFunctionCallRef).init(analysis_allocator.*);
        defer syntax_calls.deinit();
        var syntax_operators = std.array_list.Managed(SyntaxOperatorRef).init(analysis_allocator.*);
        defer syntax_operators.deinit();
        var syntax_type_decls = std.array_list.Managed(SyntaxTypeDeclRef).init(analysis_allocator.*);
        defer syntax_type_decls.deinit();
        var syntax_type_refs = std.array_list.Managed(SyntaxTypeRef).init(analysis_allocator.*);
        defer syntax_type_refs.deinit();
        var syntax_binding_decls = std.array_list.Managed(SyntaxBindingDeclRef).init(analysis_allocator.*);
        defer syntax_binding_decls.deinit();
        try collectSyntaxRefs(pipeline.syntax_files.items, pipeline.source_db, syntax_roots, &syntax_functions, &syntax_calls, &syntax_operators, &syntax_type_decls, &syntax_type_refs, &syntax_binding_decls);

        var semantic_functions = std.array_list.Managed(SemanticFunctionDeclRef).init(analysis_allocator.*);
        defer semantic_functions.deinit();
        var semantic_calls = std.array_list.Managed(SemanticFunctionCallRef).init(analysis_allocator.*);
        defer semantic_calls.deinit();
        var semantic_type_inits = std.array_list.Managed(SemanticTypeInitializerRef).init(analysis_allocator.*);
        defer semantic_type_inits.deinit();
        var semantic_types = std.array_list.Managed(SemanticTypeDeclRef).init(analysis_allocator.*);
        defer semantic_types.deinit();
        var semantic_binding_decls = std.array_list.Managed(SemanticBindingDeclRef).init(analysis_allocator.*);
        defer semantic_binding_decls.deinit();
        var semantic_binding_uses = std.array_list.Managed(SemanticBindingUseRef).init(analysis_allocator.*);
        defer semantic_binding_uses.deinit();
        var semantic_field_accesses = std.array_list.Managed(SemanticFieldAccessRef).init(analysis_allocator.*);
        defer semantic_field_accesses.deinit();
        try collectSemanticRefs(sg_nodes, &semantic_functions, &semantic_calls, &semantic_type_inits, &semantic_types, &semantic_binding_decls, &semantic_binding_uses, &semantic_field_accesses);

        return .{
            .source_db = try pipeline.source_db.clone(analysis_allocator.*),
            .tokens = try (pipeline.tokensForPath(doc.path) orelse token.View{}).clone(analysis_allocator.*),
            .sg_nodes = sg_nodes,
            .syntax_functions = try syntax_functions.toOwnedSlice(),
            .syntax_calls = try syntax_calls.toOwnedSlice(),
            .syntax_operators = try syntax_operators.toOwnedSlice(),
            .syntax_type_decls = try syntax_type_decls.toOwnedSlice(),
            .syntax_type_refs = try syntax_type_refs.toOwnedSlice(),
            .syntax_binding_decls = try syntax_binding_decls.toOwnedSlice(),
            .semantic_functions = try semantic_functions.toOwnedSlice(),
            .semantic_calls = try semantic_calls.toOwnedSlice(),
            .semantic_type_inits = try semantic_type_inits.toOwnedSlice(),
            .semantic_types = try semantic_types.toOwnedSlice(),
            .semantic_binding_decls = try semantic_binding_decls.toOwnedSlice(),
            .semantic_binding_uses = try semantic_binding_uses.toOwnedSlice(),
            .semantic_field_accesses = try semantic_field_accesses.toOwnedSlice(),
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

        var pipeline = frontend.FrontendPipeline.init(work, self.io, &diagnostics, .{});
        defer pipeline.deinit();

        _ = pipeline.parseFiles(&one_file) catch {
            const toks = pipeline.tokensForPath(doc.path) orelse token.View{};
            if (toks.len == 0) return out;

            try emitLexical(&out, gpa, pipeline.source_db, text, toks);
            return out;
        };

        const toks = pipeline.tokensForPath(doc.path) orelse token.View{};
        if (toks.len == 0) return out;
        var collected = std.array_list.Managed(SemanticToken).init(work);
        defer collected.deinit();

        try appendLexicalSemanticTokens(&collected, pipeline.source_db, text, toks);

        for (pipeline.syntax_files.items) |*tree| {
            try appendCompactSyntaxSemanticTokens(&collected, pipeline.source_db, tree);
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
        const analysis = (try self.collectModuleAnalysis(&analysis_allocator, doc)) orelse return null;
        for (analysis.syntax_functions) |syntax_fn| {
            if (!analysis.isPath(syntax_fn.decl.name.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_fn.decl.name.location, syntax_fn.decl.name.string.len)) continue;
            const contents = if (findSemanticFunctionDecl(analysis.semantic_functions, syntax_fn.decl.name.location, syntax_fn.decl.name.string)) |semantic_fn|
                try buildFunctionHoverMarkdown(
                    self.allocator,
                    &analysis.source_db,
                    semantic_fn.decl,
                    syntax_fn.decl,
                    analysis.semantic_types,
                    doc.path,
                    doc.text,
                    analysis.tokens,
                )
            else
                try buildSyntaxFunctionHoverMarkdown(self.allocator, &analysis.source_db, syntax_fn.decl, doc.path, doc.text, analysis.tokens);
            return .{
                .range = nameRange(&analysis.source_db, syntax_fn.decl.name.location, syntax_fn.decl.name.string.len),
                .contents = contents,
            };
        }

        for (analysis.syntax_calls) |syntax_call| {
            if (!analysis.isPath(syntax_call.call.callee_loc, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_call.call.callee_loc, syntax_call.call.callee.len)) continue;
            if (findSemanticTypeInitializerAtLocation(analysis.semantic_type_inits, syntax_call.call.callee_loc)) |type_init| {
                const syntax_decl = findSyntaxFunctionDecl(
                    analysis.syntax_functions,
                    type_init.init.init_fn.location,
                    type_init.init.init_fn.name,
                );
                const contents = try buildFunctionHoverMarkdown(
                    self.allocator,
                    &analysis.source_db,
                    type_init.init.init_fn,
                    if (syntax_decl) |decl_ref| decl_ref.decl else null,
                    analysis.semantic_types,
                    doc.path,
                    doc.text,
                    analysis.tokens,
                );
                return .{
                    .range = nameRange(&analysis.source_db, syntax_call.call.callee_loc, syntax_call.call.callee.len),
                    .contents = contents,
                };
            }
            const callee = if (findSemanticFunctionCall(analysis.semantic_calls, syntax_call.call.callee_loc, syntax_call.call.callee)) |semantic_call|
                semantic_call.call.callee
            else if (findSemanticFunctionDeclByName(analysis.semantic_functions, syntax_call.call.callee)) |semantic_fn|
                semantic_fn.decl
            else if (findSyntaxFunctionDeclByName(analysis.syntax_functions, syntax_call.call.callee)) |syntax_decl| {
                const contents = try buildSyntaxFunctionHoverMarkdown(self.allocator, &analysis.source_db, syntax_decl.decl, doc.path, doc.text, analysis.tokens);
                return .{
                    .range = nameRange(&analysis.source_db, syntax_call.call.callee_loc, syntax_call.call.callee.len),
                    .contents = contents,
                };
            } else continue;
            const syntax_decl = findSyntaxFunctionDecl(analysis.syntax_functions, callee.location, callee.name);
            const contents = try buildFunctionHoverMarkdown(
                self.allocator,
                &analysis.source_db,
                callee,
                if (syntax_decl) |decl_ref| decl_ref.decl else null,
                analysis.semantic_types,
                doc.path,
                doc.text,
                analysis.tokens,
            );
            return .{
                .range = nameRange(&analysis.source_db, syntax_call.call.callee_loc, syntax_call.call.callee.len),
                .contents = contents,
            };
        }
        for (analysis.syntax_operators) |syntax_op| {
            if (!analysis.isPath(syntax_op.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_op.location, syntax_op.len)) continue;
            const semantic_call = findSemanticFunctionCallAtLocation(analysis.semantic_calls, syntax_op.location) orelse continue;
            const syntax_decl = findSyntaxFunctionDecl(analysis.syntax_functions, semantic_call.call.callee.location, semantic_call.call.callee.name);
            const contents = try buildFunctionHoverMarkdown(
                self.allocator,
                &analysis.source_db,
                semantic_call.call.callee,
                if (syntax_decl) |decl_ref| decl_ref.decl else null,
                analysis.semantic_types,
                doc.path,
                doc.text,
                analysis.tokens,
            );
            return .{
                .range = nameRange(&analysis.source_db, syntax_op.location, syntax_op.len),
                .contents = contents,
            };
        }

        for (analysis.syntax_type_refs) |type_ref| {
            if (!analysis.isPath(type_ref.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, type_ref.location, type_ref.name.len)) continue;
            const semantic_type_decl = findSemanticTypeDeclByName(analysis.semantic_types, type_ref.name) orelse continue;
            const syntax_type_decl = findSyntaxTypeDeclByName(analysis.syntax_type_decls, type_ref.name);
            const contents = try buildTypeHoverMarkdown(
                self.allocator,
                &analysis.source_db,
                semantic_type_decl.decl,
                syntax_type_decl,
                analysis.semantic_types,
                doc.path,
                doc.text,
            );
            return .{
                .range = nameRange(&analysis.source_db, type_ref.location, type_ref.name.len),
                .contents = contents,
            };
        }

        for (analysis.semantic_binding_decls) |binding_decl| {
            if (!analysis.isPath(binding_decl.node.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, binding_decl.node.location, binding_decl.decl.name.len)) continue;
            const contents = try buildBindingHoverMarkdown(self.allocator, binding_decl.decl, analysis.semantic_types);
            return .{
                .range = nameRange(&analysis.source_db, binding_decl.node.location, binding_decl.decl.name.len),
                .contents = contents,
            };
        }

        for (analysis.semantic_binding_uses) |binding_use| {
            if (!analysis.isPath(binding_use.node.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, binding_use.node.location, binding_use.binding.name.len)) continue;
            const contents = try buildBindingHoverMarkdown(self.allocator, binding_use.binding, analysis.semantic_types);
            return .{
                .range = nameRange(&analysis.source_db, binding_use.node.location, binding_use.binding.name.len),
                .contents = contents,
            };
        }

        return null;
    }

    pub fn definition(self: *LanguageService, uri: []const u8, position: Position) !?Definition {
        const doc = try self.getDoc(uri);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var analysis_allocator = arena.allocator();
        const analysis = (try self.collectModuleAnalysis(&analysis_allocator, doc)) orelse return null;
        for (analysis.syntax_functions) |syntax_fn| {
            if (!analysis.isPath(syntax_fn.decl.name.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_fn.decl.name.location, syntax_fn.decl.name.string.len)) continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(syntax_fn.decl.name.location)),
                .range = nameRange(&analysis.source_db, syntax_fn.decl.name.location, syntax_fn.decl.name.string.len),
            };
        }

        for (analysis.syntax_calls) |syntax_call| {
            if (!analysis.isPath(syntax_call.call.callee_loc, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_call.call.callee_loc, syntax_call.call.callee.len)) continue;
            if (findSemanticTypeInitializerAtLocation(analysis.semantic_type_inits, syntax_call.call.callee_loc)) |type_init| {
                return .{
                    .path = try self.ownedDefinitionPath(analysis.path(type_init.init.init_fn.location)),
                    .range = nameRange(&analysis.source_db, type_init.init.init_fn.location, type_init.init.init_fn.name.len),
                };
            }
            const semantic_call = findSemanticFunctionCallAtLocation(analysis.semantic_calls, syntax_call.call.callee_loc) orelse continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(semantic_call.call.callee.location)),
                .range = nameRange(&analysis.source_db, semantic_call.call.callee.location, semantic_call.call.callee.name.len),
            };
        }

        for (analysis.syntax_operators) |syntax_op| {
            if (!analysis.isPath(syntax_op.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_op.location, syntax_op.len)) continue;
            const semantic_call = findSemanticFunctionCallAtLocation(analysis.semantic_calls, syntax_op.location) orelse continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(semantic_call.call.callee.location)),
                .range = nameRange(&analysis.source_db, semantic_call.call.callee.location, semantic_call.call.callee.name.len),
            };
        }

        for (analysis.syntax_type_decls) |syntax_decl| {
            if (!analysis.isPath(syntax_decl.name.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_decl.name.location, syntax_decl.name.string.len)) continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(syntax_decl.name.location)),
                .range = nameRange(&analysis.source_db, syntax_decl.name.location, syntax_decl.name.string.len),
            };
        }

        for (analysis.syntax_type_refs) |type_ref| {
            if (!analysis.isPath(type_ref.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, type_ref.location, type_ref.name.len)) continue;
            const target = findSyntaxTypeDeclByName(analysis.syntax_type_decls, type_ref.name) orelse continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(target.name.location)),
                .range = nameRange(&analysis.source_db, target.name.location, target.name.string.len),
            };
        }

        for (analysis.semantic_field_accesses) |field_access| {
            if (!analysis.isPath(field_access.node.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, field_access.node.location, field_access.access.field_name.len)) continue;
            const target = findFieldDefinition(&analysis.source_db, field_access, analysis.semantic_types, analysis.syntax_type_decls) orelse continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(target.location)),
                .range = nameRange(&analysis.source_db, target.location, target.string.len),
            };
        }

        for (analysis.syntax_binding_decls) |syntax_decl| {
            if (!analysis.isPath(syntax_decl.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, syntax_decl.location, syntax_decl.name.len)) continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(syntax_decl.location)),
                .range = nameRange(&analysis.source_db, syntax_decl.location, syntax_decl.name.len),
            };
        }

        for (analysis.semantic_binding_decls) |binding_decl| {
            if (!analysis.isPath(binding_decl.node.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, binding_decl.node.location, binding_decl.decl.name.len)) continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(binding_decl.decl.location)),
                .range = nameRange(&analysis.source_db, binding_decl.decl.location, binding_decl.decl.name.len),
            };
        }

        for (analysis.semantic_binding_uses) |binding_use| {
            if (!analysis.isPath(binding_use.node.location, doc.path)) continue;
            if (!positionWithinName(&analysis.source_db, position, binding_use.node.location, binding_use.binding.name.len)) continue;
            return .{
                .path = try self.ownedDefinitionPath(analysis.path(binding_use.binding.location)),
                .range = nameRange(&analysis.source_db, binding_use.binding.location, binding_use.binding.name.len),
            };
        }

        return null;
    }

    pub fn references(
        self: *LanguageService,
        uri: []const u8,
        position: Position,
        include_declaration: bool,
    ) !LocationsResult {
        const doc = try self.getDoc(uri);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var analysis_allocator = arena.allocator();
        const analysis = (try self.collectModuleAnalysis(&analysis_allocator, doc)) orelse return LocationsResult.empty(self.allocator);

        const target = resolveSymbolTarget(
            &analysis.source_db,
            doc.path,
            position,
            analysis.syntax_functions,
            analysis.syntax_calls,
            analysis.syntax_operators,
            analysis.syntax_type_decls,
            analysis.syntax_type_refs,
            analysis.syntax_binding_decls,
            analysis.semantic_functions,
            analysis.semantic_calls,
            analysis.semantic_type_inits,
            analysis.semantic_types,
            analysis.semantic_binding_decls,
            analysis.semantic_binding_uses,
        ) orelse return LocationsResult.empty(self.allocator);

        var out = std.array_list.Managed(Location).init(self.allocator);
        errdefer {
            for (out.items) |item| item.deinit(self.allocator);
            out.deinit();
        }

        switch (target) {
            .function_decl => |fn_decl| {
                if (include_declaration) {
                    try out.append(.{
                        .path = try self.ownedDefinitionPath(analysis.path(fn_decl.location)),
                        .range = nameRange(&analysis.source_db, fn_decl.location, fn_decl.name.len),
                    });
                }
                for (analysis.semantic_calls) |call_ref| {
                    if (call_ref.call.callee != fn_decl) continue;
                    try out.append(.{
                        .path = try self.ownedDefinitionPath(analysis.path(call_ref.node.location)),
                        .range = nameRange(&analysis.source_db, call_ref.node.location, call_ref.call.callee.name.len),
                    });
                }
            },
            .binding_decl => |binding_decl| {
                if (include_declaration) {
                    try out.append(.{
                        .path = try self.ownedDefinitionPath(analysis.path(binding_decl.location)),
                        .range = nameRange(&analysis.source_db, binding_decl.location, binding_decl.name.len),
                    });
                }
                for (analysis.semantic_binding_uses) |use_ref| {
                    if (use_ref.binding != binding_decl) continue;
                    try out.append(.{
                        .path = try self.ownedDefinitionPath(analysis.path(use_ref.node.location)),
                        .range = nameRange(&analysis.source_db, use_ref.node.location, binding_decl.name.len),
                    });
                }
            },
            .type_decl => |type_decl| {
                if (include_declaration) {
                    const syntax_decl = findSyntaxTypeDeclByName(analysis.syntax_type_decls, type_decl.name) orelse return LocationsResult.empty(self.allocator);
                    try out.append(.{
                        .path = try self.ownedDefinitionPath(analysis.path(syntax_decl.name.location)),
                        .range = nameRange(&analysis.source_db, syntax_decl.name.location, type_decl.name.len),
                    });
                }
                for (analysis.syntax_type_refs) |type_ref| {
                    if (!std.mem.eql(u8, type_ref.name, type_decl.name)) continue;
                    try out.append(.{
                        .path = try self.ownedDefinitionPath(analysis.path(type_ref.location)),
                        .range = nameRange(&analysis.source_db, type_ref.location, type_ref.name.len),
                    });
                }
            },
        }

        const slice = try out.toOwnedSlice();
        out.deinit();
        sortLocations(slice);
        return .{
            .allocator = self.allocator,
            .items = slice,
            .owned = true,
        };
    }

    pub fn rename(
        self: *LanguageService,
        uri: []const u8,
        position: Position,
        new_name: []const u8,
    ) !TextEditsResult {
        var refs = try self.references(uri, position, true);
        defer refs.deinit();

        if (refs.items.len == 0) return TextEditsResult.empty(self.allocator);

        var out = std.array_list.Managed(TextEdit).init(self.allocator);
        errdefer {
            for (out.items) |item| item.deinit(self.allocator);
            out.deinit();
        }

        for (refs.items) |ref| {
            try out.append(.{
                .path = try self.allocator.dupe(u8, ref.path),
                .range = ref.range,
                .new_text = try self.allocator.dupe(u8, new_name),
            });
        }

        const slice = try out.toOwnedSlice();
        out.deinit();
        return .{
            .allocator = self.allocator,
            .items = slice,
            .owned = true,
        };
    }

    pub fn prepareRename(
        self: *LanguageService,
        uri: []const u8,
        position: Position,
    ) !?PrepareRename {
        const doc = try self.getDoc(uri);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var analysis_allocator = arena.allocator();
        const analysis = (try self.collectModuleAnalysis(&analysis_allocator, doc)) orelse return null;

        const target = resolveSymbolTarget(
            &analysis.source_db,
            doc.path,
            position,
            analysis.syntax_functions,
            analysis.syntax_calls,
            analysis.syntax_operators,
            analysis.syntax_type_decls,
            analysis.syntax_type_refs,
            analysis.syntax_binding_decls,
            analysis.semantic_functions,
            analysis.semantic_calls,
            analysis.semantic_type_inits,
            analysis.semantic_types,
            analysis.semantic_binding_decls,
            analysis.semantic_binding_uses,
        ) orelse return null;

        return switch (target) {
            .function_decl => |fn_decl| .{
                .range = nameRange(&analysis.source_db, fn_decl.location, fn_decl.name.len),
                .placeholder = try self.allocator.dupe(u8, fn_decl.name),
            },
            .binding_decl => |binding_decl| .{
                .range = nameRange(&analysis.source_db, binding_decl.location, binding_decl.name.len),
                .placeholder = try self.allocator.dupe(u8, binding_decl.name),
            },
            .type_decl => |type_decl| .{
                .range = blk: {
                    const syntax_decl = findSyntaxTypeDeclByName(analysis.syntax_type_decls, type_decl.name) orelse return null;
                    break :blk nameRange(&analysis.source_db, syntax_decl.name.location, type_decl.name.len);
                },
                .placeholder = try self.allocator.dupe(u8, type_decl.name),
            },
        };
    }

    pub fn inlayHints(self: *LanguageService, uri: []const u8, range: ?Range) !InlayHintsResult {
        const doc = try self.getDoc(uri);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var analysis_allocator = arena.allocator();
        const analysis = (try self.collectModuleAnalysis(&analysis_allocator, doc)) orelse return InlayHintsResult.empty(self.allocator);

        var hints = std.array_list.Managed(InlayHint).init(self.allocator);
        errdefer {
            for (hints.items) |hint| self.allocator.free(hint.label);
            hints.deinit();
        }

        try collectFunctionInlayHints(
            self,
            &analysis.source_db,
            doc.path,
            range,
            analysis.sg_nodes,
            analysis.syntax_functions,
            &hints,
        );
        try collectCallInlayHints(
            self,
            &analysis.source_db,
            doc.path,
            range,
            analysis.sg_nodes,
            analysis.syntax_calls,
            analysis.tokens,
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
    syntax_files: []const st.SyntaxFile,
    db: *const source_db.SourceDb,
    syntax_roots: []const st.SyntaxRef,
    function_refs: *std.array_list.Managed(SyntaxFunctionDeclRef),
    call_refs: *std.array_list.Managed(SyntaxFunctionCallRef),
    operator_refs: *std.array_list.Managed(SyntaxOperatorRef),
    type_decl_refs: *std.array_list.Managed(SyntaxTypeDeclRef),
    type_refs: *std.array_list.Managed(SyntaxTypeRef),
    binding_decl_refs: *std.array_list.Managed(SyntaxBindingDeclRef),
) !void {
    var stack = std.array_list.Managed(st.SyntaxRef).init(function_refs.allocator);
    defer stack.deinit();
    for (syntax_roots) |node| try stack.append(node);

    while (popOrNull(st.SyntaxRef, &stack)) |reference| {
        const tree = st.fileForRef(syntax_files, reference);
        const node = reference.node;
        const child_file = tree.file_id;
        switch (tree.tag(node)) {
            .function_declaration, .function_declaration_once => {
                const decl = tree.functionDeclaration(node).?;
                const name = syntaxFunctionName(tree, db, node, decl.name_token);
                try function_refs.append(.{ .node = reference, .decl = .{
                    .name = name,
                    .input = try collectSyntaxStructShape(tree, db, decl.input, binding_decl_refs, type_refs, &stack),
                    .has_body = decl.body != null,
                } });
                _ = try collectSyntaxStructShape(tree, db, decl.output, binding_decl_refs, type_refs, &stack);
                for (decl.generic_params) |param| try stack.append(.{ .file_id = child_file, .node = param });
                if (decl.generic_params_struct) |params| try stack.append(.{ .file_id = child_file, .node = params });
                if (decl.body) |body| try stack.append(.{ .file_id = child_file, .node = body });
            },
            .test_declaration => {
                const decl = tree.testDeclaration(node).?.function;
                _ = try collectSyntaxStructShape(tree, db, decl.input, binding_decl_refs, type_refs, &stack);
                _ = try collectSyntaxStructShape(tree, db, decl.output, binding_decl_refs, type_refs, &stack);
                if (decl.body) |body| try stack.append(.{ .file_id = child_file, .node = body });
            },
            .function_call => {
                const call = tree.functionCall(node).?;
                const callee = tree.tokenText(db, call.callee_token);
                const input_location = tree.location(call.input);
                try call_refs.append(.{ .node = reference, .call = .{
                    .callee = callee,
                    .callee_loc = tree.tokenLocation(call.callee_token),
                    .input_location = input_location,
                    .field_names = try collectSyntaxValueFieldNames(tree, db, call.input, call_refs.allocator),
                } });
                for (call.type_arguments) |arg| try collectTypeRefsFromNode(tree, db, arg, type_refs);
                if (call.type_arguments_struct) |args| try stack.append(.{ .file_id = child_file, .node = args });
                try stack.append(.{ .file_id = child_file, .node = call.input });
            },
            .symbol_declaration_constant, .symbol_declaration_variable => {
                const decl = tree.symbolDeclaration(node).?;
                try binding_decl_refs.append(.{ .location = tree.tokenLocation(decl.name_token), .name = tree.tokenText(db, decl.name_token) });
                if (decl.type_node) |ty| try collectTypeRefsFromNode(tree, db, ty, type_refs);
                if (decl.value) |value| try stack.append(.{ .file_id = child_file, .node = value });
            },
            .type_declaration => {
                const decl = tree.typeDeclaration(node).?;
                try appendSyntaxTypeDeclaration(tree, db, reference, decl.name_token, type_decl_refs);
                for (decl.generic_params) |param| try stack.append(.{ .file_id = child_file, .node = param });
                if (decl.generic_params_struct) |params| try stack.append(.{ .file_id = child_file, .node = params });
                try stack.append(.{ .file_id = child_file, .node = decl.value });
            },
            .c_enum_declaration => {
                const decl = tree.cEnumDeclaration(node).?;
                try appendSyntaxTypeDeclaration(tree, db, reference, decl.name_token, type_decl_refs);
                if (decl.generic_params_struct) |params| try stack.append(.{ .file_id = child_file, .node = params });
                try stack.append(.{ .file_id = child_file, .node = decl.value });
            },
            .c_union_declaration => {
                const decl = tree.cUnionDeclaration(node).?;
                try appendSyntaxTypeDeclaration(tree, db, reference, decl.name_token, type_decl_refs);
                if (decl.generic_params_struct) |params| try stack.append(.{ .file_id = child_file, .node = params });
                try stack.append(.{ .file_id = child_file, .node = decl.value });
            },
            .abstract_declaration => {
                const decl = tree.abstractDeclaration(node).?;
                try appendSyntaxTypeDeclaration(tree, db, reference, decl.name_token, type_decl_refs);
                for (decl.generic_params) |param| try stack.append(.{ .file_id = child_file, .node = param });
                if (decl.generic_params_struct) |params| try stack.append(.{ .file_id = child_file, .node = params });
                for (decl.requires_abstracts) |requirement| try stack.append(.{ .file_id = child_file, .node = requirement });
                for (decl.requires_functions) |requirement| try stack.append(.{ .file_id = child_file, .node = requirement });
            },
            .abstract_implements => {
                const decl = tree.abstractImplements(node).?;
                for (decl.generic_params) |param| try stack.append(.{ .file_id = child_file, .node = param });
                if (decl.generic_params_struct) |params| try stack.append(.{ .file_id = child_file, .node = params });
                try collectTypeRefsFromNode(tree, db, decl.abstract_type, type_refs);
            },
            .abstract_defaultsto => {
                const decl = tree.abstractDefaultsTo(node).?;
                for (decl.generic_params) |param| try stack.append(.{ .file_id = child_file, .node = param });
                if (decl.generic_params_struct) |params| try stack.append(.{ .file_id = child_file, .node = params });
                try collectTypeRefsFromNode(tree, db, decl.type_node, type_refs);
            },
            .assignment => try stack.append(.{ .file_id = child_file, .node = tree.assignment(node).?.value }),
            .code_block => for (tree.codeBlock(node).?.statements) |statement| try stack.append(.{ .file_id = child_file, .node = statement }),
            .list_literal => for (tree.listLiteral(node).?.elements) |element| try stack.append(.{ .file_id = child_file, .node = element }),
            .struct_type_literal => try collectSyntaxStructChildren(tree, db, node, type_refs, &stack),
            .struct_type_field, .inferred_result_field => {
                const field = tree.structTypeField(node).?;
                if (field.type_node) |ty| try collectTypeRefsFromNode(tree, db, ty, type_refs);
                if (field.default_value) |value| try stack.append(.{ .file_id = child_file, .node = value });
            },
            .choice_type_literal => for (tree.choiceTypeLiteral(node).?.variants) |variant| try stack.append(.{ .file_id = child_file, .node = variant }),
            .choice_type_variant, .choice_type_variant_default => if (tree.choiceTypeVariant(node).?.payload_type) |payload| {
                try collectTypeRefsFromNode(tree, db, payload, type_refs);
                try stack.append(.{ .file_id = child_file, .node = payload });
            },
            .struct_value_literal => for (tree.structValueLiteral(node).?.fields) |field| try stack.append(.{ .file_id = child_file, .node = field }),
            .struct_value_field, .positional_value_field => try stack.append(.{ .file_id = child_file, .node = tree.valueField(node).?.value }),
            .choice_literal, .choice_some_literal => if (tree.choiceLiteral(node).?.payload) |payload| try stack.append(.{ .file_id = child_file, .node = payload }),
            .struct_field_access => try stack.append(.{ .file_id = child_file, .node = tree.structFieldAccess(node).?.value }),
            .choice_payload_access => try stack.append(.{ .file_id = child_file, .node = tree.choicePayloadAccess(node).?.value }),
            .if_statement => {
                const statement = tree.ifStatement(node).?;
                try stack.append(.{ .file_id = child_file, .node = statement.condition });
                try stack.append(.{ .file_id = child_file, .node = statement.then_block });
                if (statement.else_block) |else_block| try stack.append(.{ .file_id = child_file, .node = else_block });
            },
            .for_value, .for_borrow, .for_mut_borrow => {
                const statement = tree.forStatement(node).?;
                try binding_decl_refs.append(.{ .location = tree.tokenLocation(statement.name_token), .name = tree.tokenText(db, statement.name_token) });
                try stack.append(.{ .file_id = child_file, .node = statement.iterable });
                try stack.append(.{ .file_id = child_file, .node = statement.body });
            },
            .while_statement => {
                const statement = tree.whileStatement(node).?;
                try stack.append(.{ .file_id = child_file, .node = statement.condition });
                try stack.append(.{ .file_id = child_file, .node = statement.body });
            },
            .match_statement => {
                const statement = tree.matchStatement(node).?;
                try stack.append(.{ .file_id = child_file, .node = statement.value });
                for (statement.cases) |case| try stack.append(.{ .file_id = child_file, .node = case });
            },
            .match_case_value, .match_case_borrow, .match_case_mut_borrow, .match_case_move => {
                const case = tree.matchCase(node).?;
                if (case.payload_name) |name_token| try binding_decl_refs.append(.{ .location = tree.tokenLocation(name_token), .name = tree.tokenText(db, name_token) });
                try stack.append(.{ .file_id = child_file, .node = case.body });
            },
            .reach_directive => for (tree.reachDirective(node).?.alternatives) |alternative| try stack.append(.{ .file_id = child_file, .node = alternative }),
            .reach_alternative => for (tree.reachAlternative(node).?.segments) |segment| try stack.append(.{ .file_id = child_file, .node = segment }),
            .return_statement => if (tree.returnStatement(node).?.value) |value| try stack.append(.{ .file_id = child_file, .node = value }),
            .binary_add,
            .binary_subtract,
            .binary_multiply,
            .binary_divide,
            .binary_modulo,
            .compare_equal,
            .compare_not_equal,
            .compare_less,
            .compare_greater,
            .compare_less_equal,
            .compare_greater_equal,
            => {
                try appendCompactOperator(tree, node, operator_refs);
                const operation = tree.binaryOperation(node).?;
                try stack.append(.{ .file_id = child_file, .node = operation.lhs });
                try stack.append(.{ .file_id = child_file, .node = operation.rhs });
            },
            .pipe_expression, .unwrap_or, .unwrap_or_do, .logical_and, .logical_or, .error_context, .index_access, .index_assignment, .pointer_assignment => {
                const operation = tree.binaryOperation(node).?;
                try stack.append(.{ .file_id = child_file, .node = operation.lhs });
                try stack.append(.{ .file_id = child_file, .node = operation.rhs });
            },
            .expression_statement, .move_expression, .error_propagation, .nullable_test, .defer_statement, .address_of, .address_of_mut, .dereference => try stack.append(.{ .file_id = child_file, .node = tree.unaryOperand(node).? }),
            .type_name, .pointer_type, .pointer_type_mut, .nullable_type, .inferred_errable_type, .array_type, .generic_type_instantiation => try collectTypeRefsFromNode(tree, db, node, type_refs),
            .choice_option_declaration,
            .abstract_function_requirement,
            .identifier,
            .pipe_placeholder,
            .literal,
            .import_statement,
            .break_statement,
            .continue_statement,
            .keep_statement,
            => {},
        }
    }
}

fn collectSyntaxStructShape(
    tree: *const st.SyntaxFile,
    db: *const source_db.SourceDb,
    node: st.NodeIndex,
    binding_decl_refs: *std.array_list.Managed(SyntaxBindingDeclRef),
    type_refs: *std.array_list.Managed(SyntaxTypeRef),
    stack: *std.array_list.Managed(st.SyntaxRef),
) !SyntaxStructShape {
    const literal = tree.structTypeLiteral(node) orelse return .{ .field_names = &.{} };
    var names = std.array_list.Managed([]const u8).init(binding_decl_refs.allocator);
    defer names.deinit();
    for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse continue;
        const name = tree.tokenText(db, field.name_token);
        try names.append(name);
        try binding_decl_refs.append(.{ .location = tree.tokenLocation(field.name_token), .name = name });
        if (field.type_node) |ty| try collectTypeRefsFromNode(tree, db, ty, type_refs);
        if (field.default_value) |value| try stack.append(.{ .file_id = tree.file_id, .node = value });
    }
    return .{ .field_names = try names.toOwnedSlice() };
}

fn collectSyntaxStructChildren(
    tree: *const st.SyntaxFile,
    db: *const source_db.SourceDb,
    node: st.NodeIndex,
    type_refs: *std.array_list.Managed(SyntaxTypeRef),
    stack: *std.array_list.Managed(st.SyntaxRef),
) !void {
    const literal = tree.structTypeLiteral(node) orelse return;
    for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse continue;
        if (field.type_node) |ty| try collectTypeRefsFromNode(tree, db, ty, type_refs);
        if (field.default_value) |value| try stack.append(.{ .file_id = tree.file_id, .node = value });
    }
}

fn collectTypeRefsFromNode(tree: *const st.SyntaxFile, db: *const source_db.SourceDb, node: st.NodeIndex, type_refs: *std.array_list.Managed(SyntaxTypeRef)) !void {
    const syntax_type = tree.syntaxType(node) orelse return;
    switch (syntax_type) {
        .name => |name| try type_refs.append(.{ .location = tree.tokenLocation(name.name_token), .name = tree.tokenText(db, name.name_token) }),
        .pointer => |pointer| try collectTypeRefsFromNode(tree, db, pointer.child, type_refs),
        .nullable => |child| try collectTypeRefsFromNode(tree, db, child, type_refs),
        .inferred_errable => |child| try collectTypeRefsFromNode(tree, db, child, type_refs),
        .array => |array| try collectTypeRefsFromNode(tree, db, array.element, type_refs),
        .generic => |generic| {
            try collectTypeRefsFromNode(tree, db, generic.base, type_refs);
            if (tree.structTypeLiteral(generic.arguments)) |arguments| {
                for (arguments.fields) |field_node| {
                    const field = tree.structTypeField(field_node) orelse continue;
                    if (field.type_node) |field_type| try collectTypeRefsFromNode(tree, db, field_type, type_refs);
                }
            }
        },
        .struct_literal => |literal| for (literal.fields) |field_node| {
            const field = tree.structTypeField(field_node) orelse continue;
            if (field.type_node) |field_type| try collectTypeRefsFromNode(tree, db, field_type, type_refs);
        },
        .choice_literal => |literal| for (literal.variants) |variant_node| {
            const variant = tree.choiceTypeVariant(variant_node) orelse continue;
            if (variant.payload_type) |payload_type| try collectTypeRefsFromNode(tree, db, payload_type, type_refs);
        },
    }
}

fn collectSyntaxValueFieldNames(tree: *const st.SyntaxFile, db: *const source_db.SourceDb, node: st.NodeIndex, allocator: std.mem.Allocator) ![]const []const u8 {
    const literal = tree.structValueLiteral(node) orelse return &.{};
    var names = std.array_list.Managed([]const u8).init(allocator);
    defer names.deinit();
    for (literal.fields) |field_node| {
        const field = tree.valueField(field_node) orelse continue;
        if (field.name_token) |name_token| try names.append(tree.tokenText(db, name_token));
    }
    return try names.toOwnedSlice();
}

fn appendSyntaxTypeDeclaration(tree: *const st.SyntaxFile, db: *const source_db.SourceDb, reference: st.SyntaxRef, name_token: st.TokenIndex, refs: *std.array_list.Managed(SyntaxTypeDeclRef)) !void {
    var fields = std.array_list.Managed(SyntaxName).init(refs.allocator);
    const value: ?st.NodeIndex = switch (tree.tag(reference.node)) {
        .type_declaration => tree.typeDeclaration(reference.node).?.value,
        .c_union_declaration => tree.cUnionDeclaration(reference.node).?.value,
        else => null,
    };
    if (value) |value_node| {
        if (tree.structTypeLiteral(value_node)) |literal| {
            for (literal.fields) |field_node| {
                const field = tree.structTypeField(field_node).?;
                try fields.append(.{ .location = tree.tokenLocation(field.name_token), .string = tree.tokenText(db, field.name_token) });
            }
        }
    }
    try refs.append(.{ .node = reference, .name = .{ .location = tree.tokenLocation(name_token), .string = tree.tokenText(db, name_token) }, .fields = try fields.toOwnedSlice() });
}

fn syntaxFunctionName(tree: *const st.SyntaxFile, db: *const source_db.SourceDb, node: st.NodeIndex, name_token: st.TokenIndex) SyntaxName {
    const text = switch (tree.functionName(db, node) orelse return .{ .location = tree.tokenLocation(name_token), .string = tree.tokenText(db, name_token) }) {
        .identifier => |token_index| tree.tokenText(db, token_index),
        .operator => |operator| switch (operator) {
            .add => "operator +",
            .equal => "operator ==",
            .not_equal => "operator !=",
            .get => "operator get[]",
            .set => "operator set[]",
            .get_ro_pointer => "operator get_ro_pointer[]",
            .get_rw_pointer => "operator get_rw_pointer[]",
        },
    };
    return .{ .location = tree.tokenLocation(name_token), .string = text };
}

fn appendCompactOperator(tree: *const st.SyntaxFile, node: st.NodeIndex, refs: *std.array_list.Managed(SyntaxOperatorRef)) !void {
    const operator: SyntaxOperatorRef = switch (tree.tag(node)) {
        .binary_add => .{ .location = tree.location(node), .name = "operator +", .len = 1 },
        .binary_subtract => .{ .location = tree.location(node), .name = "operator -", .len = 1 },
        .binary_multiply => .{ .location = tree.location(node), .name = "operator *", .len = 1 },
        .binary_divide => .{ .location = tree.location(node), .name = "operator /", .len = 1 },
        .binary_modulo => .{ .location = tree.location(node), .name = "operator %", .len = 1 },
        .compare_equal => .{ .location = tree.location(node), .name = "operator ==", .len = 2 },
        .compare_not_equal => .{ .location = tree.location(node), .name = "operator !=", .len = 2 },
        .compare_less => .{ .location = tree.location(node), .name = "operator <", .len = 1 },
        .compare_greater => .{ .location = tree.location(node), .name = "operator >", .len = 1 },
        .compare_less_equal => .{ .location = tree.location(node), .name = "operator <=", .len = 2 },
        .compare_greater_equal => .{ .location = tree.location(node), .name = "operator >=", .len = 2 },
        else => return,
    };
    try refs.append(operator);
}

fn collectSemanticRefs(
    sg_nodes: []const *sg.SGNode,
    function_refs: *std.array_list.Managed(SemanticFunctionDeclRef),
    call_refs: *std.array_list.Managed(SemanticFunctionCallRef),
    type_init_refs: *std.array_list.Managed(SemanticTypeInitializerRef),
    type_refs: *std.array_list.Managed(SemanticTypeDeclRef),
    binding_decl_refs: *std.array_list.Managed(SemanticBindingDeclRef),
    binding_use_refs: *std.array_list.Managed(SemanticBindingUseRef),
    field_access_refs: *std.array_list.Managed(SemanticFieldAccessRef),
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
            .type_initializer => |init| {
                try type_init_refs.append(.{ .node = node, .init = init });
                try appendSgChildren(&stack, node);
            },
            .type_declaration => |decl| try type_refs.append(.{ .decl = decl }),
            .binding_declaration => |decl| {
                try binding_decl_refs.append(.{ .node = node, .decl = decl });
                try appendSgChildren(&stack, node);
            },
            .binding_use => |binding| try binding_use_refs.append(.{ .node = node, .binding = binding }),
            .struct_field_access => |access| {
                try field_access_refs.append(.{ .node = node, .access = access });
                try appendSgChildren(&stack, node);
            },
            else => try appendSgChildren(&stack, node),
        }
    }
}

fn buildFunctionHoverMarkdown(
    allocator: std.mem.Allocator,
    db: *const source_db.SourceDb,
    decl: *const sg.FunctionDeclaration,
    syntax_decl_opt: ?SyntaxFunctionShape,
    type_refs: []const SemanticTypeDeclRef,
    source_path: []const u8,
    source_text: []const u8,
    toks: token.View,
) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    if (syntax_decl_opt) |syntax_decl| {
        if (std.mem.eql(u8, db.path(syntax_decl.name.location.file), source_path)) {
            if (try collectLeadingCommentBlock(source_text, syntax_decl.name.location)) |comments| {
                try out.appendSlice(comments);
                try out.appendSlice("\n");
            }
            if (!functionHasInferredReachedFields(decl, syntax_decl)) {
                if (try extractFunctionHeaderSource(source_text, toks, syntax_decl)) |header| {
                    try out.appendSlice(header);
                    try appendInferredReasonsHoverText(&out, decl);
                    return try out.toOwnedSlice();
                }
            }
        }
    }

    try appendGeneratedSignatureText(&out, decl, syntax_decl_opt, type_refs);
    try appendInferredReasonsHoverText(&out, decl);

    return try out.toOwnedSlice();
}

fn buildSyntaxFunctionHoverMarkdown(
    allocator: std.mem.Allocator,
    db: *const source_db.SourceDb,
    syntax_decl: SyntaxFunctionShape,
    source_path: []const u8,
    source_text: []const u8,
    toks: token.View,
) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    if (std.mem.eql(u8, db.path(syntax_decl.name.location.file), source_path)) {
        if (try collectLeadingCommentBlock(source_text, syntax_decl.name.location)) |comments| {
            try out.appendSlice(comments);
            try out.appendSlice("\n");
        }
        if (try extractFunctionHeaderSource(source_text, toks, syntax_decl)) |header| {
            try out.appendSlice(header);
            return try out.toOwnedSlice();
        }
    }

    try out.appendSlice(syntax_decl.name.string);
    return try out.toOwnedSlice();
}

fn buildTypeHoverMarkdown(
    allocator: std.mem.Allocator,
    db: *const source_db.SourceDb,
    decl: *const sg.TypeDeclaration,
    syntax_decl_opt: ?SyntaxTypeDeclRef,
    type_refs: []const SemanticTypeDeclRef,
    source_path: []const u8,
    source_text: []const u8,
) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    if (syntax_decl_opt) |syntax_decl| {
        if (std.mem.eql(u8, db.path(syntax_decl.name.location.file), source_path)) {
            if (try collectLeadingCommentBlock(source_text, syntax_decl.name.location)) |comments| {
                try out.appendSlice(comments);
                try out.appendSlice("\n");
            }
        }
    }

    try out.appendSlice(decl.name);
    switch (decl.ty) {
        .struct_type => |st_ty| {
            try out.appendSlice(" : Type = (\n");
            for (st_ty.fields, 0..) |field, idx| {
                if (idx != 0) try out.appendSlice("\n");
                try out.appendSlice("    .");
                try out.appendSlice(field.name);
                try out.appendSlice(": ");
                try appendHoverType(&out, field.ty, type_refs);
            }
            if (st_ty.fields.len > 0) try out.appendSlice("\n");
            try out.appendSlice(")");
        },
        .choice_type => |choice_ty| {
            try out.appendSlice(" : Type = (\n");
            for (choice_ty.variants, 0..) |variant, idx| {
                if (idx != 0) try out.appendSlice("\n");
                try out.appendSlice("    ..");
                try out.appendSlice(variant.name);
                if (variant.payload_type) |payload_ty| {
                    try out.appendSlice("(.value: ");
                    try appendHoverType(&out, payload_ty, type_refs);
                    try out.appendSlice(")");
                }
            }
            if (choice_ty.variants.len > 0) try out.appendSlice("\n");
            try out.appendSlice(")");
        },
        else => {
            try out.appendSlice(" : Type");
        },
    }

    return try out.toOwnedSlice();
}

fn buildBindingHoverMarkdown(
    allocator: std.mem.Allocator,
    decl: *const sg.BindingDeclaration,
    type_refs: []const SemanticTypeDeclRef,
) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    try out.appendSlice(decl.name);
    try out.appendSlice(" : ");
    try appendHoverType(&out, decl.ty, type_refs);

    return try out.toOwnedSlice();
}

fn appendGeneratedSignatureText(
    out: *std.array_list.Managed(u8),
    decl: *const sg.FunctionDeclaration,
    syntax_decl_opt: ?SyntaxFunctionShape,
    type_refs: []const SemanticTypeDeclRef,
) !void {
    try out.appendSlice(decl.name);
    try out.appendSlice("(\n");

    for (decl.input.fields, 0..) |field, idx| {
        if (idx != 0) try out.appendSlice(",\n");
        try out.appendSlice("    ");

        const has_declared_field = if (syntax_decl_opt) |syntax_decl|
            syntaxStructTypeHasField(syntax_decl.input, field.name)
        else
            false;
        const is_inferred_reach = !has_declared_field and field.default_value != null and field.default_value.?.content == .reach_directive;
        if (is_inferred_reach) try out.appendSlice("*");
        try appendSignatureFieldText(out, field, type_refs);
        if (is_inferred_reach) try out.appendSlice("*");
    }

    if (decl.input.fields.len > 0) try out.appendSlice("\n");
    try out.appendSlice(") -> (");
    for (decl.output.fields, 0..) |field, idx| {
        if (idx != 0) try out.appendSlice(", ");
        try appendSignatureFieldText(out, field, type_refs);
    }
    try out.appendSlice(")");
}

fn appendInferredReasonsHoverText(
    out: *std.array_list.Managed(u8),
    decl: *const sg.FunctionDeclaration,
) !void {
    const reasons = decl.inferred_error_reasons orelse return;
    try out.appendSlice("\n\ninferred reasons: ");
    try appendHoverChoiceSet(out, reasons);
}

fn appendSignatureFieldText(
    out: *std.array_list.Managed(u8),
    field: sg.StructTypeField,
    type_refs: []const SemanticTypeDeclRef,
) !void {
    try out.appendSlice(".");
    try out.appendSlice(field.name);
    try out.appendSlice(": ");
    try appendHoverType(out, field.ty, type_refs);

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
                .comptime_int => |value| {
                    var tmp: [32]u8 = undefined;
                    const text = std.fmt.bufPrint(&tmp, "{d}", .{value}) catch unreachable;
                    try out.appendSlice(text);
                },
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
            var tmp: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&tmp, "[{d}]", .{arr.length}) catch unreachable;
            try out.appendSlice(text);
            try appendHoverType(out, arr.element_type.*, type_refs);
        },
        .struct_type => try out.appendSlice("{...}"),
        .choice_type => try out.appendSlice("choice"),
    }
}

fn appendHoverChoiceSet(
    out: *std.array_list.Managed(u8),
    choice_ty: *const sg.ChoiceType,
) !void {
    try out.appendSlice("(");
    for (choice_ty.variants, 0..) |variant, idx| {
        if (idx != 0) try out.appendSlice(", ");
        try out.appendSlice("..");
        try out.appendSlice(variant.name);
    }
    try out.appendSlice(")");
}

fn hoverTypeNameFor(ty: sg.Type, type_refs: []const SemanticTypeDeclRef) ?[]const u8 {
    for (type_refs) |ref| {
        if (typ.typesExactlyEqual(ref.decl.ty, ty)) return ref.decl.name;
    }
    return null;
}

fn functionHasInferredReachedFields(decl: *const sg.FunctionDeclaration, syntax_decl: SyntaxFunctionShape) bool {
    for (decl.input.fields) |field| {
        if (syntaxStructTypeHasField(syntax_decl.input, field.name)) continue;
        if (field.default_value) |default_value| {
            if (default_value.content == .reach_directive) return true;
        }
    }
    return false;
}

fn extractFunctionHeaderSource(
    source_text: []const u8,
    toks: token.View,
    syntax_decl: SyntaxFunctionShape,
) !?[]const u8 {
    if (syntax_decl.name.location.offset >= source_text.len) return null;
    const start_idx = findTokenIndexAtOffset(toks, syntax_decl.name.location) orelse return null;
    var paren_depth: usize = 0;
    var idx = start_idx;
    while (idx < toks.len) : (idx += 1) {
        const tk = toks.get(idx);
        if (tk.location.file != syntax_decl.name.location.file) continue;
        if (tk.location.offset > source_text.len) return null;
        switch (tk.content) {
            .open_parenthesis => paren_depth += 1,
            .close_parenthesis => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            .equal => if (paren_depth == 0) {
                const raw = source_text[syntax_decl.name.location.offset .. tk.location.offset + 1];
                return std.mem.trim(u8, raw, " \t\r\n");
            },
            .new_line => if (paren_depth == 0 and !syntax_decl.has_body) {
                const raw = source_text[syntax_decl.name.location.offset..tk.location.offset];
                return std.mem.trim(u8, raw, " \t\r\n");
            },
            else => {},
        }
    }
    return null;
}

fn findTokenIndexAtOffset(toks: token.View, loc: token.Location) ?usize {
    for (0..toks.len) |idx| {
        const tk = toks.get(idx);
        if (tk.location.file != loc.file) continue;
        if (tk.location.offset == loc.offset) return idx;
    }
    return null;
}

fn collectLeadingCommentBlock(source_text: []const u8, name_loc: token.Location) !?[]const u8 {
    if (name_loc.offset > source_text.len) return null;
    const line_starts = try computeLineStarts(std.heap.page_allocator, source_text);
    defer std.heap.page_allocator.free(line_starts);

    const name_line_idx = lineIndexForOffset(line_starts, name_loc.offset) orelse return null;
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
    return std.mem.trim(u8, source_text[start..end], "\r\n");
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
    return std.mem.trim(u8, text[start..end], "\n");
}

fn lineIndexForOffset(starts: []const usize, offset: usize) ?usize {
    if (starts.len == 0) return null;
    var idx: usize = 0;
    while (idx + 1 < starts.len and starts[idx + 1] <= offset) : (idx += 1) {}
    return idx;
}

fn collectFunctionInlayHints(
    svc: *LanguageService,
    db: *const source_db.SourceDb,
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
                if (!std.mem.eql(u8, db.path(fd.location.file), primary_path)) {
                    if (fd.body) |body| for (body.nodes) |sub| try stack.append(sub);
                    continue;
                }

                const syntax_fn = findSyntaxFunctionDecl(syntax_functions, fd.location, fd.name) orelse {
                    if (fd.body) |body| for (body.nodes) |sub| try stack.append(sub);
                    continue;
                };
                const hint_pos = positionAfterName(db, syntax_fn.decl.name.location, syntax_fn.decl.name.string.len);
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
            else => try appendSgChildren(&stack, node),
        }
    }
}

fn collectCallInlayHints(
    svc: *LanguageService,
    db: *const source_db.SourceDb,
    primary_path: []const u8,
    range: ?Range,
    sg_nodes: []const *sg.SGNode,
    syntax_calls: []const SyntaxFunctionCallRef,
    toks: token.View,
    out: *std.array_list.Managed(InlayHint),
) !void {
    var stack = std.array_list.Managed(*const sg.SGNode).init(svc.allocator);
    defer stack.deinit();
    for (sg_nodes) |node| try stack.append(node);

    while (popOrNull(*const sg.SGNode, &stack)) |node| {
        switch (node.content) {
            .function_call => |call| {
                if (!std.mem.eql(u8, db.path(node.location.file), primary_path)) continue;
                const syntax_call = findSyntaxFunctionCall(syntax_calls, node.location, call.callee.name) orelse continue;
                const hint_pos = positionAfterCallInput(db, toks, syntax_call.call.input_location) orelse
                    positionAfterName(db, syntax_call.call.callee_loc, syntax_call.call.callee.len);
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
        .nullable_unwrap_or => |unwrap| {
            try stack.append(unwrap.nullable_value);
            try stack.append(unwrap.fallback_value);
        },
        .error_propagation => |prop| {
            try stack.append(prop.errable_value);
            for (prop.cleanup_nodes) |cleanup| try stack.append(cleanup);
        },
        .error_context => |ctx| {
            try stack.append(ctx.errable_value);
            try stack.append(ctx.context);
            for (ctx.cleanup_nodes) |cleanup| try stack.append(cleanup);
        },
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
        if (!sameLocation(ref.decl.name.location, loc)) continue;
        if (!std.mem.eql(u8, ref.decl.name.string, name)) continue;
        return ref;
    }
    return null;
}

fn findSyntaxTypeDeclByName(
    refs: []const SyntaxTypeDeclRef,
    name: []const u8,
) ?SyntaxTypeDeclRef {
    for (refs) |ref| {
        if (std.mem.eql(u8, ref.name.string, name)) return ref;
    }
    return null;
}

fn findSyntaxFunctionDeclByName(
    refs: []const SyntaxFunctionDeclRef,
    name: []const u8,
) ?SyntaxFunctionDeclRef {
    for (refs) |ref| {
        if (std.mem.eql(u8, ref.decl.name.string, name)) return ref;
    }
    return null;
}

fn findSyntaxTypeDecl(
    db: *const source_db.SourceDb,
    refs: []const SyntaxTypeDeclRef,
    file_path: []const u8,
    name: []const u8,
) ?SyntaxTypeDeclRef {
    for (refs) |ref| {
        if (!std.mem.eql(u8, db.path(ref.name.location.file), file_path)) continue;
        if (!std.mem.eql(u8, ref.name.string, name)) continue;
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
        if (!sameLocation(ref.call.callee_loc, loc)) continue;
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

fn findSemanticFunctionDeclByName(
    refs: []const SemanticFunctionDeclRef,
    name: []const u8,
) ?SemanticFunctionDeclRef {
    for (refs) |ref| {
        if (std.mem.eql(u8, ref.decl.name, name)) return ref;
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

fn findSemanticFunctionCallAtLocation(
    refs: []const SemanticFunctionCallRef,
    loc: token.Location,
) ?SemanticFunctionCallRef {
    for (refs) |ref| {
        if (sameLocation(ref.node.location, loc)) return ref;
    }
    return null;
}

fn findSemanticTypeInitializerAtLocation(
    refs: []const SemanticTypeInitializerRef,
    loc: token.Location,
) ?SemanticTypeInitializerRef {
    for (refs) |ref| {
        if (sameLocation(ref.node.location, loc)) return ref;
    }
    return null;
}

fn findSemanticTypeDeclByName(
    refs: []const SemanticTypeDeclRef,
    name: []const u8,
) ?SemanticTypeDeclRef {
    for (refs) |ref| {
        if (std.mem.eql(u8, ref.decl.name, name)) return ref;
    }
    return null;
}

fn findSemanticTypeDeclByType(
    refs: []const SemanticTypeDeclRef,
    ty: sg.Type,
) ?SemanticTypeDeclRef {
    for (refs) |ref| {
        if (typ.declaredTypeMatches(ref.decl.ty, ty)) return ref;
    }
    return null;
}

fn findFieldDefinition(
    db: *const source_db.SourceDb,
    field_access: SemanticFieldAccessRef,
    semantic_types: []const SemanticTypeDeclRef,
    syntax_type_decls: []const SyntaxTypeDeclRef,
) ?SyntaxName {
    const base_type = field_access.access.struct_value.sem_type orelse return null;
    if (base_type != .struct_type) return null;
    const declaration = findSemanticTypeDeclByType(semantic_types, base_type) orelse return null;
    const syntax_declaration = findSyntaxTypeDecl(db, syntax_type_decls, declaration.decl.origin_file, declaration.decl.name) orelse return null;
    for (syntax_declaration.fields) |field| {
        if (std.mem.eql(u8, field.string, field_access.access.field_name)) return field;
    }
    return null;
}

fn binaryOperatorName(op: token.BinaryOperator) []const u8 {
    return switch (op) {
        .addition => "operator +",
        .subtraction => "operator -",
        .multiplication => "operator *",
        .division => "operator /",
        .modulo => "operator %",
    };
}

fn binaryOperatorTokenLen(op: token.BinaryOperator) usize {
    _ = op;
    return 1;
}

fn comparisonOperatorName(op: token.ComparisonOperator) []const u8 {
    return switch (op) {
        .equal => "operator ==",
        .not_equal => "operator !=",
        .less_than => "operator <",
        .greater_than => "operator >",
        .less_than_or_equal => "operator <=",
        .greater_than_or_equal => "operator >=",
    };
}

fn comparisonOperatorTokenLen(op: token.ComparisonOperator) usize {
    return switch (op) {
        .equal, .not_equal, .less_than_or_equal, .greater_than_or_equal => 2,
        .less_than, .greater_than => 1,
    };
}

fn resolveSymbolTarget(
    db: *const source_db.SourceDb,
    doc_path: []const u8,
    position: Position,
    syntax_functions: []const SyntaxFunctionDeclRef,
    syntax_calls: []const SyntaxFunctionCallRef,
    syntax_operators: []const SyntaxOperatorRef,
    syntax_type_decls: []const SyntaxTypeDeclRef,
    syntax_type_refs: []const SyntaxTypeRef,
    syntax_binding_decls: []const SyntaxBindingDeclRef,
    semantic_functions: []const SemanticFunctionDeclRef,
    semantic_calls: []const SemanticFunctionCallRef,
    semantic_type_inits: []const SemanticTypeInitializerRef,
    semantic_types: []const SemanticTypeDeclRef,
    semantic_binding_decls: []const SemanticBindingDeclRef,
    semantic_binding_uses: []const SemanticBindingUseRef,
) ?SymbolTarget {
    for (syntax_functions) |syntax_fn| {
        if (!std.mem.eql(u8, db.path(syntax_fn.decl.name.location.file), doc_path)) continue;
        if (!positionWithinName(db, position, syntax_fn.decl.name.location, syntax_fn.decl.name.string.len)) continue;
        const semantic_fn = findSemanticFunctionDecl(semantic_functions, syntax_fn.decl.name.location, syntax_fn.decl.name.string);
        if (semantic_fn) |resolved| {
            return .{ .function_decl = resolved.decl };
        }
    }

    for (syntax_calls) |syntax_call| {
        if (!std.mem.eql(u8, db.path(syntax_call.call.callee_loc.file), doc_path)) continue;
        if (!positionWithinName(db, position, syntax_call.call.callee_loc, syntax_call.call.callee.len)) continue;
        if (findSemanticTypeInitializerAtLocation(semantic_type_inits, syntax_call.call.callee_loc)) |type_init| {
            return .{ .function_decl = type_init.init.init_fn };
        }
        if (findSemanticFunctionCallAtLocation(semantic_calls, syntax_call.call.callee_loc)) |semantic_call| {
            return .{ .function_decl = semantic_call.call.callee };
        }
    }

    for (syntax_operators) |syntax_op| {
        if (!std.mem.eql(u8, db.path(syntax_op.location.file), doc_path)) continue;
        if (!positionWithinName(db, position, syntax_op.location, syntax_op.len)) continue;
        if (findSemanticFunctionCallAtLocation(semantic_calls, syntax_op.location)) |semantic_call| {
            return .{ .function_decl = semantic_call.call.callee };
        }
    }

    for (syntax_type_decls) |syntax_decl| {
        if (!std.mem.eql(u8, db.path(syntax_decl.name.location.file), doc_path)) continue;
        if (!positionWithinName(db, position, syntax_decl.name.location, syntax_decl.name.string.len)) continue;
        if (findSemanticTypeDeclByName(semantic_types, syntax_decl.name.string)) |semantic_decl| {
            return .{ .type_decl = semantic_decl.decl };
        }
    }

    for (syntax_type_refs) |type_ref| {
        if (!std.mem.eql(u8, db.path(type_ref.location.file), doc_path)) continue;
        if (!positionWithinName(db, position, type_ref.location, type_ref.name.len)) continue;
        if (findSemanticTypeDeclByName(semantic_types, type_ref.name)) |semantic_decl| {
            return .{ .type_decl = semantic_decl.decl };
        }
    }

    for (syntax_binding_decls) |syntax_decl| {
        if (!std.mem.eql(u8, db.path(syntax_decl.location.file), doc_path)) continue;
        if (!positionWithinName(db, position, syntax_decl.location, syntax_decl.name.len)) continue;
        for (semantic_binding_decls) |binding_decl| {
            if (!sameLocation(binding_decl.decl.location, syntax_decl.location)) continue;
            return .{ .binding_decl = binding_decl.decl };
        }
    }

    for (semantic_binding_decls) |binding_decl| {
        if (!std.mem.eql(u8, db.path(binding_decl.node.location.file), doc_path)) continue;
        if (!positionWithinName(db, position, binding_decl.node.location, binding_decl.decl.name.len)) continue;
        return .{ .binding_decl = binding_decl.decl };
    }

    for (semantic_binding_uses) |binding_use| {
        if (!std.mem.eql(u8, db.path(binding_use.node.location.file), doc_path)) continue;
        if (!positionWithinName(db, position, binding_use.node.location, binding_use.binding.name.len)) continue;
        return .{ .binding_decl = binding_use.binding };
    }

    return null;
}

fn sameLocation(a: token.Location, b: token.Location) bool {
    return a.file == b.file and a.offset == b.offset;
}

fn sortLocations(items: []Location) void {
    std.sort.block(Location, items, {}, struct {
        fn lessThan(_: void, a: Location, b: Location) bool {
            const path_order = std.mem.order(u8, a.path, b.path);
            if (path_order != .eq) return path_order == .lt;
            if (a.range.start.line != b.range.start.line) return a.range.start.line < b.range.start.line;
            return a.range.start.character < b.range.start.character;
        }
    }.lessThan);
}

fn nameRange(db: *const source_db.SourceDb, loc: token.Location, byte_len: usize) Range {
    const position = db.lineColumn(loc.file, loc.offset);
    const line = position.line - 1;
    const start_char = position.column - 1;
    return .{
        .start = .{ .line = line, .character = start_char },
        .end = .{ .line = line, .character = start_char + @as(u32, @intCast(byte_len)) },
    };
}

fn positionWithinName(db: *const source_db.SourceDb, pos: Position, loc: token.Location, byte_len: usize) bool {
    const range = nameRange(db, loc, byte_len);
    return positionLessOrEqual(range.start, pos) and positionLessOrEqual(pos, range.end);
}

fn findSyntaxStructField(stl: st.StructTypeLiteral, field_name: []const u8) ?st.StructTypeLiteralField {
    for (stl.fields) |field| {
        if (std.mem.eql(u8, field.name.string, field_name)) return field;
    }
    return null;
}

fn syntaxStructTypeHasField(shape: SyntaxStructShape, field_name: []const u8) bool {
    for (shape.field_names) |name| {
        if (std.mem.eql(u8, name, field_name)) return true;
    }
    return false;
}

fn syntaxCallHasExplicitField(call: SyntaxCallShape, field_name: []const u8) bool {
    for (call.field_names) |name| {
        if (std.mem.eql(u8, name, field_name)) return true;
    }
    return false;
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

fn positionAfterName(db: *const source_db.SourceDb, loc: token.Location, byte_len: usize) Position {
    const position = db.lineColumn(loc.file, loc.offset);
    const line = position.line - 1;
    const start_char = position.column - 1;
    return .{
        .line = line,
        .character = start_char + @as(u32, @intCast(byte_len)),
    };
}

fn positionAfterCallInput(db: *const source_db.SourceDb, toks: token.View, input_loc: token.Location) ?Position {
    var start_idx: ?usize = null;
    for (0..toks.len) |idx| {
        const tk = toks.get(idx);
        if (tk.location.file != input_loc.file) continue;
        if (tk.location.offset != input_loc.offset) continue;
        if (tk.content != .open_parenthesis) continue;
        start_idx = idx;
        break;
    }

    const idx0 = start_idx orelse return null;
    var depth: usize = 0;
    var idx = idx0;
    while (idx < toks.len) : (idx += 1) {
        const tk = toks.get(idx);
        if (tk.location.file != input_loc.file) continue;
        switch (tk.content) {
            .open_parenthesis => depth += 1,
            .close_parenthesis => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) {
                    const position = db.lineColumn(tk.location.file, tk.location.offset);
                    const line = position.line - 1;
                    const start_char = position.column - 1;
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

fn documentShouldAcceptVersion(doc: Document, incoming_version: ?i64) bool {
    const current = doc.version orelse return true;
    const incoming = incoming_version orelse return true;
    return incoming >= current;
}

fn locationToRange(db: *const source_db.SourceDb, loc: token.Location) Range {
    const position = db.lineColumn(loc.file, loc.offset);
    const start_line = position.line - 1;
    const start_char = position.column - 1;
    return .{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = start_line, .character = start_char + 1 },
    };
}

fn firstImportRange(text: []const u8) Range {
    if (sf.firstImportDirectiveOffset(text)) |offset| {
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

        .keyword_return, .keyword_if, .keyword_else, .keyword_match, .keyword_for, .keyword_in, .keyword_while, .keyword_break, .keyword_continue, .keyword_once, .keyword_test, .keyword_and, .keyword_or => TOKEN_INDEX.keyword,

        .comparison_operator, .binary_operator, .equal, .arrow, .colon, .double_colon, .dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar, .question_mark => TOKEN_INDEX.operator,

        .new_line, .eof => null,
    };
}

fn emitLexical(
    out: *std.array_list.Managed(u32),
    gpa: std.mem.Allocator,
    db: *const source_db.SourceDb,
    text: []const u8,
    toks: token.View,
) !void {
    _ = gpa;

    var collected = std.array_list.Managed(SemanticToken).init(std.heap.page_allocator);
    defer collected.deinit();
    try appendLexicalSemanticTokens(&collected, db, text, toks);

    var prev_line: u32 = 0;
    var prev_char: u32 = 0;
    for (collected.items) |t| {
        try pushEncoded(out, &prev_line, &prev_char, t.line, t.start, t.len, t.type_index, t.mods);
    }
}

const SemanticToken = struct { line: u32, start: u32, len: u32, type_index: u32, mods: u32 };

fn appendCompactSyntaxSemanticTokens(sink: *std.array_list.Managed(SemanticToken), db: *const source_db.SourceDb, tree: *const st.SyntaxFile) !void {
    const Role = struct { kind: u32, mods: u32 = 0 };
    const roles = try sink.allocator.alloc(?Role, tree.tokens.len);
    defer sink.allocator.free(roles);
    @memset(roles, null);
    const declaration: u32 = 1 << MOD_INDEX.declaration;
    const readonly: u32 = 1 << MOD_INDEX.readonly;

    // Dense nodes let highlighting scan once without a traversal stack. Roles
    // are indexed by token so shared names never produce overlapping entries.
    for (0..tree.nodes.len) |index| {
        const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(index)));
        var name: ?st.TokenIndex = null;
        var role = Role{ .kind = TOKEN_INDEX.property };
        switch (tree.tag(node)) {
            .function_declaration, .function_declaration_once => {
                name = tree.functionDeclaration(node).?.name_token;
                role = .{ .kind = TOKEN_INDEX.function, .mods = declaration };
            },
            .test_declaration => {
                name = tree.testDeclaration(node).?.function.name_token;
                role = .{ .kind = TOKEN_INDEX.function, .mods = declaration };
            },
            .function_call => {
                const call = tree.functionCall(node).?;
                name = call.callee_token;
                role.kind = TOKEN_INDEX.function;
                if (call.module_qualifier) |qualifier| roles[@intFromEnum(qualifier)] = .{ .kind = TOKEN_INDEX.namespace };
            },
            .symbol_declaration_constant, .symbol_declaration_variable => {
                const symbol = tree.symbolDeclaration(node).?;
                name = symbol.name_token;
                role = .{ .kind = TOKEN_INDEX.variable, .mods = declaration | (if (symbol.mutability == .constant) readonly else 0) };
            },
            .type_declaration, .c_enum_declaration, .c_union_declaration, .abstract_declaration => {
                name = tree.mainToken(node);
                role = .{ .kind = TOKEN_INDEX.type_, .mods = declaration };
            },
            .type_name => {
                const ty = tree.syntaxType(node).?.name;
                name = ty.name_token;
                role.kind = TOKEN_INDEX.type_;
                if (ty.qualifier_token) |qualifier| roles[@intFromEnum(qualifier)] = .{ .kind = TOKEN_INDEX.namespace };
            },
            .struct_type_field, .inferred_result_field => {
                name = tree.structTypeField(node).?.name_token;
                role.mods = declaration;
            },
            .choice_type_variant, .choice_type_variant_default => {
                name = tree.choiceTypeVariant(node).?.name_token;
                role.mods = declaration;
            },
            .choice_option_declaration => {
                name = tree.choiceOptionDeclaration(node).?.name_token;
                role.mods = declaration;
            },
            .struct_value_field => name = tree.valueField(node).?.name_token,
            .struct_field_access => name = tree.structFieldAccess(node).?.field_token,
            .choice_literal, .choice_some_literal => name = tree.choiceLiteral(node).?.name_token,
            .choice_payload_access => name = tree.choicePayloadAccess(node).?.variant_token,
            .for_value, .for_borrow, .for_mut_borrow => {
                name = tree.forStatement(node).?.name_token;
                role = .{ .kind = TOKEN_INDEX.variable, .mods = declaration };
            },
            .match_case_value, .match_case_borrow, .match_case_mut_borrow, .match_case_move => {
                const match_case = tree.matchCase(node).?;
                name = match_case.variant_token;
                if (match_case.payload_name) |payload| roles[@intFromEnum(payload)] = .{ .kind = TOKEN_INDEX.variable, .mods = declaration };
            },
            else => {},
        }
        if (name) |token_index| roles[@intFromEnum(token_index)] = role;
    }
    for (roles, 0..) |maybe_role, index| {
        const role = maybe_role orelse continue;
        const token_index: st.TokenIndex = @enumFromInt(@as(u32, @intCast(index)));
        if (tree.tokenContent(token_index) != .identifier) continue;
        const location = tree.tokenLocation(token_index);
        const position = db.lineColumn(location.file, location.offset);
        try sink.append(.{ .line = position.line - 1, .start = position.column - 1, .len = @intCast(tree.tokenText(db, token_index).len), .type_index = role.kind, .mods = role.mods });
    }
}

fn appendLexicalSemanticTokens(
    sink: *std.array_list.Managed(SemanticToken),
    db: *const source_db.SourceDb,
    text: []const u8,
    toks: token.View,
) !void {
    var prev_non_trivia_was_hash = false;

    for (0..toks.len) |idx| {
        const tk = toks.get(idx);
        const ty_maybe = switch (tk.content) {
            .hash => blk: {
                var j = idx + 1;
                while (j < toks.len) : (j += 1) {
                    switch (toks.get(j).content) {
                        .comment, .new_line => continue,
                        .identifier => break :blk TOKEN_INDEX.keyword,
                        else => break :blk classify_lex_only(tk.content),
                    }
                }
                break :blk classify_lex_only(tk.content);
            },
            .identifier => if (prev_non_trivia_was_hash or
                identifierTokenEquals(text, tk, "implements") or
                identifierTokenEquals(text, tk, "canbe"))
                TOKEN_INDEX.keyword
            else
                classify_lex_only(tk.content),
            else => classify_lex_only(tk.content),
        };

        const ty_opt = ty_maybe orelse {
            switch (tk.content) {
                .new_line, .comment => {},
                .hash => prev_non_trivia_was_hash = true,
                else => prev_non_trivia_was_hash = false,
            }
            continue;
        };

        const start_off: usize = tk.location.offset;
        const len_u: usize = tokenLenBytesInSource(text, tk);
        const end_off: usize = start_off + len_u;

        const position = db.lineColumn(tk.location.file, tk.location.offset);
        var line0: u32 = position.line - 1;
        var col0: u32 = position.column - 1;

        var off: usize = start_off;
        while (off < end_off) {
            const rest = text[off..end_off];
            if (std.mem.indexOfScalar(u8, rest, '\n')) |r| {
                if (r > 0) {
                    try sink.append(.{
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
                    try sink.append(.{
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

        switch (tk.content) {
            .new_line, .comment => {},
            .hash => prev_non_trivia_was_hash = true,
            else => prev_non_trivia_was_hash = false,
        }
    }
}

fn identifierTokenEquals(text: []const u8, tk: token.Token, expected: []const u8) bool {
    if (tk.content != .identifier) return false;
    const start = tk.location.offset;
    const end = start + tokenLenBytes(tk);
    if (end > text.len) return false;
    return std.mem.eql(u8, text[start..end], expected);
}

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
        .keyword_break => "break".len,
        .keyword_continue => "continue".len,
        .keyword_once => "once".len,
        .keyword_test => "test".len,
        .keyword_and => "and".len,
        .keyword_or => "or".len,

        .double_colon => 2,
        .arrow => 2,
        .comparison_operator => 2,
        .binary_operator => 2,

        .new_line => 1,

        .equal, .colon, .dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar, .tilde, .bang, .question_mark, .eof => 1,
        .double_dot, .double_bang => 2,
    };
}

fn tokenLenBytesInSource(text: []const u8, tk: token.Token) usize {
    return switch (tk.content) {
        .literal => |lit| switch (lit) {
            .string_literal => quotedLiteralLenBytes(text, tk.location.offset, '"'),
            .char_literal => quotedLiteralLenBytes(text, tk.location.offset, '\''),
            else => tokenLenBytes(tk),
        },
        else => tokenLenBytes(tk),
    };
}

fn quotedLiteralLenBytes(text: []const u8, start: usize, quote: u8) usize {
    if (start >= text.len or text[start] != quote) return 0;

    var i = start + 1;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch == '\\') {
            if (i + 1 >= text.len) return text.len - start;
            i += 1;
            continue;
        }
        if (ch == quote) return (i + 1) - start;
    }

    return text.len - start;
}

inline fn classify_lex_only(c: token.Content) ?u32 {
    return switch (c) {
        .comment => TOKEN_INDEX.comment,
        .literal => |lit| switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal, .regular_float_literal, .scientific_float_literal => TOKEN_INDEX.number,
            .string_literal, .char_literal => TOKEN_INDEX.string,
            .bool_literal => TOKEN_INDEX.keyword,
        },
        .keyword_return, .keyword_if, .keyword_else, .keyword_match, .keyword_for, .keyword_in, .keyword_while, .keyword_break, .keyword_continue, .keyword_once, .keyword_test, .keyword_and, .keyword_or => TOKEN_INDEX.keyword,
        .comparison_operator, .binary_operator, .equal, .arrow, .colon, .double_colon, .dot, .double_dot, .comma, .open_parenthesis, .close_parenthesis, .open_bracket, .close_bracket, .open_brace, .close_brace, .hash, .ampersand, .pipe, .dollar, .tilde, .bang, .double_bang, .question_mark => TOKEN_INDEX.operator,
        .identifier => null,
        .new_line, .eof => null,
    };
}

inline fn popOrNull(comptime T: type, list: *std.array_list.Managed(T)) ?T {
    if (list.items.len == 0) return null;
    return list.pop();
}

fn tmpRootUriWithCore(tmp: *std.testing.TmpDir) ![]u8 {
    try tmp.dir.createDirPath(std.testing.io, "core");
    const root_path = try tmpRootPath(tmp);
    defer std.testing.allocator.free(root_path);
    return try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{root_path});
}

test "quoted literal semantic token length includes closing quote" {
    const string_len = quotedLiteralLenBytes("\"adfasdf\"", 0, '"');
    try std.testing.expectEqual(@as(usize, 9), string_len);

    const escaped_string_len = quotedLiteralLenBytes("\"a\\\"b\"", 0, '"');
    try std.testing.expectEqual(@as(usize, 6), escaped_string_len);

    const char_len = quotedLiteralLenBytes("'a'", 0, '\'');
    try std.testing.expectEqual(@as(usize, 3), char_len);

    const escaped_char_len = quotedLiteralLenBytes("'\\n'", 0, '\'');
    try std.testing.expectEqual(@as(usize, 4), escaped_char_len);
}

test "definition resolves local binding use" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    copy := value
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const def = try svc.definition(uri, .{ .line = 2, .character = 13 });
    try std.testing.expect(def != null);
    defer def.?.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), def.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 4), def.?.range.start.character);
}

test "definition resolves function parameter use" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\identity(.value: Int32) -> (.out: Int32) := {
        \\    out = value
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = identity(1)
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const def = try svc.definition(uri, .{ .line = 1, .character = 10 });
    try std.testing.expect(def != null);
    defer def.?.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), def.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 10), def.?.range.start.character);
}

test "definition resolves operator use" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\operator ==(.left: &Int32, .right: &Int32) -> (.ok: Bool) := {
        \\    ok = true
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    if &value == &value {
        \\    }
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const def = try svc.definition(uri, .{ .line = 6, .character = 15 });
    try std.testing.expect(def != null);
    defer def.?.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), def.?.range.start.line);
}

test "definition works for open core document" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "core");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "core/sample.rg",
        .data =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    broken :: Int32 =
        \\}
        \\
        ,
    });

    const rel_path = "core/sample.rg";
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    copy := value
        \\}
        \\
    ;

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const def = try svc.definition(uri, .{ .line = 2, .character = 13 });
    try std.testing.expect(def != null);
    defer def.?.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), def.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 4), def.?.range.start.character);
}

test "definition resolves core function from project document" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "core");
    try tmp.dir.createDirPath(std.testing.io, "app");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "core/util.rg",
        .data =
        \\helper() -> (.value: Int32) := {
        \\    value = 42
        \\}
        \\
        ,
    });

    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = helper()
        \\}
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "app/main.rg", .data = code });

    const abs_path = try tmpFilePath(&tmp, "app/main.rg");
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const def = try svc.definition(uri, .{ .line = 1, .character = 18 });
    try std.testing.expect(def != null);
    defer def.?.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, def.?.path, "core/util.rg"));
    try std.testing.expectEqual(@as(u32, 0), def.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 0), def.?.range.start.character);
}

test "definition resolves imported module function" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "app/dep");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/dep/math.rg",
        .data =
        \\answer() -> (.value: Int32) := {
        \\    value = 42
        \\}
        \\
        ,
    });

    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    dep := #import("./dep")
        \\    status_code = dep.answer()
        \\}
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "app/main.rg", .data = code });

    const abs_path = try tmpFilePath(&tmp, "app/main.rg");
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const def = try svc.definition(uri, .{ .line = 2, .character = 28 });
    try std.testing.expect(def != null);
    defer def.?.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, def.?.path, "app/dep/math.rg"));
    try std.testing.expectEqual(@as(u32, 0), def.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 0), def.?.range.start.character);
}

test "definition resolves imported module struct field" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "app/dep");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/dep/point.rg",
        .data =
        \\Point : Type = (
        \\    .value: Int32
        \\)
        \\
        \\make() -> (.point: Point) := {
        \\    point = (
        \\        .value = 7,
        \\    )
        \\}
        \\
        ,
    });

    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    dep := #import("./dep")
        \\    point := dep.make()
        \\    status_code = point.value
        \\}
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "app/main.rg", .data = code });

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    const abs_path = try tmpFilePath(&tmp, "app/main.rg");
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const def = try svc.definition(uri, .{ .line = 3, .character = 29 });
    try std.testing.expect(def != null);
    defer def.?.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, def.?.path, "app/dep/point.rg"));
    try std.testing.expectEqual(@as(u32, 1), def.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 5), def.?.range.start.character);
}

test "references include binding declaration and uses" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    copy := value
        \\    other := value
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    var refs = try svc.references(uri, .{ .line = 2, .character = 13 }, true);
    defer refs.deinit();
    try std.testing.expectEqual(@as(usize, 3), refs.items.len);
    try std.testing.expectEqual(@as(u32, 1), refs.items[0].range.start.line);
    try std.testing.expectEqual(@as(u32, 4), refs.items[0].range.start.character);
    try std.testing.expectEqual(@as(u32, 2), refs.items[1].range.start.line);
    try std.testing.expectEqual(@as(u32, 12), refs.items[1].range.start.character);
    try std.testing.expectEqual(@as(u32, 3), refs.items[2].range.start.line);
    try std.testing.expectEqual(@as(u32, 13), refs.items[2].range.start.character);
}

test "references resolve function declaration and calls" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\helper(.value: Int32) -> (.out: Int32) := {
        \\    out = value
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {
        \\    helper(1)
        \\    status_code = helper(2)
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    var refs = try svc.references(uri, .{ .line = 5, .character = 4 }, true);
    defer refs.deinit();
    try std.testing.expectEqual(@as(usize, 3), refs.items.len);
    try std.testing.expectEqual(@as(u32, 0), refs.items[0].range.start.line);
    try std.testing.expectEqual(@as(u32, 5), refs.items[1].range.start.line);
    try std.testing.expectEqual(@as(u32, 6), refs.items[2].range.start.line);
}

test "rename rewrites binding declaration and uses" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    copy := value
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    var edits = try svc.rename(uri, .{ .line = 2, .character = 13 }, "number");
    defer edits.deinit();
    try std.testing.expectEqual(@as(usize, 2), edits.items.len);
    try std.testing.expectEqualStrings("number", edits.items[0].new_text);
    try std.testing.expectEqualStrings("number", edits.items[1].new_text);
    try std.testing.expectEqual(@as(u32, 1), edits.items[0].range.start.line);
    try std.testing.expectEqual(@as(u32, 2), edits.items[1].range.start.line);
}

test "hover returns information for local binding use" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    copy := value
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const hover_opt = try svc.hover(uri, .{ .line = 2, .character = 13 });
    try std.testing.expect(hover_opt != null);
    defer if (hover_opt) |hover| std.testing.allocator.free(hover.contents);
    try std.testing.expect(std.mem.indexOf(u8, hover_opt.?.contents, "value") != null);
    try std.testing.expect(std.mem.indexOf(u8, hover_opt.?.contents, "Int32") != null);
}

test "hover returns information for operator use" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\operator ==(.left: &Int32, .right: &Int32) -> (.ok: Bool) := {
        \\    ok = true
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    if &value == &value {
        \\    }
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const hover_opt = try svc.hover(uri, .{ .line = 6, .character = 15 });
    try std.testing.expect(hover_opt != null);
    defer if (hover_opt) |hover| std.testing.allocator.free(hover.contents);
    try std.testing.expect(std.mem.indexOf(u8, hover_opt.?.contents, "operator ==") != null);
    try std.testing.expect(std.mem.indexOf(u8, hover_opt.?.contents, "Bool") != null);
}

test "hover returns syntax fallback for error propagation call" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\..file_not_found
        \\..permission_denied
        \\
        \\fail() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found))) := {
        \\    result = ..error(.reason = ..file_not_found)
        \\}
        \\
        \\load() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found, ..permission_denied))) := {
        \\    value := fail()!
        \\    result = ..ok(.value = value)
        \\}
        \\
        \\main() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found, ..permission_denied))) := {
        \\    result = load()
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const hover_opt = try svc.hover(uri, .{ .line = 8, .character = 13 });
    try std.testing.expect(hover_opt != null);
    defer if (hover_opt) |hover| std.testing.allocator.free(hover.contents);
    try std.testing.expect(std.mem.indexOf(u8, hover_opt.?.contents, "fail() ->") != null);
}

test "semantic tokens include string literal and function call" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\helper(.value: Int32) -> (.out: Int32) := {
        \\    out = value
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {
        \\    print("hello")
        \\    status_code = helper(1)
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    var tokens = try svc.semanticTokensFull(uri);
    defer tokens.deinit();

    try std.testing.expect(tokens.items.len > 0);
    try std.testing.expect(tokens.items.len % 5 == 0);
    var line: u32 = 0;
    var column: u32 = 0;
    var saw_declaration = false;
    var saw_call = false;
    var saw_string = false;
    var index: usize = 0;
    while (index < tokens.items.len) : (index += 5) {
        const entry = tokens.items[index..][0..5];
        column = if (entry[0] == 0) column + entry[1] else entry[1];
        line += entry[0];
        if (line == 0 and column == 0) {
            try std.testing.expectEqual(TOKEN_INDEX.function, entry[3]);
            try std.testing.expectEqual(@as(u32, 1 << MOD_INDEX.declaration), entry[4]);
            saw_declaration = true;
        }
        if (line == 6 and column == 18) {
            try std.testing.expectEqual(TOKEN_INDEX.function, entry[3]);
            try std.testing.expectEqual(@as(u32, 0), entry[4]);
            saw_call = true;
        }
        if (line == 5 and entry[3] == TOKEN_INDEX.string) saw_string = true;
    }
    try std.testing.expect(saw_declaration and saw_call and saw_string);
}

test "inlay hints describe compact calls with reached arguments" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\helper(.value: Int32 = #reach value) -> (.out: Int32) := {
        \\    out = value
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    value :: Int32 = 42
        \\    status_code = helper()
        \\}
        \\ 
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    var hints = try svc.inlayHints(uri, null);
    defer hints.deinit();
    try std.testing.expect(hints.items.len > 0);
    var found = false;
    for (hints.items) |hint| {
        if (hint.position.line == 5 and std.mem.indexOf(u8, hint.label, "value") != null) found = true;
    }
    try std.testing.expect(found);
}

test "semantic tokens fall back to lexical tokens when syntaxing fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    print("hello")
        \\    broken :: Int32 =
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();
    try std.testing.expect(diags.items.len > 0);

    var tokens = try svc.semanticTokensFull(uri);
    defer tokens.deinit();

    try std.testing.expect(tokens.items.len > 0);
    try std.testing.expect(tokens.items.len % 5 == 0);
}

test "change document updates diagnostics" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const broken_code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    broken :: Int32 =
        \\}
        \\
    ;
    const fixed_code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    fixed :: Int32 = 1
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = broken_code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    var diags = try svc.openDocument(uri, abs_path, 1, broken_code);
    defer diags.deinit();
    try std.testing.expect(diags.items.len > 0);

    var changed = try svc.changeDocument(uri, abs_path, 2, fixed_code);
    defer changed.deinit();
    try std.testing.expectEqual(@as(usize, 0), changed.items.len);
}

test "change document ignores stale version" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const broken_code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    broken :: Int32 =
        \\}
        \\
    ;
    const fixed_code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    fixed :: Int32 = 1
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = broken_code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    var diags = try svc.openDocument(uri, abs_path, 2, fixed_code);
    defer diags.deinit();
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);

    var stale = try svc.changeDocument(uri, abs_path, 1, broken_code);
    defer stale.deinit();
    try std.testing.expectEqual(@as(usize, 0), stale.items.len);

    const doc = try svc.getDoc(uri);
    try std.testing.expectEqual(@as(?i64, 2), doc.version);
    try std.testing.expectEqualStrings(fixed_code, doc.text);
}

test "analysis uses open overlay for imported sibling document" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "app/dep");
    const dep_code =
        \\helper() -> (.value: Int32) := {
        \\    value = 42
        \\}
        \\
    ;
    const broken_dep_code =
        \\helper() -> (.value: Int32) := {
        \\    value =
        \\}
        \\
    ;
    const main_code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    dep := #import("./dep")
        \\    status_code = dep.helper()
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "app/dep/helper.rg", .data = dep_code });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "app/main.rg", .data = main_code });

    const dep_path = try tmpFilePath(&tmp, "app/dep/helper.rg");
    defer std.testing.allocator.free(dep_path);
    const dep_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{dep_path});
    defer std.testing.allocator.free(dep_uri);

    const main_path = try tmpFilePath(&tmp, "app/main.rg");
    defer std.testing.allocator.free(main_path);
    const main_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{main_path});
    defer std.testing.allocator.free(main_uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    var dep_diags = try svc.openDocument(dep_uri, dep_path, 1, dep_code);
    defer dep_diags.deinit();
    try std.testing.expectEqual(@as(usize, 0), dep_diags.items.len);

    var main_diags = try svc.openDocument(main_uri, main_path, 1, main_code);
    defer main_diags.deinit();
    try std.testing.expectEqual(@as(usize, 0), main_diags.items.len);

    var broken = try svc.changeDocument(dep_uri, dep_path, 2, broken_dep_code);
    defer broken.deinit();
    try std.testing.expect(broken.items.len > 0);

    var refreshed_main = try svc.changeDocument(main_uri, main_path, 2, main_code);
    defer refreshed_main.deinit();
    try std.testing.expectEqual(@as(usize, 0), refreshed_main.items.len);
}

test "close document removes open state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = 0
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    const root_uri = try tmpRootUriWithCore(&tmp);
    defer std.testing.allocator.free(root_uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();
    try svc.initialize(root_uri);

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();
    _ = try svc.getDoc(uri);

    svc.closeDocument(uri);
    try std.testing.expectError(error.DocumentNotOpen, svc.getDoc(uri));
}

test "prepare rename returns binding range and placeholder" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    copy := value
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    var svc = LanguageService.init(std.testing.allocator, std.testing.io);
    defer svc.deinit();

    const diags = try svc.openDocument(uri, abs_path, 1, code);
    defer diags.deinit();

    const prep = try svc.prepareRename(uri, .{ .line = 2, .character = 13 });
    try std.testing.expect(prep != null);
    defer if (prep) |p| p.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("value", prep.?.placeholder);
    try std.testing.expectEqual(@as(u32, 1), prep.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 4), prep.?.range.start.character);
}

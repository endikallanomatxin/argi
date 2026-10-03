const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const graph_mod = @import("../4_semantics/global/graph.zig");
const global_types = @import("../4_semantics/global/types.zig");
const editor_index = @import("lsp_index.zig");
const completion = @import("lsp_completion.zig");
const editor_syntax = @import("lsp_syntax.zig");
const primitives = @import("../4_semantics/primitives/schema.zig");
const frontend = @import("frontend_pipeline.zig");

const log = std.log.scoped(.lsp_service);

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
    pub const parameter: u32 = 11;
    pub const enum_member: u32 = 12;
};

const MOD_INDEX = struct {
    pub const declaration: u32 = 0;
    pub const readonly: u32 = 1;
};

// The protocol legend and emitted indices share one definition.
pub const semantic_token_types = [_][]const u8{
    "namespace",  "type",   "function", "method",  "variable", "property",
    "keyword",    "number", "string",   "comment", "operator", "parameter",
    "enumMember",
};
pub const semantic_token_modifiers = [_][]const u8{ "declaration", "readonly" };

pub const Severity = enum(u8) { err = 1, warn = 2, info = 3, hint = 4 };
pub const Position = struct { line: u32, character: u32 };
pub const Range = struct { start: Position, end: Position };
pub const Diagnostic = struct { range: Range, severity: Severity, message: []const u8 };
pub const InlayHint = struct { position: Position, label: []const u8 };
pub const Hover = struct { range: Range, contents: []const u8 };

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
        return .{ .allocator = allocator, .items = &.{}, .owned = false };
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
        return .{ .allocator = allocator, .items = &.{}, .owned = false };
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
        return .{ .allocator = allocator, .items = &.{}, .owned = false };
    }
    pub fn deinit(self: DiagnosticsResult) void {
        if (!self.owned) return;
        for (self.items) |item| self.allocator.free(item.message);
        self.allocator.free(self.items);
    }
};

pub const InlayHintsResult = struct {
    allocator: std.mem.Allocator,
    items: []InlayHint,
    owned: bool,
    pub fn empty(allocator: std.mem.Allocator) InlayHintsResult {
        return .{ .allocator = allocator, .items = &.{}, .owned = false };
    }
    pub fn deinit(self: InlayHintsResult) void {
        if (!self.owned) return;
        for (self.items) |item| self.allocator.free(item.label);
        self.allocator.free(self.items);
    }
};

pub const DocumentSymbol = struct {
    name: []const u8,
    kind: u32,
    range: Range,
    selectionRange: Range,
    children: []const DocumentSymbol = &.{},
};

pub const DocumentSymbolsResult = struct {
    arena: std.heap.ArenaAllocator,
    items: []const DocumentSymbol,

    pub fn deinit(self: DocumentSymbolsResult) void {
        var arena = self.arena;
        arena.deinit();
    }
};

const Document = struct {
    uri: []u8,
    path: []u8,
    version: ?i64,
    text: []u8,

    fn init(allocator: std.mem.Allocator, uri: []const u8, path: []const u8, version: ?i64, text: []const u8) !Document {
        return .{
            .uri = try allocator.dupe(u8, uri),
            .path = try allocator.dupe(u8, path),
            .version = version,
            .text = try allocator.dupe(u8, text),
        };
    }

    fn update(self: *Document, allocator: std.mem.Allocator, path: []const u8, version: ?i64, text: []const u8) !void {
        const new_path = try allocator.dupe(u8, path);
        errdefer allocator.free(new_path);
        const new_text = try allocator.dupe(u8, text);
        allocator.free(self.path);
        allocator.free(self.text);
        self.path = new_path;
        self.text = new_text;
        self.version = version;
    }

    fn deinit(self: *Document, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
        allocator.free(self.path);
        allocator.free(self.text);
    }
};

const Analysis = struct {
    source_db: source_db.SourceDb,
    graph: graph_mod.GlobalSemanticGraph,
    index: editor_index.Index,
    tokens: token.View,

    fn deinit(self: *Analysis, allocator: std.mem.Allocator) void {
        self.index.deinit(allocator);
        self.graph.deinit(allocator);
        allocator.free(self.tokens.contents);
        allocator.free(self.tokens.locations);
        self.source_db.deinit(allocator);
    }
};

pub const LanguageService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    documents: std.array_list.Managed(Document),
    root_path: ?[]u8 = null,
    module_cache: frontend.cache.ModuleCache,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) LanguageService {
        return .{
            .allocator = allocator,
            .io = io,
            .documents = std.array_list.Managed(Document).init(allocator),
            .module_cache = frontend.cache.ModuleCache.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *LanguageService) void {
        for (self.documents.items) |*document| document.deinit(self.allocator);
        self.documents.deinit();
        self.module_cache.deinit();
        if (self.root_path) |path| self.allocator.free(path);
    }

    pub fn initialize(self: *LanguageService, root_uri: ?[]const u8) !void {
        const uri = root_uri orelse return;
        const path = (try decodeFileUri(self.allocator, uri)) orelse return;
        if (self.root_path) |old| self.allocator.free(old);
        self.root_path = path;
    }

    pub fn openDocument(self: *LanguageService, uri: []const u8, path: []const u8, version: ?i64, text: []const u8) !DiagnosticsResult {
        if (self.findDocument(uri)) |index| {
            try self.documents.items[index].update(self.allocator, path, version, text);
        } else {
            try self.documents.append(try Document.init(self.allocator, uri, path, version, text));
        }
        return self.analyzeDocument(&self.documents.items[self.findDocument(uri).?]);
    }

    pub fn changeDocument(self: *LanguageService, uri: []const u8, path: []const u8, version: ?i64, text: []const u8) !DiagnosticsResult {
        const index = self.findDocument(uri) orelse return DiagnosticsResult.empty(self.allocator);
        if (version) |incoming| if (self.documents.items[index].version) |current| if (incoming <= current)
            return self.analyzeDocument(&self.documents.items[index]);
        try self.documents.items[index].update(self.allocator, path, version, text);
        return self.analyzeDocument(&self.documents.items[index]);
    }

    pub fn closeDocument(self: *LanguageService, uri: []const u8) void {
        const index = self.findDocument(uri) orelse return;
        self.documents.items[index].deinit(self.allocator);
        _ = self.documents.swapRemove(index);
    }

    pub fn document_text(self: *LanguageService, uri: []const u8) ?[]const u8 {
        const index = self.findDocument(uri) orelse return null;
        return self.documents.items[index].text;
    }

    pub fn documentSymbols(self: *LanguageService, uri: []const u8) !DocumentSymbolsResult {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const work = arena.allocator();
        // An outline must remain available independently of module resolution.
        const sources = [_]sf.SourceFile{.{ .path = doc.path, .code = doc.text }};
        const files = try editor_syntax.load_files(work, &sources);
        const items = try outlineNodes(work, &files[0], files[0].tree.roots);
        return .{ .arena = arena, .items = items };
    }

    pub fn completions(self: *LanguageService, uri: []const u8, position: Position) !completion.Result {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();
        const offset = completion_offset(doc.text, position) orelse return error.InvalidPosition;
        const fallback = [_]sf.SourceFile{.{ .path = doc.path, .code = doc.text }};
        const files = self.collectFiles(&work, doc) catch fallback[0..];
        return completion.complete(self.allocator, self.io, files, doc.path, offset);
    }

    pub fn semanticTokensFull(self: *LanguageService, uri: []const u8) !std.array_list.Managed(u32) {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();

        const one_file = [_]sf.SourceFile{.{ .path = doc.path, .code = doc.text }};
        var diagnostics = diag.Diagnostics.init(&work, &one_file);
        defer diagnostics.deinit();
        var pipeline = frontend.FrontendPipeline.init(work, self.io, &diagnostics, .{});
        defer pipeline.deinit();
        _ = pipeline.parseFiles(&one_file) catch {};
        const tokens = pipeline.tokensForPath(doc.path) orelse token.View{};

        var classes: std.AutoHashMap(u32, TokenClass) = .init(work);
        for (pipeline.syntax_files.items) |*tree| try classifySyntax(work, tree, doc.text, &classes);

        // Resolved identities refine syntax roles; syntax remains usable while
        // an unfinished edit prevents global semantizing from producing a graph.
        var analysis = try self.collectAnalysis(&work, doc);
        defer if (analysis) |*value| value.deinit(work);
        if (analysis) |*value| try classifyOccurrences(work, value, doc.path, &classes);

        var output = std.array_list.Managed(u32).init(self.allocator);
        errdefer output.deinit();
        var previous_line: u32 = 0;
        var previous_character: u32 = 0;
        for (0..tokens.len) |index| {
            const item = tokens.get(index);
            const classification = classes.get(item.location.offset) orelse classifyToken(item.content) orelse continue;
            const length = tokenLength(item.content, doc.text, item.location.offset);
            if (length == 0) continue;
            // Emit single-line spans even for multiline strings/comments. This
            // works with clients that do not advertise multiline token support.
            var offset: usize = item.location.offset;
            const end = @min(doc.text.len, offset + length);
            while (offset < end) {
                const newline = std.mem.indexOfScalarPos(u8, doc.text, offset, '\n') orelse end;
                const line_end = @min(end, newline);
                const span_end = if (line_end > offset and doc.text[line_end - 1] == '\r') line_end - 1 else line_end;
                if (span_end > offset) {
                    const position = diagnostics.source_db.lineColumn(item.location.file, @intCast(offset));
                    const line = position.line - 1;
                    const character = position.column - 1;
                    const delta_line = line - previous_line;
                    try output.appendSlice(&.{
                        delta_line,                  if (delta_line == 0) character - previous_character else character,
                        @intCast(span_end - offset), classification.type_index,
                        classification.modifiers,
                    });
                    previous_line = line;
                    previous_character = character;
                }
                offset = line_end + 1;
            }
        }
        return output;
    }

    pub fn hover(self: *LanguageService, uri: []const u8, position: Position) !?Hover {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();
        var analysis = (try self.collectAnalysis(&work, doc)) orelse return null;
        defer analysis.deinit(work);

        const occurrence = analysis.index.occurrenceAt(&analysis.graph, &analysis.source_db, doc.path, position.line, position.character) orelse return null;
        const contents = try formatHover(self.allocator, &analysis.graph, occurrence.target);
        return .{
            .range = sourceRange(&analysis, occurrence.source, occurrence.len) orelse return null,
            .contents = contents,
        };
    }

    pub fn definition(self: *LanguageService, uri: []const u8, position: Position) !?Definition {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();
        var analysis = (try self.collectAnalysis(&work, doc)) orelse return try self.syntax_definition(work, doc, position);
        defer analysis.deinit(work);

        const occurrence = analysis.index.occurrenceAt(&analysis.graph, &analysis.source_db, doc.path, position.line, position.character) orelse return null;
        // Specialized functions retain their source declaration but have a distinct
        // function ID. Navigation follows that declaration, not the instance ID.
        const target = analysis.index.declarationOccurrence(occurrence.target) orelse switch (occurrence.target) {
            .function => |id| blk: {
                const function = analysis.graph.functions.items[@intFromEnum(id)];
                const declaration = analysis.graph.declarations.items[@intFromEnum(function.declaration)];
                break :blk editor_index.Occurrence{
                    .source = declaration.source,
                    .len = @intCast(analysis.graph.text(declaration.name).len),
                    .target = occurrence.target,
                    .declaration = true,
                };
            },
            else => return null,
        };
        return try self.definitionForOccurrence(&analysis, target);
    }

    fn syntax_definition(self: *LanguageService, work: std.mem.Allocator, doc: *Document, position: Position) !?Definition {
        const offset = completion_offset(doc.text, position) orelse return null;
        var allocator = work;
        const files = self.collectFiles(&allocator, doc) catch return null;
        const target = (try editor_syntax.find_declaration(work, self.io, files, doc.path, offset)) orelse return null;
        for (files) |file| {
            if (!std.mem.eql(u8, file.path, target.path)) continue;
            var line: u32 = 0;
            var start: usize = 0;
            for (file.code[0..target.offset], 0..) |byte, index| if (byte == '\n') {
                line += 1;
                start = index + 1;
            };
            const character: u32 = @intCast(target.offset - start);
            return .{ .path = try self.ownedPath(target.path), .range = .{
                .start = .{ .line = line, .character = character },
                .end = .{ .line = line, .character = character + target.len },
            } };
        }
        return null;
    }

    pub fn references(self: *LanguageService, uri: []const u8, position: Position, include_declaration: bool) !LocationsResult {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();
        var analysis = (try self.collectAnalysis(&work, doc)) orelse return LocationsResult.empty(self.allocator);
        defer analysis.deinit(work);

        const selected = analysis.index.occurrenceAt(&analysis.graph, &analysis.source_db, doc.path, position.line, position.character) orelse
            return LocationsResult.empty(self.allocator);
        var output = std.array_list.Managed(Location).init(self.allocator);
        errdefer {
            for (output.items) |item| item.deinit(self.allocator);
            output.deinit();
        }
        for (analysis.index.occurrences.items) |occurrence| {
            if (!editor_index.targetsEqual(occurrence.target, selected.target)) continue;
            if (!include_declaration and occurrence.declaration) continue;
            const file = editor_index.sourceFileId(&analysis.graph, &analysis.source_db, occurrence.source) orelse continue;
            const range = sourceRange(&analysis, occurrence.source, occurrence.len) orelse continue;
            try output.append(.{ .path = try self.ownedPath(analysis.source_db.path(file)), .range = range });
        }
        const items = try output.toOwnedSlice();
        output.deinit();
        sortLocations(items);
        return .{ .allocator = self.allocator, .items = items, .owned = true };
    }

    pub fn rename(self: *LanguageService, uri: []const u8, position: Position, new_name: []const u8) !TextEditsResult {
        var locations = try self.references(uri, position, true);
        defer locations.deinit();
        if (locations.items.len == 0) return TextEditsResult.empty(self.allocator);
        const edits = try self.allocator.alloc(TextEdit, locations.items.len);
        errdefer self.allocator.free(edits);
        for (locations.items, 0..) |location, index| edits[index] = .{
            .path = try self.allocator.dupe(u8, location.path),
            .range = location.range,
            .new_text = try self.allocator.dupe(u8, new_name),
        };
        return .{ .allocator = self.allocator, .items = edits, .owned = true };
    }

    pub fn prepareRename(self: *LanguageService, uri: []const u8, position: Position) !?PrepareRename {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();
        var analysis = (try self.collectAnalysis(&work, doc)) orelse return null;
        defer analysis.deinit(work);
        const occurrence = analysis.index.occurrenceAt(&analysis.graph, &analysis.source_db, doc.path, position.line, position.character) orelse return null;
        return .{
            .range = sourceRange(&analysis, occurrence.source, occurrence.len) orelse return null,
            .placeholder = try self.allocator.dupe(u8, editor_index.Index.targetName(&analysis.graph, occurrence.target)),
        };
    }

    pub fn inlayHints(self: *LanguageService, uri: []const u8, requested_range: ?Range) !InlayHintsResult {
        const doc = try self.getDoc(uri);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();
        var analysis = (try self.collectAnalysis(&work, doc)) orelse return InlayHintsResult.empty(self.allocator);
        defer analysis.deinit(work);

        var output = std.array_list.Managed(InlayHint).init(self.allocator);
        errdefer {
            for (output.items) |item| self.allocator.free(item.label);
            output.deinit();
        }
        for (analysis.graph.nodes.items) |node| {
            const call = switch (node.content) {
                .function_call => |value| value,
                else => continue,
            };
            if (!editor_index.sourcePathEquals(&analysis.graph, &analysis.source_db, node.source, doc.path)) continue;
            const literal = switch (analysis.graph.nodes.items[@intFromEnum(call.input)].content) {
                .struct_value_literal => |value| value,
                else => continue,
            };
            const function = analysis.graph.functions.items[@intFromEnum(call.callee)];
            const count = @min(literal.dispatch_prefix_positional_count, @min(literal.fields.len, function.input.len));
            for (0..count) |index| {
                const value_field = analysis.graph.value_fields.items[literal.fields.start + @as(u32, @intCast(index))];
                const value_node = analysis.graph.nodes.items[@intFromEnum(value_field.value)];
                const source_position = sourceRange(&analysis, value_node.source, 1) orelse continue;
                if (requested_range) |wanted| if (!positionInRange(source_position.start, wanted)) continue;
                const field = analysis.graph.fields.items[function.input.start + @as(u32, @intCast(index))];
                const label = try std.fmt.allocPrint(self.allocator, ".{s}: ", .{analysis.graph.text(field.name)});
                try output.append(.{ .position = source_position.start, .label = label });
            }
        }
        std.mem.sort(InlayHint, output.items, {}, lessHint);
        const items = try output.toOwnedSlice();
        output.deinit();
        return .{ .allocator = self.allocator, .items = items, .owned = true };
    }

    fn analyzeDocument(self: *LanguageService, doc: *Document) !DiagnosticsResult {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var work = arena.allocator();
        const files = self.collectFiles(&work, doc) catch |err| return self.loadFailureDiagnostic(doc, err);
        var diagnostics = diag.Diagnostics.init(&work, files);
        defer diagnostics.deinit();
        var pipeline = frontend.FrontendPipeline.init(work, self.io, &diagnostics, .{ .module_cache = &self.module_cache });
        defer pipeline.deinit();
        _ = pipeline.semantizeGlobalFiles(files) catch {};

        var output = std.array_list.Managed(Diagnostic).init(self.allocator);
        errdefer {
            for (output.items) |item| self.allocator.free(item.message);
            output.deinit();
        }
        for (diagnostics.list.items) |entry| {
            if (!std.mem.eql(u8, diagnostics.source_db.path(entry.loc.file), doc.path)) continue;
            try output.append(.{
                .range = tokenRange(&diagnostics.source_db, entry.loc, 1),
                .severity = .err,
                .message = try self.allocator.dupe(u8, entry.msg),
            });
        }
        const items = try output.toOwnedSlice();
        output.deinit();
        return .{ .allocator = self.allocator, .items = items, .owned = true };
    }

    fn collectAnalysis(self: *LanguageService, allocator: *std.mem.Allocator, doc: *Document) !?Analysis {
        const files = self.collectFiles(allocator, doc) catch |err| {
            log.debug("LSP module load failed for {s}: {s}", .{ doc.path, @errorName(err) });
            return null;
        };
        var diagnostics = diag.Diagnostics.init(allocator, files);
        defer diagnostics.deinit();
        var pipeline = frontend.FrontendPipeline.init(allocator.*, self.io, &diagnostics, .{ .module_cache = &self.module_cache });
        defer pipeline.deinit();
        _ = pipeline.semantizeGlobalFiles(files) catch {
            // Parsing/global semantic failures leave no graph. Safety failures,
            // however, happen after GlobalSG is complete and should not disable
            // editor navigation for otherwise-resolved symbols.
            if (pipeline.global_graph == null) return null;
        };

        var graph = pipeline.global_graph.?;
        pipeline.global_graph = null;
        errdefer graph.deinit(allocator.*);
        var index = try editor_index.Index.build(allocator.*, &graph);
        errdefer index.deinit(allocator.*);
        try augmentTypeOccurrences(allocator.*, &index, &graph, &diagnostics.source_db, pipeline.syntax_files.items);
        index.sort();

        var db = try diagnostics.source_db.clone(allocator.*);
        errdefer db.deinit(allocator.*);
        const tokens = try (pipeline.tokensForPath(doc.path) orelse token.View{}).clone(allocator.*);
        return .{ .source_db = db, .graph = graph, .index = index, .tokens = tokens };
    }

    fn collectFiles(self: *LanguageService, allocator: *std.mem.Allocator, doc: *Document) ![]const sf.SourceFile {
        const core_dir = try self.preferredCoreDir(allocator.*);
        const overrides = try allocator.alloc(sf.SourceFile, self.documents.items.len);
        for (self.documents.items, overrides) |document, *source| source.* = .{ .path = document.path, .code = document.text };
        const files = try sf.collectWithEntrySourceWithOptions(allocator, self.io, .{
            .fallback_core_dir = core_dir,
            .source_overrides = overrides,
        }, doc.path, doc.text);
        return files.items;
    }

    fn preferredCoreDir(self: *LanguageService, allocator: std.mem.Allocator) ![]u8 {
        if (self.root_path) |root| return std.fs.path.join(allocator, &.{ root, "core" });
        return allocator.dupe(u8, "core");
    }

    fn findDocument(self: *LanguageService, uri: []const u8) ?usize {
        for (self.documents.items, 0..) |document, index| if (std.mem.eql(u8, document.uri, uri)) return index;
        return null;
    }

    fn getDoc(self: *LanguageService, uri: []const u8) !*Document {
        return if (self.findDocument(uri)) |index| &self.documents.items[index] else error.DocumentNotOpen;
    }

    fn ownedPath(self: *LanguageService, path: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(path)) return self.allocator.dupe(u8, path);
        if (self.root_path) |root| return std.fs.path.join(self.allocator, &.{ root, path });
        return self.allocator.dupe(u8, path);
    }

    fn definitionForOccurrence(self: *LanguageService, analysis: *const Analysis, occurrence: editor_index.Occurrence) !?Definition {
        const file = editor_index.sourceFileId(&analysis.graph, &analysis.source_db, occurrence.source) orelse return null;
        return .{
            .path = try self.ownedPath(analysis.source_db.path(file)),
            .range = sourceRange(analysis, occurrence.source, occurrence.len) orelse return null,
        };
    }

    fn loadFailureDiagnostic(self: *LanguageService, doc: *Document, err: anyerror) !DiagnosticsResult {
        const items = try self.allocator.alloc(Diagnostic, 1);
        items[0] = .{
            .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 1 } },
            .severity = .err,
            .message = try self.allocator.dupe(u8, switch (err) {
                error.FileNotFound => "failed to load an imported module",
                error.ImportCycle => "import cycle detected",
                else => "failed to load module graph",
            }),
        };
        _ = doc;
        return .{ .allocator = self.allocator, .items = items, .owned = true };
    }
};

fn augmentTypeOccurrences(
    allocator: std.mem.Allocator,
    index: *editor_index.Index,
    graph: *const graph_mod.GlobalSemanticGraph,
    db: *const source_db.SourceDb,
    syntax_files: []const st.FileSyntaxTree,
) !void {
    for (syntax_files) |*tree| {
        const global_file = globalFileForSourceFile(graph, db, tree.file_id) orelse continue;
        const current_module = graph.files.items[global_file].module;
        for (0..tree.nodes.len) |raw| {
            const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            const ty = tree.syntaxType(node) orelse continue;
            const name = switch (ty) {
                .name => |value| value,
                else => continue,
            };
            if (name.qualifier_token != null) continue;
            const spelling = tree.tokenText(db, name.name_token);
            const declaration = findTypeDeclaration(graph, current_module, spelling) orelse continue;
            try index.add(allocator, .{
                .source = .{ .file_index = global_file, .offset = tree.tokenLocation(name.name_token).offset },
                .len = @intCast(spelling.len),
                .target = .{ .declaration = declaration },
            });
        }
    }
}

fn findTypeDeclaration(graph: *const graph_mod.GlobalSemanticGraph, current_module: graph_mod.GlobalModuleId, name: []const u8) ?graph_mod.GlobalDeclId {
    var fallback: ?graph_mod.GlobalDeclId = null;
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .type and declaration.kind != .abstract_type) continue;
        if (!std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        const id: graph_mod.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
        if (graph.moduleForDeclaration(id) == current_module) return id;
        if (fallback == null) fallback = id else fallback = null;
    }
    return fallback;
}

fn globalFileForSourceFile(graph: *const graph_mod.GlobalSemanticGraph, db: *const source_db.SourceDb, file_id: source_db.FileId) ?u32 {
    const source = db.get(file_id);
    const source_dir = std.fs.path.dirname(source.path) orelse ".";
    const source_base = std.fs.path.basename(source.path);
    var fallback: ?u32 = null;
    for (graph.files.items, 0..) |file, raw| {
        if (!std.mem.eql(u8, graph.text(file.path), source_base)) continue;
        const module = graph.modules.items[@intFromEnum(file.module)];
        if (std.mem.eql(u8, graph.text(module.dir), source_dir)) return @intCast(raw);
        if (fallback == null) fallback = @intCast(raw) else fallback = null;
    }
    return fallback;
}

fn sourceRange(analysis: *const Analysis, source: primitives.SourceRef, len: u32) ?Range {
    const file = editor_index.sourceFileId(&analysis.graph, &analysis.source_db, source) orelse return null;
    return tokenRange(&analysis.source_db, .{ .file = file, .offset = source.offset }, len);
}

fn tokenRange(db: *const source_db.SourceDb, location: token.Location, len: u32) Range {
    const position = db.lineColumn(location.file, location.offset);
    return .{
        .start = .{ .line = position.line - 1, .character = position.column - 1 },
        .end = .{ .line = position.line - 1, .character = position.column - 1 + len },
    };
}

const HoverWriter = struct {
    allocator: std.mem.Allocator,
    buffer: *std.array_list.Managed(u8),

    fn writeAll(self: HoverWriter, text: []const u8) std.mem.Allocator.Error!void {
        try self.buffer.appendSlice(text);
    }

    fn print(self: HoverWriter, comptime format: []const u8, args: anytype) std.mem.Allocator.Error!void {
        const text = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(text);
        try self.buffer.appendSlice(text);
    }
};

fn formatHover(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, target: editor_index.Target) ![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();
    const writer = HoverWriter{ .allocator = allocator, .buffer = &output };
    try writer.writeAll("```argi\n");
    switch (target) {
        .function => |id| {
            const function = graph.functions.items[@intFromEnum(id)];
            const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
            if (function.flags.is_once) try writer.writeAll("once ");
            try writer.print("{s}(", .{graph.text(declaration.name)});
            try writeFieldRange(writer, graph, function.input);
            try writer.writeAll(") -> (");
            try writeFieldRange(writer, graph, function.output);
            try writer.writeAll(")");
        },
        .binding => |id| {
            const binding = graph.bindings.items[@intFromEnum(id)];
            try writer.print("{s} {s} ", .{ graph.text(binding.name), if (binding.mutability == .variable) "::" else ":" });
            try writeType(writer, graph, binding.ty);
        },
        .declaration => |id| {
            const declaration = graph.declarations.items[@intFromEnum(id)];
            const name = graph.text(declaration.name);
            switch (declaration.kind) {
                .type, .abstract_type => {
                    try writer.print("{s} : {s}", .{ name, if (declaration.kind == .type) "Type" else "Abstract" });
                    if (declaration.type_id) |ty| {
                        const self_reference = switch (graph.types.items[@intFromEnum(ty)]) {
                            .declared => |target_decl| target_decl == id,
                            else => false,
                        };
                        if (!self_reference) {
                            try writer.writeAll(" = ");
                            try writeType(writer, graph, ty);
                        }
                    }
                },
                .binding => {
                    try writer.writeAll(name);
                    if (declaration.type_id) |ty| {
                        try writer.writeAll(" : ");
                        try writeType(writer, graph, ty);
                    }
                },
                .choice_option => try writer.print("..{s}", .{name}),
                .import_alias, .function, .test_function => try writer.writeAll(name),
            }
        },
        .field => |id| {
            const field = graph.fields.items[@intFromEnum(id)];
            try writer.print(".{s}: ", .{graph.text(field.name)});
            try writeType(writer, graph, field.ty);
        },
        .variant => |id| {
            const variant = graph.variants.items[@intFromEnum(id)];
            try writer.print("..{s}", .{graph.text(variant.name)});
            if (variant.payload_type) |payload| {
                try writer.writeAll(" ");
                try writeType(writer, graph, payload);
            }
        },
    }
    try writer.writeAll("\n```");
    if (target == .declaration and graph.declarations.items[@intFromEnum(target.declaration)].kind == .import_alias)
        try writer.writeAll("\n\nImported module.");
    return try output.toOwnedSlice();
}

fn writeFieldRange(writer: HoverWriter, graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.FieldRange) std.mem.Allocator.Error!void {
    for (graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print(".{s}: ", .{graph.text(field.name)});
        try writeType(writer, graph, field.ty);
    }
}

fn writeType(writer: HoverWriter, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) std.mem.Allocator.Error!void {
    switch (graph.types.items[@intFromEnum(ty)]) {
        .builtin => |value| try writer.writeAll(@tagName(value)),
        .declared => |decl| try writer.writeAll(graph.text(graph.declarations.items[@intFromEnum(decl)].name)),
        .pointer => |pointer| {
            try writer.writeAll(if (pointer.mutability == .read_write) "$&" else "&");
            try writeType(writer, graph, pointer.child);
        },
        .array => |array| {
            try writer.print("[{d}]", .{array.length});
            try writeType(writer, graph, array.element);
        },
        .nullable => |child| {
            try writer.writeAll("?");
            try writeType(writer, graph, child);
        },
        .inferred_errable => |child| {
            try writer.writeAll("!");
            try writeType(writer, graph, child);
        },
        .inferred_choice => |choice| {
            try writeVariants(writer, graph, choice.variants);
        },
        .structural => |shape| {
            try writer.writeAll("(");
            try writeFieldRange(writer, graph, shape.fields);
            try writer.writeAll(")");
        },
        .structural_choice => |shape| try writeVariants(writer, graph, shape.variants),
        .generic => |generic| {
            try writer.writeAll(graph.text(graph.declarations.items[@intFromEnum(generic.base)].name));
            try writer.writeAll("#(");
            for (graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len], 0..) |argument, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print(".{s} {s} ", .{ graph.text(argument.name), if (argument.value == .comptime_int) "=" else ":" });
                switch (argument.value) {
                    .type => |value| try writeType(writer, graph, value),
                    .comptime_int => |value| try writer.print("{d}", .{value}),
                }
            }
            try writer.writeAll(")");
        },
        .virtual => |abstract_type| {
            try writer.writeAll("Virtual#(.abstract: ");
            try writeType(writer, graph, abstract_type);
            try writer.writeAll(")");
        },
    }
}

fn writeVariants(writer: HoverWriter, graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.VariantRange) std.mem.Allocator.Error!void {
    try writer.writeAll("(");
    for (graph.variants.items[range.start..][0..range.len], 0..) |variant, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("..{s}", .{graph.text(variant.name)});
        if (variant.payload_type) |payload| {
            try writer.writeAll(" ");
            try writeType(writer, graph, payload);
        }
    }
    try writer.writeAll(")");
}

const TokenClass = struct { type_index: u32, modifiers: u32 = 0 };

fn markSyntax(tree: *const st.FileSyntaxTree, classes: *std.AutoHashMap(u32, TokenClass), index: st.TokenIndex, kind: u32, modifiers: u32) !void {
    try classes.put(tree.tokenLocation(index).offset, .{ .type_index = kind, .modifiers = modifiers });
}

fn classifySyntax(allocator: std.mem.Allocator, tree: *const st.FileSyntaxTree, source: []const u8, classes: *std.AutoHashMap(u32, TokenClass)) !void {
    var type_names: std.StringHashMap(void) = .init(allocator);
    const declaration = @as(u32, 1) << MOD_INDEX.declaration;
    for (0..tree.nodes.len) |raw| {
        const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
        if (tree.syntaxType(node)) |ty| switch (ty) {
            .name => |name| {
                try markSyntax(tree, classes, name.name_token, TOKEN_INDEX.type_, 0);
                if (name.qualifier_token) |qualifier| try markSyntax(tree, classes, qualifier, TOKEN_INDEX.namespace, 0);
            },
            else => {},
        };
        if (tree.functionDeclaration(node)) |function| try markSyntax(tree, classes, function.name_token, TOKEN_INDEX.function, declaration);
        if (tree.typeDeclaration(node)) |ty| {
            try markSyntax(tree, classes, ty.name_token, TOKEN_INDEX.type_, declaration);
            try type_names.put(tree.tokenTextFromSource(source, ty.name_token), {});
        }
        if (tree.abstractDeclaration(node)) |ty| try markSyntax(tree, classes, ty.name_token, TOKEN_INDEX.type_, declaration);
        if (tree.symbolDeclaration(node)) |binding| {
            const readonly = if (binding.mutability == .constant) @as(u32, 1) << MOD_INDEX.readonly else 0;
            try markSyntax(tree, classes, binding.name_token, TOKEN_INDEX.variable, declaration | readonly);
        }
        if (tree.structTypeField(node)) |field| try markSyntax(tree, classes, field.name_token, TOKEN_INDEX.property, declaration);
        if (tree.valueField(node)) |field| if (field.name_token) |name| try markSyntax(tree, classes, name, TOKEN_INDEX.property, 0);
        if (tree.structFieldAccess(node)) |field| try markSyntax(tree, classes, field.field_token, TOKEN_INDEX.property, 0);
        if (tree.choiceLiteral(node)) |variant| try markSyntax(tree, classes, variant.name_token, TOKEN_INDEX.enum_member, 0);
        if (tree.choiceTypeVariant(node)) |variant| try markSyntax(tree, classes, variant.name_token, TOKEN_INDEX.enum_member, declaration);
        if (tree.functionCall(node)) |call| {
            try markSyntax(tree, classes, call.callee_token, TOKEN_INDEX.function, 0);
            if (call.module_qualifier) |qualifier| try markSyntax(tree, classes, qualifier, TOKEN_INDEX.namespace, 0);
        }
    }
    // Function fields share syntax nodes with record fields, but their role
    // in a signature is a parameter (including named result slots).
    for (0..tree.nodes.len) |raw| {
        const node: st.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
        if (tree.functionCall(node)) |call| {
            if (call.module_qualifier == null and type_names.contains(tree.tokenTextFromSource(source, call.callee_token)))
                try markSyntax(tree, classes, call.callee_token, TOKEN_INDEX.type_, 0);
        }
        const function = tree.functionDeclaration(node) orelse continue;
        for ([_]st.NodeIndex{ function.input, function.output }) |signature| {
            const fields = tree.structTypeLiteral(signature) orelse continue;
            for (fields.fields) |field_node| {
                const field = tree.structTypeField(field_node) orelse continue;
                try markSyntax(tree, classes, field.name_token, TOKEN_INDEX.parameter, declaration);
            }
        }
    }
}

fn classifyOccurrences(allocator: std.mem.Allocator, analysis: *const Analysis, path: []const u8, classes: *std.AutoHashMap(u32, TokenClass)) !void {
    const graph = &analysis.graph;
    var parameters: std.AutoHashMap(graph_mod.GlobalBindingId, void) = .init(allocator);
    var parameter_fields: std.AutoHashMap(graph_mod.GlobalFieldId, void) = .init(allocator);
    for (graph.functions.items) |function| {
        for ([_]graph_mod.FieldRange{ function.input, function.output }) |range|
            for (0..range.len) |index| try parameter_fields.put(@enumFromInt(range.start + @as(u32, @intCast(index))), {});
    }
    // Instantiated functions may also contain synthetic input bindings. Match
    // user parameters by their signature source rather than a binding range.
    const SourceKey = struct { file: u32, offset: u32 };
    var parameter_sources: std.AutoHashMap(SourceKey, graph_mod.GlobalFieldId) = .init(allocator);
    var fields = parameter_fields.keyIterator();
    while (fields.next()) |field_id| {
        const field = graph.fields.items[@intFromEnum(field_id.*)];
        try parameter_sources.put(.{ .file = field.source.file_index, .offset = field.source.offset }, field_id.*);
    }
    for (graph.bindings.items, 0..) |binding, raw| {
        const field_id = parameter_sources.get(.{ .file = binding.source.file_index, .offset = binding.source.offset }) orelse continue;
        const field = graph.fields.items[@intFromEnum(field_id)];
        if (std.mem.eql(u8, graph.text(field.name), graph.text(binding.name)))
            try parameters.put(@enumFromInt(@as(u32, @intCast(raw))), {});
    }
    for (analysis.index.occurrences.items) |occurrence| {
        const file = editor_index.sourceFileId(graph, &analysis.source_db, occurrence.source) orelse continue;
        if (!std.mem.eql(u8, analysis.source_db.path(file), path)) continue;
        if (!editor_index.occurrence_matches_source(graph, &analysis.source_db, occurrence)) continue;
        var classification: TokenClass = .{ .type_index = TOKEN_INDEX.variable };
        switch (occurrence.target) {
            .function => classification.type_index = TOKEN_INDEX.function,
            .binding => |id| {
                if (parameters.contains(id)) classification.type_index = TOKEN_INDEX.parameter;
                if (graph.bindings.items[@intFromEnum(id)].mutability == .constant)
                    classification.modifiers |= @as(u32, 1) << MOD_INDEX.readonly;
            },
            .declaration => |id| classification.type_index = switch (graph.declarations.items[@intFromEnum(id)].kind) {
                .type, .abstract_type => TOKEN_INDEX.type_,
                .import_alias => TOKEN_INDEX.namespace,
                .function, .test_function => TOKEN_INDEX.function,
                .choice_option => TOKEN_INDEX.enum_member,
                .binding => TOKEN_INDEX.variable,
            },
            .field => |id| classification.type_index = if (parameter_fields.contains(id)) TOKEN_INDEX.parameter else TOKEN_INDEX.property,
            .variant => classification.type_index = TOKEN_INDEX.enum_member,
        }
        // Syntax distinguishes a named argument label from a parameter use.
        if (classes.get(occurrence.source.offset)) |existing| {
            if (existing.type_index == TOKEN_INDEX.property and !occurrence.declaration)
                classification.type_index = TOKEN_INDEX.property;
            classification.modifiers |= existing.modifiers;
        }
        if (occurrence.declaration) classification.modifiers |= @as(u32, 1) << MOD_INDEX.declaration;
        try classes.put(occurrence.source.offset, classification);
    }
}

fn classifyToken(content: token.Content) ?TokenClass {
    return switch (content) {
        .comment => .{ .type_index = TOKEN_INDEX.comment },
        .identifier => .{ .type_index = TOKEN_INDEX.variable },
        .literal => |literal| switch (literal) {
            .string_literal, .char_literal => .{ .type_index = TOKEN_INDEX.string },
            .bool_literal => .{ .type_index = TOKEN_INDEX.keyword },
            else => .{ .type_index = TOKEN_INDEX.number },
        },
        .keyword_abort, .keyword_import, .keyword_return, .keyword_if, .keyword_else, .keyword_match, .keyword_for, .keyword_in, .keyword_while, .keyword_break, .keyword_continue, .keyword_once, .keyword_assume, .keyword_reach, .keyword_test, .keyword_and, .keyword_or => .{ .type_index = TOKEN_INDEX.keyword },
        .binary_operator, .comparison_operator, .equal, .arrow, .pipe, .tilde, .bang, .double_bang, .question_mark, .ampersand, .dollar, .colon, .double_colon => .{ .type_index = TOKEN_INDEX.operator },
        else => null,
    };
}

fn tokenLength(content: token.Content, source: []const u8, offset: u32) u32 {
    return switch (content) {
        .identifier, .comment => |range| range.len,
        .literal => |literal| switch (literal) {
            .bool_literal => |value| if (value) 4 else 5,
            .char_literal => scanQuoted(source, offset, '\''),
            .string_literal => scanQuoted(source, offset, '"'),
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal, .regular_float_literal, .scientific_float_literal => |range| range.len,
        },
        .keyword_abort => 5,
        .keyword_import => 6,
        .keyword_return => 6,
        .keyword_if => 2,
        .keyword_else => 4,
        .keyword_match => 5,
        .keyword_for => 3,
        .keyword_in => 2,
        .keyword_while => 5,
        .keyword_break => 5,
        .keyword_continue => 8,
        .keyword_once => 4,
        .keyword_assume => 6,
        .keyword_reach => 5,
        .keyword_test => 4,
        .keyword_and => 3,
        .keyword_or => 2,
        .double_colon, .arrow, .double_bang => 2,
        .comparison_operator => |operator| switch (operator) {
            .not_equal, .less_than_or_equal, .greater_than_or_equal, .equal => 2,
            else => 1,
        },
        .binary_operator, .equal, .pipe, .tilde, .bang, .question_mark, .ampersand, .dollar, .colon => 1,
        else => 0,
    };
}

fn scanQuoted(source: []const u8, start: u32, quote: u8) u32 {
    var index: usize = start + 1;
    var escaped = false;
    while (index < source.len) : (index += 1) {
        if (!escaped and source[index] == quote) return @intCast(index - start + 1);
        if (!escaped and source[index] == '\\') escaped = true else escaped = false;
    }
    return 1;
}

fn positionInRange(position: Position, range: Range) bool {
    if (position.line < range.start.line or position.line > range.end.line) return false;
    if (position.line == range.start.line and position.character < range.start.character) return false;
    if (position.line == range.end.line and position.character > range.end.character) return false;
    return true;
}

fn lessHint(_: void, a: InlayHint, b: InlayHint) bool {
    return if (a.position.line == b.position.line) a.position.character < b.position.character else a.position.line < b.position.line;
}

fn sortLocations(items: []Location) void {
    std.mem.sort(Location, items, {}, struct {
        fn lessThan(_: void, a: Location, b: Location) bool {
            const path_order = std.mem.order(u8, a.path, b.path);
            if (path_order != .eq) return path_order == .lt;
            if (a.range.start.line != b.range.start.line) return a.range.start.line < b.range.start.line;
            return a.range.start.character < b.range.start.character;
        }
    }.lessThan);
}

fn outlinePosition(code: []const u8, offset: usize) Position {
    const prefix = code[0..@min(offset, code.len)];
    const start = if (std.mem.lastIndexOfScalar(u8, prefix, '\n')) |index| index + 1 else 0;
    return .{ .line = @intCast(std.mem.count(u8, prefix, "\n")), .character = @intCast(prefix.len - start) };
}

fn outlineNodes(work: std.mem.Allocator, file: *const editor_syntax.File, nodes: []const st.NodeIndex) anyerror![]const DocumentSymbol {
    var items: std.ArrayList(DocumentSymbol) = .empty;
    for (nodes) |node| {
        var name_token: st.TokenIndex = undefined;
        var kind: u32 = undefined;
        var children: []const st.NodeIndex = &.{};
        if (file.tree.functionDeclaration(node)) |decl| {
            name_token = decl.name_token;
            kind = if (decl.c_function_pointer) 5 else 12;
            if (decl.body) |body| if (file.tree.codeBlock(body)) |block| {
                children = block.statements;
            };
        } else if (file.tree.typeDeclaration(node)) |decl| {
            name_token = decl.name_token;
            kind = 5;
            if (file.tree.structTypeLiteral(decl.value)) |value| {
                kind = 23;
                children = value.fields;
            }
            if (file.tree.choiceTypeLiteral(decl.value)) |value| {
                kind = 10;
                children = value.variants;
            }
        } else if (file.tree.cEnumDeclaration(node)) |decl| {
            name_token = decl.name_token;
            kind = 10;
            if (file.tree.choiceTypeLiteral(decl.value)) |value| children = value.variants;
        } else if (file.tree.cUnionDeclaration(node)) |decl| {
            name_token = decl.name_token;
            kind = 23;
            if (file.tree.structTypeLiteral(decl.value)) |value| children = value.fields;
        } else if (file.tree.abstractDeclaration(node)) |decl| {
            name_token = decl.name_token;
            kind = 11;
            children = decl.requires_functions;
        } else if (file.tree.abstractFunctionRequirement(node)) |decl| {
            name_token = decl.name_token;
            kind = 6;
        } else if (file.tree.symbolDeclaration(node)) |decl| {
            name_token = decl.name_token;
            kind = if (decl.mutability == .constant) 14 else 13;
            if (decl.value) |value| if (file.tree.importStatement(value) != null) {
                kind = 2;
            };
        } else if (file.tree.structTypeField(node)) |decl| {
            name_token = decl.name_token;
            kind = 8;
        } else if (file.tree.choiceTypeVariant(node)) |decl| {
            name_token = decl.name_token;
            kind = 22;
        } else if (file.tree.choiceOptionDeclaration(node)) |decl| {
            name_token = decl.name_token;
            kind = 22;
        } else continue;
        const name = file.tree.tokenTextFromSource(file.source.code, name_token);
        const start = file.tree.tokenLocation(name_token).offset;
        var end: usize = start + name.len;
        var depth: usize = 0;
        // Tokenizing keeps strings and comments opaque, so their punctuation
        // cannot terminate a declaration or change its delimiter depth.
        for (@intFromEnum(name_token)..file.tokens.len) |index| {
            const content = file.tokens.contents[index];
            if (content == .eof or (content == .new_line and depth == 0)) break;
            switch (content) {
                .open_parenthesis, .open_bracket, .open_brace => depth += 1,
                .close_parenthesis, .close_bracket, .close_brace => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                else => {},
            }
            if (content != .comment and content != .new_line) {
                const text = file.tree.tokenTextFromSource(file.source.code, @enumFromInt(@as(u32, @intCast(index))));
                end = file.tokens.locations[index].offset + text.len;
            }
        }
        try items.append(work, .{
            .name = try work.dupe(u8, name),
            .kind = kind,
            .range = .{ .start = outlinePosition(file.source.code, start), .end = outlinePosition(file.source.code, end) },
            .selectionRange = .{ .start = outlinePosition(file.source.code, start), .end = outlinePosition(file.source.code, start + name.len) },
            .children = try outlineNodes(work, file, children),
        });
    }
    return items.toOwnedSlice(work);
}

pub fn decodeFileUri(allocator: std.mem.Allocator, uri: []const u8) !?[]u8 {
    if (!std.mem.startsWith(u8, uri, "file://")) return null;
    const encoded = uri["file://".len..];
    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();
    var index: usize = 0;
    while (index < encoded.len) {
        if (encoded[index] == '%' and index + 2 < encoded.len) {
            const high = std.fmt.charToDigit(encoded[index + 1], 16) catch {
                try output.append(encoded[index]);
                index += 1;
                continue;
            };
            const low = std.fmt.charToDigit(encoded[index + 2], 16) catch {
                try output.append(encoded[index]);
                index += 1;
                continue;
            };
            try output.append(@intCast(high * 16 + low));
            index += 3;
        } else {
            try output.append(encoded[index]);
            index += 1;
        }
    }
    return try output.toOwnedSlice();
}

test "indexed LSP service public positions stay zero based" {
    const range = Range{ .start = .{ .line = 0, .character = 1 }, .end = .{ .line = 0, .character = 4 } };
    try std.testing.expect(positionInRange(.{ .line = 0, .character = 2 }, range));
    try std.testing.expect(!positionInRange(.{ .line = 1, .character = 0 }, range));
}

fn expectSemanticToken(data: []const u32, source: []const u8, needle: []const u8, kind: u32, modifiers: ?u32) !void {
    const offset = std.mem.indexOf(u8, source, needle) orelse return error.TestExpectedEqual;
    var line: u32 = 0;
    var character: u32 = 0;
    var line_start: usize = 0;
    for (source[0..offset], 0..) |byte, index| {
        if (byte == '\n') {
            line += 1;
            line_start = index + 1;
        }
    }
    const expected_character: u32 = @intCast(offset - line_start);
    var actual_line: u32 = 0;
    var index: usize = 0;
    while (index < data.len) : (index += 5) {
        actual_line += data[index];
        character = if (data[index] == 0) character + data[index + 1] else data[index + 1];
        if (actual_line == line and character == expected_character) {
            try std.testing.expectEqual(kind, data[index + 3]);
            if (modifiers) |expected| try std.testing.expectEqual(expected, data[index + 4]);
            return;
        }
    }
    return error.TestExpectedEqual;
}

test "LSP semantic tokens distinguish resolved names without synthetic recoloring" {
    const code =
        \\Point : Type = (.x: Int32)
        \\identity(.value: Int32) -> (.result: Int32) := { result = value }
        \\main(.system: System) -> (.status_code: Int32 = 0) := {
        \\    assume writer := $&system.terminal&.stdout
        \\    point ::= Point(.x = 2)
        \\    amount := identity(.value = point.x)
        \\    print("Hello world")
        \\    -- comment
        \\}
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = code });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "main.rg");
    defer std.testing.allocator.free(path);
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    try service.documents.append(try Document.init(std.testing.allocator, "file:///colors.rg", path, 1, code));
    var data = try service.semanticTokensFull("file:///colors.rg");
    defer data.deinit();
    try expectSemanticToken(data.items, code, "Point :", TOKEN_INDEX.type_, 1);
    try expectSemanticToken(data.items, code, "identity(.value:", TOKEN_INDEX.function, 1);
    try expectSemanticToken(data.items, code, "value: Int32", TOKEN_INDEX.parameter, 3);
    try expectSemanticToken(data.items, code, "value }", TOKEN_INDEX.parameter, 2);
    try expectSemanticToken(data.items, code, "result =", TOKEN_INDEX.parameter, 0);
    try expectSemanticToken(data.items, code, "System)", TOKEN_INDEX.type_, 0);
    try expectSemanticToken(data.items, code, "system.terminal", TOKEN_INDEX.parameter, 2);
    try expectSemanticToken(data.items, code, "terminal&", TOKEN_INDEX.property, 0);
    try expectSemanticToken(data.items, code, "point ::=", TOKEN_INDEX.variable, 1);
    try expectSemanticToken(data.items, code, "Point(.x", TOKEN_INDEX.type_, 0);
    try expectSemanticToken(data.items, code, "amount :=", TOKEN_INDEX.variable, 3);
    try expectSemanticToken(data.items, code, "identity(.value =", TOKEN_INDEX.function, 0);
    try expectSemanticToken(data.items, code, "value = point", TOKEN_INDEX.property, 0);
    try expectSemanticToken(data.items, code, "point.x", TOKEN_INDEX.variable, 0);
    try expectSemanticToken(data.items, code, "print(", TOKEN_INDEX.function, 0);
    try expectSemanticToken(data.items, code, "\"Hello world\"", TOKEN_INDEX.string, 0);
    try expectSemanticToken(data.items, code, "-- comment", TOKEN_INDEX.comment, 0);
}

test "LSP navigation and hovers use written symbols and source declarations" {
    const code =
        \\Point : Type = (.x: Int32)
        \\identity(.value: Int32) -> (.result: Int32) := { result = value }
        \\main(.system: System) -> (.status_code: Int32 = 0) := {
        \\    assume writer := $&system.terminal&.stdout
        \\    point ::= Point(.x = 2)
        \\    amount := identity(.value = point.x)
        \\    print("Hello world")
        \\}
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = code });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "main.rg");
    defer std.testing.allocator.free(path);
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    const uri = "file:///navigation.rg";
    try service.documents.append(try Document.init(std.testing.allocator, uri, path, 1, code));

    const nominal = (try service.hover(uri, .{ .line = 0, .character = 0 })).?;
    defer std.testing.allocator.free(nominal.contents);
    try std.testing.expectEqualStrings("```argi\nPoint : Type\n```", nominal.contents);
    const call = (try service.hover(uri, .{ .line = 5, .character = 14 })).?;
    defer std.testing.allocator.free(call.contents);
    try std.testing.expect(std.mem.startsWith(u8, call.contents, "```argi\nidentity("));
    try std.testing.expectEqual(@as(u32, 14), call.range.start.character);
    const field = (try service.hover(uri, .{ .line = 3, .character = 30 })).?;
    defer std.testing.allocator.free(field.contents);
    try std.testing.expectEqualStrings("```argi\n.terminal: $&Terminal\n```", field.contents);
    try std.testing.expectEqual(@as(u32, 30), field.range.start.character);

    const identity = (try service.definition(uri, .{ .line = 5, .character = 14 })).?;
    defer identity.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(path, identity.path);
    try std.testing.expectEqual(@as(u32, 1), identity.range.start.line);
    try std.testing.expectEqual(@as(u32, 0), identity.range.start.character);
    const specialized = (try service.definition(uri, .{ .line = 6, .character = 4 })).?;
    defer specialized.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, specialized.path, "/system/terminal.rg"));
    try std.testing.expectEqual(@as(u32, 0), specialized.range.start.character);
    try std.testing.expectEqual(@as(u32, 5), specialized.range.end.character);
    const terminal = (try service.definition(uri, .{ .line = 3, .character = 30 })).?;
    defer terminal.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, terminal.path, "/system/system.rg"));
    try std.testing.expectEqual(@as(u32, 8), terminal.range.end.character - terminal.range.start.character);
}

test "LSP semantic tokens retain syntax roles with unresolved calls and multiline text" {
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    text := "héllo
        \\world"
        \\    missing(.value = text)
        \\    abort
        \\}
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = code });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "main.rg");
    defer std.testing.allocator.free(path);
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    try service.documents.append(try Document.init(std.testing.allocator, "file:///unfinished.rg", path, 1, code));
    var data = try service.semanticTokensFull("file:///unfinished.rg");
    defer data.deinit();
    try expectSemanticToken(data.items, code, "main()", TOKEN_INDEX.function, 1);
    try expectSemanticToken(data.items, code, "Int32", TOKEN_INDEX.type_, 0);
    try expectSemanticToken(data.items, code, "missing(", TOKEN_INDEX.function, 0);
    try expectSemanticToken(data.items, code, "value =", TOKEN_INDEX.property, 0);
    try expectSemanticToken(data.items, code, "abort", TOKEN_INDEX.keyword, 0);
    try expectSemanticToken(data.items, code, "\"héllo", TOKEN_INDEX.string, 0);
    try expectSemanticToken(data.items, code, "world\"", TOKEN_INDEX.string, 0);
    var line: usize = 0;
    var character: usize = 0;
    var index: usize = 0;
    var lines = std.mem.splitScalar(u8, code, '\n');
    var spans: std.array_list.Managed([]const u8) = .init(std.testing.allocator);
    defer spans.deinit();
    while (lines.next()) |text| try spans.append(text);
    while (index < data.items.len) : (index += 5) {
        line += data.items[index];
        character = if (data.items[index] == 0) character + data.items[index + 1] else data.items[index + 1];
        try std.testing.expect(character + data.items[index + 2] <= spans.items[line].len);
    }
}

fn completion_offset(text: []const u8, position: Position) ?usize {
    var line: u32 = 0;
    var start: usize = 0;
    for (text, 0..) |byte, index| {
        if (line == position.line) break;
        if (byte == '\n') {
            line += 1;
            start = index + 1;
        }
    }
    if (line != position.line) return null;
    const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
    const line_end = if (end > start and text[end - 1] == '\r') end - 1 else end;
    if (position.character > line_end - start) return null;
    const offset = start + position.character;
    if (offset < text.len and text[offset] & 0xc0 == 0x80) return null;
    return offset;
}

test "LSP completion positions validate UTF-8 bytes and CRLF boundaries" {
    const code = "-- é\r\nmain()\r\n";
    try std.testing.expectEqual(@as(?usize, 7), completion_offset(code, .{ .line = 1, .character = 0 }));
    try std.testing.expectEqual(@as(?usize, 13), completion_offset(code, .{ .line = 1, .character = 6 }));
    try std.testing.expect(completion_offset(code, .{ .line = 1, .character = 7 }) == null);
    try std.testing.expect(completion_offset(code, .{ .line = 0, .character = 4 }) == null);
    try std.testing.expect(completion_offset(code, .{ .line = 4, .character = 0 }) == null);
}

test "LSP definitions remain available with unresolved matrix initializers" {
    const code =
        \\MatrixView : Type = (.data_p: &[2][2]Int32)
        \\main(.system: System) -> (.status_code: Int32 = 0) := {
        \\    assume writer := $&system.terminal&.stdout
        \\    data : [2][2]Int32 = ((1,2), (3,4))
        \\    mv : MatrixView = (.data_p = &data)
        \\    print("Hello world")
        \\}
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = code });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "main.rg");
    defer std.testing.allocator.free(path);
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    const uri = "file:///matrix.rg";
    try service.documents.append(try Document.init(std.testing.allocator, uri, path, 1, code));
    const system = (try service.definition(uri, .{ .line = 1, .character = 14 })).?;
    defer system.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, system.path, "/system/system.rg"));
    const print = (try service.definition(uri, .{ .line = 5, .character = 4 })).?;
    defer print.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, print.path, "/system/terminal.rg"));
    const matrix = (try service.definition(uri, .{ .line = 4, .character = 9 })).?;
    defer matrix.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(path, matrix.path);
    try std.testing.expectEqual(@as(u32, 0), matrix.range.start.line);
    const data = (try service.definition(uri, .{ .line = 4, .character = 34 })).?;
    defer data.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 3), data.range.start.line);
}

test "LSP module reuse preserves navigation across unsaved imports and file changes" {
    const code =
        \\dep := import("./dep")
        \\main() -> (.status_code: Int32) := {
        \\    status_code = dep.answer().result
        \\}
    ;
    const dependency = "answer() -> (.result: Int32 = 7) := {}\n";
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "dep", .default_dir);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = code });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "dep/answer.rg", .data = dependency });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "main.rg");
    defer std.testing.allocator.free(path);
    const dep_path = try @import("../test_support.zig").tmpFilePath(&tmp, "dep/answer.rg");
    defer std.testing.allocator.free(dep_path);
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    const uri = "file:///incremental.rg";
    const opened = try service.openDocument(uri, path, 1, code);
    defer opened.deinit();
    try std.testing.expectEqual(@as(usize, 0), opened.items.len);
    const misses = service.module_cache.misses;
    const modules = service.module_cache.entries.items.len;
    const position = Position{ .line = 2, .character = 22 };
    const definition = (try service.definition(uri, position)).?;
    defer definition.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(dep_path, definition.path);
    try std.testing.expectEqual(@as(u32, 0), definition.range.start.line);
    try std.testing.expectEqual(misses, service.module_cache.misses);
    try std.testing.expectEqual(modules, service.module_cache.hits);

    // The imported buffer stays unsaved on disk; its source location changes.
    const changed = try service.openDocument("file:///incremental-dep.rg", dep_path, 1, "\n" ++ dependency);
    defer changed.deinit();
    const moved = (try service.definition(uri, position)).?;
    defer moved.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), moved.range.start.line);
    try std.testing.expectEqual(misses + 1, service.module_cache.misses);

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "helper.rg", .data = "helper() -> () := {}\n" });
    const with_file = (try service.definition(uri, position)).?;
    defer with_file.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(dep_path, with_file.path);
    try std.testing.expectEqual(@as(u32, 1), with_file.range.start.line);
    try std.testing.expectEqual(misses + 2, service.module_cache.misses);
    try tmp.dir.deleteFile(std.testing.io, "helper.rg");
    const without_file = (try service.definition(uri, position)).?;
    defer without_file.deinit(std.testing.allocator);
    try std.testing.expectEqual(misses + 3, service.module_cache.misses);

    const broken = try service.changeDocument(uri, path, 2, "main(\n");
    defer broken.deinit();
    try std.testing.expect(broken.items.len != 0);
    const repaired = try service.changeDocument(uri, path, 3, code);
    defer repaired.deinit();
    try std.testing.expectEqual(@as(usize, 0), repaired.items.len);
    const hover = (try service.hover(uri, position)).?;
    defer std.testing.allocator.free(hover.contents);
    try std.testing.expect(std.mem.indexOf(u8, hover.contents, "answer(") != null);
    service.closeDocument("file:///incremental-dep.rg");
    const from_disk = (try service.definition(uri, position)).?;
    defer from_disk.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), from_disk.range.start.line);
    try std.testing.expect(service.module_cache.retained_bytes <= service.module_cache.limits.bytes);
}

test "LSP module reuse discovers unsaved transitive imports and cycles" {
    const code =
        \\dep := import("./dep")
        \\main() -> (.status_code: Int32) := {
        \\    status_code = dep.answer().result
        \\}
    ;
    const original = "answer() -> (.result: Int32 = 7) := {}\n";
    const edited = "next := import(\"../next\")\nanswer() -> (.result: Int32) := { result = next.number().result }\n";
    const next_code = "number() -> (.result: Int32 = 9) := {}\n";
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "dep", .default_dir);
    try tmp.dir.createDir(std.testing.io, "next", .default_dir);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = code });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "dep/answer.rg", .data = original });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "next/number.rg", .data = next_code });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "main.rg");
    defer std.testing.allocator.free(path);
    const dep_path = try @import("../test_support.zig").tmpFilePath(&tmp, "dep/answer.rg");
    defer std.testing.allocator.free(dep_path);
    const next_path = try @import("../test_support.zig").tmpFilePath(&tmp, "next/number.rg");
    defer std.testing.allocator.free(next_path);
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    const uri = "file:///unsaved-import-main.rg";
    const opened = try service.openDocument(uri, path, 1, code);
    defer opened.deinit();
    const added_import = try service.openDocument("file:///unsaved-import-dep.rg", dep_path, 1, edited);
    defer added_import.deinit();
    try std.testing.expectEqual(@as(usize, 0), added_import.items.len);
    const definition = (try service.definition(uri, .{ .line = 2, .character = 23 })).?;
    defer definition.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(dep_path, definition.path);
    try std.testing.expectEqual(@as(u32, 1), definition.range.start.line);

    const cycle = try service.openDocument("file:///unsaved-import-next.rg", next_path, 1, "back := import(\"../dep\")\n" ++ next_code);
    defer cycle.deinit();
    try std.testing.expectEqual(@as(usize, 1), cycle.items.len);
    try std.testing.expectEqualStrings("import cycle detected", cycle.items[0].message);
    const root_cycle = try service.changeDocument(uri, path, 2, code);
    defer root_cycle.deinit();
    try std.testing.expectEqualStrings("import cycle detected", root_cycle.items[0].message);
    const repaired = try service.changeDocument("file:///unsaved-import-next.rg", next_path, 2, next_code);
    defer repaired.deinit();
    try std.testing.expectEqual(@as(usize, 0), repaired.items.len);
    const root_repaired = try service.changeDocument(uri, path, 3, code);
    defer root_repaired.deinit();
    try std.testing.expectEqual(@as(usize, 0), root_repaired.items.len);
    service.closeDocument("file:///unsaved-import-dep.rg");
    const reverted = (try service.definition(uri, .{ .line = 2, .character = 23 })).?;
    defer reverted.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), reverted.range.start.line);
}

test "LSP document symbols preserve hierarchy and unsaved syntax" {
    const code =
        \\Point : Type = (
        \\    .x: Int32
        \\    .y: Int32
        \\)
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value ::= missing()
        \\}
    ;
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    try service.documents.append(try Document.init(std.testing.allocator, "file:///outline.rg", "/not-on-disk/outline.rg", 1, code));
    const result = try service.documentSymbols("file:///outline.rg");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    const point = result.items[0];
    try std.testing.expectEqualStrings("Point", point.name);
    try std.testing.expectEqual(@as(u32, 23), point.kind);
    try std.testing.expectEqual(@as(u32, 3), point.range.end.line);
    try std.testing.expectEqual(@as(u32, 1), point.range.end.character);
    try std.testing.expectEqual(@as(usize, 2), point.children.len);
    try std.testing.expectEqualStrings("x", point.children[0].name);
    try std.testing.expectEqual(@as(u32, 8), point.children[0].kind);
    try std.testing.expectEqual(@as(u32, 1), point.children[0].selectionRange.start.line);
    const main = result.items[1];
    try std.testing.expectEqualStrings("main", main.name);
    try std.testing.expectEqual(@as(u32, 12), main.kind);
    try std.testing.expectEqual(@as(u32, 6), main.range.end.line);
    try std.testing.expectEqualStrings("value", main.children[0].name);
    try std.testing.expectEqual(@as(u32, 13), main.children[0].kind);
}

test "LSP reports assignment without a previous declaration" {
    const code = "main() -> (.status_code: Int32 = 0) := {\n    value = 1\n}\n";
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = code });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "main.rg");
    defer std.testing.allocator.free(path);
    var service = LanguageService.init(std.testing.allocator, std.testing.io);
    defer service.deinit();
    const diagnostics = try service.openDocument("file:///assignment.rg", path, 1, code);
    defer diagnostics.deinit();
    try std.testing.expect(diagnostics.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.items[0].message, "cannot assign to undeclared binding 'value'") != null);
    try std.testing.expectEqual(@as(u32, 1), diagnostics.items[0].range.start.line);
    const corrected = try service.changeDocument("file:///assignment.rg", path, 2, "main() -> (.status_code: Int32 = 0) := {\n    value ::= 1\n    value = 2\n    status_code = value\n}\n");
    defer corrected.deinit();
    try std.testing.expectEqual(@as(usize, 0), corrected.items.len);
}

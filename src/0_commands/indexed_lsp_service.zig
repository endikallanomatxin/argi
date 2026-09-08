const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const graph_mod = @import("../4_semantics/global_semantic_graph.zig");
const global_types = @import("../4_semantics/global_semantic_types.zig");
const editor_index = @import("../4_semantics/global_lsp_index.zig");
const primitives = @import("../4_semantics/semantic_primitives.zig");
const frontend = @import("frontend_pipeline.zig");

const log = std.log.scoped(.indexed_lsp_service);

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

const MOD_INDEX = struct {
    pub const declaration: u32 = 0;
    pub const readonly: u32 = 1;
};

pub const Severity = enum(u8) { err = 1, warn = 2, info = 3, hint = 4 };
pub const Position = struct { line: u32, character: u32 };
pub const Range = struct { start: Position, end: Position };
pub const Diagnostic = struct { range: Range, severity: Severity, message: []const u8 };
pub const InlayHint = struct { position: Position, label: []const u8 };
pub const Hover = struct { range: Range, contents: []const u8 };

pub const Definition = struct {
    path: []u8,
    range: Range,
    pub fn deinit(self: Definition, allocator: std.mem.Allocator) void { allocator.free(self.path); }
};

pub const PrepareRename = struct {
    range: Range,
    placeholder: []u8,
    pub fn deinit(self: PrepareRename, allocator: std.mem.Allocator) void { allocator.free(self.placeholder); }
};

pub const Location = struct {
    path: []u8,
    range: Range,
    pub fn deinit(self: Location, allocator: std.mem.Allocator) void { allocator.free(self.path); }
};

pub const LocationsResult = struct {
    allocator: std.mem.Allocator,
    items: []Location,
    owned: bool,
    pub fn empty(allocator: std.mem.Allocator) LocationsResult { return .{ .allocator = allocator, .items = &.{}, .owned = false }; }
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
    pub fn empty(allocator: std.mem.Allocator) TextEditsResult { return .{ .allocator = allocator, .items = &.{}, .owned = false }; }
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
    pub fn empty(allocator: std.mem.Allocator) DiagnosticsResult { return .{ .allocator = allocator, .items = &.{}, .owned = false }; }
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
    pub fn empty(allocator: std.mem.Allocator) InlayHintsResult { return .{ .allocator = allocator, .items = &.{}, .owned = false }; }
    pub fn deinit(self: InlayHintsResult) void {
        if (!self.owned) return;
        for (self.items) |item| self.allocator.free(item.label);
        self.allocator.free(self.items);
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

    pub fn init(allocator: std.mem.Allocator, io: std.Io) LanguageService {
        return .{ .allocator = allocator, .io = io, .documents = std.array_list.Managed(Document).init(allocator) };
    }

    pub fn deinit(self: *LanguageService) void {
        for (self.documents.items) |*document| document.deinit(self.allocator);
        self.documents.deinit();
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

        var output = std.array_list.Managed(u32).init(self.allocator);
        var previous_line: u32 = 0;
        var previous_character: u32 = 0;
        for (0..tokens.len) |index| {
            const item = tokens.get(index);
            const classification = classifyToken(item.content) orelse continue;
            const length = tokenLength(item.content, doc.text, item.location.offset);
            if (length == 0) continue;
            const position = diagnostics.source_db.lineColumn(item.location.file, item.location.offset);
            const line = position.line - 1;
            const character = position.column - 1;
            const delta_line = line - previous_line;
            const delta_character = if (delta_line == 0) character - previous_character else character;
            try output.append(delta_line);
            try output.append(delta_character);
            try output.append(length);
            try output.append(classification.type_index);
            try output.append(classification.modifiers);
            previous_line = line;
            previous_character = character;
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
        var analysis = (try self.collectAnalysis(&work, doc)) orelse return null;
        defer analysis.deinit(work);

        const occurrence = analysis.index.occurrenceAt(&analysis.graph, &analysis.source_db, doc.path, position.line, position.character) orelse return null;
        const target = analysis.index.declarationOccurrence(occurrence.target) orelse return null;
        return try self.definitionForOccurrence(&analysis, target);
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
            const call = switch (node.content) { .function_call => |value| value, else => continue };
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
        var pipeline = frontend.FrontendPipeline.init(work, self.io, &diagnostics, .{});
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
        var pipeline = frontend.FrontendPipeline.init(allocator.*, self.io, &diagnostics, .{});
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
        const files = try sf.collectWithEntrySource(allocator, self.io, core_dir, doc.path, doc.text);
        for (files.items) |*source_file| for (self.documents.items) |open_document| {
            if (std.mem.eql(u8, source_file.path, open_document.path)) source_file.code = open_document.text;
        };
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
            try writer.print("{s}(", .{graph.text(declaration.name)});
            try writeFieldRange(writer, graph, function.input);
            try writer.writeAll(") -> (");
            try writeFieldRange(writer, graph, function.output);
            try writer.writeAll(")");
        },
        .binding => |id| {
            const binding = graph.bindings.items[@intFromEnum(id)];
            try writer.print("{s}: ", .{graph.text(binding.name)});
            try writeType(writer, graph, binding.ty);
        },
        .declaration => |id| {
            const declaration = graph.declarations.items[@intFromEnum(id)];
            try writer.print("{s} {s}", .{ @tagName(declaration.kind), graph.text(declaration.name) });
            if (declaration.type_id) |ty| {
                try writer.writeAll(" = ");
                try writeType(writer, graph, ty);
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
                try writer.writeAll(": ");
                try writeType(writer, graph, payload);
            }
        },
    }
    try writer.writeAll("\n```");
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
            try writer.writeAll(if (pointer.mutability == .read_write) "&mut " else "&");
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
            try writer.print("choice#{d}", .{choice.identity});
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
                try writer.print(".{s}: ", .{graph.text(argument.name)});
                switch (argument.value) {
                    .type => |value| try writeType(writer, graph, value),
                    .comptime_int => |value| try writer.print("{d}", .{value}),
                }
            }
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
            try writer.writeAll(": ");
            try writeType(writer, graph, payload);
        }
    }
    try writer.writeAll(")");
}

const TokenClass = struct { type_index: u32, modifiers: u32 = 0 };

fn classifyToken(content: token.Content) ?TokenClass {
    return switch (content) {
        .comment => .{ .type_index = TOKEN_INDEX.comment },
        .identifier => .{ .type_index = TOKEN_INDEX.variable },
        .literal => |literal| switch (literal) {
            .string_literal, .char_literal => .{ .type_index = TOKEN_INDEX.string },
            .bool_literal => .{ .type_index = TOKEN_INDEX.keyword },
            else => .{ .type_index = TOKEN_INDEX.number },
        },
        .keyword_return, .keyword_if, .keyword_else, .keyword_match, .keyword_for, .keyword_in,
        .keyword_while, .keyword_break, .keyword_continue, .keyword_once, .keyword_test,
        .keyword_and, .keyword_or => .{ .type_index = TOKEN_INDEX.keyword },
        .binary_operator, .comparison_operator, .equal, .arrow, .pipe, .tilde, .bang, .double_bang,
        .question_mark, .ampersand, .dollar, .colon, .double_colon => .{ .type_index = TOKEN_INDEX.operator },
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
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal,
            .regular_float_literal, .scientific_float_literal => |range| range.len,
        },
        .keyword_return => 6, .keyword_if => 2, .keyword_else => 4, .keyword_match => 5,
        .keyword_for => 3, .keyword_in => 2, .keyword_while => 5, .keyword_break => 5,
        .keyword_continue => 8, .keyword_once => 4, .keyword_test => 4, .keyword_and => 3, .keyword_or => 2,
        .double_colon, .arrow, .double_bang => 2,
        .comparison_operator => |operator| switch (operator) { .not_equal, .less_than_or_equal, .greater_than_or_equal, .equal => 2, else => 1 },
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

fn decodeFileUri(allocator: std.mem.Allocator, uri: []const u8) !?[]u8 {
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

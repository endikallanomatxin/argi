const std = @import("std");
const json = std.json;

const service = @import("lsp_service.zig");

const AllocError = std.mem.Allocator.Error;

const ReadMessageError = error{
    MissingContentLength,
    InvalidContentLength,
};

const UriError = error{UnsupportedUri};

pub fn start() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var server = LanguageServer.init(gpa.allocator());
    defer server.deinit();

    try server.run();
}

const LanguageServer = struct {
    allocator: std.mem.Allocator,
    buffer: std.array_list.Managed(u8),
    service: ?service.LanguageService = null,
    shutdown_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator) LanguageServer {
        return .{
            .allocator = allocator,
            .buffer = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *LanguageServer) void {
        self.buffer.deinit();
        if (self.service) |*svc| svc.deinit();
    }

    pub fn run(self: *LanguageServer) !void {
        var reader = std.fs.File.stdin().deprecatedReader();
        var writer = std.fs.File.stdout().deprecatedWriter();

        while (true) {
            const payload = self.readMessage(&reader) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            if (payload.len == 0) continue;

            var parsed = json.parseFromSlice(json.Value, self.allocator, payload, .{}) catch {
                continue;
            };
            defer parsed.deinit();

            const root = parsed.value;
            if (root != .object) continue;
            const obj = root.object;

            const method_value = obj.get("method") orelse continue;
            if (method_value != .string) continue;
            const method = method_value.string;

            const id_value = obj.get("id");
            const params_value = obj.get("params");

            if (std.mem.eql(u8, method, "initialize")) {
                if (id_value) |id| {
                    self.handleInitialize(&writer, id, params_value) catch {};
                }
            } else if (std.mem.eql(u8, method, "initialized")) {
                // No-op
            } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
                self.handleDidOpen(&writer, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
                self.handleDidChange(&writer, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
                self.handleDidClose(&writer, params_value) catch {};
            } else if (std.mem.eql(u8, method, "shutdown")) {
                if (id_value) |id| self.handleShutdown(&writer, id) catch {};
            } else if (std.mem.eql(u8, method, "exit")) {
                break;
            } else if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
                if (id_value) |id| self.handleSemanticTokensFull(&writer, id, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/semanticTokens/range")) {
                if (id_value) |id| self.handleSemanticTokensRange(&writer, id, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/hover")) {
                if (id_value) |id| self.handleHover(&writer, id, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/definition")) {
                if (id_value) |id| self.handleDefinition(&writer, id, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/references")) {
                if (id_value) |id| self.handleReferences(&writer, id, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/prepareRename")) {
                if (id_value) |id| self.handlePrepareRename(&writer, id, params_value) catch {};
            } else if (std.mem.eql(u8, method, "textDocument/rename")) {
                if (id_value) |id| self.handleRename(&writer, id, params_value) catch {};
            } else {
                // Método desconocido -> ignorar
            }
        }
    }

    fn readMessage(
        self: *LanguageServer,
        reader: anytype,
    ) (ReadMessageError || error{EndOfStream} || std.io.AnyReader.Error || AllocError)![]const u8 {
        var content_length: ?usize = null;

        while (true) {
            const line_opt = try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024);
            if (line_opt == null) return error.EndOfStream;
            const line_raw = line_opt.?;
            defer self.allocator.free(line_raw);

            const line_trimmed = std.mem.trimRight(u8, line_raw, "\r\n");
            if (line_trimmed.len == 0) break;

            if (std.mem.startsWith(u8, line_trimmed, "Content-Length:")) {
                const value_slice = std.mem.trimLeft(u8, line_trimmed["Content-Length:".len..], " ");
                content_length = std.fmt.parseInt(usize, value_slice, 10) catch return ReadMessageError.InvalidContentLength;
            }
        }

        const len = content_length orelse return ReadMessageError.MissingContentLength;
        try self.buffer.resize(len);
        try reader.readNoEof(self.buffer.items[0..len]);
        return self.buffer.items[0..len];
    }

    fn handleInitialize(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) {
            self.service = service.LanguageService.init(self.allocator);
        }

        if (params_value) |params| {
            if (params == .object) {
                if (getField(&params.object, "rootUri")) |uri_value| {
                    if (uri_value == .string) {
                        if (self.service) |*svc| {
                            svc.initialize(uri_value.string) catch {};
                        }
                    }
                }
            }
        }

        try self.respondInitialize(writer, id_value);
    }

    fn handleDidOpen(self: *LanguageServer, writer: anytype, params_value: ?json.Value) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;
        const params_obj = params.object;

        const text_document_value = getField(&params_obj, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const text_doc_obj = text_document_value.object;

        const uri_value = getField(&text_doc_obj, "uri") orelse return;
        if (uri_value != .string) return;
        const text_value = getField(&text_doc_obj, "text") orelse return;
        if (text_value != .string) return;
        const version_value = getField(&text_doc_obj, "version");

        const version: ?i64 = if (version_value) |vv| if (vv == .integer) vv.integer else null else null;

        const path = self.uriToPath(uri_value.string) catch return;
        defer self.allocator.free(path);

        if (self.service) |*svc| {
            var diagnostics = svc.openDocument(uri_value.string, path, version, text_value.string) catch return;
            defer diagnostics.deinit();
            try self.sendPublishDiagnostics(writer, uri_value.string, diagnostics.items);
        }
    }

    fn handleDidChange(self: *LanguageServer, writer: anytype, params_value: ?json.Value) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;
        const params_obj = params.object;

        const text_document_value = getField(&params_obj, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const text_doc_obj = text_document_value.object;

        const uri_value = getField(&text_doc_obj, "uri") orelse return;
        if (uri_value != .string) return;
        const version_value = getField(&text_doc_obj, "version");

        const changes_value = getField(&params_obj, "contentChanges") orelse return;
        if (changes_value != .array) return;
        if (changes_value.array.items.len == 0) return;
        const last_change = changes_value.array.items[changes_value.array.items.len - 1];
        if (last_change != .object) return;
        const text_value = getField(&last_change.object, "text") orelse return;
        if (text_value != .string) return;

        const version: ?i64 = if (version_value) |vv| if (vv == .integer) vv.integer else null else null;

        const path = self.uriToPath(uri_value.string) catch return;
        defer self.allocator.free(path);

        if (self.service) |*svc| {
            var diagnostics = svc.changeDocument(uri_value.string, path, version, text_value.string) catch return;
            defer diagnostics.deinit();
            try self.sendPublishDiagnostics(writer, uri_value.string, diagnostics.items);
        }
    }

    fn handleDidClose(self: *LanguageServer, writer: anytype, params_value: ?json.Value) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;
        const params_obj = params.object;

        const text_document_value = getField(&params_obj, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const text_doc_obj = text_document_value.object;
        const uri_value = getField(&text_doc_obj, "uri") orelse return;
        if (uri_value != .string) return;

        if (self.service) |*svc| svc.closeDocument(uri_value.string);
        try self.sendPublishDiagnostics(writer, uri_value.string, &[_]service.Diagnostic{});
    }

    fn handleShutdown(self: *LanguageServer, writer: anytype, id_value: json.Value) !void {
        self.shutdown_requested = true;
        try self.respondNullResult(writer, id_value);
    }

    fn respondInitialize(self: *LanguageServer, writer: anytype, id_value: json.Value) !void {
        var payload = std.Io.Writer.Allocating.init(self.allocator);
        defer payload.deinit();

        var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

        try stream.beginObject();
        try stream.objectField("jsonrpc");
        try stream.write("2.0");
        try stream.objectField("id");
        try stream.write(id_value);
        try stream.objectField("result");
        try stream.beginObject();

        try stream.objectField("capabilities");
        try stream.beginObject();
        try stream.objectField("positionEncoding");
        try stream.write("utf-8");
        try stream.objectField("textDocumentSync");
        try stream.beginObject();
        try stream.objectField("openClose");
        try stream.write(true);
        try stream.objectField("change");
        try stream.write(@as(i32, 1));
        try stream.endObject();
        try stream.objectField("semanticTokensProvider");
        try stream.beginObject();
        // legend
        try stream.objectField("legend");
        try stream.beginObject();
        try stream.objectField("tokenTypes");
        try stream.beginArray();
        // usa los que vayas a producir ya en el MVP:
        try stream.write("namespace");
        try stream.write("type");
        try stream.write("function");
        try stream.write("method");
        try stream.write("variable");
        try stream.write("property");
        try stream.write("keyword");
        try stream.write("number");
        try stream.write("string");
        try stream.write("comment");
        try stream.write("operator");
        try stream.endArray();
        try stream.objectField("tokenModifiers");
        try stream.beginArray();
        try stream.write("declaration"); // opcional, ya
        try stream.write("readonly"); // opcional
        try stream.endArray();
        try stream.endObject();

        // soporte
        try stream.objectField("full");
        try stream.write(true); // MVP: full, sin delta
        try stream.objectField("range");
        try stream.write(true); // si quieres implementar /range más tarde
        try stream.endObject();
        try stream.objectField("hoverProvider");
        try stream.write(true);
        try stream.objectField("definitionProvider");
        try stream.write(true);
        try stream.objectField("referencesProvider");
        try stream.write(true);
        try stream.objectField("prepareProvider");
        try stream.write(true);
        try stream.objectField("renameProvider");
        try stream.write(true);
        try stream.endObject();

        try stream.objectField("serverInfo");
        try stream.beginObject();
        try stream.objectField("name");
        try stream.write("argi");
        try stream.objectField("version");
        try stream.write("0.1.0");
        try stream.endObject();
        try stream.endObject();
        try stream.endObject();

        try self.sendMessage(writer, payload.writer.buffered());
    }

    fn respondNullResult(self: *LanguageServer, writer: anytype, id_value: json.Value) !void {
        var payload = std.Io.Writer.Allocating.init(self.allocator);
        defer payload.deinit();

        var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

        try stream.beginObject();
        try stream.objectField("jsonrpc");
        try stream.write("2.0");
        try stream.objectField("id");
        try stream.write(id_value);
        try stream.objectField("result");
        try stream.write(null);
        try stream.endObject();

        try self.sendMessage(writer, payload.writer.buffered());
    }

    fn sendPublishDiagnostics(
        self: *LanguageServer,
        writer: anytype,
        uri: []const u8,
        diagnostics: []const service.Diagnostic,
    ) !void {
        var payload = std.Io.Writer.Allocating.init(self.allocator);
        defer payload.deinit();

        var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

        try stream.beginObject();
        try stream.objectField("jsonrpc");
        try stream.write("2.0");
        try stream.objectField("method");
        try stream.write("textDocument/publishDiagnostics");
        try stream.objectField("params");
        try stream.beginObject();
        try stream.objectField("uri");
        try stream.write(uri);
        try stream.objectField("diagnostics");
        try stream.beginArray();
        for (diagnostics) |diag_item| {
            try stream.beginObject();
            try stream.objectField("range");
            try stream.beginObject();
            try stream.objectField("start");
            try stream.beginObject();
            try stream.objectField("line");
            try stream.write(diag_item.range.start.line);
            try stream.objectField("character");
            try stream.write(diag_item.range.start.character);
            try stream.endObject();
            try stream.objectField("end");
            try stream.beginObject();
            try stream.objectField("line");
            try stream.write(diag_item.range.end.line);
            try stream.objectField("character");
            try stream.write(diag_item.range.end.character);
            try stream.endObject();
            try stream.endObject();
            try stream.objectField("severity");
            try stream.write(@intFromEnum(diag_item.severity));
            try stream.objectField("source");
            try stream.write("argi");
            try stream.objectField("message");
            try stream.write(diag_item.message);
            try stream.endObject();
        }
        try stream.endArray();
        try stream.endObject();
        try stream.endObject();

        try self.sendMessage(writer, payload.writer.buffered());
    }

    fn handleSemanticTokensFull(self: *LanguageServer, writer: anytype, id_value: json.Value, params_value: ?json.Value) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;
        const text_document_value = getField(&params.object, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const uri_value = getField(&text_document_value.object, "uri") orelse return;
        if (uri_value != .string) return;

        if (self.service) |*svc| {
            var data = try svc.semanticTokensFull(uri_value.string); // ArrayList(u32)
            defer data.deinit();

            var payload = std.Io.Writer.Allocating.init(self.allocator);
            defer payload.deinit();
            var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

            try stream.beginObject();
            try stream.objectField("jsonrpc");
            try stream.write("2.0");
            try stream.objectField("id");
            try stream.write(id_value);
            try stream.objectField("result");
            try stream.beginObject();
            try stream.objectField("data");
            try stream.beginArray();
            for (data.items) |word| try stream.write(word);
            try stream.endArray();
            try stream.endObject(); // result
            try stream.endObject(); // root

            try self.sendMessage(writer, payload.writer.buffered());
        }
    }

    fn handleSemanticTokensRange(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;

        const text_document_value = getField(&params.object, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const uri_value = getField(&text_document_value.object, "uri") orelse return;
        if (uri_value != .string) return;

        // La spec manda un "range" aquí; por ahora lo ignoramos (MVP),
        // pero lo parseamos para que no falle si viene.
        _ = getField(&params.object, "range");

        if (self.service) |*svc| {
            var data = try svc.semanticTokensFull(uri_value.string);
            defer data.deinit();

            var payload = std.Io.Writer.Allocating.init(self.allocator);
            defer payload.deinit();
            var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

            try stream.beginObject();
            try stream.objectField("jsonrpc");
            try stream.write("2.0");
            try stream.objectField("id");
            try stream.write(id_value);
            try stream.objectField("result");
            try stream.beginObject();
            try stream.objectField("data");
            try stream.beginArray();
            for (data.items) |word| try stream.write(word);
            try stream.endArray();
            try stream.endObject(); // result
            try stream.endObject(); // root

            try self.sendMessage(writer, payload.writer.buffered());
        }
    }

    fn handleHover(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;

        const text_document_value = getField(&params.object, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const uri_value = getField(&text_document_value.object, "uri") orelse return;
        if (uri_value != .string) return;

        const position_value = getField(&params.object, "position") orelse return;
        const position = parsePosition(position_value) orelse return;

        if (self.service) |*svc| {
            const hover_opt = try svc.hover(uri_value.string, position);
            defer if (hover_opt) |hover| self.allocator.free(hover.contents);

            var payload = std.Io.Writer.Allocating.init(self.allocator);
            defer payload.deinit();
            var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

            try stream.beginObject();
            try stream.objectField("jsonrpc");
            try stream.write("2.0");
            try stream.objectField("id");
            try stream.write(id_value);
            try stream.objectField("result");
            if (hover_opt) |hover| {
                try stream.beginObject();
                try stream.objectField("contents");
                try stream.beginObject();
                try stream.objectField("kind");
                try stream.write("markdown");
                try stream.objectField("value");
                try stream.write(hover.contents);
                try stream.endObject();
                try stream.objectField("range");
                try stream.beginObject();
                try stream.objectField("start");
                try stream.beginObject();
                try stream.objectField("line");
                try stream.write(hover.range.start.line);
                try stream.objectField("character");
                try stream.write(hover.range.start.character);
                try stream.endObject();
                try stream.objectField("end");
                try stream.beginObject();
                try stream.objectField("line");
                try stream.write(hover.range.end.line);
                try stream.objectField("character");
                try stream.write(hover.range.end.character);
                try stream.endObject();
                try stream.endObject();
                try stream.endObject();
            } else {
                try stream.write(null);
            }
            try stream.endObject();

            try self.sendMessage(writer, payload.writer.buffered());
        }
    }

    fn handleDefinition(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;

        const text_document_value = getField(&params.object, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const uri_value = getField(&text_document_value.object, "uri") orelse return;
        if (uri_value != .string) return;

        const position_value = getField(&params.object, "position") orelse return;
        const position = parsePosition(position_value) orelse return;

        if (self.service) |*svc| {
            const definition_opt = try svc.definition(uri_value.string, position);
            defer if (definition_opt) |definition| definition.deinit(self.allocator);

            var payload = std.Io.Writer.Allocating.init(self.allocator);
            defer payload.deinit();
            var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

            try stream.beginObject();
            try stream.objectField("jsonrpc");
            try stream.write("2.0");
            try stream.objectField("id");
            try stream.write(id_value);
            try stream.objectField("result");
            if (definition_opt) |definition| {
                try stream.beginObject();
                try stream.objectField("uri");
                const target_uri = try pathToFileUri(self.allocator, definition.path);
                defer self.allocator.free(target_uri);
                try stream.write(target_uri);
                try stream.objectField("range");
                try writeRange(&stream, definition.range);
                try stream.endObject();
            } else {
                try stream.write(null);
            }
            try stream.endObject();

            try self.sendMessage(writer, payload.writer.buffered());
        }
    }

    fn handleReferences(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;

        const text_document_value = getField(&params.object, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const uri_value = getField(&text_document_value.object, "uri") orelse return;
        if (uri_value != .string) return;

        const position_value = getField(&params.object, "position") orelse return;
        const position = parsePosition(position_value) orelse return;

        var include_declaration = true;
        if (getField(&params.object, "context")) |context_value| {
            if (context_value == .object) {
                if (getField(&context_value.object, "includeDeclaration")) |inc_value| {
                    if (inc_value == .bool) include_declaration = inc_value.bool;
                }
            }
        }

        if (self.service) |*svc| {
            var refs = try svc.references(uri_value.string, position, include_declaration);
            defer refs.deinit();

            var payload = std.Io.Writer.Allocating.init(self.allocator);
            defer payload.deinit();
            var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

            try stream.beginObject();
            try stream.objectField("jsonrpc");
            try stream.write("2.0");
            try stream.objectField("id");
            try stream.write(id_value);
            try stream.objectField("result");
            try stream.beginArray();
            for (refs.items) |ref| {
                try writeLocation(&stream, self.allocator, ref);
            }
            try stream.endArray();
            try stream.endObject();

            try self.sendMessage(writer, payload.writer.buffered());
        }
    }

    fn handleRename(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;

        const text_document_value = getField(&params.object, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const uri_value = getField(&text_document_value.object, "uri") orelse return;
        if (uri_value != .string) return;

        const position_value = getField(&params.object, "position") orelse return;
        const position = parsePosition(position_value) orelse return;
        const new_name_value = getField(&params.object, "newName") orelse return;
        if (new_name_value != .string) return;

        if (self.service) |*svc| {
            var edits = try svc.rename(uri_value.string, position, new_name_value.string);
            defer edits.deinit();

            var payload = std.Io.Writer.Allocating.init(self.allocator);
            defer payload.deinit();
            var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

            try stream.beginObject();
            try stream.objectField("jsonrpc");
            try stream.write("2.0");
            try stream.objectField("id");
            try stream.write(id_value);
            try stream.objectField("result");
            try writeWorkspaceEdit(&stream, self.allocator, edits.items);
            try stream.endObject();

            try self.sendMessage(writer, payload.writer.buffered());
        }
    }

    fn handlePrepareRename(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) return;
        const params = params_value orelse return;
        if (params != .object) return;

        const text_document_value = getField(&params.object, "textDocument") orelse return;
        if (text_document_value != .object) return;
        const uri_value = getField(&text_document_value.object, "uri") orelse return;
        if (uri_value != .string) return;

        const position_value = getField(&params.object, "position") orelse return;
        const position = parsePosition(position_value) orelse return;

        if (self.service) |*svc| {
            const prep_opt = try svc.prepareRename(uri_value.string, position);
            defer if (prep_opt) |prep| prep.deinit(self.allocator);

            var payload = std.Io.Writer.Allocating.init(self.allocator);
            defer payload.deinit();
            var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

            try stream.beginObject();
            try stream.objectField("jsonrpc");
            try stream.write("2.0");
            try stream.objectField("id");
            try stream.write(id_value);
            try stream.objectField("result");
            if (prep_opt) |prep| {
                try stream.beginObject();
                try stream.objectField("range");
                try writeRange(&stream, prep.range);
                try stream.objectField("placeholder");
                try stream.write(prep.placeholder);
                try stream.endObject();
            } else {
                try stream.write(null);
            }
            try stream.endObject();

            try self.sendMessage(writer, payload.writer.buffered());
        }
    }

    fn sendMessage(self: *LanguageServer, writer: anytype, payload: []const u8) !void {
        _ = self;
        try writer.print("Content-Length: {d}\r\n\r\n", .{payload.len});
        try writer.writeAll(payload);
    }

    fn uriToPath(self: *LanguageServer, uri: []const u8) (AllocError || UriError)![]u8 {
        const decoded = try service.decodeFileUri(self.allocator, uri);
        if (decoded) |path| {
            if (path.len == 0) {
                self.allocator.free(path);
                return UriError.UnsupportedUri;
            }
            return path;
        }
        return UriError.UnsupportedUri;
    }
};

fn getField(map: *const json.ObjectMap, key: []const u8) ?json.Value {
    return map.*.get(key);
}

fn parseRange(value: json.Value) ?service.Range {
    if (value != .object) return null;
    const start_value = getField(&value.object, "start") orelse return null;
    const end_value = getField(&value.object, "end") orelse return null;
    const start_pos = parsePosition(start_value) orelse return null;
    const end_pos = parsePosition(end_value) orelse return null;
    return .{ .start = start_pos, .end = end_pos };
}

fn writeRange(stream: *json.Stringify, range: service.Range) !void {
    try stream.beginObject();
    try stream.objectField("start");
    try stream.beginObject();
    try stream.objectField("line");
    try stream.write(range.start.line);
    try stream.objectField("character");
    try stream.write(range.start.character);
    try stream.endObject();
    try stream.objectField("end");
    try stream.beginObject();
    try stream.objectField("line");
    try stream.write(range.end.line);
    try stream.objectField("character");
    try stream.write(range.end.character);
    try stream.endObject();
    try stream.endObject();
}

fn writeLocation(stream: *json.Stringify, allocator: std.mem.Allocator, loc: service.Location) !void {
    try stream.beginObject();
    try stream.objectField("uri");
    const target_uri = try pathToFileUri(allocator, loc.path);
    defer allocator.free(target_uri);
    try stream.write(target_uri);
    try stream.objectField("range");
    try writeRange(stream, loc.range);
    try stream.endObject();
}

fn writeWorkspaceEdit(stream: *json.Stringify, allocator: std.mem.Allocator, edits: []const service.TextEdit) !void {
    try stream.beginObject();
    try stream.objectField("changes");
    try stream.beginObject();

    var seen = std.array_list.Managed([]const u8).init(allocator);
    defer seen.deinit();

    for (edits) |edit| {
        var already_written = false;
        for (seen.items) |seen_path| {
            if (std.mem.eql(u8, seen_path, edit.path)) {
                already_written = true;
                break;
            }
        }
        if (already_written) continue;

        try seen.append(edit.path);
        const uri = try pathToFileUri(allocator, edit.path);
        defer allocator.free(uri);
        try stream.objectField(uri);
        try stream.beginArray();
        for (edits) |candidate| {
            if (!std.mem.eql(u8, candidate.path, edit.path)) continue;
            try stream.beginObject();
            try stream.objectField("range");
            try writeRange(stream, candidate.range);
            try stream.objectField("newText");
            try stream.write(candidate.new_text);
            try stream.endObject();
        }
        try stream.endArray();
    }

    try stream.endObject();
    try stream.endObject();
}

fn payloadFromLspMessage(message: []const u8) ![]const u8 {
    const sep = std.mem.indexOf(u8, message, "\r\n\r\n") orelse return error.InvalidLspMessage;
    return message[sep + 4 ..];
}

test "initialize response advertises hover definition references and rename" {
    var server = LanguageServer.init(std.testing.allocator);
    defer server.deinit();

    var parsed = try json.parseFromSlice(
        json.Value,
        std.testing.allocator,
        \\{
        \\  "rootUri": "file:///tmp/argi"
        \\}
    ,
        .{},
    );
    defer parsed.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try server.handleInitialize(&out.writer, .{ .integer = 1 }, parsed.value);

    const payload = try payloadFromLspMessage(out.writer.buffered());
    var response = try json.parseFromSlice(json.Value, std.testing.allocator, payload, .{});
    defer response.deinit();

    try std.testing.expect(response.value == .object);
    const root = response.value.object;
    try std.testing.expectEqualStrings("2.0", root.get("jsonrpc").?.string);
    try std.testing.expect(root.get("result").? == .object);

    const capabilities = root.get("result").?.object.get("capabilities").?.object;
    try std.testing.expect(capabilities.get("hoverProvider").?.bool);
    try std.testing.expect(capabilities.get("definitionProvider").?.bool);
    try std.testing.expect(capabilities.get("referencesProvider").?.bool);
    try std.testing.expect(capabilities.get("renameProvider").?.bool);
}

test "didOpen publishes diagnostics and hover responds with payload" {
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

    try tmp.dir.writeFile(.{ .sub_path = rel_path, .data = code });
    const abs_path = try tmp.dir.realpathAlloc(std.testing.allocator, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);

    var server = LanguageServer.init(std.testing.allocator);
    defer server.deinit();

    var init_params = try json.parseFromSlice(
        json.Value,
        std.testing.allocator,
        \\{}
    ,
        .{},
    );
    defer init_params.deinit();

    var init_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer init_out.deinit();
    try server.handleInitialize(&init_out.writer, .{ .integer = 1 }, init_params.value);

    const open_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{
        \\    "uri": "{s}",
        \\    "version": 1,
        \\    "text": "main() -> (.status_code: Int32 = 0) := {{\n    value :: Int32 = 1\n    copy := value\n}}\n"
        \\  }}
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(open_json);

    var open_params = try json.parseFromSlice(json.Value, std.testing.allocator, open_json, .{});
    defer open_params.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try server.handleDidOpen(&out.writer, open_params.value);

    const open_payload = try payloadFromLspMessage(out.writer.buffered());
    var publish = try json.parseFromSlice(json.Value, std.testing.allocator, open_payload, .{});
    defer publish.deinit();
    try std.testing.expectEqualStrings("textDocument/publishDiagnostics", publish.value.object.get("method").?.string);

    const hover_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{ "uri": "{s}" }},
        \\  "position": {{ "line": 2, "character": 13 }}
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(hover_json);

    var hover_params = try json.parseFromSlice(json.Value, std.testing.allocator, hover_json, .{});
    defer hover_params.deinit();

    var hover_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer hover_out.deinit();
    try server.handleHover(&hover_out.writer, .{ .integer = 2 }, hover_params.value);

    const hover_payload = try payloadFromLspMessage(hover_out.writer.buffered());
    var hover_response = try json.parseFromSlice(json.Value, std.testing.allocator, hover_payload, .{});
    defer hover_response.deinit();
    try std.testing.expect(hover_response.value.object.get("result").? == .object);
    const contents = hover_response.value.object.get("result").?.object.get("contents").?.object.get("value").?.string;
    try std.testing.expect(std.mem.indexOf(u8, contents, "value") != null);
}

fn pathToFileUri(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "file://{s}", .{path});
}

fn parsePosition(value: json.Value) ?service.Position {
    if (value != .object) return null;
    const line_value = getField(&value.object, "line") orelse return null;
    const char_value = getField(&value.object, "character") orelse return null;
    if (line_value != .integer or char_value != .integer) return null;
    return .{
        .line = @intCast(line_value.integer),
        .character = @intCast(char_value.integer),
    };
}

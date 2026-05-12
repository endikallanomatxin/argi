const std = @import("std");
const json = std.json;
const log = std.log.scoped(.argi_lsp);

const service = @import("lsp_service.zig");
const argi_version = @import("version.zig");
const test_support = @import("../test_support.zig");

const AllocError = std.mem.Allocator.Error;

const ReadMessageError = error{
    MissingContentLength,
    InvalidContentLength,
};

const UriError = error{UnsupportedUri};

fn repoRootPrefix() ![]u8 {
    return std.fs.path.resolve(std.testing.allocator, &.{"."});
}

pub fn start(io: std.Io) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var server = LanguageServer.init(gpa.allocator(), io);
    defer server.deinit();

    try server.run(io);
}

const LanguageServer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    buffer: std.array_list.Managed(u8),
    service: ?service.LanguageService = null,
    shutdown_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) LanguageServer {
        return .{
            .allocator = allocator,
            .io = io,
            .buffer = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *LanguageServer) void {
        self.buffer.deinit();
        if (self.service) |*svc| svc.deinit();
    }

    fn respondInternalErrorOrLog(
        self: *LanguageServer,
        writer: anytype,
        id: json.Value,
        message: []const u8,
    ) void {
        self.respondInternalError(writer, id, message) catch |err| {
            log.err("failed to send internal error response '{s}': {s}", .{ message, @errorName(err) });
        };
    }

    pub fn run(self: *LanguageServer, io: std.Io) !void {
        var stdin_buffer: [4096]u8 = undefined;
        var stdout_buffer: [4096]u8 = undefined;
        var reader = std.Io.File.stdin().reader(io, &stdin_buffer);
        var writer = std.Io.File.stdout().writer(io, &stdout_buffer);

        while (true) {
            const payload = self.readMessage(&reader) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            if (payload.len == 0) continue;

            var parsed = json.parseFromSlice(json.Value, self.allocator, payload, .{}) catch |err| {
                log.warn("failed to parse JSON-RPC payload: {s}", .{@errorName(err)});
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
                    self.handleInitialize(&writer, id, params_value) catch |err| {
                        log.err("initialize failed: {s}", .{@errorName(err)});
                        self.respondInternalErrorOrLog(&writer, id, "initialize failed");
                    };
                }
            } else if (std.mem.eql(u8, method, "initialized")) {
                // No-op
            } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
                self.handleDidOpen(&writer, params_value) catch |err| {
                    log.err("didOpen failed: {s}", .{@errorName(err)});
                };
            } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
                self.handleDidChange(&writer, params_value) catch |err| {
                    log.err("didChange failed: {s}", .{@errorName(err)});
                };
            } else if (std.mem.eql(u8, method, "textDocument/didClose")) {
                self.handleDidClose(&writer, params_value) catch |err| {
                    log.err("didClose failed: {s}", .{@errorName(err)});
                };
            } else if (std.mem.eql(u8, method, "shutdown")) {
                if (id_value) |id| self.handleShutdown(&writer, id) catch |err| {
                    log.err("shutdown failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "shutdown failed");
                };
            } else if (std.mem.eql(u8, method, "exit")) {
                break;
            } else if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
                if (id_value) |id| self.handleSemanticTokensFull(&writer, id, params_value) catch |err| {
                    log.err("semanticTokens/full failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "semantic tokens failed");
                };
            } else if (std.mem.eql(u8, method, "textDocument/semanticTokens/range")) {
                if (id_value) |id| self.handleSemanticTokensRange(&writer, id, params_value) catch |err| {
                    log.err("semanticTokens/range failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "semantic tokens failed");
                };
            } else if (std.mem.eql(u8, method, "textDocument/hover")) {
                if (id_value) |id| self.handleHover(&writer, id, params_value) catch |err| {
                    log.err("hover failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "hover failed");
                };
            } else if (std.mem.eql(u8, method, "textDocument/definition")) {
                if (id_value) |id| self.handleDefinition(&writer, id, params_value) catch |err| {
                    log.err("definition failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "definition failed");
                };
            } else if (std.mem.eql(u8, method, "textDocument/references")) {
                if (id_value) |id| self.handleReferences(&writer, id, params_value) catch |err| {
                    log.err("references failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "references failed");
                };
            } else if (std.mem.eql(u8, method, "textDocument/prepareRename")) {
                if (id_value) |id| self.handlePrepareRename(&writer, id, params_value) catch |err| {
                    log.err("prepareRename failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "prepare rename failed");
                };
            } else if (std.mem.eql(u8, method, "textDocument/rename")) {
                if (id_value) |id| self.handleRename(&writer, id, params_value) catch |err| {
                    log.err("rename failed: {s}", .{@errorName(err)});
                    self.respondInternalErrorOrLog(&writer, id, "rename failed");
                };
            } else {
                // Método desconocido -> ignorar
            }
        }
    }

    fn readMessage(
        self: *LanguageServer,
        reader: anytype,
    ) (ReadMessageError || error{EndOfStream} || std.Io.Reader.DelimiterError || std.Io.Reader.Error || AllocError)![]const u8 {
        var content_length: ?usize = null;

        while (true) {
            const line_raw = (reader.interface.takeDelimiter('\n') catch |err| switch (err) {
                else => return err,
            }) orelse return error.EndOfStream;
            const line_trimmed = std.mem.trim(u8, line_raw, "\r\n");
            if (line_trimmed.len == 0) break;

            if (std.mem.startsWith(u8, line_trimmed, "Content-Length:")) {
                const value_slice = std.mem.trim(u8, line_trimmed["Content-Length:".len..], " ");
                content_length = std.fmt.parseInt(usize, value_slice, 10) catch return ReadMessageError.InvalidContentLength;
            }
        }

        const len = content_length orelse return ReadMessageError.MissingContentLength;
        try self.buffer.resize(len);
        try reader.interface.readSliceAll(self.buffer.items[0..len]);
        return self.buffer.items[0..len];
    }

    fn handleInitialize(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        params_value: ?json.Value,
    ) !void {
        if (self.service == null) {
            self.service = service.LanguageService.init(self.allocator, self.io);
        }

        if (params_value) |params| {
            if (params == .object) {
                if (getField(&params.object, "rootUri")) |uri_value| {
                    if (uri_value == .string) {
                        if (self.service) |*svc| {
                            svc.initialize(uri_value.string) catch |err| {
                                log.err("service initialize failed for root '{s}': {s}", .{ uri_value.string, @errorName(err) });
                            };
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

        const path = self.uriToPath(uri_value.string) catch |err| {
            log.err("didOpen uriToPath failed: {s}", .{@errorName(err)});
            return;
        };
        defer self.allocator.free(path);

        if (self.service) |*svc| {
            var diagnostics = svc.openDocument(uri_value.string, path, version, text_value.string) catch |err| {
                log.err("openDocument failed for '{s}' ({s}): {s}", .{ uri_value.string, path, @errorName(err) });
                return;
            };
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

        const path = self.uriToPath(uri_value.string) catch |err| {
            log.err("didChange uriToPath failed: {s}", .{@errorName(err)});
            return;
        };
        defer self.allocator.free(path);

        if (self.service) |*svc| {
            var diagnostics = svc.changeDocument(uri_value.string, path, version, text_value.string) catch |err| {
                log.err("changeDocument failed for '{s}' ({s}): {s}", .{ uri_value.string, path, @errorName(err) });
                return;
            };
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
        try stream.write(false);
        try stream.endObject();
        try stream.objectField("hoverProvider");
        try stream.write(true);
        try stream.objectField("definitionProvider");
        try stream.write(true);
        try stream.objectField("referencesProvider");
        try stream.write(true);
        try stream.objectField("renameProvider");
        try stream.beginObject();
        try stream.objectField("prepareProvider");
        try stream.write(true);
        try stream.endObject();
        try stream.endObject();

        try stream.objectField("serverInfo");
        try stream.beginObject();
        try stream.objectField("name");
        try stream.write("argi");
        try stream.objectField("version");
        try stream.write(argi_version.current);
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

    fn respondInternalError(
        self: *LanguageServer,
        writer: anytype,
        id_value: json.Value,
        message: []const u8,
    ) !void {
        var payload = std.Io.Writer.Allocating.init(self.allocator);
        defer payload.deinit();

        var stream: json.Stringify = .{ .writer = &payload.writer, .options = .{} };

        try stream.beginObject();
        try stream.objectField("jsonrpc");
        try stream.write("2.0");
        try stream.objectField("id");
        try stream.write(id_value);
        try stream.objectField("error");
        try stream.beginObject();
        try stream.objectField("code");
        try stream.write(@as(i32, -32603));
        try stream.objectField("message");
        try stream.write(message);
        try stream.endObject();
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
        try writer.interface.print("Content-Length: {d}\r\n\r\n", .{payload.len});
        try writer.interface.writeAll(payload);
        try writer.interface.flush();
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

test "readMessage consumes LSP header delimiters between messages" {
    var server = LanguageServer.init(std.testing.allocator, std.testing.io);
    defer server.deinit();

    const input = std.Io.Reader.fixed(
        "Content-Length: 2\r\n\r\n{}" ++
            "Content-Length: 2\r\n\r\n[]",
    );
    var reader = struct {
        interface: std.Io.Reader,
    }{ .interface = input };

    const first = try server.readMessage(&reader);
    try std.testing.expectEqualStrings("{}", first);

    const second = try server.readMessage(&reader);
    try std.testing.expectEqualStrings("[]", second);
}

const CapturedResponseWriter = struct {
    allocator: std.mem.Allocator,
    buffer: std.array_list.Managed(u8),
    flushed: bool = false,
    writer: Writer = undefined,

    fn init(self: *CapturedResponseWriter, allocator: std.mem.Allocator) void {
        self.* = .{
            .allocator = allocator,
            .buffer = std.array_list.Managed(u8).init(allocator),
        };
        self.writer = .{ .parent = self };
        self.writer.interface = .{ .parent = &self.writer };
    }

    fn deinit(self: *CapturedResponseWriter) void {
        self.buffer.deinit();
    }

    fn buffered(self: *CapturedResponseWriter) []const u8 {
        return self.buffer.items;
    }

    const Writer = struct {
        parent: *CapturedResponseWriter,
        interface: Interface = undefined,

        fn buffered(self: *Writer) []const u8 {
            return self.parent.buffer.items;
        }

        const Interface = struct {
            parent: *Writer,

            fn print(self: *Interface, comptime fmt: []const u8, args: anytype) !void {
                const parent = self.parent.parent;
                const text = try std.fmt.allocPrint(parent.allocator, fmt, args);
                defer parent.allocator.free(text);
                try parent.buffer.appendSlice(text);
            }

            fn writeAll(self: *Interface, bytes: []const u8) !void {
                try self.parent.parent.buffer.appendSlice(bytes);
            }

            fn flush(self: *Interface) !void {
                self.parent.parent.flushed = true;
            }
        };
    };
};

test "initialize response is framed and flushed" {
    var server = LanguageServer.init(std.testing.allocator, std.testing.io);
    defer server.deinit();

    var parsed = try json.parseFromSlice(json.Value, std.testing.allocator, "{}", .{});
    defer parsed.deinit();

    var out: CapturedResponseWriter = undefined;
    out.init(std.testing.allocator);
    defer out.deinit();

    try server.handleInitialize(&out.writer, .{ .integer = 1 }, parsed.value);

    try std.testing.expect(out.flushed);

    const payload = try payloadFromLspMessage(out.writer.buffered());
    var response = try json.parseFromSlice(json.Value, std.testing.allocator, payload, .{});
    defer response.deinit();

    try std.testing.expectEqualStrings("2.0", response.value.object.get("jsonrpc").?.string);
    try std.testing.expectEqual(@as(i64, 1), response.value.object.get("id").?.integer);
    try std.testing.expect(response.value.object.get("result").? == .object);
    const capabilities = response.value.object.get("result").?.object.get("capabilities").?.object;
    try std.testing.expect(capabilities.get("hoverProvider").?.bool);
    try std.testing.expect(capabilities.get("definitionProvider").?.bool);
}

test "initialize response advertises hover definition references and rename" {
    var server = LanguageServer.init(std.testing.allocator, std.testing.io);
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

    var out: CapturedResponseWriter = undefined;
    out.init(std.testing.allocator);
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
    try std.testing.expect(capabilities.get("prepareProvider") == null);

    const semantic_tokens = capabilities.get("semanticTokensProvider").?.object;
    try std.testing.expect(semantic_tokens.get("full").?.bool);
    try std.testing.expect(!semantic_tokens.get("range").?.bool);

    const rename_provider = capabilities.get("renameProvider").?.object;
    try std.testing.expect(rename_provider.get("prepareProvider").?.bool);
}

test "didOpen publishes diagnostics" {
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
    const abs_path = try test_support.tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);
    const root_path = try repoRootPrefix();
    defer std.testing.allocator.free(root_path);
    const root_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{root_path});
    defer std.testing.allocator.free(root_uri);

    var server = LanguageServer.init(std.testing.allocator, std.testing.io);
    defer server.deinit();

    const init_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{ "rootUri": "{s}" }}
    ,
        .{root_uri},
    );
    defer std.testing.allocator.free(init_json);

    var init_params = try json.parseFromSlice(json.Value, std.testing.allocator, init_json, .{});
    defer init_params.deinit();

    var init_out: CapturedResponseWriter = undefined;
    init_out.init(std.testing.allocator);
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

    var out: CapturedResponseWriter = undefined;
    out.init(std.testing.allocator);
    defer out.deinit();
    try server.handleDidOpen(&out.writer, open_params.value);

    const open_payload = try payloadFromLspMessage(out.writer.buffered());
    var publish = try json.parseFromSlice(json.Value, std.testing.allocator, open_payload, .{});
    defer publish.deinit();
    try std.testing.expectEqualStrings("textDocument/publishDiagnostics", publish.value.object.get("method").?.string);
}

test "didChange publishes diagnostics and ignores stale versions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const fixed_code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\}
        \\
    ;
    const broken_code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 =
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = fixed_code });
    const abs_path = try test_support.tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);
    const root_path = try repoRootPrefix();
    defer std.testing.allocator.free(root_path);
    const root_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{root_path});
    defer std.testing.allocator.free(root_uri);

    var server = LanguageServer.init(std.testing.allocator, std.testing.io);
    defer server.deinit();

    const init_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{ "rootUri": "{s}" }}
    ,
        .{root_uri},
    );
    defer std.testing.allocator.free(init_json);

    var init_params = try json.parseFromSlice(json.Value, std.testing.allocator, init_json, .{});
    defer init_params.deinit();
    var init_out: CapturedResponseWriter = undefined;
    init_out.init(std.testing.allocator);
    defer init_out.deinit();
    try server.handleInitialize(&init_out.writer, .{ .integer = 1 }, init_params.value);

    const open_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{
        \\    "uri": "{s}",
        \\    "version": 2,
        \\    "text": "main() -> (.status_code: Int32 = 0) := {{\n    value :: Int32 = 1\n}}\n"
        \\  }}
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(open_json);

    var open_params = try json.parseFromSlice(json.Value, std.testing.allocator, open_json, .{});
    defer open_params.deinit();
    var open_out: CapturedResponseWriter = undefined;
    open_out.init(std.testing.allocator);
    defer open_out.deinit();
    try server.handleDidOpen(&open_out.writer, open_params.value);

    const change_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{
        \\    "uri": "{s}",
        \\    "version": 3
        \\  }},
        \\  "contentChanges": [{{
        \\    "text": "main() -> (.status_code: Int32 = 0) := {{\n    value :: Int32 =\n}}\n"
        \\  }}]
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(change_json);

    var change_params = try json.parseFromSlice(json.Value, std.testing.allocator, change_json, .{});
    defer change_params.deinit();
    var change_out: CapturedResponseWriter = undefined;
    change_out.init(std.testing.allocator);
    defer change_out.deinit();
    try server.handleDidChange(&change_out.writer, change_params.value);

    const change_payload = try payloadFromLspMessage(change_out.writer.buffered());
    var change_response = try json.parseFromSlice(json.Value, std.testing.allocator, change_payload, .{});
    defer change_response.deinit();
    const change_diags = change_response.value.object.get("params").?.object.get("diagnostics").?.array.items;
    try std.testing.expect(change_diags.len > 0);

    const broken_code_json = try std.fmt.allocPrint(
        std.testing.allocator,
        "{f}",
        .{std.json.fmt(broken_code, .{})},
    );
    defer std.testing.allocator.free(broken_code_json);

    const stale_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{
        \\    "uri": "{s}",
        \\    "version": 2
        \\  }},
        \\  "contentChanges": [{{
        \\    "text": {s}
        \\  }}]
        \\}}
    ,
        .{ uri, broken_code_json },
    );
    defer std.testing.allocator.free(stale_json);

    var stale_params = try json.parseFromSlice(json.Value, std.testing.allocator, stale_json, .{});
    defer stale_params.deinit();
    var stale_out: CapturedResponseWriter = undefined;
    stale_out.init(std.testing.allocator);
    defer stale_out.deinit();
    try server.handleDidChange(&stale_out.writer, stale_params.value);

    const stale_payload = try payloadFromLspMessage(stale_out.writer.buffered());
    var stale_response = try json.parseFromSlice(json.Value, std.testing.allocator, stale_payload, .{});
    defer stale_response.deinit();
    const stale_diags = stale_response.value.object.get("params").?.object.get("diagnostics").?.array.items;
    try std.testing.expect(stale_diags.len > 0);
}

test "didClose publishes empty diagnostics" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try test_support.tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);
    const root_path = try repoRootPrefix();
    defer std.testing.allocator.free(root_path);
    const root_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{root_path});
    defer std.testing.allocator.free(root_uri);

    var server = LanguageServer.init(std.testing.allocator, std.testing.io);
    defer server.deinit();

    const init_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{ "rootUri": "{s}" }}
    ,
        .{root_uri},
    );
    defer std.testing.allocator.free(init_json);

    var init_params = try json.parseFromSlice(json.Value, std.testing.allocator, init_json, .{});
    defer init_params.deinit();
    var init_out: CapturedResponseWriter = undefined;
    init_out.init(std.testing.allocator);
    defer init_out.deinit();
    try server.handleInitialize(&init_out.writer, .{ .integer = 1 }, init_params.value);

    const open_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{
        \\    "uri": "{s}",
        \\    "version": 1,
        \\    "text": "main() -> (.status_code: Int32 = 0) := {{\n    value :: Int32 = 1\n}}\n"
        \\  }}
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(open_json);

    var open_params = try json.parseFromSlice(json.Value, std.testing.allocator, open_json, .{});
    defer open_params.deinit();
    var open_out: CapturedResponseWriter = undefined;
    open_out.init(std.testing.allocator);
    defer open_out.deinit();
    try server.handleDidOpen(&open_out.writer, open_params.value);

    const close_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{ "uri": "{s}" }}
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(close_json);

    var close_params = try json.parseFromSlice(json.Value, std.testing.allocator, close_json, .{});
    defer close_params.deinit();
    var close_out: CapturedResponseWriter = undefined;
    close_out.init(std.testing.allocator);
    defer close_out.deinit();
    try server.handleDidClose(&close_out.writer, close_params.value);

    const close_payload = try payloadFromLspMessage(close_out.writer.buffered());
    var close_response = try json.parseFromSlice(json.Value, std.testing.allocator, close_payload, .{});
    defer close_response.deinit();
    const close_diags = close_response.value.object.get("params").?.object.get("diagnostics").?.array.items;
    try std.testing.expectEqual(@as(usize, 0), close_diags.len);
}

test "definition responds with target location over protocol" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const rel_path = "main.rg";
    const code =
        \\helper() -> (.value: Int32) := {
        \\    value = 42
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = helper()
        \\}
        \\
    ;

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = rel_path, .data = code });
    const abs_path = try test_support.tmpFilePath(&tmp, rel_path);
    defer std.testing.allocator.free(abs_path);
    const uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{abs_path});
    defer std.testing.allocator.free(uri);
    const root_path = try repoRootPrefix();
    defer std.testing.allocator.free(root_path);
    const root_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{root_path});
    defer std.testing.allocator.free(root_uri);

    var server = LanguageServer.init(std.testing.allocator, std.testing.io);
    defer server.deinit();

    const init_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{ "rootUri": "{s}" }}
    ,
        .{root_uri},
    );
    defer std.testing.allocator.free(init_json);

    var init_params = try json.parseFromSlice(json.Value, std.testing.allocator, init_json, .{});
    defer init_params.deinit();
    var init_out: CapturedResponseWriter = undefined;
    init_out.init(std.testing.allocator);
    defer init_out.deinit();
    try server.handleInitialize(&init_out.writer, .{ .integer = 1 }, init_params.value);

    const open_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{
        \\    "uri": "{s}",
        \\    "version": 1,
        \\    "text": "helper() -> (.value: Int32) := {{\n    value = 42\n}}\n\nmain() -> (.status_code: Int32 = 0) := {{\n    status_code = helper()\n}}\n"
        \\  }}
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(open_json);

    var open_params = try json.parseFromSlice(json.Value, std.testing.allocator, open_json, .{});
    defer open_params.deinit();
    var open_out: CapturedResponseWriter = undefined;
    open_out.init(std.testing.allocator);
    defer open_out.deinit();
    try server.handleDidOpen(&open_out.writer, open_params.value);

    const definition_json = try std.fmt.allocPrint(
        std.testing.allocator,
        \\{{
        \\  "textDocument": {{ "uri": "{s}" }},
        \\  "position": {{ "line": 5, "character": 21 }}
        \\}}
    ,
        .{uri},
    );
    defer std.testing.allocator.free(definition_json);

    var definition_params = try json.parseFromSlice(json.Value, std.testing.allocator, definition_json, .{});
    defer definition_params.deinit();
    var definition_out: CapturedResponseWriter = undefined;
    definition_out.init(std.testing.allocator);
    defer definition_out.deinit();
    try server.handleDefinition(&definition_out.writer, .{ .integer = 2 }, definition_params.value);

    const definition_payload = try payloadFromLspMessage(definition_out.writer.buffered());
    var definition_response = try json.parseFromSlice(json.Value, std.testing.allocator, definition_payload, .{});
    defer definition_response.deinit();
    const result = definition_response.value.object.get("result").?.object;
    const target_uri = result.get("uri").?.string;
    try std.testing.expect(std.mem.startsWith(u8, target_uri, "file://"));
    try std.testing.expect(std.mem.endsWith(u8, target_uri, abs_path));
    try std.testing.expectEqual(@as(i64, 0), result.get("range").?.object.get("start").?.object.get("line").?.integer);
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

const std = @import("std");
const json = std.json;

const service = @import("../lsp_service.zig");

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
    buffer: std.ArrayList(u8),
    service: ?service.LanguageService = null,
    shutdown_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator) LanguageServer {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *LanguageServer) void {
        self.buffer.deinit();
        if (self.service) |*svc| svc.deinit();
    }

    pub fn run(self: *LanguageServer) !void {
        var reader = std.io.getStdIn().reader();
        var writer = std.io.getStdOut().writer();

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
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        var stream = json.writeStream(payload.writer(), .{});
        defer stream.deinit();

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

        try self.sendMessage(writer, payload.items);
    }

    fn respondNullResult(self: *LanguageServer, writer: anytype, id_value: json.Value) !void {
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        var stream = json.writeStream(payload.writer(), .{});
        defer stream.deinit();

        try stream.beginObject();
        try stream.objectField("jsonrpc");
        try stream.write("2.0");
        try stream.objectField("id");
        try stream.write(id_value);
        try stream.objectField("result");
        try stream.write(null);
        try stream.endObject();

        try self.sendMessage(writer, payload.items);
    }

    fn sendPublishDiagnostics(
        self: *LanguageServer,
        writer: anytype,
        uri: []const u8,
        diagnostics: []const service.Diagnostic,
    ) !void {
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        var stream = json.writeStream(payload.writer(), .{});
        defer stream.deinit();

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

        try self.sendMessage(writer, payload.items);
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

            var payload = std.ArrayList(u8).init(self.allocator);
            defer payload.deinit();
            var stream = json.writeStream(payload.writer(), .{});
            defer stream.deinit();

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

            try self.sendMessage(writer, payload.items);
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

            var payload = std.ArrayList(u8).init(self.allocator);
            defer payload.deinit();
            var stream = json.writeStream(payload.writer(), .{});
            defer stream.deinit();

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

            try self.sendMessage(writer, payload.items);
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

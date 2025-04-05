const std = @import("std");
const json = std.json;
const allocator: *std.mem.Allocator = std.heap.page_allocator;

const LSPError = error{
    InvalidJson,
};

pub fn start() !void {
    const stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var bufferedReader = std.io.bufferedReader(stdin);

    while (true) {
        // Leemos un mensaje LSP completo (cabecera + payload)
        const msg = try readLSPMessage(&bufferedReader);
        std.debug.print("Recibido: {s}\n", .{msg});

        // Parseamos el mensaje JSON
        var parser = json.Parser.init(msg);
        const root = try parser.parseValue();

        // Extraemos el campo "method"
        const method = try getMethod(root);
        std.debug.print("Método: {s}\n", .{method});

        if (std.mem.eql(u8, method, "initialize")) {
            try writeResponse(&stdout, initializeResponse());
        } else if (std.mem.eql(u8, method, "textDocument/didOpen") or
            std.mem.eql(u8, method, "textDocument/didChange"))
        {
            // Extraemos el texto del documento; en una implementación real,
            // se accedería a params.textDocument.text
            const text = try getTextFromParams(root);
            std.debug.print("Texto del documento:\n{text}\n", .{text});

            // Aquí se podría invocar al lexer y parser existentes para generar
            // diagnósticos. En este ejemplo, simulamos que no se encontraron errores.
            const diagnostics = processText(text);
            try writeResponse(&stdout, diagnosticsResponse(diagnostics));
        } else if (std.mem.eql(u8, method, "shutdown")) {
            break;
        } else {
            // Métodos no implementados se ignoran en este prototipo.
            std.debug.print("Método no manejado: {s}\n", .{method});
        }
    }
}

/// Lee el mensaje LSP desde el BufferedReader.
/// Se asume el formato:
///   Content-Length: <n>\r\n
///   \r\n
///   <payload JSON de n bytes>
fn readLSPMessage(reader: *std.io.BufferedReader(1024, std.io.Reader(File, ReadError, read))) ![]const u8 {
    var contentLength: usize = 0;
    // Leemos las cabeceras hasta una línea en blanco.
    while (true) {
        var headerLine = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n');
        if (headerLine.len == 0 or std.mem.eql(u8, headerLine, "\r\n")) break;
        if (std.mem.startsWith(headerLine, "Content-Length: ")) {
            const lenStr = std.mem.trim(u8, headerLine[16..], " \r\n");
            contentLength = try std.fmt.parseInt(usize, lenStr, 10);
        }
    }
    // Leemos el payload de la longitud indicada.
    const buffer = try allocator.alloc(u8, contentLength);
    try reader.readExact(buffer);
    return buffer;
}

/// Extrae el campo "method" del objeto JSON raíz.
fn getMethod(value: anytype) ![]const u8 {
    const obj = value.Object orelse return LSPError.InvalidJson;
    const methodVal = obj.get("method") orelse return LSPError.InvalidJson;
    return methodVal.String orelse return LSPError.InvalidJson;
}

/// Extrae el texto del documento del mensaje LSP.
/// Se espera que el JSON tenga la siguiente estructura:
/// {
///   "params": {
///      "textDocument": {
///         "text": "<código fuente>"
///      }
///   }
/// }
fn getTextFromParams(value: anytype) ![]const u8 {
    const obj = value.Object orelse return LSPError.InvalidJson;
    const paramsVal = obj.get("params") orelse return LSPError.InvalidJson;
    const paramsObj = paramsVal.Object orelse return LSPError.InvalidJson;
    const tdVal = paramsObj.get("textDocument") orelse return LSPError.InvalidJson;
    const tdObj = tdVal.Object orelse return LSPError.InvalidJson;
    const textVal = tdObj.get("text") orelse return LSPError.InvalidJson;
    return textVal.String orelse return LSPError.InvalidJson;
}

/// Retorna una respuesta de inicialización en formato JSON.
fn initializeResponse() []const u8 {
    return 
    \\{
    \\  "jsonrpc": "2.0",
    \\  "id": 1,
    \\  "result": {
    \\    "capabilities": {
    \\      "textDocumentSync": 1,
    \\      "completionProvider": { "resolveProvider": false, "triggerCharacters": ["+"] }
    \\    }
    \\  }
    \\}
    ;
}

/// Crea un mensaje de diagnóstico, utilizando el contenido recibido (en este ejemplo, una cadena que representa
/// un array JSON de diagnósticos). En una implementación real, se generarían diagnósticos a partir de errores
/// detectados por el lexer/parser.
fn diagnosticsResponse(diagnostics: []const u8) []const u8 {
    return std.fmt.allocPrint(allocator,
        \\{
        \\  "jsonrpc": "2.0",
        \\  "method": "textDocument/publishDiagnostics",
        \\  "params": {
        \\    "uri": "file:///dummy.argi",
        \\    "diagnostics": %s
        \\  }
        \\}
    , .{diagnostics});
}

/// Procesa el texto fuente usando el lexer y parser ya existentes.
/// Aquí se simula que el análisis fue correcto y se devuelven diagnósticos vacíos.
fn processText(text: []const u8) []const u8 {
    _ = text;
    // Aquí podrías crear una instancia del lexer y luego del parser, invocar el análisis
    // y capturar errores para transformarlos en diagnósticos.
    // Por simplicidad, devolvemos un array vacío de diagnósticos.
    return "[]";
}

/// Escribe una respuesta LSP en stdout, incluyendo la cabecera "Content-Length".
fn writeResponse(stdout: *std.io.Writer, response: []const u8) !void {
    const header = try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n\r\n", .{response.len});
    try stdout.writeAll(header);
    try stdout.writeAll(response);
}

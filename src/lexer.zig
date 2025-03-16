const std = @import("std");

pub const Token = struct {
    kind: TokenKind,
    value: []const u8,
};

pub const TokenKind = enum {
    identifier,
    keyword_func,
    number,
    string,
    symbol, // para otros símbolos que no sean : o =
    colon, // token para ":"
    equal, // token para "="
    eof,
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);
    errdefer tokens.deinit();

    var i: usize = 0;
    var current_line: usize = 1;
    var current_column: usize = 1;

    while (i < source.len) {
        const c = source[i];

        if (c == '\r') {
            i += 1;
            continue;
        }

        if (c == '\n') {
            current_line += 1;
            current_column = 1;
            i += 1;
            continue;
        }

        if (std.ascii.isWhitespace(c)) {
            i += 1;
            continue;
        }

        if (std.ascii.isDigit(c)) {
            // Detectar números
            const start = i;
            while (i < source.len and std.ascii.isDigit(source[i])) {
                i += 1;
            }
            try tokens.append(Token{ .kind = .number, .value = source[start..i] });
            continue;
        }

        if (std.ascii.isAlphabetic(c) or c == '_') {
            // Detectar identificadores y palabras clave
            const start = i;
            while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                i += 1;
            }
            const word = source[start..i];

            // Comprobar si es una palabra clave (ej. `func`)
            if (std.mem.eql(u8, word, "func")) {
                try tokens.append(Token{ .kind = .keyword_func, .value = word });
            } else {
                try tokens.append(Token{ .kind = .identifier, .value = word });
            }
            continue;
        }

        // Ejemplo de fragmento de tokenización en el lexer:
        if (c == ':') {
            // Agrega el token colon.
            try tokens.append(Token{
                .kind = .colon,
                .value = source[i .. i + 1],
                .line = current_line,
                .column = current_column,
            });
            i += 1;
            continue;
        } else if (c == '=') {
            // Agrega el token equal.
            try tokens.append(Token{
                .kind = .equal,
                .value = source[i .. i + 1],
                .line = current_line,
                .column = current_column,
            });
            i += 1;
            continue;
        }

        // Detectar símbolos individuales (puedes expandirlo según necesites)
        switch (c) {
            '(', ')', '{', '}', '+', '-', '*', '/', '=' => {
                try tokens.append(Token{ .kind = .symbol, .value = source[i .. i + 1] });
                i += 1;
                continue;
            },
            else => {
                std.debug.print("Error: Caracter desconocido '{c}' en posición {}\n", .{ c, i });
                return error.UnrecognizedCharacter;
            },
        }
    }

    // Agregar token de fin de archivo
    try tokens.append(Token{ .kind = .eof, .value = "" });

    return tokens;
}

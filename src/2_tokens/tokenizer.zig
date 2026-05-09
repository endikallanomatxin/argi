const std = @import("std");
const tok = @import("token.zig");
const tok_print = @import("token_print.zig");
const diag = @import("../1_base/diagnostic.zig");
const sf = @import("../1_base/source_files.zig");

pub const TokenizerError = error{
    UnknownCharacter,
};

pub const Tokenizer = struct {
    allocator: *const std.mem.Allocator,
    diagnostics: *diag.Diagnostics,
    source: []const u8,
    tokens: std.array_list.Managed(tok.Token),

    location: tok.Location,

    pub fn init(
        allocator: *const std.mem.Allocator,
        diagnostics: *diag.Diagnostics,
        source: []const u8,
        file_name: []const u8,
    ) Tokenizer {
        return Tokenizer{
            .allocator = allocator,
            .diagnostics = diagnostics,
            .source = source,
            .tokens = std.array_list.Managed(tok.Token).init(allocator.*),
            .location = tok.Location{
                .file = file_name,
                .offset = 0,
                .line = 1,
                .column = 1,
            },
        };
    }

    /// Llama a `lexNextToken` repetidas veces hasta terminar, y devuelve
    /// el slice de `Token` generado.
    pub fn tokenize(self: *Tokenizer) ![]tok.Token {
        while (self.location.offset < self.source.len) {
            lexNextToken(self) catch |err| {
                if (err == error.ReachedEOF) {
                    break;
                } else {
                    return err;
                }
            };
        }
        // Añadir el token EOF al final
        try self.addToken(tok.Content{ .eof = .{} }, self.location);
        return self.tokens.items;
    }

    /// Añade un token a la lista de tokens, actualizando la ubicación actual.
    pub fn addToken(self: *Tokenizer, content: tok.Content, location: tok.Location) !void {
        const token = tok.Token{
            .content = content,
            .location = location,
        };
        try self.tokens.append(token);
    }

    pub fn peek(self: *Tokenizer) ?u8 {
        if (self.location.offset >= self.source.len) return null;
        return self.source[self.location.offset];
    }

    pub fn peekNext(self: *Tokenizer) ?u8 {
        if (self.location.offset + 1 >= self.source.len) return null;
        return self.source[self.location.offset + 1];
    }

    pub fn advance(self: *Tokenizer) bool {
        const c = self.peek() orelse return false;
        self.location.offset += 1;
        if (c == '\n') {
            self.location.line += 1;
            self.location.column = 1;
        } else {
            self.location.column += 1;
        }
        return true;
    }

    pub fn this(self: *Tokenizer) u8 {
        return self.peek() orelse unreachable;
    }

    pub fn next(self: *Tokenizer) !u8 {
        return self.peekNext() orelse error.ReachedEOF;
    }

    pub fn advanceOne(self: *Tokenizer) !void {
        if (!self.advance()) return error.ReachedEOF;
    }

    fn isHexDigit(c: u8) bool {
        return std.ascii.isDigit(c) or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
    }

    fn isNumberTail(c: u8) bool {
        return std.ascii.isDigit(c) or c == '.' or c == 'e' or c == 'E';
    }

    pub fn lexNextToken(self: *Tokenizer) !void {
        const loc = self.location;
        const current = self.peek() orelse return;

        if (current == '\n') {
            try self.addToken(tok.Content{ .new_line = .{} }, loc);
            _ = self.advance();
            return;
        }

        if (std.ascii.isWhitespace(current)) {
            _ = self.advance();
            return;
        }

        // Comments
        if (current == '-' and self.peekNext() == '-') {
            const start = self.location.offset;
            while (self.peek()) |c| {
                if (c == '\n') break;
                _ = self.advance();
            }
            const comment = self.source[start..self.location.offset];
            try self.addToken(tok.Content{ .comment = comment }, loc);
            return;
        }

        // Double dot / dot
        if (current == '.' and self.peekNext() == '.') {
            try self.addToken(tok.Content{ .double_dot = .{} }, loc);
            _ = self.advance();
            _ = self.advance();
            return;
        }
        if (current == '.') {
            try self.addToken(tok.Content{ .dot = .{} }, loc);
            _ = self.advance();
            return;
        }

        // Comma
        if (current == ',') {
            try self.addToken(tok.Content{ .comma = .{} }, loc);
            _ = self.advance();
            return;
        }

        // Literales
        if (std.ascii.isDigit(current)) {
            const start = self.location.offset;
            var literal: tok.Literal = tok.Literal{ .decimal_int_literal = "" };
            if (current == '0') {
                // Check for hexadecimal, octal or binary
                _ = self.advance(); // Avanzar el '0'
                if (self.peek()) |prefix| {
                    if (prefix == 'x' or prefix == 'X') {
                        // Hexadecimal
                        literal = tok.Literal{ .hexadecimal_int_literal = "" };
                        _ = self.advance();
                        const digit_start = self.location.offset;
                        while (self.peek()) |c| {
                            if (!isHexDigit(c)) break;
                            _ = self.advance();
                        }
                        if (self.location.offset == digit_start) {
                            try self.diagnostics.add(loc, .syntax, "incomplete hexadecimal integer literal", .{});
                            return TokenizerError.UnknownCharacter;
                        }
                    } else if (prefix == 'b' or prefix == 'B') {
                        // Binary
                        literal = tok.Literal{ .binary_int_literal = "" };
                        _ = self.advance();
                        const digit_start = self.location.offset;
                        while (self.peek()) |c| {
                            if (c != '0' and c != '1') break;
                            _ = self.advance();
                        }
                        if (self.location.offset == digit_start) {
                            try self.diagnostics.add(loc, .syntax, "incomplete binary integer literal", .{});
                            return TokenizerError.UnknownCharacter;
                        }
                    } else if (prefix == 'o' or prefix == 'O') {
                        // Octal
                        literal = tok.Literal{ .octal_int_literal = "" };
                        _ = self.advance();
                        const digit_start = self.location.offset;
                        while (self.peek()) |c| {
                            if (c < '0' or c > '7') break;
                            _ = self.advance();
                        }
                        if (self.location.offset == digit_start) {
                            try self.diagnostics.add(loc, .syntax, "incomplete octal integer literal", .{});
                            return TokenizerError.UnknownCharacter;
                        }
                    } else {
                        // ESTO
                        while (self.peek()) |c| {
                            if (!isNumberTail(c)) break;
                            if (c == '.') {
                                literal = tok.Literal{ .regular_float_literal = "" };
                            }
                            if (c == 'e' or c == 'E') {
                                literal = tok.Literal{ .scientific_float_literal = "" };
                            }
                            _ = self.advance();
                        }
                    }
                }
            } else {
                // Y ESTO SON IGUALES
                while (self.peek()) |c| {
                    if (!isNumberTail(c)) break;
                    if (c == '.') {
                        literal = tok.Literal{ .regular_float_literal = "" };
                    }
                    if (c == 'e' or c == 'E') {
                        literal = tok.Literal{ .scientific_float_literal = "" };
                    }
                    _ = self.advance();
                }
            }
            const num_str = self.source[start..self.location.offset];
            if (num_str[num_str.len - 1] == 'e' or num_str[num_str.len - 1] == 'E') {
                try self.diagnostics.add(loc, .syntax, "incomplete scientific float literal", .{});
                return TokenizerError.UnknownCharacter;
            }
            literal = switch (literal) {
                .decimal_int_literal => tok.Literal{ .decimal_int_literal = num_str },
                .hexadecimal_int_literal => tok.Literal{ .hexadecimal_int_literal = num_str },
                .octal_int_literal => tok.Literal{ .octal_int_literal = num_str },
                .binary_int_literal => tok.Literal{ .binary_int_literal = num_str },
                .regular_float_literal => tok.Literal{ .regular_float_literal = num_str },
                .scientific_float_literal => tok.Literal{ .scientific_float_literal = num_str },
                else => unreachable,
            };

            try self.addToken(tok.Content{ .literal = literal }, loc);
            return;
        }

        // Identificadores y keywords
        if (std.ascii.isAlphabetic(current) or current == '_') {
            const start = self.location.offset;
            while (self.peek()) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') break;
                _ = self.advance();
            }
            const word = self.source[start..self.location.offset];
            if (std.mem.eql(u8, word, "return")) {
                try self.addToken(tok.Content{ .keyword_return = .{} }, loc);
            } else if (std.mem.eql(u8, word, "if")) {
                try self.addToken(tok.Content{ .keyword_if = .{} }, loc);
            } else if (std.mem.eql(u8, word, "else")) {
                try self.addToken(tok.Content{ .keyword_else = .{} }, loc);
            } else if (std.mem.eql(u8, word, "match")) {
                try self.addToken(tok.Content{ .keyword_match = .{} }, loc);
            } else if (std.mem.eql(u8, word, "for")) {
                try self.addToken(tok.Content{ .keyword_for = .{} }, loc);
            } else if (std.mem.eql(u8, word, "in")) {
                try self.addToken(tok.Content{ .keyword_in = .{} }, loc);
            } else if (std.mem.eql(u8, word, "while")) {
                try self.addToken(tok.Content{ .keyword_while = .{} }, loc);
            } else if (std.mem.eql(u8, word, "break")) {
                try self.addToken(tok.Content{ .keyword_break = .{} }, loc);
            } else if (std.mem.eql(u8, word, "continue")) {
                try self.addToken(tok.Content{ .keyword_continue = .{} }, loc);
            } else if (std.mem.eql(u8, word, "once")) {
                try self.addToken(tok.Content{ .keyword_once = .{} }, loc);
            } else if (std.mem.eql(u8, word, "test")) {
                try self.addToken(tok.Content{ .keyword_test = .{} }, loc);
            } else if (std.mem.eql(u8, word, "and")) {
                try self.addToken(tok.Content{ .keyword_and = .{} }, loc);
            } else if (std.mem.eql(u8, word, "or")) {
                try self.addToken(tok.Content{ .keyword_or = .{} }, loc);
            } else if (std.mem.eql(u8, word, "true")) {
                try self.addToken(tok.Content{ .literal = .{ .bool_literal = true } }, loc);
            } else if (std.mem.eql(u8, word, "false")) {
                try self.addToken(tok.Content{ .literal = .{ .bool_literal = false } }, loc);
            } else {
                try self.addToken(tok.Content{ .identifier = word }, loc);
            }
            return;
        }

        // Para tokens individuales según el carácter:
        switch (current) {
            '#' => {
                try self.addToken(tok.Content{ .hash = .{} }, loc);
            },
            '(' => {
                try self.addToken(tok.Content{ .open_parenthesis = .{} }, loc);
            },
            ')' => {
                try self.addToken(tok.Content{ .close_parenthesis = .{} }, loc);
            },
            '[' => {
                try self.addToken(tok.Content{ .open_bracket = .{} }, loc);
            },
            ']' => {
                try self.addToken(tok.Content{ .close_bracket = .{} }, loc);
            },
            '{' => {
                try self.addToken(tok.Content{ .open_brace = .{} }, loc);
            },
            '}' => {
                try self.addToken(tok.Content{ .close_brace = .{} }, loc);
            },
            ':' => {
                // Check for double colon
                if (self.peekNext() == ':') {
                    try self.addToken(tok.Content{ .double_colon = .{} }, loc);
                    _ = self.advance(); // Avanzar el segundo ':'
                } else {
                    try self.addToken(tok.Content{ .colon = .{} }, loc);
                }
            },
            '=' => {
                if (self.peekNext() == '=') {
                    try self.addToken(tok.Content{ .comparison_operator = .equal }, loc);
                    _ = self.advance(); // Avanzar el segundo '='
                } else {
                    try self.addToken(tok.Content{ .equal = .{} }, loc);
                }
            },
            '!' => {
                if (self.peekNext() == '=') {
                    try self.addToken(tok.Content{ .comparison_operator = .not_equal }, loc);
                    _ = self.advance(); // Avanzar el segundo '!'
                } else if (self.peekNext() == '!') {
                    try self.addToken(tok.Content{ .double_bang = .{} }, loc);
                    _ = self.advance(); // Avanzar el segundo '!'
                } else {
                    try self.addToken(tok.Content{ .bang = .{} }, loc);
                }
            },
            '<' => {
                if (self.peekNext() == '=') {
                    try self.addToken(tok.Content{ .comparison_operator = .less_than_or_equal }, loc);
                    _ = self.advance(); // Avanzar el '='
                } else {
                    try self.addToken(tok.Content{ .comparison_operator = .less_than }, loc);
                }
            },
            '>' => {
                if (self.peekNext() == '=') {
                    try self.addToken(tok.Content{ .comparison_operator = .greater_than_or_equal }, loc);
                    _ = self.advance(); // Avanzar el '='
                } else {
                    try self.addToken(tok.Content{ .comparison_operator = .greater_than }, loc);
                }
            },

            '+' => {
                try self.addToken(tok.Content{ .binary_operator = .addition }, loc);
            },
            '-' => {
                if (self.peekNext() == '>') {
                    try self.addToken(tok.Content{ .arrow = .{} }, loc);
                    _ = self.advance();
                    _ = self.advance();
                    return;
                } else {
                    try self.addToken(tok.Content{ .binary_operator = .subtraction }, loc);
                }
            },
            '*' => {
                try self.addToken(tok.Content{ .binary_operator = .multiplication }, loc);
            },
            '/' => {
                try self.addToken(tok.Content{ .binary_operator = .division }, loc);
            },
            '%' => {
                try self.addToken(tok.Content{ .binary_operator = .modulo }, loc);
            },
            '$' => {
                try self.addToken(tok.Content{ .dollar = .{} }, loc);
            },
            '&' => {
                try self.addToken(tok.Content{ .ampersand = .{} }, loc);
            },
            '|' => {
                try self.addToken(tok.Content{ .pipe = .{} }, loc);
            },
            '~' => {
                try self.addToken(tok.Content{ .tilde = .{} }, loc);
            },
            '?' => {
                try self.addToken(tok.Content{ .question_mark = .{} }, loc);
            },
            '\'' => {
                // Salta la comilla de apertura
                _ = self.advance();

                // 1. ¿escape (`\`) o carácter directo?
                var char_val: u8 = undefined;
                if (self.peek() == null) {
                    try self.diagnostics.add(loc, .syntax, "unterminated char literal", .{});
                    return TokenizerError.UnknownCharacter;
                }
                if (self.peek().? == '\\') { // -- escape --
                    _ = self.advance(); // salta la '\'

                    const esc = self.peek() orelse {
                        try self.diagnostics.add(loc, .syntax, "unterminated char literal", .{});
                        return TokenizerError.UnknownCharacter;
                    };
                    char_val = switch (esc) {
                        'n' => '\n', // salto de línea
                        't' => '\t', // tabulador
                        'r' => '\r', // retorno de carro
                        '\\' => '\\', // barra invertida
                        '\'' => '\'', // comilla simple
                        '0' => 0, // NUL
                        else => {
                            try self.diagnostics.add(loc, .syntax, "unsupported escape: \\{c}", .{esc});
                            return TokenizerError.UnknownCharacter;
                        },
                    };
                    _ = self.advance(); // salta la letra de escape
                } else { // -- carácter simple --
                    if (self.peek().? == '\'') {
                        try self.diagnostics.add(loc, .syntax, "empty char literal", .{});
                        return TokenizerError.UnknownCharacter;
                    }
                    char_val = self.peek().?;
                    _ = self.advance();
                }

                // 2. debe venir la comilla de cierre
                if (self.peek() != '\'') {
                    try self.diagnostics.add(loc, .syntax, "unterminated char literal", .{});
                    return TokenizerError.UnknownCharacter;
                }
                _ = self.advance(); // salta la comilla de cierre

                try self.addToken(
                    tok.Content{ .literal = tok.Literal{ .char_literal = char_val } },
                    loc,
                );
                return;
            },

            '"' => {
                // saltamos la comilla inicial
                _ = self.advance();

                var buf = std.array_list.Managed(u8).init(self.allocator.*);
                defer buf.deinit();

                // recopilamos caracteres, gestionando escapes
                while (self.peek()) |c| {
                    if (c == '"') break;
                    if (c == '\\') {
                        _ = self.advance(); // salta '\'
                        const esc = self.peek() orelse {
                            try self.diagnostics.add(loc, .syntax, "unterminated string literal", .{});
                            return TokenizerError.UnknownCharacter;
                        };
                        const ch: u8 = switch (esc) { // escapes comunes
                            'n' => '\n',
                            't' => '\t',
                            'r' => '\r',
                            '\\' => '\\',
                            '"' => '"',
                            '0' => 0,
                            else => {
                                try self.diagnostics.add(loc, .syntax, "unsupported escape: \\{c}", .{esc});
                                return TokenizerError.UnknownCharacter;
                            },
                        };
                        try buf.append(ch);
                        _ = self.advance();
                    } else {
                        try buf.append(c);
                        _ = self.advance();
                    }
                }
                if (self.peek() != '"') {
                    try self.diagnostics.add(loc, .syntax, "unterminated string literal", .{});
                    return TokenizerError.UnknownCharacter;
                }
                // cerramos comilla
                _ = self.advance();

                // copiamos a memoria propia (slice independiente del source)
                const data = try self.allocator.alloc(u8, buf.items.len);
                std.mem.copyForwards(u8, data, buf.items);

                try self.addToken(
                    tok.Content{ .literal = tok.Literal{ .string_literal = data } },
                    loc,
                );
                return;
            },
            else => {
                try self.diagnostics.add(loc, .syntax, "unrecognized character: '{c}'", .{current});
                _ = self.advance(); // saltamos y seguimos
                return;
            },
        }
        _ = self.advance();
        return;
    }

    pub fn deinit(self: *Tokenizer) void {
        self.tokens.deinit();
    }

    pub fn printTokens(self: *Tokenizer) void {
        std.debug.print("\nTOKENS\n", .{});
        var i: usize = 0;
        for (self.tokens.items) |token| {
            std.debug.print("{d}: ", .{i});
            tok_print.printTokenWithLocation(token, token.location);
            i += 1;
        }
    }
};

fn expectTokenizerDiagnostics(source: []const u8, should_diagnose: bool) !void {
    const files = [_]sf.SourceFile{.{
        .path = "tokenizer_crash_resistance.rg",
        .code = source,
    }};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var diagnostics = diag.Diagnostics.init(&allocator, files[0..]);
    defer diagnostics.deinit();

    var tokenizer_ctx = Tokenizer.init(
        &allocator,
        &diagnostics,
        source,
        files[0].path,
    );
    defer tokenizer_ctx.deinit();

    _ = tokenizer_ctx.tokenize() catch {};
    try std.testing.expectEqual(should_diagnose, diagnostics.hasErrors());
}

test "tokenizer crash resistance at EOF" {
    try expectTokenizerDiagnostics("-- comentario sin newline final", false);
    try expectTokenizerDiagnostics("0", false);
    try expectTokenizerDiagnostics("0x", true);
    try expectTokenizerDiagnostics("0b", true);
    try expectTokenizerDiagnostics("1e", true);
    try expectTokenizerDiagnostics("\"string sin cerrar", true);
    try expectTokenizerDiagnostics("'c", true);
    try expectTokenizerDiagnostics("-", false);
}

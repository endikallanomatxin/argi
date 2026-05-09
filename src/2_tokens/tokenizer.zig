const std = @import("std");
const tok = @import("token.zig");
const tok_print = @import("token_print.zig");
const diag = @import("../1_base/diagnostic.zig");
const sf = @import("../1_base/source_files.zig");

pub const TokenizerError = error{
    UnknownCharacter,
};

const NumericLiteralKind = enum {
    decimal_int,
    hexadecimal_int,
    octal_int,
    binary_int,
    regular_float,
    scientific_float,
};

const LiteralTag = std.meta.Tag(tok.Literal);

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

    fn isBinaryDigit(c: u8) bool {
        return c == '0' or c == '1';
    }

    fn isOctalDigit(c: u8) bool {
        return c >= '0' and c <= '7';
    }

    fn isNumericLiteralTail(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '.';
    }

    fn consumeInvalidNumberTail(self: *Tokenizer, allow_signs: bool) void {
        while (self.peek()) |c| {
            if (isNumericLiteralTail(c) or (allow_signs and (c == '+' or c == '-'))) {
                _ = self.advance();
                continue;
            }
            break;
        }
    }

    fn numericError(
        self: *Tokenizer,
        loc: tok.Location,
        comptime message: []const u8,
        allow_signs: bool,
    ) !void {
        try self.diagnostics.add(loc, .syntax, message, .{});
        self.consumeInvalidNumberTail(allow_signs);
        return TokenizerError.UnknownCharacter;
    }

    fn addNumericToken(
        self: *Tokenizer,
        loc: tok.Location,
        start: usize,
        kind: NumericLiteralKind,
    ) !void {
        const num_str = self.source[start..self.location.offset];
        const literal = switch (kind) {
            .decimal_int => tok.Literal{ .decimal_int_literal = num_str },
            .hexadecimal_int => tok.Literal{ .hexadecimal_int_literal = num_str },
            .octal_int => tok.Literal{ .octal_int_literal = num_str },
            .binary_int => tok.Literal{ .binary_int_literal = num_str },
            .regular_float => tok.Literal{ .regular_float_literal = num_str },
            .scientific_float => tok.Literal{ .scientific_float_literal = num_str },
        };
        try self.addToken(tok.Content{ .literal = literal }, loc);
    }

    fn lexPrefixedInteger(
        self: *Tokenizer,
        loc: tok.Location,
        start: usize,
        kind: NumericLiteralKind,
        digit_ok: fn (u8) bool,
        comptime incomplete_msg: []const u8,
        comptime invalid_msg: []const u8,
    ) !void {
        const digit_start = self.location.offset;
        while (self.peek()) |c| {
            if (!digit_ok(c)) break;
            _ = self.advance();
        }

        if (self.location.offset == digit_start) {
            return self.numericError(loc, incomplete_msg, false);
        }

        if (self.peek()) |tail| {
            if (isNumericLiteralTail(tail)) {
                return self.numericError(loc, invalid_msg, false);
            }
        }

        try self.addNumericToken(loc, start, kind);
    }

    fn lexDecimalOrFloat(self: *Tokenizer, loc: tok.Location, start: usize) !void {
        var kind: NumericLiteralKind = .decimal_int;

        while (self.peek()) |c| {
            if (!std.ascii.isDigit(c)) break;
            _ = self.advance();
        }

        if (self.peek()) |c| {
            if (c == '.') {
                if (self.peekNext() == '.') {
                    return self.numericError(loc, "invalid numeric literal", false);
                }

                kind = .regular_float;
                _ = self.advance();
                const fraction_start = self.location.offset;
                while (self.peek()) |d| {
                    if (!std.ascii.isDigit(d)) break;
                    _ = self.advance();
                }

                if (self.location.offset == fraction_start) {
                    return self.numericError(loc, "incomplete regular float literal", false);
                }

                if (self.peek()) |tail| {
                    if (tail == 'e' or tail == 'E') {
                        kind = .scientific_float;
                    } else if (isNumericLiteralTail(tail)) {
                        return self.numericError(loc, "invalid numeric literal", false);
                    }
                }
            } else if (c == 'e' or c == 'E') {
                kind = .scientific_float;
            } else if (isNumericLiteralTail(c)) {
                return self.numericError(loc, "invalid numeric literal", false);
            }
        }

        if (kind == .scientific_float) {
            _ = self.advance(); // consume e/E
            if (self.peek()) |sign| {
                if (sign == '+' or sign == '-') {
                    _ = self.advance();
                }
            }

            const exponent_start = self.location.offset;
            while (self.peek()) |c| {
                if (!std.ascii.isDigit(c)) break;
                _ = self.advance();
            }

            if (self.location.offset == exponent_start) {
                if (self.peek()) |tail| {
                    if (isNumericLiteralTail(tail) or tail == '+' or tail == '-') {
                        return self.numericError(loc, "invalid scientific float literal", true);
                    }
                }
                return self.numericError(loc, "incomplete scientific float literal", true);
            }

            if (self.peek()) |tail| {
                if (tail == 'e' or tail == 'E' or isNumericLiteralTail(tail)) {
                    return self.numericError(loc, "invalid scientific float literal", false);
                }
            }
        }

        try self.addNumericToken(loc, start, kind);
    }

    fn lexNumber(self: *Tokenizer, loc: tok.Location) !void {
        const start = self.location.offset;
        const first = self.peek().?;

        if (first == '0') {
            _ = self.advance();
            if (self.peek()) |prefix| {
                switch (prefix) {
                    'x', 'X' => {
                        _ = self.advance();
                        return self.lexPrefixedInteger(
                            loc,
                            start,
                            .hexadecimal_int,
                            isHexDigit,
                            "incomplete hexadecimal integer literal",
                            "invalid hexadecimal integer literal",
                        );
                    },
                    'b', 'B' => {
                        _ = self.advance();
                        return self.lexPrefixedInteger(
                            loc,
                            start,
                            .binary_int,
                            isBinaryDigit,
                            "incomplete binary integer literal",
                            "invalid binary integer literal",
                        );
                    },
                    'o', 'O' => {
                        _ = self.advance();
                        return self.lexPrefixedInteger(
                            loc,
                            start,
                            .octal_int,
                            isOctalDigit,
                            "incomplete octal integer literal",
                            "invalid octal integer literal",
                        );
                    },
                    else => {},
                }
            }
        } else {
            _ = self.advance();
        }

        return self.lexDecimalOrFloat(loc, start);
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
            try self.lexNumber(loc);
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

fn expectNumericLiteralToken(source: []const u8, expected_tag: LiteralTag) !void {
    const files = [_]sf.SourceFile{.{
        .path = "numeric_literal.rg",
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

    const tokens = try tokenizer_ctx.tokenize();
    try std.testing.expect(!diagnostics.hasErrors());
    try std.testing.expect(tokens.len >= 2);
    try std.testing.expect(tokens[0].content == .literal);
    try std.testing.expectEqual(expected_tag, std.meta.activeTag(tokens[0].content.literal));
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

test "tokenizer numeric literals" {
    try expectNumericLiteralToken("0", .decimal_int_literal);
    try expectNumericLiteralToken("123", .decimal_int_literal);
    try expectNumericLiteralToken("0xFF", .hexadecimal_int_literal);
    try expectNumericLiteralToken("0XAB", .hexadecimal_int_literal);
    try expectNumericLiteralToken("0b1010", .binary_int_literal);
    try expectNumericLiteralToken("0B1010", .binary_int_literal);
    try expectNumericLiteralToken("0o77", .octal_int_literal);
    try expectNumericLiteralToken("0O123", .octal_int_literal);
    try expectNumericLiteralToken("1.0", .regular_float_literal);
    try expectNumericLiteralToken("0.5", .regular_float_literal);
    try expectNumericLiteralToken("1e2", .scientific_float_literal);
    try expectNumericLiteralToken("1e+2", .scientific_float_literal);
    try expectNumericLiteralToken("1e-2", .scientific_float_literal);
    try expectNumericLiteralToken("1.5e-2", .scientific_float_literal);
}

test "tokenizer invalid numeric literals" {
    try expectTokenizerDiagnostics("0x", true);
    try expectTokenizerDiagnostics("0X", true);
    try expectTokenizerDiagnostics("0xz", true);
    try expectTokenizerDiagnostics("0b", true);
    try expectTokenizerDiagnostics("0B", true);
    try expectTokenizerDiagnostics("0b2", true);
    try expectTokenizerDiagnostics("0o", true);
    try expectTokenizerDiagnostics("0O", true);
    try expectTokenizerDiagnostics("0o8", true);
    try expectTokenizerDiagnostics("1e", true);
    try expectTokenizerDiagnostics("1e+", true);
    try expectTokenizerDiagnostics("1e-", true);
    try expectTokenizerDiagnostics("1ee2", true);
    try expectTokenizerDiagnostics("1e2e3", true);
    try expectTokenizerDiagnostics("1.2e3e4", true);
    try expectTokenizerDiagnostics("1e+-2", true);
    try expectTokenizerDiagnostics("1..2", true);
    try expectTokenizerDiagnostics("1.2.3", true);
    try expectTokenizerDiagnostics("1.", true);
}

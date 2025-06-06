const std = @import("std");
const tok = @import("token.zig");
const tok_print = @import("token_print.zig");

pub const TokenizerError = error{
    UnknownCharacter,
};

pub const Tokenizer = struct {
    allocator: *const std.mem.Allocator,
    source: []const u8,
    tokens: std.ArrayList(tok.Token),

    location: tok.Location,

    pub fn init(
        allocator: *const std.mem.Allocator,
        source: []const u8,
        file_name: []const u8,
    ) Tokenizer {
        return Tokenizer{
            .allocator = allocator,
            .source = source,
            .tokens = std.ArrayList(tok.Token).init(allocator.*),
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
    pub fn tokenize(self: *Tokenizer) !std.ArrayList(tok.Token) {
        while (self.location.offset < self.source.len) {
            lexNextToken(self) catch |err| {
                if (err == error.ReachedEOF) {
                    break;
                } else {
                    std.debug.print("Error al lexear: {any}\n", .{err});
                    return err;
                }
            };
        }
        // Añadir el token EOF al final
        try self.addToken(tok.Content{ .eof = .{} }, self.location);
        return self.tokens;
    }

    /// Añade un token a la lista de tokens, actualizando la ubicación actual.
    pub fn addToken(self: *Tokenizer, content: tok.Content, location: tok.Location) !void {
        const token = tok.Token{
            .content = content,
            .location = location,
        };
        try self.tokens.append(token);
    }

    pub fn this(self: *Tokenizer) u8 {
        return self.source[self.location.offset];
    }

    pub fn next(self: *Tokenizer) !u8 {
        if (self.location.offset + 1 >= self.source.len) {
            return error.ReachedEOF;
        }
        return self.source[self.location.offset + 1];
    }

    pub fn advanceOne(self: *Tokenizer) !void {
        const c = self.this();
        if (self.location.offset >= self.source.len) {
            return error.ReachedEOF;
        }
        self.location.offset += 1;
        if (c == '\n') {
            self.location.line += 1;
            self.location.column = 1;
        } else {
            self.location.column += 1;
        }
    }

    pub fn lexNextToken(self: *Tokenizer) !void {
        const loc = self.location;

        if (self.this() == '\n') {
            try self.addToken(tok.Content{ .new_line = .{} }, loc);
            try self.advanceOne();
            return;
        }

        if (std.ascii.isWhitespace(self.this())) {
            try self.advanceOne();
            return;
        }

        // Comments
        if (self.this() == '-' and try self.next() == '-') {
            const start = self.location.offset;
            while (self.this() != '\n') {
                try self.advanceOne();
            }
            const comment = self.source[start..self.location.offset];
            try self.addToken(tok.Content{ .comment = comment }, loc);
            return;
        }

        // Literales
        if (std.ascii.isDigit(self.this())) {
            const start = self.location.offset;
            var literal: tok.Literal = tok.Literal{ .decimal_int_literal = "" };
            if (self.this() == '0') {
                // Check for hexadecimal, octal or binary
                try self.advanceOne(); // Avanzar el '0'
                if (self.this() == 'x' or self.this() == 'X') {
                    // Hexadecimal
                    literal = tok.Literal{ .hexadecimal_int_literal = "" };
                    try self.advanceOne();
                    while (self.this() >= '0' and self.this() <= '9' or
                        (self.this() >= 'a' and self.this() <= 'f') or
                        (self.this() >= 'A' and self.this() <= 'F'))
                    {
                        try self.advanceOne();
                    }
                } else if (self.this() == 'b' or self.this() == 'B') {
                    // Binary
                    literal = tok.Literal{ .binary_int_literal = "" };
                    try self.advanceOne();
                    while (self.this() == '0' or self.this() == '1') {
                        try self.advanceOne();
                    }
                } else if (self.this() == 'o' or self.this() == 'O') {
                    // Octal
                    literal = tok.Literal{ .octal_int_literal = "" };
                    try self.advanceOne();
                    while (self.this() >= '0' and self.this() <= '7') {
                        try self.advanceOne();
                    }
                } else {
                    // ESTO
                    while ((std.ascii.isDigit(self.this()) or self.this() == '.') or
                        self.this() == 'e' or self.this() == 'E')
                    {
                        if (self.this() == '.') {
                            literal = tok.Literal{ .regular_float_literal = "" };
                        }
                        if (self.this() == 'e' or self.this() == 'E') {
                            literal = tok.Literal{ .scientific_float_literal = "" };
                        }
                        try self.advanceOne();
                    }
                }
            } else {
                // Y ESTO SON IGUALES
                while ((std.ascii.isDigit(self.this()) or self.this() == '.') or
                    self.this() == 'e' or self.this() == 'E')
                {
                    if (self.this() == '.') {
                        literal = tok.Literal{ .regular_float_literal = "" };
                    }
                    if (self.this() == 'e' or self.this() == 'E') {
                        literal = tok.Literal{ .scientific_float_literal = "" };
                    }
                    try self.advanceOne();
                }
            }
            const num_str = self.source[start..self.location.offset];
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
        if (std.ascii.isAlphabetic(self.this()) or self.this() == '_') {
            const start = self.location.offset;
            while (std.ascii.isAlphanumeric(self.this()) or self.this() == '_') {
                try self.advanceOne();
            }
            const word = self.source[start..self.location.offset];
            if (std.mem.eql(u8, word, "return")) {
                try self.addToken(tok.Content{ .keyword_return = .{} }, loc);
            } else {
                try self.addToken(tok.Content{ .identifier = word }, loc);
            }
            return;
        }

        // Para tokens individuales según el carácter:
        switch (self.this()) {
            '(' => {
                try self.addToken(tok.Content{ .open_parenthesis = .{} }, loc);
            },
            ')' => {
                try self.addToken(tok.Content{ .close_parenthesis = .{} }, loc);
            },
            '{' => {
                try self.addToken(tok.Content{ .open_brace = .{} }, loc);
            },
            '}' => {
                try self.addToken(tok.Content{ .close_brace = .{} }, loc);
            },
            ':' => {
                // Check for double colon
                if (try self.next() == ':') {
                    try self.addToken(tok.Content{ .double_colon = .{} }, loc);
                    try self.advanceOne(); // Avanzar el segundo ':'
                } else {
                    try self.addToken(tok.Content{ .colon = .{} }, loc);
                }
            },
            '=' => {
                if (try self.next() == '=') {
                    try self.addToken(tok.Content{ .check_equals = .{} }, loc);
                    try self.advanceOne(); // Avanzar el segundo '='
                } else {
                    try self.addToken(tok.Content{ .equal = .{} }, loc);
                }
            },
            '!' => {
                if (try self.next() == '=') {
                    try self.addToken(tok.Content{ .check_not_equals = .{} }, loc);
                    try self.advanceOne(); // Avanzar el segundo '!'
                } else {
                    std.debug.print("Unknown character: {c}\n", .{self.this()});
                    return TokenizerError.UnknownCharacter;
                }
            },
            '+' => {
                try self.addToken(tok.Content{ .binary_operator = .addition }, loc);
            },
            '-' => {
                if (self.next() catch 0 == '>') {
                    try self.addToken(tok.Content{ .arrow = .{} }, loc);
                    try self.advanceOne();
                    try self.advanceOne();
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
            else => {
                std.debug.print("Unknown character: {c}\n", .{self.this()});
                return TokenizerError.UnknownCharacter;
            },
        }
        try self.advanceOne();
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
            tok_print.printToken(token);
            i += 1;
        }
    }
};

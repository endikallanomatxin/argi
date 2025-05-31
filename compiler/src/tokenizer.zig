const std = @import("std");
const tok = @import("token.zig");

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

        // Literales enteros
        if (std.ascii.isDigit(self.this())) {
            const start = self.location.offset;
            var is_float = false;
            while ((std.ascii.isDigit(self.this()) or self.this() == '.')) {
                if (self.source[self.location.offset] == '.') {
                    is_float = true;
                }
                self.location.offset += 1;
            }
            const num_str = self.source[start..self.location.offset];

            var literal: tok.Literal = undefined;
            if (is_float) {
                const number = try std.fmt.parseFloat(f64, num_str);
                literal = tok.Literal{ .float_literal = number };
            } else {
                const number = try std.fmt.parseInt(i64, num_str, 10);
                literal = tok.Literal{ .int_literal = number };
            }
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
                } else {
                    try self.addToken(tok.Content{ .colon = .{} }, loc);
                }
            },
            '=' => {
                try self.addToken(tok.Content{ .equal = .{} }, loc);
            },
            '+' => {
                try self.addToken(tok.Content{ .binary_operator = .addition }, loc);
            },
            '-' => {
                try self.addToken(tok.Content{ .binary_operator = .subtraction }, loc);
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
            printToken(token);
            i += 1;
        }
    }
};

pub fn printToken(token: tok.Token) void {
    switch (token.content) {
        .eof => {
            std.debug.print("eof\n", .{});
        },
        .new_line => {
            std.debug.print("new_line\n", .{});
        },
        .comment => |val| {
            std.debug.print("comment: {s}\n", .{val});
        },
        .identifier => |val| {
            std.debug.print("identifier: {s}\n", .{val});
        },
        .open_parenthesis => {
            std.debug.print("open_parenthesis\n", .{});
        },
        .close_parenthesis => {
            std.debug.print("close_parenthesis\n", .{});
        },
        .open_brace => {
            std.debug.print("open_brace\n", .{});
        },
        .close_brace => {
            std.debug.print("close_brace\n", .{});
        },
        .comma => {
            std.debug.print("comma\n", .{});
        },
        .keyword_return => {
            std.debug.print("keyword_return\n", .{});
        },
        .literal => |lit| {
            switch (lit) {
                .int_literal => |val| {
                    std.debug.print("literal: int_literal {d}\n", .{val});
                },
                .float_literal => |val| {
                    std.debug.print("literal: float_literal {e}\n", .{val});
                },
                .string_literal => |val| {
                    std.debug.print("literal: string_literal {s}\n", .{val});
                },
            }
        },
        .colon => {
            std.debug.print("colon\n", .{});
        },
        .double_colon => {
            std.debug.print("double_colon\n", .{});
        },
        .equal => {
            std.debug.print("equal\n", .{});
        },
        .binary_operator => |op| {
            switch (op) {
                .addition => {
                    std.debug.print("binary_operator: addition\n", .{});
                },
                .subtraction => {
                    std.debug.print("binary_operator: subtraction\n", .{});
                },
                .multiplication => {
                    std.debug.print("binary_operator: multiplication\n", .{});
                },
                .division => {
                    std.debug.print("binary_operator: division\n", .{});
                },
                .modulo => {
                    std.debug.print("binary_operator: modulo\n", .{});
                },
            }
        },
    }
}

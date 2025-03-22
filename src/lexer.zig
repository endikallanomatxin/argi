const std = @import("std");

pub const Token = union(enum) {
    eof: struct {},

    // Names
    identifier: []const u8,

    // Literals
    literal: Literal,

    // Delimiters
    open_parenthesis: struct {},
    close_parenthesis: struct {},
    open_brace: struct {},
    close_brace: struct {},

    // Keywords
    keyword_return: struct {},

    // Operators
    colon: struct {}, // TODO: Give it a more semantically meaningful name
    double_colon: struct {},
    equal: struct {},
    binary_operator: BinaryOperator,
};

pub const Literal = union(enum) {
    int_literal: i64,
    float_literal: f64,
    string_literal: []const u8,
};

pub const BinaryOperator = enum {
    Addition,
    Subtraction,
    Multiplication,
    Division,
    Modulo,
};

pub const LexerError = error{
    UnknownCharacter,
};

pub const Lexer = struct {
    allocator: *const std.mem.Allocator,
    source: []const u8,
    tokens: std.ArrayList(Token),
    index: usize,

    pub fn init(allocator: *const std.mem.Allocator, source: []const u8) Lexer {
        return Lexer{
            .allocator = allocator,
            .source = source,
            .tokens = std.ArrayList(Token).init(allocator.*),
            .index = 0,
        };
    }

    pub fn tokenize(self: *Lexer) !std.ArrayList(Token) {
        while (self.index < self.source.len) {
            lexNextToken(self) catch |err| {
                std.debug.print("Error al lexear: {any}\n", .{err});
                return err;
            };
        }
        return self.tokens;
    }

    pub fn lexNextToken(self: *Lexer) !void {
        const c = self.source[self.index];

        if (std.ascii.isWhitespace(c)) {
            self.index += 1;
            return;
        }

        // Literales enteros
        if (std.ascii.isDigit(c)) {
            const start = self.index;
            while (self.index < self.source.len and std.ascii.isDigit(self.source[self.index])) : (self.index += 1) {}
            const num_str = self.source[start..self.index];
            const number = try std.fmt.parseInt(i64, num_str, 10);
            const literal = Literal{ .int_literal = number };
            try self.tokens.append(Token{ .literal = literal });
            return;
        }

        // Identificadores y keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            const start = self.index;
            while (self.index < self.source.len and (std.ascii.isAlphanumeric(self.source[self.index]) or self.source[self.index] == '_')) : (self.index += 1) {}
            const word = self.source[start..self.index];
            if (std.mem.eql(u8, word, "return")) {
                try self.tokens.append(Token{ .keyword_return = .{} });
            } else {
                try self.tokens.append(Token{ .identifier = word });
            }
            return;
        }

        // Para tokens individuales según el carácter:
        switch (c) {
            '(' => {
                try self.tokens.append(Token{ .open_parenthesis = .{} });
                self.index += 1;
                return;
            },
            ')' => {
                try self.tokens.append(Token{ .close_parenthesis = .{} });
                self.index += 1;
                return;
            },
            '{' => {
                try self.tokens.append(Token{ .open_brace = .{} });
                self.index += 1;
                return;
            },
            '}' => {
                try self.tokens.append(Token{ .close_brace = .{} });
                self.index += 1;
                return;
            },
            ':' => {
                // Check for double colon
                if (self.index + 1 < self.source.len and self.source[self.index + 1] == ':') {
                    try self.tokens.append(Token{ .double_colon = .{} });
                    self.index += 2;
                    return;
                } else {
                    try self.tokens.append(Token{ .colon = .{} });
                    self.index += 1;
                    return;
                }
            },
            '=' => {
                try self.tokens.append(Token{ .equal = .{} });
                self.index += 1;
                return;
            },
            '+' => {
                try self.tokens.append(Token{ .binary_operator = .Addition });
                self.index += 1;
                return;
            },
            '-' => {
                try self.tokens.append(Token{ .binary_operator = .Subtraction });
                self.index += 1;
                return;
            },
            '*' => {
                try self.tokens.append(Token{ .binary_operator = .Multiplication });
                self.index += 1;
                return;
            },
            '/' => {
                try self.tokens.append(Token{ .binary_operator = .Division });
                self.index += 1;
                return;
            },
            '%' => {
                try self.tokens.append(Token{ .binary_operator = .Modulo });
                self.index += 1;
                return;
            },
            else => {
                std.debug.print("Unknown character: {c}\n", .{c});
                return LexerError.UnknownCharacter;
            },
        }
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
    }

    pub fn printTokens(self: *Lexer) void {
        std.debug.print("\nTOKENS\n", .{});
        var i: usize = 0;
        for (self.tokens.items) |token| {
            std.debug.print("{d}: ", .{i});
            printToken(token);
            i += 1;
        }
    }
};

pub fn printToken(token: Token) void {
    switch (token) {
        .eof => {
            std.debug.print("eof\n", .{});
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
                .Addition => {
                    std.debug.print("binary_operator: Addition\n", .{});
                },
                .Subtraction => {
                    std.debug.print("binary_operator: Subtraction\n", .{});
                },
                .Multiplication => {
                    std.debug.print("binary_operator: Multiplication\n", .{});
                },
                .Division => {
                    std.debug.print("binary_operator: Division\n", .{});
                },
                .Modulo => {
                    std.debug.print("binary_operator: Modulo\n", .{});
                },
            }
        },
    }
}

const std = @import("std");

pub const Token = union(enum) {
    identifier: []const u8,
    keyword_func: struct {},
    keyword_return: struct {},
    int_literal: i64,
    string_literal: []const u8,
    colon: struct {},
    equal: struct {},
    open_parenthesis: struct {},
    close_parenthesis: struct {},
    open_brace: struct {},
    close_brace: struct {},
    symbol: []const u8,
    eof: struct {},
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);

    var i: usize = 0;
    while (i < source.len) {
        const c = source[i];

        if (std.ascii.isWhitespace(c)) {
            i += 1;
            continue;
        }

        // Literales enteros
        if (std.ascii.isDigit(c)) {
            const start = i;
            while (i < source.len and std.ascii.isDigit(source[i])) : (i += 1) {}
            const num_str = source[start..i];
            const number = try std.fmt.parseInt(i64, num_str, 10);
            try tokens.append(Token{ .int_literal = number });
            continue;
        }

        // Identificadores y keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            const start = i;
            while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) : (i += 1) {}
            const word = source[start..i];
            if (std.mem.eql(u8, word, "func")) {
                try tokens.append(Token{ .keyword_func = .{} });
            } else if (std.mem.eql(u8, word, "return")) {
                try tokens.append(Token{ .keyword_return = .{} });
            } else {
                try tokens.append(Token{ .identifier = word });
            }
            continue;
        }

        // Para tokens individuales según el carácter:
        switch (c) {
            ':' => {
                try tokens.append(Token{ .colon = .{} });
                i += 1;
                continue;
            },
            '=' => {
                try tokens.append(Token{ .equal = .{} });
                i += 1;
                continue;
            },
            '(' => {
                try tokens.append(Token{ .open_parenthesis = .{} });
                i += 1;
                continue;
            },
            ')' => {
                try tokens.append(Token{ .close_parenthesis = .{} });
                i += 1;
                continue;
            },
            '{' => {
                try tokens.append(Token{ .open_brace = .{} });
                i += 1;
                continue;
            },
            '}' => {
                try tokens.append(Token{ .close_brace = .{} });
                i += 1;
                continue;
            },
            else => {
                // Para cualquier otro símbolo
                try tokens.append(Token{ .symbol = source[i .. i + 1] });
                i += 1;
                continue;
            },
        }
    }

    try tokens.append(Token{ .eof = .{} });
    return tokens;
}

pub fn printToken(token: Token) void {
    switch (token) {
        .identifier => |val| {
            std.debug.print("identifier: {s}\n", .{val});
        },
        .keyword_func => {
            std.debug.print("keyword_func\n", .{});
        },
        .keyword_return => {
            std.debug.print("keyword_return\n", .{});
        },
        .int_literal => |num| {
            std.debug.print("int_literal: {d}\n", .{num});
        },
        .string_literal => |s| {
            std.debug.print("string_literal: {s}\n", .{s});
        },
        .colon => {
            std.debug.print("colon\n", .{});
        },
        .equal => {
            std.debug.print("equal\n", .{});
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
        .symbol => |sym| {
            std.debug.print("symbol: {s}\n", .{sym});
        },
        .eof => {
            std.debug.print("eof\n", .{});
        },
    }
}

pub fn printTokenList(tokens: []Token, indent: usize) void {
    for (tokens) |token| {
        for (0..indent) |_| {
            std.debug.print(" ", .{});
        }
        printToken(token);
    }
}

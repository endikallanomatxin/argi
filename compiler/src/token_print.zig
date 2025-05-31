const std = @import("std");
const tok = @import("token.zig");

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
                .bool_literal => |val| {
                    std.debug.print("bool_literal: {}\n", .{val});
                },
                .decimal_int_literal => |val| {
                    std.debug.print("decimal_int_literal: {s}\n", .{val});
                },
                .hexadecimal_int_literal => |val| {
                    std.debug.print("hexadecimal_int_literal: {s}\n", .{val});
                },
                .octal_int_literal => |val| {
                    std.debug.print("octal_int_literal: {s}\n", .{val});
                },
                .binary_int_literal => |val| {
                    std.debug.print("binary_int_literal: {s}\n", .{val});
                },
                .regular_float_literal => |val| {
                    std.debug.print("float_literal: {s}\n", .{val});
                },
                .scientific_float_literal => |val| {
                    std.debug.print("scientific_float_literal: {s}\n", .{val});
                },
                .char_literal => |val| {
                    std.debug.print("char_literal: {c}\n", .{val});
                },
                .string_literal => |val| {
                    std.debug.print("string_literal: {s}\n", .{val});
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

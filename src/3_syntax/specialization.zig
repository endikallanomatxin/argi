const tok = @import("../2_tokens/token.zig");

/// Recognize an angle-list envelope in expression position without consulting
/// names or types. The parser owns the list grammar and reports its errors.
pub fn starts(tokens: []const tok.Content, first: usize) bool {
    if (first >= tokens.len or tokens[first] != .comparison_operator or tokens[first].comparison_operator != .less_than) return false;
    var angles: usize = 1;
    var parentheses: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    var argument_started = false;
    for (tokens[first + 1 ..], first + 1..) |token, cursor| {
        const top = parentheses == 0 and brackets == 0 and braces == 0 and angles == 1;
        if (top) switch (token) {
            .new_line => if (argument_started) {
                var next = cursor + 1;
                while (next < tokens.len and (tokens[next] == .new_line or tokens[next] == .comment)) : (next += 1) {}
                if (next >= tokens.len) return false;
                const following = tokens[next];
                const closing = following == .comparison_operator and (following.comparison_operator == .greater_than or following.comparison_operator == .greater_than_or_equal);
                if (!closing and following != .comma and following != .dot) return false;
            },
            .comma => argument_started = false,
            .comment => {},
            .keyword_and, .keyword_or => return false,
            else => argument_started = true,
        };
        switch (token) {
            .open_parenthesis => parentheses += 1,
            .open_bracket => brackets += 1,
            .open_brace => braces += 1,
            .close_parenthesis => if (parentheses != 0) {
                parentheses -= 1;
            } else return false,
            .close_bracket => if (brackets != 0) {
                brackets -= 1;
            } else return false,
            .close_brace => if (braces != 0) {
                braces -= 1;
            } else return false,
            .comparison_operator => |operator| {
                if (parentheses != 0 or brackets != 0 or braces != 0) continue;
                switch (operator) {
                    .less_than => angles += 1,
                    .greater_than, .greater_than_or_equal => {
                        angles -= 1;
                        if (angles != 0) continue;
                        if (operator == .greater_than_or_equal) return true;
                        if (cursor + 1 >= tokens.len) return true;
                        return follows(tokens[cursor + 1]);
                    },
                    else => {},
                }
            },
            .eof => return false,
            .semicolon => if (parentheses == 0 and brackets == 0 and braces == 0) return false,
            else => {},
        }
    }
    return false;
}

fn follows(token: tok.Content) bool {
    return switch (token) {
        .identifier,
        .literal,
        .keyword_return,
        .keyword_abort,
        .keyword_if,
        .keyword_else,
        .keyword_for,
        .keyword_while,
        .keyword_match,
        .keyword_test,
        .keyword_implement,
        .keyword_assume,
        .keyword_once,
        .keyword_import,
        .keyword_reach,
        .keyword_defer,
        .keyword_break,
        .keyword_continue,
        .keyword_in,
        .dollar,
        .hash,
        .tilde,
        => false,
        else => true,
    };
}

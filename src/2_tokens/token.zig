const std = @import("std");
const source_db = @import("../1_base/source_db.zig");

pub const Token = struct {
    content: Content,
    location: Location,
};

/// Owned compact token columns retained by a syntax file.
pub const List = std.MultiArrayList(Token);

/// Borrowed access to the owned SoA token columns of a file artifact.
pub const View = struct {
    contents: []const Content = &.{},
    locations: []const Location = &.{},
    len: usize = 0,

    /// Accepts a token List during construction or its retained Slice.
    pub fn init(list: anytype) View {
        return .{ .contents = list.items(.content), .locations = list.items(.location), .len = list.len };
    }

    pub fn get(view: View, index: usize) Token {
        return .{ .content = view.contents[index], .location = view.locations[index] };
    }

    pub fn clone(view: View, allocator: std.mem.Allocator) !View {
        const contents = try allocator.dupe(Content, view.contents);
        errdefer allocator.free(contents);
        return .{ .contents = contents, .locations = try allocator.dupe(Location, view.locations), .len = view.len };
    }
};

pub const Location = struct {
    file: source_db.FileId,
    offset: u32,
};

/// Source-relative text payload. Unlike a slice, this is stable across arena
/// lifetimes and can be written to disk verbatim with the token stream.
pub const TextRange = struct {
    start: u32,
    len: u32,

    pub fn slice(self: TextRange, source: []const u8) []const u8 {
        const start: usize = self.start;
        return source[start .. start + self.len];
    }
};

/// The explicit byte tag keeps the serialized token representation compact
/// while leaving room for the language's punctuation and keyword vocabulary.
pub const Content = union(enum(u8)) {
    eof: struct {},
    new_line: struct {},

    // Comments
    comment: TextRange,

    // Names
    identifier: TextRange,

    // Literals
    literal: TokenLiteral,

    // Delimiters
    open_parenthesis: struct {},
    close_parenthesis: struct {},
    open_bracket: struct {},
    close_bracket: struct {},
    open_brace: struct {},
    close_brace: struct {},
    hash: struct {},

    dot: struct {},
    double_dot: struct {},
    comma: struct {},

    // Keywords
    keyword_return: struct {},
    keyword_if: struct {},
    keyword_else: struct {},
    keyword_match: struct {},
    keyword_for: struct {},
    keyword_in: struct {},
    keyword_while: struct {},
    keyword_break: struct {},
    keyword_continue: struct {},
    keyword_once: struct {},
    keyword_test: struct {},
    keyword_and: struct {},
    keyword_or: struct {},

    // Variables and constants
    colon: struct {},
    double_colon: struct {},

    // Assignment operators
    equal: struct {},
    arrow: struct {},

    // Function operators
    pipe: struct {}, // |
    tilde: struct {}, // ~
    bang: struct {}, // !
    double_bang: struct {}, // !!
    question_mark: struct {}, // ?

    // Arithmetic operators
    binary_operator: BinaryOperator,

    // Equations
    comparison_operator: ComparisonOperator,

    // Pointers and dereferences
    ampersand: struct {}, // &

    // Side-effect indicator
    dollar: struct {},

    // Comptime
    // comptime_run: struct {},
};

pub const TokenLiteral = union(enum(u8)) {
    bool_literal: bool,

    decimal_int_literal: TextRange,
    hexadecimal_int_literal: TextRange,
    octal_int_literal: TextRange,
    binary_int_literal: TextRange,

    regular_float_literal: TextRange,
    scientific_float_literal: TextRange,
    // TODO: Usar una r como separador para periódicos.

    char_literal: u8,
    string_literal: TextRange,
};

/// Materialized literal payload used by the current pointer-based syntax
/// tree. Token streams use TokenLiteral ranges; SyntaxStore will eventually
/// remove this transient representation.
pub const Literal = union(enum) {
    bool_literal: bool,
    decimal_int_literal: []const u8,
    hexadecimal_int_literal: []const u8,
    octal_int_literal: []const u8,
    binary_int_literal: []const u8,
    regular_float_literal: []const u8,
    scientific_float_literal: []const u8,
    char_literal: u8,
    string_literal: []const u8,
};

pub const BinaryOperator = enum {
    addition,
    subtraction,
    multiplication,
    division,
    modulo,
};

pub const ComparisonOperator = enum {
    equal,
    not_equal,
    less_than,
    greater_than,
    less_than_or_equal,
    greater_than_or_equal,
};

test "token stream records remain compact" {
    try @import("std").testing.expectEqual(@as(usize, 8), @sizeOf(Location));
    try @import("std").testing.expectEqual(@as(usize, 24), @sizeOf(Token));
}

// Token text borrows source storage. Decode escapes only when a consumer
// needs the literal value; unescaped strings continue borrowing the source.
pub fn decodeStringLiteral(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;
    var decoded = std.array_list.Managed(u8).init(allocator);
    var index: usize = 0;
    while (index < raw.len) : (index += 1) {
        if (raw[index] != '\\') {
            try decoded.append(raw[index]);
            continue;
        }
        index += 1;
        const escaped = raw[index];
        try decoded.append(switch (escaped) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            '\\' => '\\',
            '"' => '"',
            '0' => 0,
            else => unreachable,
        });
    }
    return try decoded.toOwnedSlice();
}

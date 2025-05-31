pub const Token = struct {
    content: Content,
    location: Location,
};

pub const Location = struct {
    file: []const u8,
    offset: u32,
    line: u32,
    column: u32,
};

pub const Content = union(enum) {
    eof: struct {},
    new_line: struct {},

    // Comments
    comment: []const u8,

    // Names
    identifier: []const u8,

    // Literals
    literal: Literal,

    // Delimiters
    open_parenthesis: struct {},
    close_parenthesis: struct {},
    open_brace: struct {},
    close_brace: struct {},

    comma: struct {},

    // Keywords
    keyword_return: struct {},

    // Operators
    colon: struct {},
    double_colon: struct {},
    equal: struct {},
    binary_operator: BinaryOperator,

    // Pointers and dereferences
    // amperstand: struct {},

    // Side-effect indicator
    // dollar: struct {},

    // Comptime
    // comptime_run: struct {},
};

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

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
    open_bracket: struct {},
    close_bracket: struct {},
    open_brace: struct {},
    close_brace: struct {},

    dot: struct {},
    comma: struct {},

    // Keywords
    keyword_return: struct {},
    keyword_if: struct {},
    keyword_else: struct {},

    // Variables and constants
    colon: struct {},
    double_colon: struct {},

    // Assignment operators
    equal: struct {},
    arrow: struct {},

    // Function operators
    pipe: struct {}, // |

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

pub const Literal = union(enum) {
    bool_literal: bool,

    decimal_int_literal: []const u8,
    hexadecimal_int_literal: []const u8,
    octal_int_literal: []const u8,
    binary_int_literal: []const u8,

    regular_float_literal: []const u8,
    scientific_float_literal: []const u8,
    // TODO: Usar una r como separador para periódicos.

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

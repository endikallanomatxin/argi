const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/09X_integer_literal_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/09X_integer_literal_overflow",
        \\tests/feature_tests/basics/09X_integer_literal_overflow/main.rg:2:20: error: integer literal 300 does not fit in 'UInt8' (max 255)
        \\      value: UInt8 = 300
        \\                     ^
        \\
    );
}

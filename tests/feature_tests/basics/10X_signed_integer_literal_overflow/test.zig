const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/10X_signed_integer_literal_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/10X_signed_integer_literal_overflow",
        \\tests/feature_tests/basics/10X_signed_integer_literal_overflow/main.rg:2:19: error: integer literal 128 does not fit in 'Int8' (min -128, max 127)
        \\      value: Int8 = 128
        \\                    ^
        \\
    );
}

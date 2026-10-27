const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/30X_unsigned_literal_magnitude_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/30X_unsigned_literal_magnitude_overflow",
        \\tests/feature_tests/basics/30X_unsigned_literal_magnitude_overflow/main.rg:2:21: error: integer literal magnitude exceeds the supported 64-bit range
        \\      value: UInt64 = 18446744073709551616
        \\                      ^
        \\
    );
}

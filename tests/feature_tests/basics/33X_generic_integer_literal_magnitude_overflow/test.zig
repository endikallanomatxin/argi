const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/33X_generic_integer_literal_magnitude_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/33X_generic_integer_literal_magnitude_overflow",
        \\tests/feature_tests/basics/33X_generic_integer_literal_magnitude_overflow/main.rg:1:54: error: integer literal magnitude exceeds the supported 64-bit range
        \\  maximum := #(.t: Type) () -> (.result: t) { result = 18446744073709551616 }
        \\                                                       ^
        \\
    );
}

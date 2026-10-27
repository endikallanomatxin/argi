const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/27X_mixed_width_arithmetic" {
    try buildExpectFailExact("tests/feature_tests/basics/27X_mixed_width_arithmetic",
        \\tests/feature_tests/basics/27X_mixed_width_arithmetic/main.rg:4:22: error: operator '+' is not defined for 'UIntNative' and 'UInt8'
        \\      invalid ::= wide + narrow
        \\                       ^
        \\
    );
}

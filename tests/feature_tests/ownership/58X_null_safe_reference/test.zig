const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/58X_null_safe_reference" {
    try buildExpectFailExact("tests/feature_tests/ownership/58X_null_safe_reference",
        \\tests/feature_tests/ownership/58X_null_safe_reference/main.rg:3:23: error: no function named 'cast' exists
        \\      reference ::= cast#(.to: $&Int32)(.value = zero)
        \\                        ^
        \\
    );
}

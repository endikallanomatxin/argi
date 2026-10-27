const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/63X_malloc_direct_safe_cast" {
    try buildExpectFailExact("tests/feature_tests/ownership/63X_malloc_direct_safe_cast",
        \\tests/feature_tests/ownership/63X_malloc_direct_safe_cast/main.rg:4:24: error: no function named 'cast' exists
        \\      fabricated ::= cast#(.to: $&UInt8)(.value = address)
        \\                         ^
        \\
    );
}

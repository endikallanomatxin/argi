const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/pointers/07X_pointer_arithmetic_requires_cast" {
    try buildExpectFailExact("tests/feature_tests/pointers/07X_pointer_arithmetic_requires_cast",
        \\tests/feature_tests/pointers/07X_pointer_arithmetic_requires_cast/main.rg:4:14: error: pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back
        \\      _addr := ptr + 1
        \\               ^
        \\
    );
}

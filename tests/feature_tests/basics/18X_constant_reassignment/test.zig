const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/18X_constant_reassignment" {
    try buildExpectFailExact("tests/feature_tests/basics/18X_constant_reassignment",
        \\tests/feature_tests/basics/18X_constant_reassignment/main.rg:3:5: error: binding 'answer' is constant and cannot be reassigned after initialization
        \\      answer = 2
        \\      ^
        \\
    );
}

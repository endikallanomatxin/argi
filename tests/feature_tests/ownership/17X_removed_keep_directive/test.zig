const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/17X_removed_keep_directive" {
    try buildExpectFailExact("tests/feature_tests/ownership/17X_removed_keep_directive",
        \\tests/feature_tests/ownership/17X_removed_keep_directive/main.rg:3:5: error: unknown directive '#keep'
        \\      #keep value
        \\      ^
        \\
    );
}

const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/51X_loop_may_move_value" {
    try buildExpectFailExact("tests/feature_tests/ownership/51X_loop_may_move_value",
        \\tests/feature_tests/ownership/51X_loop_may_move_value/main.rg:8:32: error: place rooted at 'pair' is moved and cannot be used (moved at tests/feature_tests/ownership/51X_loop_may_move_value/main.rg:8:26)
        \\          consume(.value = ~pair.left)
        \\                                 ^
        \\
    );
}

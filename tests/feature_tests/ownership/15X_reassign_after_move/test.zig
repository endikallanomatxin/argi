const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/15X_reassign_after_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/15X_reassign_after_move",
        \\tests/feature_tests/ownership/15X_reassign_after_move/main.rg:26:5: error: binding 'handle' was moved and cannot be reassigned (moved at tests/feature_tests/ownership/15X_reassign_after_move/main.rg:25:34)
        \\      handle = Resource()
        \\      ^
        \\
    );
}

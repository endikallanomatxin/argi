const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/14X_use_after_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/14X_use_after_move",
        \\tests/feature_tests/ownership/14X_use_after_move/main.rg:26:34: error: binding 'handle' was moved and cannot be used again (moved at tests/feature_tests/ownership/14X_use_after_move/main.rg:25:34)
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
    );
}

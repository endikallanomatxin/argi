const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/19X_continue_outside_loop" {
    try buildExpectFailExact("tests/feature_tests/control_flow/19X_continue_outside_loop",
        \\tests/feature_tests/control_flow/19X_continue_outside_loop/main.rg:2:5: error: continue used outside of a loop
        \\      continue
        \\      ^
        \\
    );
}

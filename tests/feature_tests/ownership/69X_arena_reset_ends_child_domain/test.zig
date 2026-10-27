const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/69X_arena_reset_ends_child_domain" {
    try buildExpectFail(
        "tests/feature_tests/ownership/69X_arena_reset_ends_child_domain",
        "reference depends on a root that has ended",
    );
}

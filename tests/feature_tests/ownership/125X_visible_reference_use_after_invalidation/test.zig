const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/125X_visible_reference_use_after_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/125X_visible_reference_use_after_invalidation",
        "reference depends on a root that has ended",
    );
}

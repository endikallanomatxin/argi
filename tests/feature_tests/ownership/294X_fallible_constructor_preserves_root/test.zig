const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/294X_fallible_constructor_preserves_root" {
    try buildExpectFail(
        "tests/feature_tests/ownership/294X_fallible_constructor_preserves_root",
        "reference depends on a root that has ended",
    );
}

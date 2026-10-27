const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/33X_dynamic_array_retains_external_borrow" {
    try buildExpectFail(
        "tests/feature_tests/collections/33X_dynamic_array_retains_external_borrow",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

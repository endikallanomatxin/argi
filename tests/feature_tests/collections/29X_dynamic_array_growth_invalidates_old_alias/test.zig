const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/29X_dynamic_array_growth_invalidates_old_alias" {
    try buildExpectFail(
        "tests/feature_tests/collections/29X_dynamic_array_growth_invalidates_old_alias",
        "root that has ended",
    );
}

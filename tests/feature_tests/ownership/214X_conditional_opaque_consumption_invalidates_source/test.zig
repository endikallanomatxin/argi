const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/214X_conditional_opaque_consumption_invalidates_source" {
    try buildExpectFail(
        "tests/feature_tests/ownership/214X_conditional_opaque_consumption_invalidates_source",
        "place rooted at 'source' is moved and cannot be used",
    );
}

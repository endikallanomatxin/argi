const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/138X_virtual_nested_cleanup_effect" {
    try buildExpectFail("tests/feature_tests/polymorphism/138X_virtual_nested_cleanup_effect", "a storage transition is not permitted");
}

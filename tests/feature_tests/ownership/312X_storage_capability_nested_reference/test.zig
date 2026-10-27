const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/312X_storage_capability_nested_reference" {
    try buildExpectFail("tests/feature_tests/ownership/312X_storage_capability_nested_reference", "already been consumed");
}

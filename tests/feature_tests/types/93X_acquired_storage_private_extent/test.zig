const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/93X_acquired_storage_private_extent" {
    try buildExpectFail("tests/feature_tests/types/93X_acquired_storage_private_extent", "field '_size' is private to its module");
}

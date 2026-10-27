const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/95X_acquired_storage_duplicate_establishment" {
    try buildExpectFail("tests/feature_tests/types/95X_acquired_storage_duplicate_establishment", "was moved and cannot be used again");
}

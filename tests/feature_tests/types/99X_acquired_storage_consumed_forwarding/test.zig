const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/99X_acquired_storage_consumed_forwarding" {
    try buildExpectFail("tests/feature_tests/types/99X_acquired_storage_consumed_forwarding", "was moved and cannot be used again");
}

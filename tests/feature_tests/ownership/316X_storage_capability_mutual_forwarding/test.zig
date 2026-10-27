const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/316X_storage_capability_mutual_forwarding" {
    try buildExpectFail("tests/feature_tests/ownership/316X_storage_capability_mutual_forwarding", "already been consumed");
}

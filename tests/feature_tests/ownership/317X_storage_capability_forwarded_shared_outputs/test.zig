const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/317X_storage_capability_forwarded_shared_outputs" {
    try buildExpectFail("tests/feature_tests/ownership/317X_storage_capability_forwarded_shared_outputs", "already been consumed");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/301X_storage_capability_forwarded_twice" {
    try buildExpectFail("tests/feature_tests/ownership/301X_storage_capability_forwarded_twice", "already been consumed");
}

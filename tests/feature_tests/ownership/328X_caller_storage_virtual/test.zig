const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/328X_caller_storage_virtual" {
    try buildExpectFail("tests/feature_tests/ownership/328X_caller_storage_virtual", "local storage generation");
}

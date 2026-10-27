const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/321X_caller_storage_cleanup" {
    try buildExpectFail("tests/feature_tests/ownership/321X_caller_storage_cleanup", "local storage generation");
}

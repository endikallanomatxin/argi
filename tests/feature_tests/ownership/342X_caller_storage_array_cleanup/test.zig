const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/342X_caller_storage_array_cleanup" {
    try buildExpectFail("tests/feature_tests/ownership/342X_caller_storage_array_cleanup", "local storage generation");
}

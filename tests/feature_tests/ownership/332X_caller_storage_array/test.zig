const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/332X_caller_storage_array" {
    try buildExpectFail("tests/feature_tests/ownership/332X_caller_storage_array", "local storage generation");
}

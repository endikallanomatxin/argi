const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/325X_caller_storage_recursive" {
    try buildExpectFail("tests/feature_tests/ownership/325X_caller_storage_recursive", "local storage generation");
}

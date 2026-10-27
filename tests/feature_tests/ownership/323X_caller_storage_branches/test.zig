const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/323X_caller_storage_branches" {
    try buildExpectFail("tests/feature_tests/ownership/323X_caller_storage_branches", "local storage generation");
}

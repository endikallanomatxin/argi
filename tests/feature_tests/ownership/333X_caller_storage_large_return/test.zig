const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/333X_caller_storage_large_return" {
    try buildExpectFail("tests/feature_tests/ownership/333X_caller_storage_large_return", "local storage generation");
}

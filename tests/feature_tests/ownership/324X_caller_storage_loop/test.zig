const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/324X_caller_storage_loop" {
    try buildExpectFail("tests/feature_tests/ownership/324X_caller_storage_loop", "local storage generation");
}

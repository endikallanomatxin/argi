const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/337X_caller_storage_cleanup_after_borrow" {
    try buildExpectFail("tests/feature_tests/ownership/337X_caller_storage_cleanup_after_borrow", "local storage generation");
}

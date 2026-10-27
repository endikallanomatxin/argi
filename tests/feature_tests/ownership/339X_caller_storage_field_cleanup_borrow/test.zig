const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/339X_caller_storage_field_cleanup_borrow" {
    try buildExpectFail("tests/feature_tests/ownership/339X_caller_storage_field_cleanup_borrow", "local storage generation");
}

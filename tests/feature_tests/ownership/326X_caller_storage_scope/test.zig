const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/326X_caller_storage_scope" {
    try buildExpectFail("tests/feature_tests/ownership/326X_caller_storage_scope", "local storage generation");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/326X_selected_deferred_operation_body" {
    try buildExpectFail("tests/feature_tests/contracts/326X_selected_deferred_operation_body", "cannot materialize function body");
}

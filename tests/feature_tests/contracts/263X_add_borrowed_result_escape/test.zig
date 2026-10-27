const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/263X_add_borrowed_result_escape" {
    try buildExpectFail("tests/feature_tests/contracts/263X_add_borrowed_result_escape", "function output cannot depend on a local storage generation");
}

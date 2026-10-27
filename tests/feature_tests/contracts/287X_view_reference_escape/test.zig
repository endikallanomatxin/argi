const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/287X_view_reference_escape" {
    try buildExpectFail("tests/feature_tests/contracts/287X_view_reference_escape", "local");
}

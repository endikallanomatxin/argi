const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/72X_computed_selected_branch" {
    try buildExpectFail("tests/feature_tests/execution/72X_computed_selected_branch", "cannot materialize function body");
}

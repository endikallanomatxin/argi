const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/31X_split_separator_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/31X_split_separator_after_cleanup", "root that has ended");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/50X_split_for_source_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/50X_split_for_source_after_cleanup", "root that has ended");
}

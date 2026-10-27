const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/48X_general_purpose_backing_ended" {
    try buildExpectFail("tests/feature_tests/system/48X_general_purpose_backing_ended", "reference depends on a root that has ended");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/28X_ambiguous_copy_assignment" {
    try buildExpectFail("tests/feature_tests/ownership/28X_ambiguous_copy_assignment", "cannot be copied implicitly");
}

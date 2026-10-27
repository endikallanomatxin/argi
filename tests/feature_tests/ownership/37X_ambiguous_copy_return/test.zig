const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/37X_ambiguous_copy_return" {
    try buildExpectFail("tests/feature_tests/ownership/37X_ambiguous_copy_return", "cannot be copied implicitly");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/375X_symbolic_call_possible_initialization" {
    try buildExpectFail("tests/feature_tests/ownership/375X_symbolic_call_possible_initialization", "reference depends on a root that has ended");
}

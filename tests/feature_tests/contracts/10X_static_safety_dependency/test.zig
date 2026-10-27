const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/10X_static_safety_dependency" {
    try buildExpectFail("tests/feature_tests/contracts/10X_static_safety_dependency", "undeclared output dependency");
}

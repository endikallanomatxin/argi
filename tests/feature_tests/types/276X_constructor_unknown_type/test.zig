const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/276X_constructor_unknown_type" {
    try buildExpectFail("tests/feature_tests/types/276X_constructor_unknown_type", "an implementation participant type is unknown or unresolved");
}

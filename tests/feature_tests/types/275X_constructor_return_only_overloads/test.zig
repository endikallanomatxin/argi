const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/275X_constructor_return_only_overloads" {
    try buildExpectFail("tests/feature_tests/types/275X_constructor_return_only_overloads", "equivalent implementation participant patterns are not allowed");
}

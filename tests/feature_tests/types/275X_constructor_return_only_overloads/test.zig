const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/275X_constructor_return_only_overloads" {
    try expectFrontendFailure("tests/feature_tests/types/275X_constructor_return_only_overloads", "equivalent implementation participant patterns are not allowed");
}

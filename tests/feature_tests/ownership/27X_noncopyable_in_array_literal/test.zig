const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/27X_noncopyable_in_array_literal" {
    try expectFrontendFailure("tests/feature_tests/ownership/27X_noncopyable_in_array_literal", "type 'Resource' cannot be copied implicitly");
}

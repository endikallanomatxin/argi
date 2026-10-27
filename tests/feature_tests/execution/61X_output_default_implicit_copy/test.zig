const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/61X_output_default_implicit_copy" {
    try expectFrontendFailure("tests/feature_tests/execution/61X_output_default_implicit_copy", "cannot be copied implicitly");
}

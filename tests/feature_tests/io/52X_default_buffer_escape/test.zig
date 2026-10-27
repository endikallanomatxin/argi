const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/52X_default_buffer_escape" {
    try expectFrontendFailure("tests/feature_tests/io/52X_default_buffer_escape", "function output cannot depend on a local storage generation");
}

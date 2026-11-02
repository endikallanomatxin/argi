const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/110X_computed_import_cycle" {
    try expectFrontendFailure("tests/feature_tests/execution/110X_computed_import_cycle", "import cycle detected after compile-time selection");
}

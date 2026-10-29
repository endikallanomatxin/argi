const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/63X_process_missing_capability" {
    try expectFrontendFailure("tests/feature_tests/system/63X_process_missing_capability", ".self: &ProcessManager");
}

const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/267X_loop_local_storage_escape_break" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/267X_loop_local_storage_escape_break",
        "reference depends on a root that has ended",
    );
}

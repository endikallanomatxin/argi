const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/266X_loop_local_storage_escape" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/266X_loop_local_storage_escape",
        "reference depends on a root that has ended",
    );
}

const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/91X_relocation_stale_destination_alias" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/91X_relocation_stale_destination_alias",
        "reference depends on a root that has ended",
    );
}

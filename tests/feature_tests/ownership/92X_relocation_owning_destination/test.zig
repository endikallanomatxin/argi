const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/92X_relocation_owning_destination" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/92X_relocation_owning_destination",
        "relocate destination is initialized",
    );
}

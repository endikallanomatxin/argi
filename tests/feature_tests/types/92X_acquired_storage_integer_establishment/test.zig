const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/92X_acquired_storage_integer_establishment" {
    try expectFrontendFailure("tests/feature_tests/types/92X_acquired_storage_integer_establishment", "no function named 'establish_allocation' accepts arguments");
}

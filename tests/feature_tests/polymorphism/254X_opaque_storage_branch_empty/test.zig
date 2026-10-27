const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/254X_opaque_storage_branch_empty" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/254X_opaque_storage_branch_empty", "cannot prove empties", "failed without a diagnostic");
}

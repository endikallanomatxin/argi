const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/256X_opaque_storage_old_owner_reference" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/256X_opaque_storage_old_owner_reference", "opaque ownership storage requires no live external aliases to the consumed root", "failed without a diagnostic");
}

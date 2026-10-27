const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/270X_internal_storage_old_owner_alias" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/270X_internal_storage_old_owner_alias", "opaque ownership storage requires no live external aliases to the consumed root", "failed without a diagnostic");
}

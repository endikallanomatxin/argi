const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/249X_opaque_storage_erased_receiver" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/249X_opaque_storage_erased_receiver", "opaque storage clauses on an erased participant require mapped hidden storage identities", "failed without a diagnostic");
}

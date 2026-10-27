const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/29X_imported_abstract_ambiguous_overload" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/29X_imported_abstract_ambiguous_overload", "multiple applicable operation identities", "panic");
}

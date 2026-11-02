const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/47X_match_value_payload_ambiguous_copy" {
    try expectFrontendFailure("tests/feature_tests/types/47X_match_value_payload_ambiguous_copy", "cannot be copied implicitly");
}

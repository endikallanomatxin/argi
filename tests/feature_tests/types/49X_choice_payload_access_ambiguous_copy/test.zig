const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/49X_choice_payload_access_ambiguous_copy" {
    try expectFrontendFailure("tests/feature_tests/types/49X_choice_payload_access_ambiguous_copy", "cannot be copied implicitly");
}

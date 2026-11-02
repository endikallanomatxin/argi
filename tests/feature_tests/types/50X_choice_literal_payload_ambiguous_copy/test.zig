const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/50X_choice_literal_payload_ambiguous_copy" {
    try expectFrontendFailure("tests/feature_tests/types/50X_choice_literal_payload_ambiguous_copy", "cannot be copied implicitly");
}

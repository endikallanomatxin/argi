const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/253X_choice_payload_integer_address_rejected_across_call" {
    try expectFrontendFailure(
        "tests/feature_tests/types/253X_choice_payload_integer_address_rejected_across_call",
        "no function named 'cast' exists",
    );
}

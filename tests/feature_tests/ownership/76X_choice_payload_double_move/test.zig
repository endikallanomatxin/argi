const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/76X_choice_payload_double_move" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/76X_choice_payload_double_move",
        "binding 'payload' was moved and cannot be used again",
    );
}

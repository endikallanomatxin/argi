const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/247X_choice_literal_payload_move_consumes_source" {
    try expectFrontendFailure(
        "tests/feature_tests/types/247X_choice_literal_payload_move_consumes_source",
        "reference depends on a root that has ended",
    );
}

const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/288X_aggregate_read_after_field_move" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/288X_aggregate_read_after_field_move",
        "place rooted at 'pair' is moved and cannot be used",
    );
}

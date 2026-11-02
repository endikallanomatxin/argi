const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/379X_record_input_keeps_possible_alias_stale" {
    try expectFrontendFailure("tests/feature_tests/ownership/379X_record_input_keeps_possible_alias_stale", "observes storage after an aliased participant");
}

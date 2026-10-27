const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/379X_record_input_keeps_possible_alias_stale" {
    try buildExpectFail("tests/feature_tests/ownership/379X_record_input_keeps_possible_alias_stale", "observes storage after an aliased participant");
}

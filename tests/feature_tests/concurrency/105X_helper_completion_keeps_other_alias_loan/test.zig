const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 105X_helper_completion_keeps_other_alias_loan" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/105X_helper_completion_keeps_other_alias_loan", "concurrent access conflicts through aliased function inputs");
}

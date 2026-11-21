const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "a conditional field load retains every possible reference dependency" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/313X_conditional_field_load_retains_reference", "reference depends on a root that has ended");
}

const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "235X_aliased_reference_retention" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/235X_aliased_reference_retention", "reference read may observe an expired value through aliased function inputs");
}

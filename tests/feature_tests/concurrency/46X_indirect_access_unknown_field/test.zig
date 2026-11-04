const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 46X_indirect_access_unknown_field" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/46X_indirect_access_unknown_field", "access bound selects an unknown field");
}

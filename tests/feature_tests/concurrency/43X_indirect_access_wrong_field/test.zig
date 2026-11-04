const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 43X_indirect_access_wrong_field" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/43X_indirect_access_wrong_field", "memory access exceeds the declared reads/writes bounds");
}

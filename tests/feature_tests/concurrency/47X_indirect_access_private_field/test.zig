const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 47X_indirect_access_private_field" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/47X_indirect_access_private_field", "access bounds cannot select private fields of another module");
}

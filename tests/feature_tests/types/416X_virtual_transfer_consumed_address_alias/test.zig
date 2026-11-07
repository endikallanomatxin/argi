const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/416X_virtual_transfer_consumed_address_alias" {
    try support.expectFrontendFailure("tests/feature_tests/types/416X_virtual_transfer_consumed_address_alias", "physical storage capability has already been consumed");
}

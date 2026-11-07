const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/417X_virtual_transfer_consumed_receipt_alias" {
    try support.expectFrontendFailure("tests/feature_tests/types/417X_virtual_transfer_consumed_receipt_alias", "physical storage capability has already been consumed");
}

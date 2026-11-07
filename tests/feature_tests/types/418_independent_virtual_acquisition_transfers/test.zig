const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/418_independent_virtual_acquisition_transfers" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/418_independent_virtual_acquisition_transfers");
    try support.runExpect("tests/feature_tests/types/418_independent_virtual_acquisition_transfers", 0);
}

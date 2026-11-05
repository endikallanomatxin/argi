const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 116_generic_transfer_keeps_virtual_regions" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/116_generic_transfer_keeps_virtual_regions");
    try support.runExpect("tests/feature_tests/concurrency/116_generic_transfer_keeps_virtual_regions", 0);
}

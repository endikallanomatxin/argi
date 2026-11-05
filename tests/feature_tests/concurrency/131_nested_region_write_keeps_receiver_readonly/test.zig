const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency/131_nested_region_write_keeps_receiver_readonly" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/131_nested_region_write_keeps_receiver_readonly");
    try support.runExpect("tests/feature_tests/concurrency/131_nested_region_write_keeps_receiver_readonly", 0);
}

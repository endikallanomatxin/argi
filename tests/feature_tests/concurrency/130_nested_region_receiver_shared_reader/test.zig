const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 130_nested_region_receiver_shared_reader" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/130_nested_region_receiver_shared_reader");
    try support.runExpect("tests/feature_tests/concurrency/130_nested_region_receiver_shared_reader", 0);
}

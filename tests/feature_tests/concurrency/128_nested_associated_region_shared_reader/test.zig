const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 128_nested_associated_region_shared_reader" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/128_nested_associated_region_shared_reader");
    try support.runExpect("tests/feature_tests/concurrency/128_nested_associated_region_shared_reader", 0);
}

const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency/133_nested_region_forwarding_without_access" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/133_nested_region_forwarding_without_access");
    try support.runExpect("tests/feature_tests/concurrency/133_nested_region_forwarding_without_access", 0);
}

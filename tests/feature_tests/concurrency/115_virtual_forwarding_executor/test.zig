const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 115_virtual_forwarding_executor" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/115_virtual_forwarding_executor");
    try support.runExpect("tests/feature_tests/concurrency/115_virtual_forwarding_executor", 0);
}

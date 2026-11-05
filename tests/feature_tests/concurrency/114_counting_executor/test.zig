const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 114_counting_executor" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/114_counting_executor");
    try support.runExpect("tests/feature_tests/concurrency/114_counting_executor", 0);
}

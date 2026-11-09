const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency/136_stable_reference_loop_shared_reader" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/136_stable_reference_loop_shared_reader");
    try support.runExpect("tests/feature_tests/concurrency/136_stable_reference_loop_shared_reader", 0);
}

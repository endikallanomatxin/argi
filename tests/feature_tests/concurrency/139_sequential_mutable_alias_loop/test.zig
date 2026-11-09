const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency/139_sequential_mutable_alias_loop" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/139_sequential_mutable_alias_loop");
    try support.runExpect("tests/feature_tests/concurrency/139_sequential_mutable_alias_loop", 0);
}

const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 148_execution_protocol_failures" {
    try support.checkNativeCFixture("tests/feature_tests/concurrency/148_execution_protocol_failures", &.{});
}

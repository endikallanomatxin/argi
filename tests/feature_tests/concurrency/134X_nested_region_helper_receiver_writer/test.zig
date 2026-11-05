const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency nested helper retains locating reads" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/134X_nested_region_helper_receiver_writer", "pending execution");
}

const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "435X_worker_replaces_allocation_address" {
    try support.expectFrontendDiagnostic("tests/feature_tests/concurrency/435X_worker_replaces_allocation_address", .{
        .origin = .bundled_core,
        .message = "task result lacks a static ownership-transfer guarantee",
    });
}

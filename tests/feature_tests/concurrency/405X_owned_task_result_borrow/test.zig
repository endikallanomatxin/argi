const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "405X_owned_task_result_borrow" {
    const path = "tests/feature_tests/concurrency/405X_owned_task_result_borrow";
    try support.expectFrontendDiagnostic(path, .{
        .origin = .bundled_core,
        .message = "task result retains safety evidence that its native output slot cannot transport",
    });
}

const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/collections/184X_loop_push_invalidates_array_view" {
    try support.expectFrontendDiagnostic("tests/feature_tests/collections/184X_loop_push_invalidates_array_view", .{
        .message = "root that has ended",
        .file = "main.rg",
        .marker = "(&borrowed, .index = 0",
    });
}

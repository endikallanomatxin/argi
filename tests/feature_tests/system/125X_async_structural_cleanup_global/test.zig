const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "access effects: 125X_async_structural_cleanup_global" {
    try support.expectFrontendDiagnostic("tests/feature_tests/system/125X_async_structural_cleanup_global", .{
        .message = "isolated callback cannot write mutable global storage",
        .origin = .bundled_core,
        .forbidden = &.{"failed without a diagnostic"},
    });
}

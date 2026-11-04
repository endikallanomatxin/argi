const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "access effects: 126X_async_recursive_global_read" {
    try support.expectFrontendDiagnostic("tests/feature_tests/system/126X_async_recursive_global_read", .{
        .message = "isolated callback cannot read mutable global storage",
        .origin = .bundled_core,
        .forbidden = &.{"failed without a diagnostic"},
    });
}

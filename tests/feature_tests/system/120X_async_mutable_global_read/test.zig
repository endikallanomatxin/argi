const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "access effects: 120X_async_mutable_global_read" {
    try support.expectFrontendDiagnostic("tests/feature_tests/system/120X_async_mutable_global_read", .{
        .message = "isolated callback cannot read mutable global storage",
        .origin = .bundled_core,
        .forbidden = &.{"failed without a diagnostic"},
    });
}

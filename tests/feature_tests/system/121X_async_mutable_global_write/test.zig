const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "access effects: 121X_async_mutable_global_write" {
    try support.expectFrontendDiagnostic("tests/feature_tests/system/121X_async_mutable_global_write", .{
        .message = "isolated callback cannot write mutable global storage",
        .origin = .bundled_core,
        .forbidden = &.{"failed without a diagnostic"},
    });
}

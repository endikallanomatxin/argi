const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "access effects: 124X_async_global_reference_write" {
    try support.expectFrontendDiagnostic("tests/feature_tests/system/124X_async_global_reference_write", .{
        .message = "isolated callback cannot write mutable global storage",
        .origin = .bundled_core,
        .forbidden = &.{"failed without a diagnostic"},
    });
}

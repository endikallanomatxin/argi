const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "async rejects nonplain global environment" {
    try support.expectFrontendDiagnostic("tests/feature_tests/system/119_async_global_reference_rejected", .{
        .message = "isolated callback cannot access nonplain global storage",
        .origin = .bundled_core,
        .forbidden = &.{"failed without a diagnostic"},
    });
}

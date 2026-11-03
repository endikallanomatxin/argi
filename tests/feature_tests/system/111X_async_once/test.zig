const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "async callback cannot consume once function" {
    try support.expectFrontendDiagnostic("tests/feature_tests/system/111X_async_once", .{
        .message = "callback may be invoked repeatedly and cannot consume a once function",
        .origin = .bundled_core,
        .forbidden = &.{"failed without a diagnostic"},
    });
}

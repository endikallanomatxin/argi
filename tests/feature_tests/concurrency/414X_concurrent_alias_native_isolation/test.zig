const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "414X_concurrent_alias_native_isolation" {
    try support.expectFrontendDiagnostic("tests/feature_tests/concurrency/414X_concurrent_alias_native_isolation", .{
        .origin = .bundled_core,
        .message = "isolated callback cannot access foreign or unresolved functions",
    });
}

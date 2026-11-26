const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "422X_storage_capability_retargeted_loop_condition" {
    try support.expectFrontendDiagnostic("tests/feature_tests/ownership/422X_storage_capability_retargeted_loop_condition", .{
        .message = "function may consume the same physical storage capability more than once",
        .file = "main.rg",
        .marker = "(.address = address, .root = root, .ffi = system.ffi)",
    });
}

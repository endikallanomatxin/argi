const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "421X_loop_propagates_fresh_reference" {
    try support.expectFrontendDiagnostic("tests/feature_tests/ownership/421X_loop_propagates_fresh_reference", .{
        .message = "root that has ended",
        .file = "main.rg",
        .marker = "&.value\n}",
    });
}

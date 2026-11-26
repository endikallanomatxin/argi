const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "420X_loop_push_propagates_retired_reference" {
    try support.expectFrontendDiagnostic("tests/feature_tests/ownership/420X_loop_push_propagates_retired_reference", .{
        .message = "root that has ended",
        .file = "main.rg",
        .marker = "&.value\n}",
    });
}

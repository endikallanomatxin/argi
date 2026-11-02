const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/25X_abort_is_not_an_expression" {
    try support.expectFrontendDiagnostic("tests/feature_tests/basics/25X_abort_is_not_an_expression", .{
        .message = "'abort' is a statement and cannot be used as a value",
        .kind = .syntax,
        .file = "main.rg",
        .marker = "abort",
    });
}

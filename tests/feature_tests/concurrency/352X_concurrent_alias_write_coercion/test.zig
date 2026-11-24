const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "352X_concurrent_alias_write_coercion" {
    const path = "tests/feature_tests/concurrency/352X_concurrent_alias_write_coercion";
    try support.expectFrontendFailure(path, "accepts arguments (.: $$&Cell)");
}

const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "351X_concurrent_alias_read_coercion" {
    const path = "tests/feature_tests/concurrency/351X_concurrent_alias_read_coercion";
    try support.expectFrontendFailure(path, "accepts arguments (.: $$&Cell)");
}

const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "taken owner retains its local provider" {
    const path = "tests/feature_tests/ownership/321X_taken_owner_retains_local_provider";
    try support.expectFrontendFailure(path, "function output cannot depend on a local storage generation");
}

const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/348X_return_owner_and_local_reference" {
    try expectFrontendFailure("tests/feature_tests/ownership/348X_return_owner_and_local_reference", "local storage generation");
}

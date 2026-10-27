const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/170X_virtual_consumes_external_write" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/170X_virtual_consumes_external_write", "a storage transition is not permitted");
}

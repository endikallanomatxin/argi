const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/169X_virtual_consumes_erased_self" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/169X_virtual_consumes_erased_self", "consumes on an erased participant requires receiver cleanup identities");
}

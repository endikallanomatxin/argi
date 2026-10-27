const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/225X_virtual_relocates_wrong_outcome" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/225X_virtual_relocates_wrong_outcome", "storage transition is not permitted by this preservation contract");
}

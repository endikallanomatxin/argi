const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/386X_virtual_hides_acquisition_requirement" {
    try support.expectFrontendFailure("tests/feature_tests/types/386X_virtual_hides_acquisition_requirement", "storage acquisition requirements are not published by this contract");
}

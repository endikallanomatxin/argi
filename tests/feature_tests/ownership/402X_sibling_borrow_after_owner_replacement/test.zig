const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/402X_sibling_borrow_after_owner_replacement" {
    try support.expectFrontendFailure(
        "tests/feature_tests/ownership/402X_sibling_borrow_after_owner_replacement",
        "reference depends on a root that has ended",
    );
}

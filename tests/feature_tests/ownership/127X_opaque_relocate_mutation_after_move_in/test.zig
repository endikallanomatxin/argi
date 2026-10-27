const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/127X_opaque_relocate_mutation_after_move_in" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/127X_opaque_relocate_mutation_after_move_in",
        "relocation would invalidate a hidden opaque dependency",
    );
}

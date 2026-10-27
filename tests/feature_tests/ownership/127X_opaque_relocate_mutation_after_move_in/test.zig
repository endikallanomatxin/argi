const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/127X_opaque_relocate_mutation_after_move_in" {
    try buildExpectFail(
        "tests/feature_tests/ownership/127X_opaque_relocate_mutation_after_move_in",
        "relocation would invalidate a hidden opaque dependency",
    );
}

const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/143X_opaque_mutation_existing_internal_pointer_blocks_relocation" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/143X_opaque_mutation_existing_internal_pointer_blocks_relocation",
        "relocation would invalidate a hidden opaque dependency",
    );
}

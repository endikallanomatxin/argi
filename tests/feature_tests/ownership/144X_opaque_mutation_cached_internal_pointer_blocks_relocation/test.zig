const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/144X_opaque_mutation_cached_internal_pointer_blocks_relocation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/144X_opaque_mutation_cached_internal_pointer_blocks_relocation",
        "relocation would invalidate a hidden opaque dependency",
    );
}

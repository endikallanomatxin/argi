const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/85X_semantic_relocation_double" {
    try buildExpectFail(
        "tests/feature_tests/ownership/85X_semantic_relocation_double",
        "binding 'source' was moved and cannot be used again",
    );
}

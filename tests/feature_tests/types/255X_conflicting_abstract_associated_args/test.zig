const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/255X_conflicting_abstract_associated_args" {
    try buildExpectFail(
        "tests/feature_tests/types/255X_conflicting_abstract_associated_args",
        "ambiguous conformances for the same participant tuple",
    );
}

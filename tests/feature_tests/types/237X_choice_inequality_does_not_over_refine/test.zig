const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/237X_choice_inequality_does_not_over_refine" {
    try buildExpectFail(
        "tests/feature_tests/types/237X_choice_inequality_does_not_over_refine",
        "choice payload '..0' is not active",
    );
}

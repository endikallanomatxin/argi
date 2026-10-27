const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/235X_wrong_known_choice_literal_payload" {
    try buildExpectFail(
        "tests/feature_tests/types/235X_wrong_known_choice_literal_payload",
        "choice payload '..0' is not active",
    );
}

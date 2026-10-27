const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/252X_choice_payload_integer_address_rejected_on_use" {
    try buildExpectFail(
        "tests/feature_tests/types/252X_choice_payload_integer_address_rejected_on_use",
        "no function named 'cast' exists",
    );
}

const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/11X_choice_payload_access_without_payload" {
    try buildExpectFailExact("tests/feature_tests/types/11X_choice_payload_access_without_payload",
        \\tests/feature_tests/types/11X_choice_payload_access_without_payload/main.rg:8:23: error: choice variant '..north' has no payload
        \\      payload := value..north
        \\                        ^
        \\
    );
}

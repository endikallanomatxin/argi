const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/04X_choice_missing_payload" {
    try buildExpectFailExact("tests/feature_tests/types/04X_choice_missing_payload",
        \\tests/feature_tests/types/04X_choice_missing_payload/main.rg:7:21: error: choice variant '..ok' requires a payload
        \\      value: Result = ..ok
        \\                      ^
        \\
    );
}

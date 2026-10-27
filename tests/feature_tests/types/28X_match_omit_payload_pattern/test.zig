const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/28X_match_omit_payload_pattern" {
    try buildExpectFailExact("tests/feature_tests/types/28X_match_omit_payload_pattern",
        \\tests/feature_tests/types/28X_match_omit_payload_pattern/main.rg:13:11: error: choice variant '..error' carries a payload and match must bind it explicitly; use '..error _' to ignore it
        \\          ..error {
        \\            ^
        \\
    );
}

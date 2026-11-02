const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/48X_match_move_payload_consumes_binding" {
    try buildExpectFailExact("tests/feature_tests/types/48X_match_move_payload_consumes_binding",
        \\tests/feature_tests/types/48X_match_move_payload_consumes_binding/main.rg:28:8: error: binding 'value' was moved and cannot be used again (moved at tests/feature_tests/types/48X_match_move_payload_consumes_binding/main.rg:19:11)
        \\      if value == ..error {
        \\         ^
        \\
    );
}

const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/32X_match_value_noncopyable_payload" {
    try buildExpectFailExact("tests/feature_tests/types/32X_match_value_noncopyable_payload",
        \\tests/feature_tests/types/32X_match_value_noncopyable_payload/main.rg:20:14: error: type '<anonymous>' cannot be copied implicitly; use '~value' to transfer ownership
        \\          ..ok payload {
        \\               ^
        \\
    );
}

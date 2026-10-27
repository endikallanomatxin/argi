const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/13X_match_bind_payload_without_payload" {
    try buildExpectFailExact("tests/feature_tests/types/13X_match_bind_payload_without_payload",
        \\tests/feature_tests/types/13X_match_bind_payload_without_payload/main.rg:10:17: error: choice variant '..north' has no payload to bind
        \\          ..north payload {
        \\                  ^
        \\
    );
}

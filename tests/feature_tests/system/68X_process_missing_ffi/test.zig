const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/68X_process_missing_ffi" {
    try expectFrontendFailure("tests/feature_tests/system/68X_process_missing_ffi", "Init argument '.ffi' requires a reachable value or an explicit argument");
}

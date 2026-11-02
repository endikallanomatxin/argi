const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/64X_process_private_handle" {
    try expectFrontendFailure("tests/feature_tests/system/64X_process_private_handle", "field '_handle' is private to its module");
}

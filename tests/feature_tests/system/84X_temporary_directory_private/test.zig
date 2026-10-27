const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/84X_temporary_directory_private" {
    try expectFrontendFailure("tests/feature_tests/system/84X_temporary_directory_private", "field '_handle' is private");
}

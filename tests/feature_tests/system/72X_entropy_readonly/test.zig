const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/72X_entropy_readonly" {
    try buildExpectFail("tests/feature_tests/system/72X_entropy_readonly", "no function named 'fill_random_bytes' accepts arguments");
}

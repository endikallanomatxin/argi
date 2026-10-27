const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/74X_core_path_not_trusted" {
    try buildExpectFail(
        "tests/feature_tests/ownership/74X_core_path_not_trusted",
        "no function named 'cast' exists",
    );
}

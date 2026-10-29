const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/49X_initializer_temporary_ends_backing" {
    try buildExpectFail("tests/feature_tests/system/49X_initializer_temporary_ends_backing", "main.rg:35:30: error: reference depends on a root that has ended");
}

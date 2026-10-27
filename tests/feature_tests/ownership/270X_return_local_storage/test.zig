const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/270X_return_local_storage" {
    try buildExpectFail("tests/feature_tests/ownership/270X_return_local_storage", "local storage generation");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/344X_return_local_deallocator" {
    try buildExpectFail("tests/feature_tests/ownership/344X_return_local_deallocator", "local storage generation");
}

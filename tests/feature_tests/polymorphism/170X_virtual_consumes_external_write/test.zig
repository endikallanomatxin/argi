const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/170X_virtual_consumes_external_write" {
    try buildExpectFail("tests/feature_tests/polymorphism/170X_virtual_consumes_external_write", "a storage transition is not permitted");
}

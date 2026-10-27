const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/322X_caller_storage_forwarding" {
    try buildExpectFail("tests/feature_tests/ownership/322X_caller_storage_forwarding", "local storage generation");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/322X_used_conformance_consumption" {
    try buildExpectFail("tests/feature_tests/contracts/322X_used_conformance_consumption", "cannot prove consumes");
}

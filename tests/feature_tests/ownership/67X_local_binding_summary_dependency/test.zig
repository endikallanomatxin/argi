const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/67X_local_binding_summary_dependency" {
    try buildExpectFail("tests/feature_tests/ownership/67X_local_binding_summary_dependency", "local storage generation");
}

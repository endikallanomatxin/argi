const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/351X_propagated_local_error_tracer" {
    try buildExpectFail("tests/feature_tests/ownership/351X_propagated_local_error_tracer", "local storage generation");
}

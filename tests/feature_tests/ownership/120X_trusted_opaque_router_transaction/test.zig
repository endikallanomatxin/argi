const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/120X_trusted_opaque_router_transaction" {
    try buildExpectFail(
        "tests/feature_tests/ownership/120X_trusted_opaque_router_transaction",
        "opaque ownership storage cannot hide dependencies on external roots",
    );
}

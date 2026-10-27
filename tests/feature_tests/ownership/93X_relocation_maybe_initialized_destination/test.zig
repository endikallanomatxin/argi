const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/93X_relocation_maybe_initialized_destination" {
    try buildExpectFail(
        "tests/feature_tests/ownership/93X_relocation_maybe_initialized_destination",
        "relocate destination may be initialized",
    );
}

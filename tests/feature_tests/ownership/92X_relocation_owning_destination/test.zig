const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/92X_relocation_owning_destination" {
    try buildExpectFail(
        "tests/feature_tests/ownership/92X_relocation_owning_destination",
        "relocate destination is initialized",
    );
}

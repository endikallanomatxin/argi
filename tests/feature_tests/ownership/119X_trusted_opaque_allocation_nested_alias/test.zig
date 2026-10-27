const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/119X_trusted_opaque_allocation_nested_alias" {
    try buildExpectFail(
        "tests/feature_tests/ownership/119X_trusted_opaque_allocation_nested_alias",
        "opaque ownership storage requires no live external aliases to the consumed root",
    );
}

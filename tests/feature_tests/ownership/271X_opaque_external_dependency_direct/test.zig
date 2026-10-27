const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/271X_opaque_external_dependency_direct" {
    try buildExpectFail(
        "tests/feature_tests/ownership/271X_opaque_external_dependency_direct",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/189X_opaque_pointer_assignment_after_release_repopulates" {
    try buildExpectFail(
        "tests/feature_tests/ownership/189X_opaque_pointer_assignment_after_release_repopulates",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

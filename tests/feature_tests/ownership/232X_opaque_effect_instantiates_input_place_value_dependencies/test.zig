const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/232X_opaque_effect_instantiates_input_place_value_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/232X_opaque_effect_instantiates_input_place_value_dependencies",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/30X_nonconstant_module_binding_initialization" {
    try buildExpectFailExact("tests/feature_tests/modules/30X_nonconstant_module_binding_initialization",
        \\tests/feature_tests/modules/30X_nonconstant_module_binding_initialization/main.rg:5:1: error: module-level binding 'computed' must use a constant initializer for now
        \\  computed: Int32 = make_value().value
        \\  ^
        \\
    );
}

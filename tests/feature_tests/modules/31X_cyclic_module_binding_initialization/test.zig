const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/31X_cyclic_module_binding_initialization" {
    try buildExpectFailExact("tests/feature_tests/modules/31X_cyclic_module_binding_initialization",
        \\tests/feature_tests/modules/31X_cyclic_module_binding_initialization/a_first.rg:1:1: error: module-level binding 'first' participates in a cyclic initializer dependency
        \\  first : Int32 = second + 1
        \\  ^
        \\
    );
}

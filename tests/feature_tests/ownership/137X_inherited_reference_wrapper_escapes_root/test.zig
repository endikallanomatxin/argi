const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/137X_inherited_reference_wrapper_escapes_root" {
    try buildExpectFail("tests/feature_tests/ownership/137X_inherited_reference_wrapper_escapes_root", "local storage generation");
}

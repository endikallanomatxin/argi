const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/135X_inherited_reference_escapes_root" {
    try buildExpectFail("tests/feature_tests/ownership/135X_inherited_reference_escapes_root", "local storage generation");
}

const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/227X_virtual_relocates_inherited_duplicate" {
    try buildExpectFail("tests/feature_tests/polymorphism/227X_virtual_relocates_inherited_duplicate", "inherited relocates clauses cannot share");
}

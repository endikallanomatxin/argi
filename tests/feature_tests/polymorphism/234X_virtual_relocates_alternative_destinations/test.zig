const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/234X_virtual_relocates_alternative_destinations" {
    try buildExpectFail("tests/feature_tests/polymorphism/234X_virtual_relocates_alternative_destinations", "alternative relocates clauses sharing an input must describe the same source and destination");
}

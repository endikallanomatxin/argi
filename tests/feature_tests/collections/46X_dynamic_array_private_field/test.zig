const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/46X_dynamic_array_private_field" {
    try buildExpectFailExact("tests/feature_tests/collections/46X_dynamic_array_private_field",
        \\tests/feature_tests/collections/46X_dynamic_array_private_field/main.rg:6:11: error: field '_length' is private to its module
        \\      array._length = 100
        \\            ^
        \\
    );
}

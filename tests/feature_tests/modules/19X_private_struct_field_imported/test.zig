const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/19X_private_struct_field_imported" {
    try buildExpectFailExact("tests/feature_tests/modules/19X_private_struct_field_imported",
        \\tests/feature_tests/modules/19X_private_struct_field_imported/main.rg:4:25: error: field '_hidden' is private to its module
        \\      status_code = point._hidden
        \\                          ^
        \\
    );
}

const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/pointers/04X_read-write_pointer_to_constant" {
    try buildExpectFailExact("tests/feature_tests/pointers/04X_read-write_pointer_to_constant",
        \\tests/feature_tests/pointers/04X_read-write_pointer_to_constant/main.rg:4:31: error: binding 'value' is immutable; declare it with '::' or use '&value'
        \\      mutable_view: $&Int32 = $&value
        \\                                ^
        \\
    );
}

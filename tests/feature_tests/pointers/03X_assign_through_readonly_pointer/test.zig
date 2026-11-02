const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/pointers/03X_assign_through_readonly_pointer" {
    try buildExpectFailExact("tests/feature_tests/pointers/03X_assign_through_readonly_pointer",
        \\tests/feature_tests/pointers/03X_assign_through_readonly_pointer/main.rg:5:11: error: cannot assign through pointer '&Int32' because it is read-only; use '$&' when acquiring it
        \\      reader&= 1
        \\            ^
        \\
    );
}

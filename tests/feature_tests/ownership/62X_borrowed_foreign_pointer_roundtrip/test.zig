const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/62X_borrowed_foreign_pointer_roundtrip" {
    try buildExpectFailExact("tests/feature_tests/ownership/62X_borrowed_foreign_pointer_roundtrip",
        \\tests/feature_tests/ownership/62X_borrowed_foreign_pointer_roundtrip/main.rg:5:24: error: no function named 'cast' exists
        \\      fabricated ::= cast#(.to: &CChar)(.value = address)
        \\                         ^
        \\
    );
}

const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/47X_integer_roundtrip_has_no_safe_provenance" {
    try buildExpectFailExact("tests/feature_tests/ownership/47X_integer_roundtrip_has_no_safe_provenance",
        \\tests/feature_tests/ownership/47X_integer_roundtrip_has_no_safe_provenance/main.rg:4:23: error: no function named 'cast' exists
        \\      reference ::= cast#(.to: $&Int32)(.value = address)
        \\                        ^
        \\
    );
}

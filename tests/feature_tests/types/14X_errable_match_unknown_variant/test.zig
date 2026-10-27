const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/14X_errable_match_unknown_variant" {
    try buildExpectFailExact("tests/feature_tests/types/14X_errable_match_unknown_variant",
        \\tests/feature_tests/types/14X_errable_match_unknown_variant/main.rg:7:11: error: choice type 'Errable#(.t: Int32, .reasons: (..test_error))' has no variant '..none'
        \\          ..none {
        \\            ^
        \\
    );
}

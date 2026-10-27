const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/12X_match_non_choice" {
    try buildExpectFailExact("tests/feature_tests/types/12X_match_non_choice",
        \\tests/feature_tests/types/12X_match_non_choice/main.rg:4:11: error: match expects a choice value, found 'Int32'
        \\      match value {
        \\            ^
        \\
    );
}

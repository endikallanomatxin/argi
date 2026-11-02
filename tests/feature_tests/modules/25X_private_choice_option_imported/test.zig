const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/25X_private_choice_option_imported" {
    try buildExpectFailExact("tests/feature_tests/modules/25X_private_choice_option_imported",
        \\tests/feature_tests/modules/25X_private_choice_option_imported/main.rg:4:11: error: choice option '_hidden_reason' is private to its module
        \\      dep .._hidden_reason
        \\            ^
        \\
    );
}

const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/14X_positional_after_named_call" {
    try buildExpectFailExact("tests/feature_tests/functions/14X_positional_after_named_call",
        \\tests/feature_tests/functions/14X_positional_after_named_call/main.rg:6:40: error: positional collection items must appear before named items
        \\      status_code = subtract(.left = 44, 2).diff
        \\                                         ^
        \\
    );
}

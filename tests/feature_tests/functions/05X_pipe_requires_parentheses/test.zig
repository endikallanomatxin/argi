const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/05X_pipe_requires_parentheses" {
    try buildExpectFailExact("tests/feature_tests/functions/05X_pipe_requires_parentheses",
        \\tests/feature_tests/functions/05X_pipe_requires_parentheses/main.rg:6:22: error: pipe right-hand side must use at least one argument placeholder
        \\      status_code = 41 | add_one
        \\                       ^
        \\
    );
}

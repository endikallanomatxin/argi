const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/06X_pipe_requires_placeholder" {
    try buildExpectFailExact("tests/feature_tests/functions/06X_pipe_requires_placeholder",
        \\tests/feature_tests/functions/06X_pipe_requires_placeholder/main.rg:6:22: error: pipe right-hand side must use at least one argument placeholder
        \\      status_code = 41 | add_one(41)
        \\                       ^
        \\
    );
}

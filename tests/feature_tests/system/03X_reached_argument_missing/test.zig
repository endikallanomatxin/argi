const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/03X_reached_argument_missing" {
    try buildExpectFailExact("tests/feature_tests/system/03X_reached_argument_missing",
        \\tests/feature_tests/system/03X_reached_argument_missing/main.rg:12:26: error: cannot resolve reached argument '.writer' with alternatives [writer, terminal.writer, system.terminal.writer] expected as 'Int32'
        \\      status_code = forward()
        \\                           ^
        \\
    );
}

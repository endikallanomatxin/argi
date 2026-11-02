const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/12X_for_nullable_not_iterable" {
    try buildExpectFailExact("tests/feature_tests/control_flow/12X_for_nullable_not_iterable",
        \\tests/feature_tests/control_flow/12X_for_nullable_not_iterable/main.rg:4:5: error: for expects a type implementing contract 'Iterable', got '?Int32'
        \\      for item in value {
        \\      ^
        \\
    );
}

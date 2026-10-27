const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/50X_undeclared_assignment" {
    try buildExpectFailExact("tests/feature_tests/basics/50X_undeclared_assignment",
        \\tests/feature_tests/basics/50X_undeclared_assignment/main.rg:2:5: error: cannot assign to undeclared binding 'value'; declare it first with ':=' or '::='
        \\      value = 1
        \\      ^
        \\
    );
}

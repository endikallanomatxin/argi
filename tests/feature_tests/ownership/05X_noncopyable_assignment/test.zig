const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/05X_noncopyable_assignment" {
    try buildExpectFailExact("tests/feature_tests/ownership/05X_noncopyable_assignment",
        \\tests/feature_tests/ownership/05X_noncopyable_assignment/main.rg:21:15: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      second := first
        \\                ^
        \\
    );
}

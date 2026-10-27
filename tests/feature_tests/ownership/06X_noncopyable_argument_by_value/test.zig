const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/06X_noncopyable_argument_by_value" {
    try buildExpectFailExact("tests/feature_tests/ownership/06X_noncopyable_argument_by_value",
        \\tests/feature_tests/ownership/06X_noncopyable_argument_by_value/main.rg:25:34: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
    );
}

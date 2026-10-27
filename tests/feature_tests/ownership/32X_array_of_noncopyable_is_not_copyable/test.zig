const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable" {
    try buildExpectFailExact("tests/feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable",
        \\tests/feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable/main.rg:21:15: error: type '[2]Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      copied := resources
        \\                ^
        \\
    );
}

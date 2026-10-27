const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/07X_noncopyable_struct_field" {
    try buildExpectFailExact("tests/feature_tests/ownership/07X_noncopyable_struct_field",
        \\tests/feature_tests/ownership/07X_noncopyable_struct_field/main.rg:25:32: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      wrapped: Wrapper = (.res = handle)
        \\                                 ^
        \\
    );
}

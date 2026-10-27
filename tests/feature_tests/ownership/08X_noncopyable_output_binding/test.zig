const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/08X_noncopyable_output_binding" {
    try buildExpectFailExact("tests/feature_tests/ownership/08X_noncopyable_output_binding",
        \\tests/feature_tests/ownership/08X_noncopyable_output_binding/main.rg:20:11: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      out = res
        \\            ^
        \\
    );
}

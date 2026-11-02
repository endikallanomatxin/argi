const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/256X_abstract_associated_arg_mismatch" {
    try expectFrontendFailure(
        "tests/feature_tests/types/256X_abstract_associated_arg_mismatch",
        "contract constraint 'Capability' required by generic function parameter '.t' of 'require_uint'",
    );
}

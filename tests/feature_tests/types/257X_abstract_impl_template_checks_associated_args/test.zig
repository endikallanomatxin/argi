const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/257X_abstract_impl_template_checks_associated_args" {
    try buildExpectFail(
        "tests/feature_tests/types/257X_abstract_impl_template_checks_associated_args",
        "contract constraint 'Other' required by generic function parameter '.t' of 'require_other'",
    );
}

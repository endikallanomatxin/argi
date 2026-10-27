const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/259X_abstract_associated_comptime_mismatch" {
    try buildExpectFail(
        "tests/feature_tests/types/259X_abstract_associated_comptime_mismatch",
        "contract constraint 'AbstractMatrix' required by generic function parameter '.t' of 'require_four_rows'",
    );
}

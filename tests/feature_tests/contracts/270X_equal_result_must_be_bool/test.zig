const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/270X_equal_result_must_be_bool" {
    try buildExpectFail("tests/feature_tests/contracts/270X_equal_result_must_be_bool", "Equal.equal must return exactly (.ok: Bool)");
}

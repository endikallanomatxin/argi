const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/23X_assume_unknown_variable" {
    try buildExpectFail("tests/feature_tests/functions/23X_assume_unknown_variable", "assume requires an existing variable; 'missing' is not declared in this scope");
}

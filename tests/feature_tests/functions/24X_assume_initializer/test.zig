const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/24X_assume_initializer" {
    try buildExpectFail("tests/feature_tests/functions/24X_assume_initializer", "use ':=' to declare an assumed variable, or 'assume name' for an existing variable");
}

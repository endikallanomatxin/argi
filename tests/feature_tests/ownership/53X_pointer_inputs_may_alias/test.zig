const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/53X_pointer_inputs_may_alias" {
    try buildExpectFail("tests/feature_tests/ownership/53X_pointer_inputs_may_alias", "observes storage after an aliased participant");
}

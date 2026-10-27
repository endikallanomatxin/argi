const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/88X_named_record_field_escape" {
    try buildExpectFail("tests/feature_tests/basics/88X_named_record_field_escape", "local storage generation");
}

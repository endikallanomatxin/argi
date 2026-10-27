const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/23X_abstract_writer_field_conflicting_assignment" {
    try buildExpectFail("tests/feature_tests/io/23X_abstract_writer_field_conflicting_assignment", "cannot assign reference of type");
}

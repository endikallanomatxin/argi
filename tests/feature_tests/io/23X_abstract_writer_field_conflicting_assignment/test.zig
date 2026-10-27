const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/23X_abstract_writer_field_conflicting_assignment" {
    try expectFrontendFailure("tests/feature_tests/io/23X_abstract_writer_field_conflicting_assignment", "cannot assign reference of type");
}

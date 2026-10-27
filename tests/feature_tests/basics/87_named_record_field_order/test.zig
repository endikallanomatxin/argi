const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/87_named_record_field_order" {
    try expectSuccessfulBuild("tests/feature_tests/basics/87_named_record_field_order");
    try runExpect("tests/feature_tests/basics/87_named_record_field_order", 0);
}

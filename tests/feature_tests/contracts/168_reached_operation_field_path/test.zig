const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/168_reached_operation_field_path" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/168_reached_operation_field_path");
}

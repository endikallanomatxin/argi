const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/155_writer_unqualified_operation" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/155_writer_unqualified_operation");
}

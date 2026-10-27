const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/150_scoped_virtual_writer" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/150_scoped_virtual_writer");
}

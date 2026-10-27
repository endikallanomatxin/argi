const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/152_reader_selected_virtual_evidence" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/152_reader_selected_virtual_evidence");
}

const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/68_system_storage_initialization" {
    try expectSuccessfulBuild("tests/feature_tests/system/68_system_storage_initialization");
    try runExpect("tests/feature_tests/system/68_system_storage_initialization", 42);
}

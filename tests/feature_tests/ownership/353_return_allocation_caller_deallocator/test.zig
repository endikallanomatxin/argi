const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/353_return_allocation_caller_deallocator" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/353_return_allocation_caller_deallocator");
    try runExpect("tests/feature_tests/ownership/353_return_allocation_caller_deallocator", 0);
}

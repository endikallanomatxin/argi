const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/227_explicit_generic_allocator_conformance" {
    const path = "tests/feature_tests/contracts/227_explicit_generic_allocator_conformance";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/346_explicit_caller_owners" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/346_explicit_caller_owners");
    try runExpect("tests/feature_tests/ownership/346_explicit_caller_owners", 0);
}

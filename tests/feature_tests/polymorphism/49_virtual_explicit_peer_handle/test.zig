const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/49_virtual_explicit_peer_handle" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/49_virtual_explicit_peer_handle");
    try runExpect("tests/feature_tests/polymorphism/49_virtual_explicit_peer_handle", 0);
}

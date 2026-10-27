const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/53_virtual_receiver_identity_same_type_argument" {
    const path = "tests/feature_tests/polymorphism/53_virtual_receiver_identity_same_type_argument";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

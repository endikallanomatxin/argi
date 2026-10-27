const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/107_trusted_opaque_drop_user_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/107_trusted_opaque_drop_user_call");
}

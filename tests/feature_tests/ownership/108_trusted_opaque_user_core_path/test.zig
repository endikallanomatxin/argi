const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/108_trusted_opaque_user_core_path" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/108_trusted_opaque_user_core_path/core");
}

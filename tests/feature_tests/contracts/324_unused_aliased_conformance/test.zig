const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/324_unused_aliased_conformance" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/324_unused_aliased_conformance");
}

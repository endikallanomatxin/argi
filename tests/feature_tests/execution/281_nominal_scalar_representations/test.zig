const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/281_nominal_scalar_representations" {
    try expectSuccessfulBuild("tests/feature_tests/execution/281_nominal_scalar_representations");
    try run("tests/feature_tests/execution/281_nominal_scalar_representations");
}

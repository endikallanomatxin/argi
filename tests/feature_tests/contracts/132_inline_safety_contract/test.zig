const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/132_inline_safety_contract" {
    const path = "tests/feature_tests/contracts/132_inline_safety_contract";
    try expectSuccessfulBuild(path);
    try run(path);
}

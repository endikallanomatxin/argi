const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/189_init_fallible" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/189_init_fallible");
    try run("tests/feature_tests/contracts/189_init_fallible");
}

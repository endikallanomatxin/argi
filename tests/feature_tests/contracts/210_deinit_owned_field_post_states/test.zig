const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/210_deinit_owned_field_post_states" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/210_deinit_owned_field_post_states");
    try run("tests/feature_tests/contracts/210_deinit_owned_field_post_states");
}

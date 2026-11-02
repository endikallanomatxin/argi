const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/42_choice_struct_payload_access" {
    const test_path = "tests/feature_tests/types/42_choice_struct_payload_access";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

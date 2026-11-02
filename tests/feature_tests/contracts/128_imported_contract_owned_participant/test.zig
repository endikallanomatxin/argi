const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/128_imported_contract_owned_participant" {
    const path = "tests/feature_tests/contracts/128_imported_contract_owned_participant";
    try expectSuccessfulBuild(path);
    try run(path);
}

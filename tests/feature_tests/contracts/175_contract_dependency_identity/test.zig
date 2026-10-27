const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/175_contract_dependency_identity" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/175_contract_dependency_identity");
    try run("tests/feature_tests/contracts/175_contract_dependency_identity");
}

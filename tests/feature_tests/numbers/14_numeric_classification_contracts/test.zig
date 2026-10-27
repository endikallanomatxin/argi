const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/14_numeric_classification_contracts" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/14_numeric_classification_contracts");
    try run("tests/feature_tests/numbers/14_numeric_classification_contracts");
}

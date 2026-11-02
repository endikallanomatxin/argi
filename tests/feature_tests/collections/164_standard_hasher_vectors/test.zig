const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/164_standard_hasher_vectors" {
    try expectSuccessfulBuild("tests/feature_tests/collections/164_standard_hasher_vectors");
    try run("tests/feature_tests/collections/164_standard_hasher_vectors");
}

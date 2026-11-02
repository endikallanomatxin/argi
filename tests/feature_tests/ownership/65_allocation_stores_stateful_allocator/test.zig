const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/65_allocation_stores_stateful_allocator" {
    const test_path = "tests/feature_tests/ownership/65_allocation_stores_stateful_allocator";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

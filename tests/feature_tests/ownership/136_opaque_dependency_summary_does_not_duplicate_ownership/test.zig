const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/136_opaque_dependency_summary_does_not_duplicate_ownership" {
    const test_path = "tests/feature_tests/ownership/136_opaque_dependency_summary_does_not_duplicate_ownership";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "tests/feature_tests/ownership/136_opaque_dependency_summary_does_not_duplicate_ownership wrapper parity" {
    try support.expectSafetyWrapperParity("tests/feature_tests/ownership/136_opaque_dependency_summary_does_not_duplicate_ownership", null);
}

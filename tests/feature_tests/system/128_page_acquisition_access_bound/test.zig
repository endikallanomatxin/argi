const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "page_allocator fresh acquisition satisfies a read bound on Memory" {
    try support.expectSuccessfulBuild("tests/feature_tests/system/128_page_acquisition_access_bound");
}

const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/407_allocator_larger_reservation" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/407_allocator_larger_reservation");
    try support.runExpect("tests/feature_tests/types/407_allocator_larger_reservation", 0);
}

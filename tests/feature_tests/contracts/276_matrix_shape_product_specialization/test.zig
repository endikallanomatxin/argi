const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/contracts/276_matrix_shape_product_specialization" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/276_matrix_shape_product_specialization");
    try runExpect("tests/feature_tests/contracts/276_matrix_shape_product_specialization", 0);
    try vmExpect("tests/feature_tests/contracts/276_matrix_shape_product_specialization", 0, null);
}

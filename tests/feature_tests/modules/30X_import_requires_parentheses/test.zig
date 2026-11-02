const support = @import("../../../support.zig");
const expectSyntaxFailure = support.expectSyntaxFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/modules/30X_import_requires_parentheses" {
    try expectSyntaxFailure("tests/feature_tests/modules/30X_import_requires_parentheses", "expected '(' after import");
}

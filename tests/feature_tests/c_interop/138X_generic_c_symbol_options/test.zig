const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "generic C bodies cannot acquire an exported symbol" {
    try support.expectSyntaxFailure("tests/feature_tests/c_interop/138X_generic_c_symbol_options", "generic CFunction definitions require a body without symbol options or lexical captures");
}

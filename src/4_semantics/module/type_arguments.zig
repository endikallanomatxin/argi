const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");

// Empty names retain ordinary positional arguments through syntax-free IR.
// Language-level constructors need their canonical names before their
// special lowering; ordinary generic declarations bind by parameter order.
pub fn name(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField, base_name: []const u8) []const u8 {
    const position = field.position orelse return tree.tokenTextFromSource(source, field.name_token);
    const names: []const []const u8 = if (std.mem.eql(u8, base_name, "Errable"))
        &.{ "t", "reasons" }
    else if (std.mem.eql(u8, base_name, "Array"))
        &.{ "n", "t" }
    else if (std.mem.eql(u8, base_name, "Virtual"))
        &.{"abstract"}
    else if (std.mem.eql(u8, base_name, "choice_union"))
        &.{ "a", "b" }
    else
        &.{};
    return if (position < names.len) names[position] else "";
}

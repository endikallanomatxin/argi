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
        &.{"contract"}
    else if (std.mem.eql(u8, base_name, "choice_union"))
        &.{ "a", "b" }
    else
        &.{};
    return if (position < names.len) names[position] else "";
}

// Virtual uses the canonical contract argument name or a positional argument.
pub fn isVirtualContractParameter(parameter_name: []const u8) bool {
    return std.mem.eql(u8, parameter_name, "contract");
}

// These arguments need retained parameterized IR rather than literal folding.
pub fn requiresResolution(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex) bool {
    if (tree.tag(node) == .identifier or tree.tag(node) == .associated_type_projection or tree.tag(node) == .comptime_entry) return true;
    if (tree.binaryOperation(node)) |operation|
        return requiresResolution(tree, operation.lhs) or requiresResolution(tree, operation.rhs);
    if (tree.specializationArguments(node)) |literal| for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse continue;
        if (field.default_value) |value| if (requiresResolution(tree, value)) return true;
    };
    return false;
}

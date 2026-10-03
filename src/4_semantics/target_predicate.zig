const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const tok = @import("../2_tokens/token.zig");
const diag = @import("../1_base/diagnostic.zig");
const target = @import("../1_base/target.zig");
const selection = @import("../1_base/target_selection.zig");

// Both ordinary and parameterized bodies bake target predicates into their
// module artifacts. The target is already part of every module's cache key.
pub fn evaluate(allocator: std.mem.Allocator, tree: *const syn.FileSyntaxTree, source: []const u8, node: syn.NodeIndex, config: target.Config, diagnostics: ?*diag.Diagnostics) !?bool {
    const call = tree.functionCall(node) orelse return null;
    if (call.module_qualifier != null) return null;
    const name = tree.tokenTextFromSource(source, call.callee_token);
    const query = std.meta.stringToEnum(selection.Query, name) orelse return null;
    if (call.type_arguments.len != 0 or call.type_arguments_struct != null)
        return report(tree, node, diagnostics, "target predicates do not accept generic arguments");
    const literal_input = tree.structValueLiteral(call.input) orelse
        return report(tree, node, diagnostics, "target predicates require one positional literal string argument");
    if (literal_input.fields.len != 1) return report(tree, node, diagnostics, "target predicates require one positional literal string argument");
    const argument = tree.valueField(literal_input.fields[0]).?;
    if (argument.name_token != null) return report(tree, node, diagnostics, "target predicates require a positional literal string argument");
    const literal = tree.literal(argument.value) orelse return report(tree, node, diagnostics, "target predicates require a literal string argument");
    if (tree.tokenContent(literal.token).literal != .string_literal) return report(tree, node, diagnostics, "target predicates require a literal string argument");
    const raw = tree.tokenTextFromSource(source, literal.token);
    const decoded = try tok.decodeStringLiteral(allocator, raw);
    defer if (std.mem.indexOfScalar(u8, raw, '\\') != null) allocator.free(decoded);
    return selection.matches(config, query, decoded) catch
        return report(tree, node, diagnostics, "unknown OS, architecture, or ABI name in target predicate");
}

fn report(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex, diagnostics: ?*diag.Diagnostics, message: []const u8) error{ OutOfMemory, Reported } {
    if (diagnostics) |bag| try bag.add(tree.tokenLocation(tree.mainToken(node)), .semantic, "{s}", .{message});
    return error.Reported;
}

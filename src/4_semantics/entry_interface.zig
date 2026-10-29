const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");

pub const Input = enum { none, system };
pub const InputPolicy = enum { program, isolated };

/// Classify the host-provided argument, not its type spelling. The generated
/// ordinary call checks compatibility with the actual System value. Program
/// entries may declare other defaulted inputs; isolated interfaces expose only
/// optional System. Ordinary call resolution completes the declared inputs.
pub fn classifyInput(tree: *const syn.FileSyntaxTree, source: []const u8, syntax: ?syn.NodeIndex, policy: InputPolicy) error{InvalidEntryInputs}!Input {
    const input = syntax orelse return .none;
    const literal = tree.structTypeLiteral(input) orelse return error.InvalidEntryInputs;
    var result: Input = .none;
    for (literal.fields) |node| {
        const field = tree.structTypeField(node) orelse return error.InvalidEntryInputs;
        if (std.mem.eql(u8, tree.tokenTextFromSource(source, field.name_token), "system")) {
            result = .system;
        } else if (policy == .isolated) return error.InvalidEntryInputs;
    }
    if (policy == .isolated and literal.fields.len > 1) return error.InvalidEntryInputs;
    return result;
}

pub const comptime_input_message = "compile-time entries accept no inputs or one '.system: System' input; pass ordinary arguments to functions inside the entry body";
pub const test_input_message = "test inputs must use a record signature; System is supplied by the test entry and other inputs use ordinary defaults and assumptions";

pub const system_scope = @embedFile("entry_system_scope.rg");
pub const bootstrap_source = "bootstrap := () -> () {\n" ++ system_scope ++ "}\n";

/// Both concrete and parameterized lowering use this ordinary checked scope.
/// Only the selected execution environment decides which host effects exist.
pub fn parseSystemScope(allocator: std.mem.Allocator) !syn.FileSyntaxTree {
    const diagnostics_mod = @import("../1_base/diagnostic.zig");
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    var tokenizer = @import("../2_tokens/tokenizer.zig").Tokenizer.init(allocator, &diagnostics, bootstrap_source, @enumFromInt(0));
    defer tokenizer.deinit();
    _ = try tokenizer.tokenize();
    const file = syn.FileSyntaxTree.initOwnedTokens(@enumFromInt(0), tokenizer.takeTokens());
    var parser = @import("../3_syntax/syntaxer.zig").Syntaxer.initFile(allocator, file, bootstrap_source, &diagnostics);
    defer parser.deinit();
    return parser.parse();
}

test "entry inputs share shape rules without checking type spellings" {
    const a = std.testing.allocator;
    const diagnostics_mod = @import("../1_base/diagnostic.zig");
    const Case = struct { inputs: []const u8, policy: InputPolicy, expected: ?Input };
    for ([_]Case{
        .{ .inputs = "", .policy = .isolated, .expected = .none },
        .{ .inputs = ".system: System", .policy = .isolated, .expected = .system },
        .{ .inputs = ".system: SystemAlias", .policy = .isolated, .expected = .system },
        .{ .inputs = ".value: Int32", .policy = .isolated, .expected = null },
        .{ .inputs = ".system: System, .value: Int32", .policy = .isolated, .expected = null },
        .{ .inputs = ".writer: Int32", .policy = .program, .expected = .none },
        .{ .inputs = ".system: System, .writer: Int32", .policy = .program, .expected = .system },
    }) |case| {
        const source = try std.fmt.allocPrint(a, "entry := ({s}) -> () {{}}", .{case.inputs});
        defer a.free(source);
        var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
        defer diagnostics.deinit();
        var tokenizer = @import("../2_tokens/tokenizer.zig").Tokenizer.init(a, &diagnostics, source, @enumFromInt(0));
        defer tokenizer.deinit();
        _ = try tokenizer.tokenize();
        const file = syn.FileSyntaxTree.initOwnedTokens(@enumFromInt(0), tokenizer.takeTokens());
        var parser = @import("../3_syntax/syntaxer.zig").Syntaxer.initFile(a, file, source, &diagnostics);
        defer parser.deinit();
        var tree = try parser.parse();
        defer tree.deinit(a);
        const input = tree.functionDeclaration(tree.roots[0]).?.input;
        if (case.expected) |expected| {
            try std.testing.expectEqual(expected, try classifyInput(&tree, source, input, case.policy));
        } else try std.testing.expectError(error.InvalidEntryInputs, classifyInput(&tree, source, input, case.policy));
    }
}

test "entry resource scope parser releases failed construction" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn parse(a: std.mem.Allocator) !void {
            var tree = try parseSystemScope(a);
            defer tree.deinit(a);
            try std.testing.expectEqual(@as(usize, 1), tree.roots.len);
        }
    }.parse, .{});
}

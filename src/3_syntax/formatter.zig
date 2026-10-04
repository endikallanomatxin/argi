const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const syntaxer = @import("syntaxer.zig");
const syn = @import("syntax_tree.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");

const Tag = std.meta.Tag(tok.Content);
const List = std.array_list.Managed(u8);
const Frame = struct { tag: Tag, multiline: bool, expand: bool = false, signature: bool = false, comma_free: bool = false };
const line_width = 100;
const InsertedToken = struct { ordinal: usize, tag: Tag };

/// Formatting uses the complete token stream, including discarded target
/// branches. Newlines are syntax in Argi, so existing breaks are retained and
/// syntaxing identifies complete signature groups and statement boundaries.
/// New breaks occur at collection fields and those boundaries. Token text
/// stays verbatim: comments, escapes, and numeric spellings are never rebuilt.
/// Added scalar grouping brackets and removed multiline struct separators are
/// tracked explicitly and verified against the original syntax structure
/// before an edit is returned.
pub fn format(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var current = try formatOnce(allocator, source);
    errdefer allocator.free(current);
    // Alignment can expose a line break, whose indentation in turn changes
    // the field group. Retained newlines make this converge without oscillating.
    for (0..8) |_| {
        const next = try formatOnce(allocator, current);
        if (std.mem.eql(u8, current, next)) {
            allocator.free(current);
            return next;
        }
        allocator.free(current);
        current = next;
    }
    return error.UnstableFormat;
}

fn formatOnce(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temporary = arena.allocator();
    const files = [_]source_files.SourceFile{.{ .path = "format.rg", .code = source }};
    var diagnostics = diagnostic.Diagnostics.init(&temporary, &files);
    defer diagnostics.deinit();
    var lex = tokenizer.Tokenizer.init(temporary, &diagnostics, source, diagnostics.source_db.fileId(0));
    const tokens = try lex.tokenize();
    if (diagnostics.hasErrors()) return error.InvalidSource;
    const layout = try Layout.init(temporary, tokens, source);
    var out = List.init(temporary);
    var stack = std.array_list.Managed(Frame).init(temporary);
    var inserted = std.array_list.Managed(InsertedToken).init(temporary);
    const removed = try temporary.alloc(bool, tokens.len);
    @memset(removed, false);
    var emitted_tokens: usize = 0;
    var previous: ?Tag = null;
    var line_start: usize = 0;
    var pending_newlines: usize = 0;
    var source_newlines: usize = 0;
    for (0..tokens.len) |i| {
        const tag = std.meta.activeTag(tokens.contents[i]);
        if (tag == .eof) break;
        if (tag == .new_line) {
            if (layout.suppress_newlines[i]) continue;
            source_newlines += 1;
            continue;
        }
        if (tag == .comma and stack.items.len != 0) {
            const frame = stack.items[stack.items.len - 1];
            if (frame.expand and frame.comma_free) {
                removed[i] = true;
                if (tokens.contents[i + 1] != .comment) pending_newlines = @max(pending_newlines, 1);
                continue;
            }
        }
        for (0..layout.wrap_before[i]) |_| {
            if (previous) |left| if (needsSpace(left, .open_bracket, tokens, i)) try out.append(' ');
            try inserted.append(.{ .ordinal = emitted_tokens, .tag = .open_bracket });
            emitted_tokens += 1;
            try out.append('[');
            try stack.append(.{ .tag = .open_bracket, .multiline = true, .expand = true });
            pending_newlines = @max(pending_newlines, 1);
            previous = .open_bracket;
        }
        pending_newlines = @max(pending_newlines, @max(source_newlines, layout.breaks[i]));
        source_newlines = 0;
        var closing_indent: usize = 0;
        const closing = tag == .close_parenthesis or tag == .close_bracket or tag == .close_brace;
        if (closing) {
            if (stack.items.len == 0) return error.UnbalancedDelimiters;
            const frame = stack.pop().?;
            const expected: Tag = switch (tag) {
                .close_parenthesis => .open_parenthesis,
                .close_bracket => .open_bracket,
                else => .open_brace,
            };
            if (frame.tag != expected) return error.UnbalancedDelimiters;
            if (frame.expand) {
                pending_newlines = @max(pending_newlines, 1);
                if (frame.signature) closing_indent = 4;
            }
        }
        if (pending_newlines != 0) {
            if (out.items.len != 0) {
                trimSpaces(&out);
                try out.append('\n');
                if (pending_newlines > 1) try out.append('\n');
            }
            line_start = out.items.len;
            pending_newlines = 0;
            previous = null;
        }
        if (previous == null) {
            var indent = closing_indent;
            for (stack.items) |frame| if (frame.multiline) {
                indent += if (frame.signature) @as(usize, 8) else 4;
            };
            try out.appendNTimes(' ', indent);
        } else if (needsSpace(previous.?, tag, tokens, i) or (previous.? == .binary_operator and i != 0 and layout.breaks[i - 1] != 0)) try out.append(' ');
        const start: usize = tokens.locations[i].offset;
        const end: usize = if (i + 1 < tokens.len) tokens.locations[i + 1].offset else source.len;
        const text = std.mem.trimEnd(u8, source[start..end], " \t\r\n");
        try out.appendSlice(text);
        emitted_tokens += 1;
        previous = tag;
        if (tag == .open_parenthesis or tag == .open_bracket or tag == .open_brace) {
            const multiline = containsNewline(tokens, i);
            const expand = layout.expand[i] or ((tag == .open_parenthesis or (tag == .open_bracket and layout.scalar_groups[i])) and multiline) or (tag != .open_bracket and
                layout.ends[i] > i + 1 and
                out.items.len - line_start + flatLength(tokens, source, i, layout.ends[i] + 1) > line_width);
            try stack.append(.{ .tag = tag, .multiline = multiline or expand, .expand = expand, .signature = layout.signature[i], .comma_free = layout.struct_literals[i] });
            if (expand) pending_newlines = 1;
        }
        // Expanded collections use complete rows rather than spilling only
        // the last argument onto a continuation line.
        if (tag == .comma and stack.items.len != 0 and stack.items[stack.items.len - 1].expand and stack.items[stack.items.len - 1].tag == .open_parenthesis)
            pending_newlines = @max(pending_newlines, 1);
        for (0..layout.wrap_after[i]) |_| {
            const frame = stack.pop().?;
            std.debug.assert(frame.tag == .open_bracket);
            trimSpaces(&out);
            try out.append('\n');
            line_start = out.items.len;
            var indent: usize = 0;
            for (stack.items) |enclosing| if (enclosing.multiline) {
                indent += if (enclosing.signature) @as(usize, 8) else 4;
            };
            try out.appendNTimes(' ', indent);
            try inserted.append(.{ .ordinal = emitted_tokens, .tag = .close_bracket });
            emitted_tokens += 1;
            try out.append(']');
            previous = .close_bracket;
        }
    }
    if (stack.items.len != 0) return error.UnbalancedDelimiters;
    trimSpaces(&out);
    while (out.items.len != 0 and out.items[out.items.len - 1] == '\n') _ = out.pop();
    if (out.items.len != 0) try out.append('\n');
    const result = try alignFields(allocator, out.items);
    errdefer allocator.free(result);
    var verification = tokenizer.Tokenizer.init(temporary, &diagnostics, result, diagnostics.source_db.fileId(0));
    const formatted_tokens = try verification.tokenize();
    var original_index: usize = 0;
    var formatted_ordinal: usize = 0;
    var inserted_index: usize = 0;
    for (0..formatted_tokens.len) |index| {
        if (formatted_tokens.contents[index] == .new_line) continue;
        defer formatted_ordinal += 1;
        if (inserted_index < inserted.items.len and inserted.items[inserted_index].ordinal == formatted_ordinal) {
            if (std.meta.activeTag(formatted_tokens.contents[index]) != inserted.items[inserted_index].tag) return error.TokenSequenceChanged;
            inserted_index += 1;
            continue;
        }
        while (original_index < tokens.len and (tokens.contents[original_index] == .new_line or removed[original_index])) original_index += 1;
        if (original_index >= tokens.len or std.meta.activeTag(formatted_tokens.contents[index]) != std.meta.activeTag(tokens.contents[original_index])) return error.TokenSequenceChanged;
        if (!std.mem.eql(u8, tokenText(tokens, source, original_index), tokenText(formatted_tokens, result, index))) return error.TokenSequenceChanged;
        original_index += 1;
    }
    while (original_index < tokens.len and (tokens.contents[original_index] == .new_line or removed[original_index])) original_index += 1;
    if (original_index != tokens.len or inserted_index != inserted.items.len) return error.TokenSequenceChanged;
    if (layout.syntax_tags) |tags| {
        // Token identity alone is insufficient: newlines can end expressions.
        // Refuse an edit that changes the syntax of an initially valid file.
        const result_files = [_]source_files.SourceFile{.{ .path = "format.rg", .code = result }};
        var result_diagnostics = diagnostic.Diagnostics.init(&temporary, &result_files);
        defer result_diagnostics.deinit();
        var parser = try syntaxer.Syntaxer.init(temporary, formatted_tokens, result, &result_diagnostics);
        defer parser.deinit();
        var tree = parser.parse() catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return error.InvalidFormattedSyntax,
        };
        defer tree.deinit(temporary);
        if (tree.roots.len != layout.root_count or !std.mem.eql(syn.Node.Tag, tags, tree.nodes.items(.tag)))
            return error.SyntaxStructureChanged;
    }
    return result;
}

const Layout = struct {
    ends: []usize,
    breaks: []u8,
    expand: []bool,
    signature: []bool,
    wrap_before: []u16,
    wrap_after: []u16,
    suppress_newlines: []bool,
    scalar_groups: []bool,
    struct_literals: []bool,
    syntax_tags: ?[]const syn.Node.Tag = null,
    root_count: usize = 0,

    fn init(allocator: std.mem.Allocator, tokens: tok.View, source: []const u8) !Layout {
        var layout: Layout = .{
            .ends = try allocator.alloc(usize, tokens.len),
            .breaks = try allocator.alloc(u8, tokens.len),
            .expand = try allocator.alloc(bool, tokens.len),
            .signature = try allocator.alloc(bool, tokens.len),
            .wrap_before = try allocator.alloc(u16, tokens.len),
            .wrap_after = try allocator.alloc(u16, tokens.len),
            .suppress_newlines = try allocator.alloc(bool, tokens.len),
            .scalar_groups = try allocator.alloc(bool, tokens.len),
            .struct_literals = try allocator.alloc(bool, tokens.len),
        };
        @memset(layout.ends, 0);
        @memset(layout.breaks, 0);
        @memset(layout.expand, false);
        @memset(layout.signature, false);
        @memset(layout.wrap_before, 0);
        @memset(layout.wrap_after, 0);
        @memset(layout.suppress_newlines, false);
        @memset(layout.scalar_groups, false);
        @memset(layout.struct_literals, false);
        var opens = std.array_list.Managed(usize).init(allocator);
        for (tokens.contents, 0..) |content, i| switch (content) {
            .open_parenthesis, .open_bracket, .open_brace => try opens.append(i),
            .close_parenthesis, .close_bracket, .close_brace => {
                const open = opens.pop() orelse return error.UnbalancedDelimiters;
                const expected: Tag = switch (content) {
                    .close_parenthesis => .open_parenthesis,
                    .close_bracket => .open_bracket,
                    else => .open_brace,
                };
                if (std.meta.activeTag(tokens.contents[open]) != expected) return error.UnbalancedDelimiters;
                layout.ends[open] = i;
                layout.ends[i] = open;
            },
            else => {},
        };
        if (opens.items.len != 0) return error.UnbalancedDelimiters;

        // Editing and target directives can leave a tokenizable document that
        // does not syntax successfully. Preserve its manual layout in that case;
        // never guess statement boundaries from adjacent identifiers.
        const files = [_]source_files.SourceFile{.{ .path = "format.rg", .code = source }};
        var diagnostics = diagnostic.Diagnostics.init(&allocator, &files);
        defer diagnostics.deinit();
        var parser = try syntaxer.Syntaxer.init(allocator, tokens, source, &diagnostics);
        defer parser.deinit();
        var tree = parser.parse() catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return layout,
        };
        defer tree.deinit(allocator);
        layout.syntax_tags = try allocator.dupe(syn.Node.Tag, tree.nodes.items(.tag));
        layout.root_count = tree.roots.len;
        for (tokens.contents, 0..) |content, i| if (content == .open_bracket) {
            layout.scalar_groups[i] = true;
        };
        for (0..tree.nodes.len) |raw| {
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            if (tree.tag(node) == .struct_value_literal) {
                layout.struct_literals[@intFromEnum(tree.mainToken(node))] = true;
            }
            if (tree.tag(node) == .index_access or tree.tag(node) == .array_type) {
                const open = @intFromEnum(tree.mainToken(node));
                if (tokens.contents[open] == .open_bracket) layout.scalar_groups[open] = false;
            }
        }
        for (tree.roots, 0..) |root, index| {
            if (index != 0 and (isGlobalDeclaration(tree.tag(root)) or isGlobalDeclaration(tree.tag(tree.roots[index - 1])))) {
                var start = firstToken(&tree, root);
                // Keep leading documentation comments attached to declarations.
                var cursor = start;
                while (cursor != 0) {
                    cursor -= 1;
                    if (tokens.contents[cursor] == .new_line) continue;
                    if (tokens.contents[cursor] != .comment) break;
                    if (cursor != 0 and tokens.contents[cursor - 1] != .new_line) break;
                    start = cursor;
                }
                layout.breaks[start] = 2;
            }
        }
        for (0..tree.nodes.len) |raw| {
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            if (tree.functionDeclaration(node) orelse if (tree.testDeclaration(node)) |test_decl| test_decl.function else null) |function| {
                const start = firstToken(&tree, node);
                const output = @intFromEnum(tree.mainToken(function.output));
                const end = if (tokens.contents[output] == .open_parenthesis) layout.ends[output] + 1 else layout.ends[@intFromEnum(tree.mainToken(function.input))] + 1;
                const groups = [_]?syn.NodeIndex{ function.generic_params_struct, function.input, function.output };
                var multiline = flatLength(tokens, source, start, end) > line_width;
                for (groups) |group| if (group) |value| {
                    const open = @intFromEnum(tree.mainToken(value));
                    if (tokens.contents[open] == .open_parenthesis and containsNewline(tokens, open)) multiline = true;
                };
                for (groups) |group| if (group) |value| {
                    const open = @intFromEnum(tree.mainToken(value));
                    if (tokens.contents[open] != .open_parenthesis) continue;
                    layout.signature[open] = multiline;
                    layout.expand[open] = multiline and layout.ends[open] > open + 1;
                };
            }
            if (tree.codeBlock(node)) |block| {
                const open = @intFromEnum(tree.mainToken(node));
                if (block.statements.len > 1) {
                    layout.expand[open] = true;
                    for (block.statements) |statement| {
                        var start = firstToken(&tree, statement);
                        // Scalar grouping brackets do not create syntax nodes.
                        // Include any enclosing group in the statement boundary.
                        for (open + 1..start) |candidate| {
                            if (tokens.contents[candidate] == .open_bracket and layout.ends[candidate] >= start) {
                                start = candidate;
                                break;
                            }
                        }
                        layout.breaks[start] = @max(layout.breaks[start], 1);
                    }
                }
            }
        }
        const handled = try allocator.alloc(bool, tokens.len);
        const enclosed = try allocator.alloc(bool, tokens.len);
        @memset(handled, false);
        @memset(enclosed, false);
        // Visit parents before children. Break the weakest operator chain first;
        // a nested stronger expression gets its own group only if still too wide.
        var raw = tree.nodes.len;
        while (raw != 0) {
            raw -= 1;
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            if (operationPriority(tree.tag(node)) == null) continue;
            const operator = @intFromEnum(tree.mainToken(node));
            if (handled[operator]) continue;
            const span = expressionSpan(&tree, node, tokens, layout);
            const offset = tokens.locations[span.first].offset;
            const line_begin = if (std.mem.lastIndexOfScalar(u8, source[0..offset], '\n')) |newline| newline + 1 else 0;
            var indent: usize = 0;
            while (line_begin + indent < source.len and source[line_begin + indent] == ' ') indent += 1;
            const prefix = if (enclosed[operator]) indent + 4 else offset - line_begin;
            const manual = (operator != 0 and tokens.contents[operator - 1] == .new_line) or tokens.contents[operator + 1] == .new_line;
            if (prefix + flatLength(tokens, source, span.first, span.last + 1) <= line_width and !manual) continue;
            const grouped = layout.scalar_groups[span.first] and layout.ends[span.first] == span.last;
            if (enclosed[operator] and !grouped and prefix + flatLength(tokens, source, span.first, span.last + 1) <= line_width) {
                markOperatorChain(&tree, node, node, tokens, &layout, handled);
                continue;
            }
            if (grouped) {
                layout.expand[span.first] = true;
            } else {
                layout.wrap_before[span.first] += 1;
                layout.wrap_after[span.last] += 1;
            }
            @memset(enclosed[span.first .. span.last + 1], true);
            markOperatorChain(&tree, node, node, tokens, &layout, handled);
        }
        return layout;
    }
};

const ExpressionSpan = struct { first: usize, last: usize };

fn operationPriority(tag: syn.Node.Tag) ?u8 {
    return switch (tag) {
        .unwrap_or => 0,
        .logical_or => 1,
        .logical_and => 2,
        .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal => 3,
        .binary_add, .binary_subtract => 4,
        .binary_multiply, .binary_divide, .binary_modulo => 5,
        .pipe_expression => 6,
        else => null,
    };
}

fn expressionSpan(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex, tokens: tok.View, layout: Layout) ExpressionSpan {
    var first = firstToken(tree, node);
    var last: usize = @intFromEnum(tree.mainToken(node));
    if (tree.literal(node)) |literal| {
        last = @intFromEnum(literal.token);
    } else if (tree.binaryOperation(node)) |binary| {
        last = @max(last, expressionSpan(tree, binary.rhs, tokens, layout).last);
        if (tree.tag(node) == .index_access) last = layout.ends[@intFromEnum(tree.mainToken(node))];
    } else if (tree.unaryOperand(node)) |child| {
        last = @max(last, expressionSpan(tree, child, tokens, layout).last);
    } else if (tree.functionCall(node)) |call| {
        last = layout.ends[@intFromEnum(tree.mainToken(call.input))];
    } else if (tree.structFieldAccess(node)) |access| {
        last = @intFromEnum(access.field_token);
    } else if (tree.choicePayloadAccess(node)) |access| {
        last = @intFromEnum(access.variant_token);
    } else if (tree.choiceLiteral(node)) |choice| {
        last = @intFromEnum(choice.name_token);
        if (choice.payload) |payload| last = expressionSpan(tree, payload, tokens, layout).last;
    } else if (tokens.contents[last] == .open_parenthesis or tokens.contents[last] == .open_brace or tokens.contents[last] == .open_bracket) {
        last = layout.ends[last];
    }
    // Scalar brackets are transparent in the syntax tree, but their original
    // boundaries still belong to the operand being laid out.
    while (true) {
        var cursor = first;
        while (cursor != 0 and (tokens.contents[cursor - 1] == .new_line or tokens.contents[cursor - 1] == .comment)) cursor -= 1;
        if (cursor == 0 or !layout.scalar_groups[cursor - 1]) break;
        const close = layout.ends[cursor - 1];
        if (close > last) {
            var after = last + 1;
            while (after < tokens.len and (tokens.contents[after] == .new_line or tokens.contents[after] == .comment)) after += 1;
            if (after != close) break;
            last = close;
        }
        first = cursor - 1;
    }
    while (true) {
        var cursor = last + 1;
        while (cursor < tokens.len and (tokens.contents[cursor] == .new_line or tokens.contents[cursor] == .comment)) cursor += 1;
        if (cursor >= tokens.len or tokens.contents[cursor] != .close_bracket or layout.ends[cursor] < first or !layout.scalar_groups[layout.ends[cursor]]) break;
        last = cursor;
    }
    return .{ .first = first, .last = last };
}

fn markOperatorChain(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex, root: syn.NodeIndex, tokens: tok.View, layout: *Layout, handled: []bool) void {
    if (operationPriority(tree.tag(node)) != operationPriority(tree.tag(root))) return;
    const span = expressionSpan(tree, node, tokens, layout.*);
    if (node != root and layout.scalar_groups[span.first] and layout.ends[span.first] == span.last) return;
    const operator = @intFromEnum(tree.mainToken(node));
    handled[operator] = true;
    layout.breaks[operator] = @max(layout.breaks[operator], 1);
    // Move a plain trailing-operator break to the operator's leading side.
    // A comment after the operator remains attached to that original line.
    var cursor = operator + 1;
    while (tokens.contents[cursor] == .new_line) cursor += 1;
    if (tokens.contents[cursor] != .comment) {
        for (operator + 1..cursor) |newline| layout.suppress_newlines[newline] = true;
        if (cursor > operator + 2) layout.breaks[operator] = @max(layout.breaks[operator], 2);
    }
    const binary = tree.binaryOperation(node).?;
    markOperatorChain(tree, binary.lhs, root, tokens, layout, handled);
    markOperatorChain(tree, binary.rhs, root, tokens, layout, handled);
}

fn isGlobalDeclaration(tag: syn.Node.Tag) bool {
    return switch (tag) {
        .function_declaration, .function_declaration_once, .test_declaration, .c_function_pointer_declaration, .type_declaration, .abstract_declaration, .c_enum_declaration, .c_union_declaration, .c_struct_declaration, .c_incomplete_declaration => true,
        else => false,
    };
}

fn firstToken(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex) usize {
    var first: usize = @intFromEnum(tree.mainToken(node));
    if (tree.tag(node) == .assume_statement and first != 0) return first - 1;
    if (tree.functionCall(node)) |call| if (call.module_qualifier) |qualifier| {
        return @min(first, @intFromEnum(qualifier));
    };
    if (tree.functionDeclaration(node)) |function| {
        if (function.constructor_type orelse function.destructor_type) |receiver| first = @intFromEnum(receiver);
        if (function.is_once and first != 0) first -= 1;
        return first;
    }
    const child: ?syn.NodeIndex = switch (tree.tag(node)) {
        .expression_statement, .error_propagation, .nullable_test, .dereference => tree.unaryOperand(node),
        .struct_field_access => tree.structFieldAccess(node).?.value,
        .choice_payload_access => tree.choicePayloadAccess(node).?.value,
        .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo, .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal, .logical_and, .logical_or, .pipe_expression, .index_access, .index_assignment, .pointer_assignment, .error_context, .unwrap_or, .unwrap_or_do => tree.binaryOperation(node).?.lhs,
        else => null,
    };
    if (child) |value| first = @min(first, firstToken(tree, value));
    return first;
}

fn flatLength(tokens: tok.View, source: []const u8, start: usize, end: usize) usize {
    var length: usize = 0;
    var previous: ?Tag = null;
    for (start..@min(end, tokens.len)) |i| {
        const tag = std.meta.activeTag(tokens.contents[i]);
        if (tag == .new_line or tag == .eof) continue;
        if (previous) |left| if (needsSpace(left, tag, tokens, i)) {
            length += 1;
        };
        length += tokenText(tokens, source, i).len;
        previous = tag;
    }
    return length;
}

fn tokenText(tokens: tok.View, source: []const u8, index: usize) []const u8 {
    const start: usize = tokens.locations[index].offset;
    const end: usize = if (index + 1 < tokens.len) tokens.locations[index + 1].offset else source.len;
    return std.mem.trimEnd(u8, source[start..end], " \t\r\n");
}

fn trimSpaces(out: *List) void {
    while (out.items.len != 0 and (out.items[out.items.len - 1] == ' ' or out.items[out.items.len - 1] == '\t')) _ = out.pop();
}

fn containsNewline(tokens: tok.View, start: usize) bool {
    var depth: usize = 0;
    for (tokens.contents[start..]) |content| switch (content) {
        .open_parenthesis, .open_bracket, .open_brace => depth += 1,
        .close_parenthesis, .close_bracket, .close_brace => {
            depth -= 1;
            if (depth == 0) return false;
        },
        .new_line => return true,
        else => {},
    };
    return false;
}

fn operandEnd(tag: Tag) bool {
    return switch (tag) {
        .identifier, .literal, .close_parenthesis, .close_bracket, .ampersand, .bang => true,
        else => false,
    };
}

fn needsSpace(left: Tag, right: Tag, tokens: tok.View, index: usize) bool {
    if (right == .comment) return true;
    if (right == .comma or right == .close_parenthesis or right == .close_bracket) return false;
    if (left == .comma) return true;
    if (right == .dot or right == .hash or right == .bang or right == .double_bang) return false;
    if (left == .dot or left == .double_dot or left == .hash or left == .dollar or left == .tilde or left == .question_mark) return false;
    if (left == .open_parenthesis or left == .open_bracket) return false;
    if (right == .double_colon) return true;
    if (right == .colon) return index + 1 < tokens.len and tokens.contents[index + 1] == .equal;
    if ((left == .colon or left == .double_colon) and right == .equal) return false;
    if (right == .ampersand) return !operandEnd(left) and left != .dollar;
    if (left == .ampersand) return false;
    if (left == .close_bracket and right == .identifier) return false;
    if (right == .open_parenthesis) return left != .identifier and left != .close_parenthesis and left != .close_bracket;
    if (right == .open_bracket) return !operandEnd(left);
    if (left == .open_brace and right == .close_brace) return false;
    if (left == .binary_operator and index >= 2 and !operandEnd(std.meta.activeTag(tokens.contents[index - 2]))) return false;
    return true;
}

const Field = struct { indent: usize, name_end: usize, marker_end: usize, equal: ?usize };
fn field(line: []const u8) ?Field {
    const trimmed = std.mem.trimStart(u8, line, " ");
    if (trimmed.len < 2 or trimmed[0] != '.' or trimmed[1] == '.') return null;
    const indent = line.len - trimmed.len;
    var end = indent + 1;
    while (end < line.len and (std.ascii.isAlphanumeric(line[end]) or line[end] == '_')) end += 1;
    if (end == indent + 1) return null;
    var marker = end;
    while (marker < line.len and line[marker] == ' ') marker += 1;
    if (marker >= line.len or (line[marker] != ':' and line[marker] != '=')) return null;
    var marker_end = marker + 1;
    if (line[marker] == ':' and marker_end < line.len and line[marker_end] == ':') marker_end += 1;
    if (marker_end < line.len and line[marker_end] == '=') marker_end += 1;
    // Only align a field's top-level default, never equals inside its type.
    var depth: usize = 0;
    var equal: ?usize = null;
    var quote: ?u8 = null;
    var escaped = false;
    for (line[marker_end..], marker_end..) |ch, i| {
        if (quote) |q| {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == q) {
                quote = null;
            }
            continue;
        }
        if (ch == '"' or ch == '\'') {
            quote = ch;
            continue;
        }
        if (ch == '(' or ch == '[' or ch == '{') depth += 1;
        if (ch == ')' or ch == ']' or ch == '}') {
            if (depth == 0) break;
            depth -= 1;
        }
        if (ch == '=' and depth == 0) {
            equal = i;
            break;
        }
        if (ch == '-' and i + 1 < line.len and line[i + 1] == '-') break;
    }
    return .{ .indent = indent, .name_end = end, .marker_end = marker_end, .equal = equal };
}

fn alignFields(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var lines = std.array_list.Managed([]const u8).init(allocator);
    defer lines.deinit();
    var split = std.mem.splitScalar(u8, source, '\n');
    while (split.next()) |line| try lines.append(line);
    const literal_lines = try allocator.alloc(bool, lines.items.len);
    defer allocator.free(literal_lines);
    var quote: ?u8 = null;
    var escaped = false;
    for (lines.items, 0..) |line, index| {
        literal_lines[index] = quote != null;
        for (line, 0..) |ch, column| {
            if (quote) |q| {
                if (escaped) escaped = false else if (ch == '\\') escaped = true else if (ch == q) quote = null;
            } else if (ch == '"' or ch == '\'') {
                quote = ch;
            } else if (ch == '-' and column + 1 < line.len and line[column + 1] == '-') break;
        }
        literal_lines[index] = literal_lines[index] or quote != null;
        escaped = false;
    }
    var out = List.init(allocator);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < lines.items.len) {
        const first = (if (literal_lines[i]) null else field(lines.items[i])) orelse {
            try out.appendSlice(lines.items[i]);
            if (i + 1 < lines.items.len) try out.append('\n');
            i += 1;
            continue;
        };
        var end = i;
        var name_width: usize = 0;
        var type_width: usize = 0;
        while (end < lines.items.len) : (end += 1) {
            if (literal_lines[end]) break;
            const row = field(lines.items[end]) orelse break;
            if (row.indent != first.indent) break;
            name_width = @max(name_width, row.name_end - row.indent);
            const type_end = row.equal orelse lines.items[end].len;
            type_width = @max(type_width, std.mem.trim(u8, lines.items[end][row.marker_end..type_end], " ").len);
        }
        for (lines.items[i..end]) |line| {
            const row = field(line).?;
            var marker = row.name_end;
            while (line[marker] == ' ') marker += 1;
            try out.appendSlice(line[0..row.name_end]);
            try out.appendNTimes(' ', name_width - (row.name_end - row.indent) + 1);
            try out.appendSlice(line[marker..row.marker_end]);
            const type_end = row.equal orelse line.len;
            const type_text = std.mem.trimStart(u8, line[row.marker_end..type_end], " ");
            if (type_text.len != 0) {
                try out.append(' ');
                try out.appendSlice(std.mem.trimEnd(u8, type_text, " "));
            }
            if (row.equal) |equal| {
                try out.appendNTimes(' ', type_width - std.mem.trim(u8, type_text, " ").len + 1);
                try out.appendSlice(line[equal..]);
            }
            try out.append('\n');
        }
        i = end;
    }
    return out.toOwnedSlice();
}

fn expectFormat(source: []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    const result = try format(allocator, source);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(expected, result);
    const repeated = try format(allocator, result);
    defer allocator.free(repeated);
    try std.testing.expectEqualStrings(result, repeated);
}

test "formatter preserves manual layout and aligns multiline fields" {
    try expectFormat(
        "Point:Type=(\n.x:Int32=1\n.long_name:UInt8=2\n)\nmain()->(.status_code:Int32=0):={ status_code=1 }\n",
        "Point: Type = (\n    .x         : Int32 = 1\n    .long_name : UInt8 = 2\n)\n\nmain() -> (.status_code: Int32 = 0) := { status_code = 1 }\n",
    );
}

test "formatter preserves comments literals grouping and target branches" {
    try expectFormat(
        "\n\n#if target_os(\"linux\") {\n-- keep  these spaces\nvalue::Int32=[2+3]*4\ntext:=\"a  b\\n\"\n}\n\n\n",
        "#if target_os(\"linux\") {\n    -- keep  these spaces\n    value :: Int32 = [2 + 3] * 4\n    text := \"a  b\\n\"\n}\n",
    );
}

test "formatter keeps list breaks and separates field groups" {
    try expectFormat(
        "x:Type=(\n.a:Int8\n\n-- group\n.long:Int64\n.b:UInt8\n)\nf(.x=1,.y=-2)\n",
        "x: Type = (\n    .a : Int8\n\n    -- group\n    .long : Int64\n    .b    : UInt8\n)\n\nf(.x = 1, .y = -2)\n",
    );
}

test "formatter rejects damaged delimiters" {
    try std.testing.expectError(error.UnbalancedDelimiters, format(std.testing.allocator, "main(]"));
}

test "formatter is idempotent across core and feature sources" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "core", "more", "tests/feature_tests" }) |root| {
        var dir = try std.Io.Dir.cwd().openDir(std.testing.io, root, .{ .iterate = true });
        defer dir.close(std.testing.io);
        var walker = try dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next(std.testing.io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".rg")) continue;
            const source = try dir.readFileAlloc(std.testing.io, entry.path, allocator, .limited(4 * 1024 * 1024));
            defer allocator.free(source);
            const first = format(allocator, source) catch |err| switch (err) {
                error.UnknownCharacter, error.InvalidSource, error.UnbalancedDelimiters => continue,
                else => {
                    std.debug.print("formatter failed for {s}/{s}: {s}\n", .{ root, entry.path, @errorName(err) });
                    return err;
                },
            };
            defer allocator.free(first);
            const second = try format(allocator, first);
            defer allocator.free(second);
            expectSameSyntax(allocator, source, first) catch |err| {
                std.debug.print("formatter changes syntax for {s}/{s}\n", .{ root, entry.path });
                return err;
            };
            if (!std.mem.eql(u8, first, second)) {
                std.debug.print("formatter is unstable for {s}/{s}\n", .{ root, entry.path });
                return error.UnstableFormat;
            }
        }
    }
}

test "formatter preserves field-like text inside multiline strings" {
    try expectFormat("text:=\"first\n.fake:Int32= 1\n\"\n", "text := \"first\n.fake:Int32= 1\n\"\n");
}

test "formatter expands complete long signature groups" {
    try expectFormat(
        "add#(.n:UIntNative,.t:Type:Scalar)(.left:&Vector#(.n=n,.t:t),.right:&Vector#(.n=n,.t:t))->(.result:Vector#(.n=n,.t:t)):={ result=left }\n",
        "add#(\n        .n : UIntNative,\n        .t : Type: Scalar\n    )(\n        .left  : &Vector#(.n = n, .t: t),\n        .right : &Vector#(.n = n, .t: t)\n    ) -> (\n        .result : Vector#(.n = n, .t: t)\n    ) := { result = left }\n",
    );
}

test "formatter retains short signatures and expands multiple statements" {
    try expectFormat(
        "Counter:Type=(.value:Int32)\nbump(.self:$&Counter)->():={self&.value=self&.value+1}\nrun()->():={i::UIntNative=0 while i<2 {values[i]=values[i]+1 i=i+1} return}\n",
        "Counter: Type = (.value: Int32)\n\nbump(.self: $&Counter) -> () := { self&.value = self&.value + 1 }\n\nrun() -> () := {\n    i :: UIntNative = 0\n    while i < 2 {\n        values[i] = values[i] + 1\n        i = i + 1\n    }\n    return\n}\n",
    );
}

test "formatter keeps declaration comments attached and manual blank lines" {
    try expectFormat(
        "First:Type=()\n-- documentation\nSecond:Type=()\nf()->():={\n\nreturn\n\n}\n",
        "First: Type = ()\n\n-- documentation\nSecond: Type = ()\n\nf() -> () := {\n\n    return\n\n}\n",
    );
}

test "formatter expands long calls into complete argument rows" {
    try expectFormat(
        "result:=operation(.first_argument=\"abcdefghijklmnopqrstuvwxyz0123456789\",.second_argument=\"abcdefghijklmnopqrstuvwxyz0123456789\")\n",
        "result := operation(\n    .first_argument  = \"abcdefghijklmnopqrstuvwxyz0123456789\"\n    .second_argument = \"abcdefghijklmnopqrstuvwxyz0123456789\"\n)\n",
    );
}

fn testSyntaxTree(allocator: std.mem.Allocator, source: []const u8) !?syn.FileSyntaxTree {
    const files = [_]source_files.SourceFile{.{ .path = "format.rg", .code = source }};
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();
    var lex = tokenizer.Tokenizer.init(allocator, &diagnostics, source, diagnostics.source_db.fileId(0));
    const tokens = try lex.tokenize();
    var parser = try syntaxer.Syntaxer.init(allocator, tokens, source, &diagnostics);
    defer parser.deinit();
    return parser.parse() catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => null,
    };
}

fn expectSameSyntax(allocator: std.mem.Allocator, source: []const u8, formatted: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temporary = arena.allocator();
    var original = (try testSyntaxTree(temporary, source)) orelse return;
    defer original.deinit(temporary);
    var result = (try testSyntaxTree(temporary, formatted)) orelse return error.FormattedSyntaxInvalid;
    defer result.deinit(temporary);
    try std.testing.expectEqual(original.roots.len, result.roots.len);
    try std.testing.expectEqualSlices(syn.Node.Tag, original.nodes.items(.tag), result.nodes.items(.tag));
}

test "formatter preserves prefixes and grouping at statement boundaries" {
    try expectFormat(
        "f()->():={assume allocator:=source mod.write(.value=1)!!\"context\"\n[values[index]]=2 return}\n",
        "f() -> () := {\n    assume allocator := source\n    mod.write(.value = 1)!! \"context\"\n    [values[index]] = 2\n    return\n}\n",
    );
}

test "formatter separates associated lifecycle declarations before their prefixes" {
    try expectFormat(
        "Point:Type=(.value:Int32)\nonce Point init(.value:Int32)->(.result:Point):={result=(.value=value)}\nPoint deinit(.self:$&Point)->():={}\n",
        "Point: Type = (.value: Int32)\n\nonce Point init(.value: Int32) -> (.result: Point) := { result = (.value = value) }\n\nPoint deinit(.self: $&Point) -> () := {}\n",
    );
}

test "formatter retains trailing comments when separating declarations" {
    try expectFormat(
        "First:Type=() -- trailing\n-- second documentation\nSecond:Type=()\n",
        "First: Type = () -- trailing\n\n-- second documentation\nSecond: Type = ()\n",
    );
}

test "formatter wraps long operations with leading operators" {
    try expectFormat(
        "result:=base_amount+additional_service_charge+international_delivery_cost-loyalty_discount-promotional_discount\n",
        "result := [\n    base_amount\n    + additional_service_charge\n    + international_delivery_cost\n    - loyalty_discount\n    - promotional_discount\n]\n",
    );
}

test "formatter moves trailing operator breaks to their leading side" {
    try expectFormat(
        "result := [first +\nsecond -\nthird]\n",
        "result := [\n    first\n    + second\n    - third\n]\n",
    );
}

test "formatter keeps products compact when breaking an additive expression" {
    try expectFormat(
        "result:=first_long_operand*second_long_operand+third_long_operand*fourth_long_operand+fifth_long_operand\n",
        "result := [\n    first_long_operand * second_long_operand\n    + third_long_operand * fourth_long_operand\n    + fifth_long_operand\n]\n",
    );
}

test "formatter preserves signed literals in multiline conditions" {
    const source = "condition:=first_record.nested_payload.repeated_field_name!=-42 or second_record.nested_payload.repeated_field_name!=-7\n";
    const result = try format(std.testing.allocator, source);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "!= -42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "!= -7") != null);
    try expectSameSyntax(std.testing.allocator, source, result);
}

test "formatter omits commas in multiline struct literals" {
    try expectFormat(
        "value := (\n.first = 1,\n.second = 2,\n)\n",
        "value := (\n    .first  = 1\n    .second = 2\n)\n",
    );
}

test "formatter retains inline struct commas and nested inline separators" {
    try expectFormat(
        "value:=(.first=1,.second=2)\n",
        "value := (.first = 1, .second = 2)\n",
    );
    try expectFormat(
        "value := (\n.outer = (.first = 1, .second = 2), -- outer comment\n.other = 3,\n)\n",
        "value := (\n    .outer = (.first = 1, .second = 2) -- outer comment\n    .other = 3\n)\n",
    );
}

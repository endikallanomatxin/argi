const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const syntaxer = @import("syntaxer.zig");
const syn = @import("syntax_tree.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");

const Tag = std.meta.Tag(tok.Content);
const List = std.array_list.Managed(u8);
const Frame = struct { tag: Tag, multiline: bool, expand: bool = false, hanging: bool = false, reflow: bool = false, comma_free: bool = false };
const line_width = 96;
const max_alignment_padding = 24;
const InsertedToken = struct { ordinal: usize, tag: Tag };

/// Formatting uses the complete token stream, including discarded target
/// branches. Syntaxing identifies function groups and statement boundaries.
/// Calls and signature groups reflow against the emitted 96-column budget;
/// comments and expression-level breaks retain their syntax-significant layout.
/// Token text stays verbatim: comments, escapes, and numeric spellings are never
/// rebuilt. Added separators/grouping brackets and removed multiline separators
/// are tracked explicitly and verified against the original syntax structure
/// before an edit is returned.
pub fn format(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var current = try formatOnce(allocator, source);
    errdefer allocator.free(current);
    // Alignment can expose a line break, whose indentation in turn changes
    // the field group. Require a fixed point before publishing the edit.
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
    var line_alignment_padding: usize = 0;
    var pending_newlines: usize = 0;
    var source_newlines: usize = 0;
    for (0..tokens.len) |i| {
        const tag = layout.delimiterTag(tokens, i);
        if (tag == .eof) break;
        if (tag == .new_line) {
            if (layout.suppress_newlines[i]) continue;
            if (stack.items.len != 0 and stack.items[stack.items.len - 1].reflow and previous != .comment) continue;
            source_newlines += 1;
            continue;
        }
        if (layout.item_start[i] and stack.items.len != 0) {
            const frame = stack.items[stack.items.len - 1];
            if (frame.reflow and frame.tag == .open_parenthesis and previous != .open_parenthesis) {
                if (frame.expand and !frame.hanging) {
                    pending_newlines = @max(pending_newlines, 1);
                } else if (previous != .comma) {
                    trimSpaces(&out);
                    try inserted.append(.{ .ordinal = emitted_tokens, .tag = .comma });
                    emitted_tokens += 1;
                    try out.append(',');
                    previous = .comma;
                }
            }
        }
        if (tag == .comma and stack.items.len != 0) {
            const frame = stack.items[stack.items.len - 1];
            var next = i + 1;
            while (next < tokens.len and tokens.contents[next] == .new_line) : (next += 1) {}
            if (frame.reflow and (!frame.expand or frame.hanging) and layout.delimiterTag(tokens, next) == .close_parenthesis) {
                removed[i] = true;
                continue;
            }
            if (frame.expand and !frame.hanging and frame.comma_free) {
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
        if (layout.join_before[i] and previous != .comment) source_newlines = 0;
        pending_newlines = @max(pending_newlines, @max(source_newlines, layout.breaks[i]));
        source_newlines = 0;
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
            }
        }
        if (pending_newlines != 0) {
            if (out.items.len != 0) {
                trimSpaces(&out);
                try out.append('\n');
                if (pending_newlines > 1) try out.append('\n');
            }
            line_start = out.items.len;
            line_alignment_padding = 0;
            pending_newlines = 0;
            previous = null;
        }
        if (previous == null) {
            if (layout.item_start[i] and !(stack.items.len != 0 and stack.items[stack.items.len - 1].hanging))
                line_alignment_padding = layout.item_padding[i];
            var indent: usize = 0;
            for (stack.items) |frame| if (frame.multiline) {
                indent += 4;
            };
            try out.appendNTimes(' ', indent);
        } else if (!layout.tight_before[i] and (layout.space_before[i] or needsSpace(previous.?, tag, tokens, i) or (previous.? == .binary_operator and i != 0 and layout.breaks[i - 1] != 0))) try out.append(' ');
        const start: usize = tokens.locations[i].offset;
        const end: usize = if (i + 1 < tokens.len) tokens.locations[i + 1].offset else source.len;
        const text = std.mem.trimEnd(u8, source[start..end], " \t\r\n");
        try out.appendSlice(text);
        emitted_tokens += 1;
        previous = tag;
        if (tag == .open_parenthesis or tag == .open_bracket or tag == .open_brace) {
            const reflow = layout.reflow[i] and canFlatten(tokens, source, i, layout);
            const multiline = for (tokens.contents[i..][0 .. layout.ends[i] - i]) |content| {
                if (content == .new_line) break true;
            } else false;
            const expand = if (reflow)
                layout.table_rows[i] or out.items.len - line_start - 1 + line_alignment_padding + layout.chain_suffix[i] + compactLength(tokens, source, i, layout.ends[i] + 1, layout) > line_width
            else
                layout.expand[i] or ((tag == .open_parenthesis or (tag == .open_bracket and layout.scalar_groups[i])) and multiline) or (tag != .open_bracket and
                    layout.ends[i] > i + 1 and
                    out.items.len - line_start + flatLength(tokens, source, i, layout.ends[i] + 1) > line_width);
            var continuation_indent: usize = 4;
            for (stack.items) |frame| if (frame.multiline) {
                continuation_indent += 4;
            };
            // A hanging group keeps its arguments together on a fresh line.
            // The closing delimiter and any suffix resume on the next line.
            const hanging = !layout.table_rows[i] and tag == .open_parenthesis and reflow and expand and continuation_indent + compactLength(tokens, source, i, layout.ends[i] + 1, layout) - 2 <= line_width;
            try stack.append(.{ .tag = tag, .multiline = if (reflow) expand else multiline or expand, .expand = expand, .hanging = hanging, .reflow = reflow, .comma_free = layout.struct_literals[i] });
            if (expand) pending_newlines = 1;
        }
        // Expanded collections use complete rows rather than spilling only
        // the last argument onto a continuation line.
        if (tag == .comma and stack.items.len != 0 and stack.items[stack.items.len - 1].expand and !stack.items[stack.items.len - 1].hanging and stack.items[stack.items.len - 1].tag == .open_parenthesis)
            pending_newlines = @max(pending_newlines, 1);
        for (0..layout.wrap_after[i]) |_| {
            const frame = stack.pop().?;
            std.debug.assert(frame.tag == .open_bracket);
            trimSpaces(&out);
            try out.append('\n');
            line_start = out.items.len;
            line_alignment_padding = 0;
            var indent: usize = 0;
            for (stack.items) |enclosing| if (enclosing.multiline) {
                indent += 4;
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
    angle_delimiters: []i8,
    breaks: []u8,
    expand: []bool,
    reflow: []bool,
    table_rows: []bool,
    chain_suffix: []usize,
    item_start: []bool,
    item_padding: []usize,
    group: []bool,
    join_before: []bool,
    wrap_before: []u16,
    wrap_after: []u16,
    suppress_newlines: []bool,
    scalar_groups: []bool,
    struct_literals: []bool,
    space_before: []bool,
    tight_before: []bool,
    syntax_tags: ?[]const syn.Node.Tag = null,
    root_count: usize = 0,

    fn delimiterTag(self: Layout, tokens: tok.View, index: usize) Tag {
        return switch (self.angle_delimiters[index]) {
            1 => .open_parenthesis,
            -1 => .close_parenthesis,
            else => std.meta.activeTag(tokens.contents[index]),
        };
    }

    /// Angle groups are identified by syntax, never guessed from comparisons.
    /// Normal nested delimiters are already paired in ends.
    fn markAngleGroup(self: *Layout, tokens: tok.View, open: usize, application: bool) void {
        if (tokens.contents[open] != .comparison_operator or tokens.contents[open].comparison_operator != .less_than) return;
        self.tight_before[open] = application;
        var depth: usize = 1;
        var cursor = open + 1;
        var first = true;
        while (cursor < tokens.len) : (cursor += 1) {
            const token = tokens.contents[cursor];
            if (token == .new_line or token == .comment) continue;
            if (first) {
                self.tight_before[cursor] = true;
                first = false;
            }
            if (token == .open_parenthesis or token == .open_bracket or token == .open_brace) {
                cursor = self.ends[cursor];
                continue;
            }
            if (token != .comparison_operator) continue;
            switch (token.comparison_operator) {
                .less_than => depth += 1,
                .greater_than, .greater_than_or_equal => {
                    depth -= 1;
                    if (depth != 0) continue;
                    self.tight_before[cursor] = true;
                    // A combined >= token also carries assignment syntax and
                    // cannot be moved as an independent closing delimiter.
                    if (token.comparison_operator == .greater_than) {
                        self.ends[open] = cursor;
                        self.ends[cursor] = open;
                        self.angle_delimiters[open] = 1;
                        self.angle_delimiters[cursor] = -1;
                        self.reflow[open] = true;
                    }
                    var following = cursor + 1;
                    while (following < tokens.len and tokens.contents[following] == .new_line) : (following += 1) {}
                    if (following < tokens.len and tokens.contents[following] == .open_parenthesis and token.comparison_operator == .greater_than) {
                        self.tight_before[following] = application;
                        self.space_before[following] = !application;
                    }
                    return;
                },
                else => {},
            }
        }
    }

    fn markSignature(self: *Layout, tree: *const syn.FileSyntaxTree, tokens: tok.View, parameters: ?syn.NodeIndex, input: syn.NodeIndex, output: syn.NodeIndex) void {
        const groups = [_]?syn.NodeIndex{ parameters, input, output };
        for (groups) |group| if (group) |value| {
            const open = @intFromEnum(tree.mainToken(value));
            if (tokens.contents[open] == .open_parenthesis) {
                self.reflow[open] = true;
                self.join_before[open] = true;
            }
        };
        const input_open = @intFromEnum(tree.mainToken(input));
        const output_open = @intFromEnum(tree.mainToken(output));
        const input_end = self.ends[input_open];
        if (input_end < output_open) {
            for (input_end + 1..output_open) |index| {
                if (tokens.contents[index] == .arrow) self.join_before[index] = true;
            }
        }
    }

    fn init(allocator: std.mem.Allocator, tokens: tok.View, source: []const u8) !Layout {
        var layout: Layout = .{
            .ends = try allocator.alloc(usize, tokens.len),
            .angle_delimiters = try allocator.alloc(i8, tokens.len),
            .breaks = try allocator.alloc(u8, tokens.len),
            .expand = try allocator.alloc(bool, tokens.len),
            .reflow = try allocator.alloc(bool, tokens.len),
            .table_rows = try allocator.alloc(bool, tokens.len),
            .chain_suffix = try allocator.alloc(usize, tokens.len),
            .item_start = try allocator.alloc(bool, tokens.len),
            .item_padding = try allocator.alloc(usize, tokens.len),
            .group = try allocator.alloc(bool, tokens.len),
            .join_before = try allocator.alloc(bool, tokens.len),
            .wrap_before = try allocator.alloc(u16, tokens.len),
            .wrap_after = try allocator.alloc(u16, tokens.len),
            .suppress_newlines = try allocator.alloc(bool, tokens.len),
            .scalar_groups = try allocator.alloc(bool, tokens.len),
            .struct_literals = try allocator.alloc(bool, tokens.len),
            .space_before = try allocator.alloc(bool, tokens.len),
            .tight_before = try allocator.alloc(bool, tokens.len),
        };
        @memset(layout.ends, 0);
        @memset(layout.angle_delimiters, 0);
        @memset(layout.breaks, 0);
        @memset(layout.expand, false);
        @memset(layout.reflow, false);
        @memset(layout.table_rows, false);
        @memset(layout.chain_suffix, 0);
        @memset(layout.item_start, false);
        @memset(layout.item_padding, 0);
        @memset(layout.group, false);
        @memset(layout.join_before, false);
        @memset(layout.wrap_before, 0);
        @memset(layout.wrap_after, 0);
        @memset(layout.suppress_newlines, false);
        @memset(layout.scalar_groups, false);
        @memset(layout.struct_literals, false);
        @memset(layout.space_before, false);
        @memset(layout.tight_before, false);
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
            if (tree.parameterList(node) != null or tree.specializationArguments(node) != null)
                layout.markAngleGroup(tokens, @intFromEnum(tree.mainToken(node)), tree.specializationArguments(node) != null);
            if (tree.contractConformance(node)) |conformance| {
                layout.space_before[@intFromEnum(tree.mainToken(conformance.implementation_members))] = true;
                if (conformance.generic_params_struct) |group| layout.reflow[@intFromEnum(tree.mainToken(group))] = true;
            }
            if (tree.syntaxType(node)) |ty| switch (ty) {
                .generic => |generic| {
                    const open = groupOpening(&tree, generic.arguments, tokens);
                    if (tokens.contents[open] == .open_parenthesis) layout.reflow[open] = true;
                },
                else => {},
            };

            const members: ?[]const syn.NodeIndex = if (tree.structTypeLiteral(node)) |literal|
                literal.fields
            else if (tree.parameterList(node)) |literal|
                literal.fields
            else if (tree.specializationArguments(node)) |literal|
                literal.fields
            else if (tree.structValueLiteral(node)) |literal|
                literal.fields
            else if (tree.listLiteral(node)) |literal|
                literal.elements
            else
                null;
            if (members) |items| {
                const opening = groupOpening(&tree, node, tokens);
                if (tokens.contents[opening] == .comparison_operator and layout.angle_delimiters[opening] != 1) continue;
                layout.group[opening] = true;
                // Reserve the padding a compact row would receive from its
                // siblings, even when an expanded child currently separates them.
                const widths = try allocator.alloc(?usize, items.len);
                defer allocator.free(widths);
                for (items, 0..) |item, index| widths[index] = if (memberName(&tree, item)) |name| tokenText(tokens, source, @intFromEnum(name)).len else null;
                const targets = try alignmentTargets(allocator, widths);
                defer allocator.free(targets);
                for (items, 0..) |item, index| {
                    var start = if (tree.valueField(item)) |value_field|
                        if (value_field.name_token) |name| @intFromEnum(name) else expressionSpan(&tree, value_field.value, tokens, layout).first
                    else if (tree.structTypeField(item)) |type_field|
                        if (type_field.position != null and type_field.type_node != null) firstToken(&tree, type_field.type_node.?) else firstToken(&tree, item)
                    else
                        firstToken(&tree, item);
                    if (start > 0 and tokens.contents[start - 1] == .dot) start -= 1;
                    layout.item_start[start] = true;
                    if (memberName(&tree, item)) |name|
                        layout.item_padding[start] = targets[index] - tokenText(tokens, source, @intFromEnum(name)).len;
                }
            }
            if (tree.tag(node) == .struct_value_literal) {
                layout.struct_literals[@intFromEnum(tree.mainToken(node))] = true;
            }
            if (tree.tag(node) == .index_access or tree.tag(node) == .array_type) {
                const open = @intFromEnum(tree.mainToken(node));
                if (tokens.contents[open] == .open_bracket) layout.scalar_groups[open] = false;
            }
        }
        for (tree.roots, 0..) |root, index| {
            if (index != 0 and (isGlobalDeclaration(&tree, root) or isGlobalDeclaration(&tree, tree.roots[index - 1]))) {
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
                layout.markSignature(&tree, tokens, function.generic_params_struct, function.input, function.output);
            }
            if (tree.comptimeEntry(node)) |entry| if (entry.input) |input| {
                layout.markSignature(&tree, tokens, null, input, entry.output.?);
                layout.space_before[@intFromEnum(tree.mainToken(input))] = true;
            };
            if (tree.contractFunctionRequirement(node)) |requirement| {
                layout.markSignature(&tree, tokens, requirement.generic_params_struct, requirement.input, requirement.output);
            }
            if (tree.functionCall(node)) |call| {
                layout.reflow[@intFromEnum(tree.mainToken(call.input))] = true;
                if (call.specialization_arguments) |args| layout.reflow[@intFromEnum(tree.mainToken(args))] = true;
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
        // A chain is one visual unit: once one branch needs an expanded
        // block, expand its siblings instead of mixing inline and block arms.
        for (0..tree.nodes.len) |raw| {
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw)));
            const first = tree.ifStatement(node) orelse continue;
            if (first.else_block == null) continue;
            var cursor: ?syn.NodeIndex = node;
            var expand_chain = false;
            while (cursor) |current| {
                if (tree.ifStatement(current)) |statement| {
                    expand_chain = expand_chain or blockNeedsExpansion(&tree, statement.then_block, tokens, source, layout);
                    cursor = statement.else_block;
                } else {
                    expand_chain = expand_chain or blockNeedsExpansion(&tree, current, tokens, source, layout);
                    break;
                }
            }
            if (!expand_chain) continue;
            cursor = node;
            while (cursor) |current| {
                if (tree.ifStatement(current)) |statement| {
                    layout.expand[@intFromEnum(tree.mainToken(statement.then_block))] = true;
                    cursor = statement.else_block;
                } else {
                    layout.expand[@intFromEnum(tree.mainToken(current))] = true;
                    break;
                }
            }
        }
        for (0..tokens.len) |open| {
            if (!layout.reflow[open] or tokens.contents[open] != .open_parenthesis) continue;
            for (open + 1..layout.ends[open]) |child| {
                if (layout.group[child] and tokens.contents[child] == .open_parenthesis)
                    layout.reflow[child] = true;
            }
        }
        // Keep literal tables legible even when the complete table fits inline.
        for (0..tree.nodes.len) |raw_node| {
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(raw_node)));
            const literal = tree.listLiteral(node) orelse continue;
            if (literal.elements.len < 2) continue;
            var rows = true;
            for (literal.elements) |element| {
                if (tree.listLiteral(element) == null) rows = false;
            }
            if (rows) {
                const open = @intFromEnum(tree.mainToken(node));
                layout.table_rows[open] = true;
                layout.reflow[open] = true;
                for (literal.elements) |element| layout.reflow[@intFromEnum(tree.mainToken(element))] = true;
            }
        }
        // Budget a following member call along with its receiver's arguments.
        for (0..tokens.len) |open| {
            if (!layout.reflow[open] or tokens.contents[open] != .open_parenthesis) continue;
            const close = layout.ends[open];
            var end = close + 1;
            while (end < tokens.len and tokens.contents[end] == .dot) {
                if (end + 1 >= tokens.len or tokens.contents[end + 1] != .identifier) break;
                end += 2;
                while (end < tokens.len) {
                    if (tokens.contents[end] == .hash) {
                        end += 1;
                        continue;
                    }
                    if (tokens.contents[end] != .open_parenthesis) break;
                    end = layout.ends[end] + 1;
                }
            }
            if (end > close + 1) layout.chain_suffix[open] = flatLength(tokens, source, close + 1, end);
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
            const grouped = layout.scalar_groups[span.first] and layout.ends[span.first] == span.last;
            if (grouped and canFlatten(tokens, source, span.first, layout) and
                prefix + flatLength(tokens, source, span.first, span.last + 1) <= line_width)
            {
                // Scalar brackets remain explicit; only their layout changes.
                // Parent grouping already fits, so its stronger children do too.
                for (span.first..span.last) |index| {
                    if (tokens.contents[index] == .open_bracket and layout.scalar_groups[index])
                        layout.reflow[index] = true;
                }
                @memset(handled[span.first .. span.last + 1], true);
                continue;
            }
            const manual = (operator != 0 and tokens.contents[operator - 1] == .new_line) or tokens.contents[operator + 1] == .new_line;
            if (prefix + flatLength(tokens, source, span.first, span.last + 1) <= line_width and !manual) continue;
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
    if (tree.tag(node) == .error_report_return_block) {
        last = layout.ends[@intFromEnum(tree.mainToken(tree.data(node).node_and_node.second))];
    } else if (tree.literal(node)) |literal| {
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

fn isGlobalDeclaration(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex) bool {
    if (tree.definitionValue(node)) |value| {
        if (tree.parameterizedDefinition(value) != null) return true;
        if (tree.functionDefinition(value) != null) return true;
        if (tree.structTypeLiteral(value) != null or tree.choiceTypeLiteral(value) != null) return true;
    }
    return switch (tree.tag(node)) {
        .test_declaration,
        .c_function_pointer_declaration,
        .contract_declaration,
        .contract_conformance,
        .c_enum_declaration,
        .c_union_declaration,
        .c_struct_declaration,
        .c_incomplete_declaration,
        => true,
        else => false,
    };
}

fn firstToken(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex) usize {
    var first: usize = @intFromEnum(tree.mainToken(node));
    if (tree.tag(node) == .assume_statement and first != 0) return first - 1;
    if (tree.functionCall(node)) |call| {
        if (call.contract_type) |contract_type| first = @min(first, firstToken(tree, contract_type));
        if (call.module_qualifier) |qualifier| first = @min(first, @intFromEnum(qualifier));
        return first;
    }
    if (tree.syntaxType(node)) |ty| switch (ty) {
        .name => |name| if (name.qualifier_token) |qualifier| {
            first = @min(first, @intFromEnum(qualifier));
        },
        .generic => |generic| first = @min(first, firstToken(tree, generic.base)),
        .projection => |projection| first = @min(first, firstToken(tree, projection.base)),
        else => {},
    };
    if (tree.functionDeclaration(node)) |function| {
        if (function.is_once and first != 0) first -= 1;
        return first;
    }
    const child: ?syn.NodeIndex = switch (tree.tag(node)) {
        .expression_statement, .error_propagation, .error_report_return, .error_report_return_block, .nullable_test, .dereference => tree.unaryOperand(node),
        .handle_expression => tree.extraData(syn.HandleExtra, tree.data(node).extra).value,
        .struct_field_access => tree.structFieldAccess(node).?.value,
        .choice_payload_access => tree.choicePayloadAccess(node).?.value,
        .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo, .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal, .logical_and, .logical_or, .pipe_expression, .index_access, .index_assignment, .pointer_assignment, .error_context, .unwrap_or, .unwrap_or_do => tree.binaryOperation(node).?.lhs,
        else => null,
    };
    if (child) |value| first = @min(first, firstToken(tree, value));
    return first;
}

fn blockNeedsExpansion(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex, tokens: tok.View, source: []const u8, layout: Layout) bool {
    const open = @intFromEnum(tree.mainToken(node));
    if (tree.codeBlock(node) == null or tokens.contents[open] != .open_brace) return false;
    if (layout.expand[open] or containsNewline(tokens, open)) return true;
    const offset = tokens.locations[open].offset;
    const start = if (std.mem.lastIndexOfScalar(u8, source[0..offset], '\n')) |newline| newline + 1 else 0;
    return offset - start + flatLength(tokens, source, open, layout.ends[open] + 1) > line_width;
}

fn groupOpening(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex, tokens: tok.View) usize {
    const main = @intFromEnum(tree.mainToken(node));
    if (tokens.contents[main] == .identifier and main + 2 < tokens.len and tokens.contents[main + 1] == .hash and tokens.contents[main + 2] == .open_parenthesis) return main + 2;
    return main;
}

fn memberName(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex) ?syn.TokenIndex {
    if (tree.valueField(node)) |value| return value.name_token;
    if (tree.structTypeField(node)) |value| return value.name_token;
    if (tree.functionDeclaration(node)) |value| return value.name_token;
    if (tree.contractFunctionRequirement(node)) |value| return value.name_token;
    return null;
}

fn canFlatten(tokens: tok.View, source: []const u8, open: usize, layout: Layout) bool {
    for (open + 1..layout.ends[open]) |index| {
        if (layout.table_rows[index]) return false;
        if (tokens.contents[index] == .literal and std.mem.indexOfScalar(u8, tokenText(tokens, source, index), '\n') != null) return false;
        switch (tokens.contents[index]) {
            .comment, .open_brace, .close_brace => return false,
            .new_line => {},
            else => {},
        }
    }
    return true;
}

fn compactLength(tokens: tok.View, source: []const u8, start: usize, end: usize, layout: Layout) usize {
    var length: usize = 0;
    var previous: ?Tag = null;
    for (start..end) |index| {
        const tag = layout.delimiterTag(tokens, index);
        if (tag == .new_line) continue;
        if (tag == .comma) {
            var next = index + 1;
            while (next < end and tokens.contents[next] == .new_line) : (next += 1) {}
            if (next < end and layout.delimiterTag(tokens, next) == .close_parenthesis and layout.reflow[layout.ends[next]]) continue;
        }
        if (layout.item_start[index] and previous != .open_parenthesis and previous != .comma and previous != null) {
            length += 1;
            previous = .comma;
        }
        if (previous) |left| if (!layout.tight_before[index] and needsSpace(left, tag, tokens, index)) {
            length += 1;
        };
        length += tokenText(tokens, source, index).len;
        previous = tag;
    }
    return length;
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
    if (left == .arrow and right == .bang) return true;
    if (left == .bang and index >= 2 and tokens.contents[index - 2] == .arrow) return false;
    if (right == .semicolon) return false;
    if (left == .semicolon) return true;
    if (right == .comma or right == .close_parenthesis or right == .close_bracket) return false;
    if (left == .comma) return true;
    // A named compile-time directive starts an operand. Generic argument
    // groups instead attach '#(' to the preceding declaration/callee.
    if (right == .hash) return index + 1 < tokens.len and
        (tokens.contents[index + 1] == .identifier or tokens.contents[index + 1] == .keyword_if or tokens.contents[index + 1] == .keyword_else) and
        left != .open_parenthesis and left != .open_bracket;
    if (right == .dot or right == .bang or right == .double_bang or right == .triple_bang) return false;
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
    // Assignment members have values, not a type column. A compact function
    // value must not push associated-member defaults across the whole line.
    const assignment = line[marker] == '=';
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
        if (ch == ',' and depth == 0) {
            const remaining = std.mem.trimStart(u8, line[i + 1 ..], " ");
            // Several fields on one continuation row use compact separators,
            // rather than aligning only the first field on that row.
            if (remaining.len != 0 and !std.mem.startsWith(u8, remaining, "--")) return null;
        }
        if (ch == '=' and depth == 0 and !assignment) {
            equal = i;
            break;
        }
        if (ch == '-' and i + 1 < line.len and line[i + 1] == '-') break;
    }
    return .{ .indent = indent, .name_end = end, .marker_end = marker_end, .equal = equal };
}

/// Remove the longest outliers from a column until its padding fits, then
/// align those outliers in subsequent columns. Sorting widths keeps the
/// grouping independent of source order without moving any source rows.
fn alignmentTargets(allocator: std.mem.Allocator, widths: []const ?usize) ![]usize {
    const Entry = struct {
        width: usize,
        index: usize,
        fn less(_: void, a: @This(), b: @This()) bool {
            return a.width < b.width;
        }
    };
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(allocator);
    for (widths, 0..) |width, index| if (width) |value| try entries.append(allocator, .{ .width = value, .index = index });
    std.mem.sort(Entry, entries.items, {}, Entry.less);
    const targets = try allocator.alloc(usize, widths.len);
    @memset(targets, 0);
    var start: usize = 0;
    while (start < entries.items.len) {
        var end = start + 1;
        while (end < entries.items.len and entries.items[end].width - entries.items[start].width <= max_alignment_padding) : (end += 1) {}
        const target = entries.items[end - 1].width;
        for (entries.items[start..end]) |entry| targets[entry.index] = target;
        start = end;
    }
    return targets;
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
        while (end < lines.items.len) : (end += 1) {
            if (literal_lines[end]) break;
            const row = field(lines.items[end]) orelse break;
            if (row.indent != first.indent) break;
        }
        const widths = try allocator.alloc(?usize, end - i);
        defer allocator.free(widths);
        for (lines.items[i..end], 0..) |line, index| {
            const row = field(line).?;
            widths[index] = row.name_end - row.indent;
        }
        const names = try alignmentTargets(allocator, widths);
        defer allocator.free(names);
        // Default assignments align by their complete prefix, so different
        // name columns cannot accidentally create a second excessive gap.
        for (lines.items[i..end], 0..) |line, index| {
            const row = field(line).?;
            var marker = row.name_end;
            while (line[marker] == ' ') marker += 1;
            const type_end = row.equal orelse line.len;
            const type_len = std.mem.trim(u8, line[row.marker_end..type_end], " ").len;
            widths[index] = if (line[row.marker_end - 1] == '=') null else names[index] + 1 + row.marker_end - marker + (if (type_len == 0) @as(usize, 0) else type_len + 1);
        }
        const defaults = try alignmentTargets(allocator, widths);
        defer allocator.free(defaults);
        for (lines.items[i..end], 0..) |line, index| {
            const row = field(line).?;
            var marker = row.name_end;
            while (line[marker] == ' ') marker += 1;
            try out.appendSlice(line[0..row.name_end]);
            try out.appendNTimes(' ', names[index] - (row.name_end - row.indent) + 1);
            try out.appendSlice(line[marker..row.marker_end]);
            const type_end = row.equal orelse line.len;
            const type_text = std.mem.trimStart(u8, line[row.marker_end..type_end], " ");
            if (type_text.len != 0) {
                try out.append(' ');
                try out.appendSlice(std.mem.trimEnd(u8, type_text, " "));
            }
            if (row.equal) |equal| {
                try out.appendNTimes(' ', defaults[index] - widths[index].? + 1);
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

test "formatter expands signature groups independently" {
    try expectFormat(
        "add#(.n:UIntNative,.t:Type:Scalar)(.left:&Vector#(.n=n,.t:t),.right:&Vector#(.n=n,.t:t))->(.result:Vector#(.n=n,.t:t)):={ result=left }\n",
        "add#(.n: UIntNative, .t: Type: Scalar)(\n    .left: &Vector#(.n = n, .t: t), .right: &Vector#(.n = n, .t: t)\n) -> (.result: Vector#(.n = n, .t: t)) := { result = left }\n",
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

test "formatter preserves anonymous compile-time entry structure" {
    try expectFormat("#run{calculate()}\n", "#run { calculate() }\n");
    try expectFormat(
        "answer::=#run()->(.result:Int32){result=42}\n",
        "answer ::= #run () -> (.result: Int32) { result = 42 }\n",
    );
    try expectFormat(
        "answer::=#run(.system:System)->(.result:Int32){assume writer::=$&system.terminal&.stdout\nresult=42}\n",
        "answer ::= #run (.system: System) -> (.result: Int32) {\n    assume writer ::= $&system.terminal&.stdout\n    result = 42\n}\n",
    );
}

test "formatter preserves prefixes and grouping at statement boundaries" {
    try expectFormat(
        "f()->():={assume allocator:=source mod.write(.value=1)!!\"context\"\n[values[index]]=2 return}\n",
        "f() -> () := {\n    assume allocator := source\n    mod.write(.value = 1)!! \"context\"\n    [values[index]] = 2\n    return\n}\n",
    );
}

test "formatter separates scoped cleanup implementations from ordinary declarations" {
    try expectFormat(
        "Point:Type=(.value:Int32)\nonce acquire(.value:Int32)->(.result:Point):={result=(.value=value)}\nimplement Deinit#(Point)(.deinit=(.self:$&Point)->(){})\n",
        "Point: Type = (.value: Int32)\n\nonce acquire(.value: Int32) -> (.result: Point) := { result = (.value = value) }\n\nimplement Deinit#(Point) (.deinit = (.self: $&Point) -> () {})\n",
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

test "formatter compacts short expressions with trailing operator breaks" {
    try expectFormat(
        "result := [first +\nsecond -\nthird]\n",
        "result := [first + second - third]\n",
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

test "formatter preserves inferred fallible output defaults" {
    try expectFormat(
        "main()->!Void=..ok Void():={work()!}\n",
        "main() -> !Void = ..ok Void() := { work()! }\n",
    );
}

test "formatter preserves local error handlers" {
    try expectFormat(
        "main()->():={value:=fallible() handle error,result{result=0}}\n",
        "main() -> () := { value := fallible() handle error, result { result = 0 } }\n",
    );
    try expectFormat(
        "main()->():={fallible() handle error{report(error)!}}\n",
        "main() -> () := { fallible() handle error { report(error)! } }\n",
    );
}

test "formatter preserves reporting return postfix" {
    try expectFormat("main()->():={value:=attempt()!!!}\n", "main() -> () := { value := attempt()!!! }\n");
}

test "formatter preserves reporting return action blocks" {
    try expectFormat(
        "main()->(.status_code:Int32=0):={attempt()!!!{status_code=1}}\n",
        "main() -> (.status_code: Int32 = 0) := { attempt()!!! { status_code = 1 } }\n",
    );
    try expectFormat(
        "main()->():={if [ready()!!!{return}]{work()}}\n",
        "main() -> () := { if [ready()!!! { return }] { work() } }\n",
    );
}

test "formatter flattens calls and signatures regardless of existing breaks" {
    try expectFormat(
        "f(\n.first = 1\n.second = 2\n)\n",
        "f(.first = 1, .second = 2)\n",
    );
    try expectFormat(
        "identity#(\n.T: Type\n)(\n.value: T\n) -> (\n.result: T\n) := { result = value }\n",
        "identity#(.T: Type)(.value: T) -> (.result: T) := { result = value }\n",
    );
    try expectFormat(
        "C#(.T: Type): Contract = (\n.op: (\n.value: T\n) -> (\n.result: T\n)\n)\nimplement C#(Int32) (\n.op =\n(.value: Int32) -> (.result: Int32) { result = value }\n)\n",
        "C#(.T: Type): Contract = (\n    .op : (.value: T) -> (.result: T)\n)\n\nimplement C#(Int32) (\n    .op = (.value: Int32) -> (.result: Int32) { result = value }\n)\n",
    );
}

test "formatter retains argument comments while using four-space indentation" {
    try expectFormat(
        "f(\n.first = 1 -- explanation\n.second = 2\n)\n",
        "f(\n    .first  = 1 -- explanation\n    .second = 2\n)\n",
    );
}

test "formatter counts indentation at the call width boundary" {
    const allocator = std.testing.allocator;
    // 4 spaces + call( + a quoted argument + ) = 96 columns.
    const payload = try allocator.alloc(u8, 84);
    defer allocator.free(payload);
    @memset(payload, 'a');
    const source = try std.fmt.allocPrint(allocator, "main() -> () := {{\ncall(\n\"{s}\"\n)\n}}\n", .{payload});
    defer allocator.free(source);
    const expected = try std.fmt.allocPrint(allocator, "main() -> () := {{\n    call(\"{s}\")\n}}\n", .{payload});
    defer allocator.free(expected);
    try expectFormat(source, expected);
    const wide = try std.fmt.allocPrint(allocator, "main() -> () := {{\ncall(\"{s}a\")\n}}\n", .{payload});
    defer allocator.free(wide);
    const expanded = try std.fmt.allocPrint(allocator, "main() -> () := {{\n    call(\n        \"{s}a\"\n    )\n}}\n", .{payload});
    defer allocator.free(expanded);
    try expectFormat(wide, expanded);
}

test "formatter flattens nested comma-free call arguments" {
    try expectFormat(
        "result := outer(\n.first = inner(\n.left = 1\n.right = 2\n)\n.second = [3 + 4]\n)\n",
        "result := outer(.first = inner(.left = 1, .right = 2), .second = [3 + 4])\n",
    );
    try expectFormat(
        "identity#(\n.T: Int32\n)(\n.value = 1,\n)\n",
        "identity#(.T: Int32)(.value = 1)\n",
    );
}

test "formatter does not align associated defaults with function values" {
    try expectFormat(
        "implement C#(Int32) (\n.Result: Type = Int32\n.op = (.value: Int32) -> (.result: Int32) { result = value }\n)\n",
        "implement C#(Int32) (\n    .Result : Type = Int32\n    .op     = (.value: Int32) -> (.result: Int32) { result = value }\n)\n",
    );
}

test "formatter includes aligned member padding in the width budget" {
    const allocator = std.testing.allocator;
    const name = try allocator.alloc(u8, 70);
    defer allocator.free(name);
    @memset(name, 'T');
    const source = try std.fmt.allocPrint(
        allocator,
        "implement C#(Int32) (\n.ResultType: Type = Int32\n.op = (.value: {s}) -> (.result: Int32) {{ result = 0 }}\n)\n",
        .{name},
    );
    defer allocator.free(source);
    const result = try format(allocator, source);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "= (\n") != null);
    const repeated = try format(allocator, result);
    defer allocator.free(repeated);
    try std.testing.expectEqualStrings(result, repeated);
}

test "formatter chooses inline hanging and vertical calls at 96 columns" {
    const allocator = std.testing.allocator;
    for ([_]usize{ 10, 41, 42 }) |length| {
        const text = try allocator.alloc(u8, length);
        defer allocator.free(text);
        @memset(text, 'x');
        const source = try std.fmt.allocPrint(allocator, "main() -> () := {{\n    result := combine(\"{s}\", \"{s}\").value\n}}\n", .{ text, text });
        defer allocator.free(source);
        const expected = if (length == 10)
            try std.fmt.allocPrint(allocator, "main() -> () := {{\n    result := combine(\"{s}\", \"{s}\").value\n}}\n", .{ text, text })
        else if (length == 41)
            try std.fmt.allocPrint(allocator, "main() -> () := {{\n    result := combine(\n        \"{s}\", \"{s}\"\n    ).value\n}}\n", .{ text, text })
        else
            try std.fmt.allocPrint(allocator, "main() -> () := {{\n    result := combine(\n        \"{s}\"\n        \"{s}\"\n    ).value\n}}\n", .{ text, text });
        defer allocator.free(expected);
        try expectFormat(source, expected);
    }
}

test "formatter expands conditional chains consistently" {
    try expectFormat(
        "main() -> () := {\nif a { first() } else if b { second() third() } else { last() }\n}\n",
        "main() -> () := {\n    if a {\n        first()\n    } else if b {\n        second()\n        third()\n    } else {\n        last()\n    }\n}\n",
    );
    try expectFormat(
        "main() -> () := {\nif a { first() } else { last() }\n}\n",
        "main() -> () := {\n    if a { first() } else { last() }\n}\n",
    );
}

test "formatter bounds field name and default alignment" {
    try expectFormat(
        "T: Type = (\n.a: Int32 = 1\n.an_extremely_long_field_name: Int32 = 2\n)\n",
        "T: Type = (\n    .a : Int32 = 1\n    .an_extremely_long_field_name : Int32 = 2\n)\n",
    );
}

test "formatter permits up to 24 spaces of alignment padding" {
    const allocator = std.testing.allocator;
    const letters = "abcdefghijklmnopqrstuvwxyz";
    const spaces = "                         ";
    for ([_]usize{ 9, 24, 25 }) |padding| {
        const name = letters[0 .. padding + 1];
        const extra = if (padding <= 24) padding else 0;
        const source = try std.fmt.allocPrint(allocator, "T: Type = (\n.a: Int32 = 1\n.{s}: Int32 = 2\n)\n", .{name});
        defer allocator.free(source);
        const expected = try std.fmt.allocPrint(allocator, "T: Type = (\n    .a{s} : Int32 = 1\n    .{s} : Int32 = 2\n)\n", .{ spaces[0..extra], name });
        defer allocator.free(expected);
        try expectFormat(source, expected);

        const defaults = try std.fmt.allocPrint(allocator, "T: Type = (\n.a: A = 1\n.b: {s} = 2\n)\n", .{name});
        defer allocator.free(defaults);
        const aligned_defaults = try std.fmt.allocPrint(allocator, "T: Type = (\n    .a : A{s} = 1\n    .b : {s} = 2\n)\n", .{ spaces[0..extra], name });
        defer allocator.free(aligned_defaults);
        try expectFormat(defaults, aligned_defaults);
    }
}

test "formatter retries alignment after removing long outliers" {
    try expectFormat(
        "call(\n.this_name_is_far_beyond_the_first_column = 3\n.a = 1\n.this_name_is_far_beyond_the_first_column_suffix = 4\n.short_name = 2\n)\n",
        "call(\n    .this_name_is_far_beyond_the_first_column        = 3\n    .a          = 1\n    .this_name_is_far_beyond_the_first_column_suffix = 4\n    .short_name = 2\n)\n",
    );
    try expectFormat(
        "T: Type = (\n.a: A = 1\n.b: ShortType = 2\n.c: ExceptionallyLongTypeNameForSecondaryColumn = 3\n.d: ExceptionallyLongTypeNameForSecondaryColumnSuffix = 4\n)\n",
        "T: Type = (\n    .a : A         = 1\n    .b : ShortType = 2\n    .c : ExceptionallyLongTypeNameForSecondaryColumn       = 3\n    .d : ExceptionallyLongTypeNameForSecondaryColumnSuffix = 4\n)\n",
    );
}

test "formatter compacts short grouped arithmetic without removing precedence" {
    try expectFormat(
        "result := [\n    first * second\n    + third * fourth\n]\n",
        "result := [first * second + third * fourth]\n",
    );
    try expectFormat(
        "result := [\n    [first + second]\n    * third\n]\n",
        "result := [[first + second] * third]\n",
    );
    try expectFormat(
        "result := [\n    first -- keep this explanation\n    + second\n]\n",
        "result := [\n    first -- keep this explanation\n    + second\n]\n",
    );
}

test "formatter keeps nested matrix rows together" {
    try expectFormat(
        "values := ((1, 2), (3, 4))\n",
        "values := (\n    (1, 2),\n    (3, 4)\n)\n",
    );
    try expectFormat("values := (1, 2, 3)\n", "values := (1, 2, 3)\n");
    try expectFormat(
        "values := consume(((1, 2), (3, 4)))\n",
        "values := consume(\n    (\n        (1, 2),\n        (3, 4)\n    )\n)\n",
    );
}

test "formatter budgets member calls after generic arguments" {
    try expectFormat(
        "transposed ::= math.MatrixTransposition#(math.Matrix#(.rows = 3, .cols = 2, .t: Float64)).transpose(&design)\n",
        "transposed ::= math.MatrixTransposition#(\n    math.Matrix#(.rows = 3, .cols = 2, .t: Float64)\n).transpose(&design)\n",
    );
}

test "formatter separates compile-time execution prefixes from assignments" {
    try expectFormat(
        "answer:=#run()->(.value:Int32){value=42}\n",
        "answer := #run () -> (.value: Int32) { value = 42 }\n",
    );
    try expectFormat(
        "main()->(.result:Int32=0):={result=#run ()->(.answer:Int32){answer=calculate(.value=40)}}\n",
        "main() -> (.result: Int32 = 0) := {\n    result = #run () -> (.answer: Int32) { answer = calculate(.value = 40) }\n}\n",
    );
}

test "formatter retains conditional compilation directive boundaries" {
    try expectFormat(
        "main() -> () := {\n#if true { f() }#else { g() }\n}\n",
        "main() -> () := {\n    #if true { f() } #else { g() }\n}\n",
    );
}

test "formatter preserves modern test declaration syntax" {
    try expectFormat(
        "test example:=(.system:System)->!(){testing.expect(true)!}\n",
        "test example := (.system: System) -> !() { testing.expect(true)! }\n",
    );
}

test "formatter preserves implementation and defer keywords" {
    try expectFormat(
        "implement Marker#(Value)()\nmain:=()->(){defer cleanup()}\n",
        "implement Marker#(Value) ()\n\nmain := () -> () { defer cleanup() }\n",
    );
}

test "formatter preserves explicit semicolon statement boundaries" {
    try expectFormat(
        "x:=1;y:=2;\nmain:=()->(){return;}\n",
        "x := 1; y := 2;\n\nmain := () -> () { return; }\n",
    );
    try expectFormat(
        "main:=()->(){x:=1;y:=2;}\n",
        "main := () -> () {\n    x := 1;\n    y := 2;\n}\n",
    );
}

test "formatter distinguishes specialization brackets from comparisons" {
    try expectFormat(
        "read:=(.value:Box<Int32>)->(.result:Int32){result=value.value}\n",
        "read := (.value: Box<Int32>) -> (.result: Int32) { result = value.value }\n",
    );
    try expectFormat(
        "Box:=<.T:Type>(.value:T)\nidentity:=<.T:Type>(.value:T)->(.result:T){result=value}\n",
        "Box := <.T: Type> (.value: T)\n\nidentity := <.T: Type> (.value: T) -> (.result: T) { result = value }\n",
    );
    try expectFormat(
        "result:=identity<Int32>(.value=42)\nother:=Box<Box<Int32>>\ncomparison:=a<b or c>=d\n",
        "result := identity<Int32>(.value = 42)\nother := Box<Box<Int32>>\ncomparison := a < b or c >= d\n",
    );
}

test "formatter reflows angle parameter and specialization lists with the ordinary width budget" {
    try expectFormat(
        "Box:=<\n.T:Type\n>(.value:T)\nvalue:=Box<\nInt32\n>(.value=42)\n",
        "Box := <.T: Type> (.value: T)\n\nvalue := Box<Int32>(.value = 42)\n",
    );
    try expectFormat(
        "Example:=<.FirstCompileTimeTypeParameterWithLongName:Type,.OtherCompileTimeTypeParameterWithLongName:Type>(.value:FirstCompileTimeTypeParameterWithLongName)\n",
        "Example := <\n    .FirstCompileTimeTypeParameterWithLongName : Type,\n    .OtherCompileTimeTypeParameterWithLongName : Type\n> (.value: FirstCompileTimeTypeParameterWithLongName)\n",
    );
}

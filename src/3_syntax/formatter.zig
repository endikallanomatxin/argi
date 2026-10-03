const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");

const Tag = std.meta.Tag(tok.Content);
const List = std.array_list.Managed(u8);
const Frame = struct { tag: Tag, multiline: bool, expand: bool = false };

/// Formatting uses the complete token stream, including discarded target
/// branches. Newlines are syntax in Argi, so existing breaks are retained and
/// new ones are introduced only after commas inside parentheses or at block
/// boundaries. Token text stays verbatim: comments, escapes, and numeric
/// spellings are never rebuilt.
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
    var out = List.init(temporary);
    var stack = std.array_list.Managed(Frame).init(temporary);
    var previous: ?Tag = null;
    var line_start: usize = 0;
    var pending_newlines: usize = 0;
    for (0..tokens.len) |i| {
        const tag = std.meta.activeTag(tokens.contents[i]);
        if (tag == .eof) break;
        if (tag == .new_line) {
            pending_newlines += 1;
            continue;
        }
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
            if (frame.expand) pending_newlines = @max(pending_newlines, 1);
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
            var depth: usize = 0;
            for (stack.items) |frame| if (frame.multiline) {
                depth += 1;
            };
            try out.appendNTimes(' ', depth * 4);
        } else if (needsSpace(previous.?, tag, tokens, i)) try out.append(' ');
        const start: usize = tokens.locations[i].offset;
        const end: usize = if (i + 1 < tokens.len) tokens.locations[i + 1].offset else source.len;
        const text = std.mem.trimEnd(u8, source[start..end], " \t\r\n");
        try out.appendSlice(text);
        previous = tag;
        if (tag == .open_parenthesis or tag == .open_bracket or tag == .open_brace) {
            const multiline = containsNewline(tokens, i);
            const expand = tag == .open_brace and !multiline and out.items.len - line_start + inlineLength(tokens, source, i) > 100;
            try stack.append(.{ .tag = tag, .multiline = multiline or expand, .expand = expand });
            if (expand) pending_newlines = 1;
        }
        // Break long comma-separated lines without flattening manual layout.
        // The break is stable on subsequent passes and cannot end a statement.
        if (tag == .comma and out.items.len - line_start + nextElementLength(tokens, source, i + 1) > 100 and stack.items.len != 0 and stack.items[stack.items.len - 1].tag == .open_parenthesis) {
            pending_newlines = @max(pending_newlines, 1);
            stack.items[stack.items.len - 1].multiline = true;
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
    for (0..formatted_tokens.len) |index| {
        if (formatted_tokens.contents[index] == .new_line) continue;
        while (original_index < tokens.len and tokens.contents[original_index] == .new_line) original_index += 1;
        if (original_index >= tokens.len or std.meta.activeTag(formatted_tokens.contents[index]) != std.meta.activeTag(tokens.contents[original_index])) return error.TokenSequenceChanged;
        if (!std.mem.eql(u8, tokenText(tokens, source, original_index), tokenText(formatted_tokens, result, index))) return error.TokenSequenceChanged;
        original_index += 1;
    }
    while (original_index < tokens.len and tokens.contents[original_index] == .new_line) original_index += 1;
    if (original_index != tokens.len) return error.TokenSequenceChanged;
    return result;
}

fn inlineLength(tokens: tok.View, source: []const u8, start: usize) usize {
    var depth: usize = 0;
    for (start..tokens.len) |i| {
        switch (tokens.contents[i]) {
            .open_parenthesis, .open_bracket, .open_brace => depth += 1,
            .close_parenthesis, .close_bracket, .close_brace => {
                depth -= 1;
                if (depth == 0) return tokens.locations[i].offset - tokens.locations[start].offset;
            },
            .new_line, .eof => return 0,
            else => {},
        }
    }
    return source.len - tokens.locations[start].offset;
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

fn nextElementLength(tokens: tok.View, source: []const u8, start: usize) usize {
    if (start >= tokens.len) return 0;
    var depth: usize = 0;
    for (start..tokens.len) |i| {
        switch (tokens.contents[i]) {
            .new_line, .eof, .comment => return 0,
            .open_parenthesis, .open_bracket, .open_brace => depth += 1,
            .close_parenthesis, .close_bracket, .close_brace => {
                if (depth == 0) return tokens.locations[i].offset - tokens.locations[start].offset + 1;
                depth -= 1;
            },
            .comma => if (depth == 0) {
                return tokens.locations[i].offset - tokens.locations[start].offset + 1;
            },
            else => {},
        }
    }
    return source.len - tokens.locations[start].offset;
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
        "Point: Type = (\n    .x         : Int32 = 1\n    .long_name : UInt8 = 2\n)\nmain() -> (.status_code: Int32 = 0) := { status_code = 1 }\n",
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
        "x: Type = (\n    .a : Int8\n\n    -- group\n    .long : Int64\n    .b    : UInt8\n)\nf(.x = 1, .y = -2)\n",
    );
}

test "formatter rejects damaged delimiters" {
    try std.testing.expectError(error.UnbalancedDelimiters, format(std.testing.allocator, "main(]"));
}

test "formatter is idempotent across core and feature sources" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "core", "tests/feature_tests" }) |root| {
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
                else => return err,
            };
            defer allocator.free(first);
            const second = try format(allocator, first);
            defer allocator.free(second);
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

const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const tokp = @import("../2_tokens/token_print.zig");
const syn = @import("syntax_tree.zig");
const synp = @import("syntax_tree_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

pub const SyntaxerError = error{
    ExpectedIdentifier,
    ExpectedColon,
    ExpectedEqual,
    ExpectedIntLiteral,
    ExpectedLeftParen,
    ExpectedRightParen,
    ExpectedLeftBracket,
    ExpectedRightBracket,
    ExpectedLeftBrace,
    ExpectedRightBrace,
    ExpectedStructField,
    ExpectedArrow,
    ExpectedDoubleColon,
    ExpectedAssignment,
    ExpectedDeclarationOrAssignment,
    ExpectedKeywordReturn,
    ExpectedKeywordIf,
    ExpectedKeywordFor,
    ExpectedKeywordIn,
    ExpectedKeywordWhile,
    ExpectedAmpersand,
    ExpectedStringLiteral,
    OutOfMemory,
};

// ─────────────────────────────────────────────────────────────────────────────
// Syntaxer state
// ─────────────────────────────────────────────────────────────────────────────
pub const Syntaxer = struct {
    tokens: []const tok.Token,
    source: []const u8,
    index: usize,
    allocator: std.mem.Allocator,
    file: syn.SyntaxFile,
    diags: *diagnostic.Diagnostics,
    parsing_pipe_rhs: bool,

    pub fn init(alloc: std.mem.Allocator, toks: []const tok.Token, source: []const u8, diags: *diagnostic.Diagnostics) !Syntaxer {
        return .{
            .tokens = toks,
            .source = source,
            .index = 0,
            .allocator = alloc,
            .file = try syn.SyntaxFile.init(alloc, toks[0].location.file, toks),
            .diags = diags,
            .parsing_pipe_rhs = false,
        };
    }

    pub fn nodeCount(self: *const Syntaxer) usize {
        return self.file.nodes.len;
    }

    pub fn parse(self: *Syntaxer) !syn.SyntaxFile {
        const roots = parseSentences(self) catch |err| {
            if (err == SyntaxerError.OutOfMemory) {
                try self.diags.add(self.tokenLocation(), .internal, "out of memory while parsing", .{});
            } else {
                try self.diags.add(self.tokenLocation(), .syntax, "syntax error: {s}", .{@errorName(err)});
            }
            return err;
        };
        try self.file.roots.appendSlice(self.allocator, roots.items);
        roots.deinit();
        return self.file;
    }

    // ───────────────────────────────── token helpers ─────────────────────────
    fn current(self: *Syntaxer) tok.Token {
        return self.tokens[self.index];
    }
    fn next(self: *Syntaxer) ?tok.Token {
        return if (self.index + 1 < self.tokens.len) self.tokens[self.index + 1] else null;
    }
    fn advanceOne(self: *Syntaxer) void {
        if (self.index < self.tokens.len) self.index += 1;
    }
    fn tokenLocation(self: *Syntaxer) tok.Location {
        return self.current().location;
    }

    fn tokenIs(self: *Syntaxer, tag: tok.Content) bool {
        return std.meta.activeTag(self.current().content) == std.meta.activeTag(tag);
    }

    fn currentIdentifierEquals(self: *Syntaxer, expected: []const u8) bool {
        return switch (self.current().content) {
            .identifier => |range| std.mem.eql(u8, range.slice(self.source), expected),
            else => false,
        };
    }

    fn tokenText(self: *const Syntaxer, range: tok.TextRange) []const u8 {
        return range.slice(self.source);
    }

    fn decodeStringLiteral(self: *Syntaxer, range: tok.TextRange) ![]const u8 {
        const raw = self.tokenText(range);
        if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;
        var decoded = std.array_list.Managed(u8).init(self.allocator);
        var index: usize = 0;
        while (index < raw.len) : (index += 1) {
            if (raw[index] != '\\') {
                try decoded.append(raw[index]);
                continue;
            }
            index += 1;
            const escaped = raw[index];
            try decoded.append(switch (escaped) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                '"' => '"',
                '0' => 0,
                else => unreachable,
            });
        }
        return try decoded.toOwnedSlice();
    }

    fn materializeLiteral(self: *Syntaxer, literal: tok.TokenLiteral) !tok.Literal {
        return switch (literal) {
            .bool_literal => |value| .{ .bool_literal = value },
            .decimal_int_literal => |range| .{ .decimal_int_literal = self.tokenText(range) },
            .hexadecimal_int_literal => |range| .{ .hexadecimal_int_literal = self.tokenText(range) },
            .octal_int_literal => |range| .{ .octal_int_literal = self.tokenText(range) },
            .binary_int_literal => |range| .{ .binary_int_literal = self.tokenText(range) },
            .regular_float_literal => |range| .{ .regular_float_literal = self.tokenText(range) },
            .scientific_float_literal => |range| .{ .scientific_float_literal = self.tokenText(range) },
            .char_literal => |value| .{ .char_literal = value },
            .string_literal => |range| .{ .string_literal = try self.decodeStringLiteral(range) },
        };
    }

    fn currentCanStartBareExpressionStatement(self: *Syntaxer) bool {
        return switch (self.current().content) {
            .literal,
            .open_parenthesis,
            .open_brace,
            .double_dot,
            .ampersand,
            .dollar,
            .tilde,
            => true,
            else => false,
        };
    }

    fn lookaheadIsTypeArgument(self: *Syntaxer) bool {
        if (!self.tokenIs(.open_bracket)) return false;

        var depth: i32 = 0;
        var idx: usize = self.index;
        while (idx < self.tokens.len) : (idx += 1) {
            const tag = std.meta.activeTag(self.tokens[idx].content);
            switch (tag) {
                .open_bracket => depth += 1,
                .close_bracket => {
                    depth -= 1;
                    if (depth == 0) {
                        var lookahead = idx + 1;
                        while (lookahead < self.tokens.len) : (lookahead += 1) {
                            const next_tag = std.meta.activeTag(self.tokens[lookahead].content);
                            switch (next_tag) {
                                .new_line, .comment => continue,
                                else => return next_tag == .open_parenthesis,
                            }
                        }
                        return false;
                    }
                },
                else => {},
            }
        }
        return false;
    }

    fn skipNewLinesAndComments(self: *Syntaxer) void {
        while (self.index < self.tokens.len) {
            switch (self.current().content) {
                .new_line, .comment => self.advanceOne(),
                else => break,
            }
        }
    }

    // ─────────────────────────────── node helpers ────────────────────────────
    fn addNode(self: *Syntaxer, tag: syn.Node.Tag, main_token: syn.TokenIndex, data: syn.Node.Data) !syn.NodeIndex {
        if (self.file.nodes.len >= std.math.maxInt(u32)) return error.OutOfMemory;
        const index: syn.NodeIndex = @enumFromInt(self.file.nodes.len);
        try self.file.nodes.append(self.allocator, .{ .tag = tag, .main_token = main_token, .data = data });
        return index;
    }

    fn addExtra(self: *Syntaxer, extra: anytype) !syn.ExtraIndex {
        const fields = std.meta.fields(@TypeOf(extra));
        if (self.file.extra_data.items.len + fields.len >= std.math.maxInt(u32)) return error.OutOfMemory;
        try self.file.extra_data.ensureUnusedCapacity(self.allocator, fields.len);
        const result: syn.ExtraIndex = @enumFromInt(self.file.extra_data.items.len);
        inline for (fields) |field| {
            const value = @field(extra, field.name);
            const raw: u32 = switch (field.type) {
                syn.NodeIndex, syn.OptionalNodeIndex, syn.ExtraIndex => @intFromEnum(value),
                u32 => value,
                else => if (@typeInfo(field.type) == .@"enum") @intFromEnum(value) else @compileError("unsupported extra_data field " ++ @typeName(field.type)),
            };
            self.file.extra_data.appendAssumeCapacity(raw);
        }
        return result;
    }

    fn addNodeRange(self: *Syntaxer, nodes: []const syn.NodeIndex) !syn.NodeRange {
        if (self.file.extra_data.items.len + nodes.len >= std.math.maxInt(u32)) return error.OutOfMemory;
        const start: syn.ExtraIndex = @enumFromInt(self.file.extra_data.items.len);
        try self.file.extra_data.appendSlice(self.allocator, @ptrCast(nodes));
        return .{ .start = start, .end = @enumFromInt(self.file.extra_data.items.len) };
    }

    fn parseSignedNumericLiteral(self: *Syntaxer) !syn.NodeIndex {
        const minus_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        const minus_loc = self.tokenLocation();
        self.advanceOne();
        self.skipNewLinesAndComments();

        const literal = switch (self.current().content) {
            .literal => |lit| lit,
            else => {
                try self.diags.add(minus_loc, .syntax, "expected numeric literal after unary '-'", .{});
                return SyntaxerError.ExpectedIntLiteral;
            },
        };

        switch (literal) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal, .regular_float_literal, .scientific_float_literal => {},
            else => {
                try self.diags.add(minus_loc, .syntax, "expected numeric literal after unary '-'", .{});
                return SyntaxerError.ExpectedIntLiteral;
            },
        }

        self.advanceOne();
        return try self.addNode(.literal, minus_token, .{ .token = @enumFromInt(@intFromEnum(minus_token) + 1) });
    }

    // ───────────────────────────────  atoms ──────────────────────────────────
    fn parseIdentifier(self: *Syntaxer) SyntaxerError![]const u8 {
        const t = self.current();
        if (t.content != .identifier) {
            try self.diags.add(self.tokenLocation(), .syntax, "expected identifier, found '{s}'", .{@tagName(self.current().content)});
            return SyntaxerError.ExpectedIdentifier;
        }
        const name = self.tokenText(t.content.identifier);
        self.advanceOne();
        return name;
    }

    const ParsedName = struct { token: syn.TokenIndex, text: []const u8 };

    fn parseName(self: *Syntaxer) SyntaxerError!ParsedName {
        const token_index: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        return .{ .token = token_index, .text = try self.parseIdentifier() };
    }

    fn parseOperatorName(self: *Syntaxer, operator_token: syn.TokenIndex) SyntaxerError!ParsedName {
        switch (self.current().content) {
            .identifier => {
                const ident = try self.parseIdentifier();

                if (std.mem.eql(u8, ident, "get") or
                    std.mem.eql(u8, ident, "set") or
                    std.mem.eql(u8, ident, "get_ro_pointer") or
                    std.mem.eql(u8, ident, "get_rw_pointer"))
                {
                    if (!self.tokenIs(.open_bracket)) return SyntaxerError.ExpectedLeftBracket;
                    self.advanceOne();
                    if (!self.tokenIs(.close_bracket)) return SyntaxerError.ExpectedRightBracket;
                    self.advanceOne();
                    return .{ .token = operator_token, .text = try std.fmt.allocPrint(self.allocator, "operator {s}[]", .{ident}) };
                }

                try self.diags.add(self.tokenLocation(), .syntax, "unsupported operator '{s}'", .{ident});
                return SyntaxerError.ExpectedIdentifier;
            },
            .comparison_operator => |cmp| {
                const name = switch (cmp) {
                    .equal => "operator ==",
                    .not_equal => "operator !=",
                    else => blk: {
                        try self.diags.add(self.tokenLocation(), .syntax, "unsupported comparison operator after 'operator'", .{});
                        break :blk "";
                    },
                };
                if (name.len == 0) return SyntaxerError.ExpectedIdentifier;
                self.advanceOne();
                return .{ .token = operator_token, .text = name };
            },
            .binary_operator => |op| {
                const name = switch (op) {
                    .addition => "operator +",
                    else => blk: {
                        try self.diags.add(self.tokenLocation(), .syntax, "unsupported binary operator after 'operator'", .{});
                        break :blk "";
                    },
                };
                if (name.len == 0) return SyntaxerError.ExpectedIdentifier;
                self.advanceOne();
                return .{ .token = operator_token, .text = name };
            },
            else => {
                try self.diags.add(self.tokenLocation(), .syntax, "expected operator name after 'operator'", .{});
                return SyntaxerError.ExpectedIdentifier;
            },
        }
    }

    fn parseGenericParamNames(self: *Syntaxer) SyntaxerError![]const syn.NodeIndex {
        // Parses: [T, U, ...]
        if (!self.tokenIs(.open_bracket)) return SyntaxerError.ExpectedLeftBracket;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var names = std.array_list.Managed(syn.NodeIndex).init(self.allocator);
        while (!self.tokenIs(.close_bracket)) {
            const token_index: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            _ = try self.parseIdentifier();
            try names.append(try self.addNode(.type_name, token_index, .{ .unused = .{ 0, 0 } }));
            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            } else break;
        }
        if (!self.tokenIs(.close_bracket)) return SyntaxerError.ExpectedRightBracket;
        self.advanceOne();
        return names.items;
    }

    fn parseTypeList(self: *Syntaxer) SyntaxerError![]const syn.NodeIndex {
        // Parses: [Type, &Type, ( .a: Type=..., ... ) , ...]
        if (!self.tokenIs(.open_bracket)) return SyntaxerError.ExpectedLeftBracket;
        self.advanceOne();
        self.skipNewLinesAndComments();
        var tys = std.array_list.Managed(syn.NodeIndex).init(self.allocator);
        while (!self.tokenIs(.close_bracket)) {
            const t = (try self.parseType()).?; // types are mandatory here
            try tys.append(t);
            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            } else break;
        }
        if (!self.tokenIs(.close_bracket)) return SyntaxerError.ExpectedRightBracket;
        self.advanceOne();
        return tys.items;
    }

    // ────────────────────────────  TYPE ANNOTATIONS ──────────────────────────
    fn parseType(self: *Syntaxer) SyntaxerError!?syn.NodeIndex {
        // permitimos omitir la anotación
        if (self.tokenIs(.equal) or self.tokenIs(.comma) or self.tokenIs(.close_parenthesis))
            return null;

        if (self.tokenIs(.question_mark)) {
            const question_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            const question_loc = self.tokenLocation();
            self.advanceOne();

            const inner_ty_opt = try self.parseType();
            if (inner_ty_opt == null) {
                try self.diags.add(question_loc, .syntax, "expected type after '?'", .{});
                return SyntaxerError.ExpectedIdentifier;
            }

            return try self.addNode(.nullable_type, question_token, .{ .node = inner_ty_opt.? });
        } else if (self.tokenIs(.open_parenthesis) and self.next() != null and self.next().?.content == .close_parenthesis) {
            return try self.parseStructTypeLiteral();
        } else if (self.tokenIs(.open_bracket)) {
            const bracket_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            const len_loc = self.tokenLocation();
            self.advanceOne();
            self.skipNewLinesAndComments();

            if (std.meta.activeTag(self.current().content) != .literal) {
                try self.diags.add(len_loc, .syntax, "expected array length integer literal", .{});
                return SyntaxerError.ExpectedIntLiteral;
            }

            const length_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            switch (self.current().content.literal) {
                .decimal_int_literal => {},
                else => {
                    try self.diags.add(len_loc, .syntax, "array length must be a decimal integer literal", .{});
                    return SyntaxerError.ExpectedIntLiteral;
                },
            }
            self.advanceOne();
            self.skipNewLinesAndComments();

            if (!self.tokenIs(.close_bracket)) {
                try self.diags.add(len_loc, .syntax, "expected ']' after array length", .{});
                return SyntaxerError.ExpectedRightBracket;
            }
            self.advanceOne();

            const elem_ty_opt = try self.parseType();
            if (elem_ty_opt == null) {
                try self.diags.add(len_loc, .syntax, "expected element type after array length", .{});
                return SyntaxerError.ExpectedIdentifier;
            }
            return try self.addNode(.array_type, bracket_token, .{ .token_and_node = .{ .token = length_token, .node = elem_ty_opt.? } });
        } else if (self.tokenIs(.ampersand) or self.tokenIs(.dollar)) {
            var mutable = false;
            const main_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            var op_loc = self.tokenLocation();

            if (self.tokenIs(.dollar)) {
                mutable = true;
                self.advanceOne();

                if (!self.tokenIs(.ampersand)) {
                    try self.diags.add(op_loc, .syntax, "expected '&' after '$' for mutable pointer type", .{});
                    return SyntaxerError.ExpectedAmpersand;
                }
                op_loc = self.tokenLocation();
            }

            if (!self.tokenIs(.ampersand)) {
                try self.diags.add(op_loc, .syntax, "expected '&' for pointer type", .{});
                return SyntaxerError.ExpectedAmpersand;
            }

            self.advanceOne();
            const base_ty_opt = try self.parseType();
            if (base_ty_opt == null) {
                try self.diags.add(op_loc, .syntax, "expected type after pointer prefix", .{});
                return SyntaxerError.ExpectedIdentifier;
            }
            return try self.addNode(if (mutable) .pointer_type_mut else .pointer_type, main_token, .{ .node = base_ty_opt.? });
        } else if (self.tokenIs(.open_parenthesis)) {
            if (self.parenthesizedTypeIsChoiceLiteral()) {
                return try self.parseChoiceTypeLiteral();
            }
            return try self.parseStructTypeLiteral();
        }

        const name = try self.parseName();
        var qualifier_token: ?syn.TokenIndex = null;
        var name_token = name.token;
        if (self.tokenIs(.dot)) {
            self.advanceOne();
            const rhs = try self.parseName();
            qualifier_token = name.token;
            name_token = rhs.token;
        }
        const base = try self.addNode(.type_name, name_token, .{ .token_and_optional_token = .{
            .token = name_token,
            .optional = syn.OptionalTokenIndex.init(qualifier_token),
        } });
        if (self.tokenIs(.hash)) {
            const hash_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            const gen_args = try self.parseStructTypeLiteral();
            return try self.addNode(.generic_type_instantiation, hash_token, .{ .node_and_node = .{ .first = base, .second = gen_args } });
        }
        return base;
    }

    // Parse an abstract body: a parenthesized, comma-separated list of items.
    // Each item can be:
    //   - an identifier: composed abstract name (e.g., Addable)
    //   - a function requirement: name ( StructTypeLiteral ) -> ( StructTypeLiteral )
    // Newlines and comments are ignored.
    fn parseAbstractBody(self: *Syntaxer) SyntaxerError!struct {
        req_names: []const syn.NodeIndex,
        req_funcs: []const syn.NodeIndex,
    } {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var names = std.array_list.Managed(syn.NodeIndex).init(self.allocator);
        var funcs = std.array_list.Managed(syn.NodeIndex).init(self.allocator);

        while (!self.tokenIs(.close_parenthesis)) {
            var name = try self.parseName();
            if (std.mem.eql(u8, name.text, "operator")) {
                name = try self.parseOperatorName(name.token);
            }

            if (self.tokenIs(.open_parenthesis)) {
                const in_st = try self.parseStructTypeLiteral();
                if (!self.tokenIs(.arrow)) return SyntaxerError.ExpectedArrow;
                self.advanceOne();
                const out_st = try self.parseStructTypeLiteral();
                const empty = try self.addNodeRange(&.{});
                const extra = try self.addExtra(syn.FunctionExtra{
                    .generic_params_start = empty.start,
                    .generic_params_end = empty.end,
                    .generic_params_struct = .none,
                    .input = in_st,
                    .output = out_st,
                    .body = .none,
                });
                try funcs.append(try self.addNode(.abstract_function_requirement, name.token, .{ .extra = extra }));
            } else {
                try names.append(try self.addNode(.type_name, name.token, .{ .unused = .{ 0, 0 } }));
            }

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }
        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();
        return .{ .req_names = names.items, .req_funcs = funcs.items };
    }

    fn parseListLiteral(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        const start_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        self.advanceOne();
        self.skipNewLinesAndComments();

        var elems = std.array_list.Managed(syn.NodeIndex).init(self.allocator);

        while (!self.tokenIs(.close_parenthesis)) {
            const elem = try self.parseExpression();
            try elems.append(elem);

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            } else break;
        }

        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();

        return try self.addNode(.list_literal, start_token, .{ .extra_range = try self.addNodeRange(elems.items) });
    }

    // ( .field : Type? (= expr)? , ... )
    fn parseStructTypeLiteral(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        const start_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.array_list.Managed(syn.NodeIndex).init(self.allocator);

        while (!self.tokenIs(.close_parenthesis)) {
            if (!self.tokenIs(.dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected struct field, found '{s}'", .{@tagName(self.current().content)});
                return SyntaxerError.ExpectedStructField;
            }
            self.advanceOne();
            const fname = try self.parseName();

            var ftype: ?syn.NodeIndex = null;
            if (self.tokenIs(.colon)) {
                self.advanceOne();
                ftype = try self.parseType();
            }

            var def_val: ?syn.NodeIndex = null;
            if (self.tokenIs(.equal)) {
                self.advanceOne();
                def_val = try self.parseExpression();
            }

            const extra = try self.addExtra(syn.FieldExtra{
                .type_node = syn.OptionalNodeIndex.init(ftype),
                .default_value = syn.OptionalNodeIndex.init(def_val),
            });
            try fields.append(try self.addNode(.struct_type_field, fname.token, .{ .extra = extra }));

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }
        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();

        return try self.addNode(.struct_type_literal, start_token, .{ .extra_range = try self.addNodeRange(fields.items) });
    }

    fn parseFunctionOutputType(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        if (self.tokenIs(.bang)) {
            const bang_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            const bang_loc = self.tokenLocation();
            self.advanceOne();

            const inner_ty_opt = try self.parseType();
            if (inner_ty_opt == null) {
                try self.diags.add(bang_loc, .syntax, "expected type after '!'", .{});
                return SyntaxerError.ExpectedIdentifier;
            }

            const inferred = try self.addNode(.inferred_errable_type, bang_token, .{ .node = inner_ty_opt.? });
            const field_extra = try self.addExtra(syn.FieldExtra{ .type_node = inferred.optional(), .default_value = .none });
            const field = try self.addNode(.inferred_result_field, bang_token, .{ .extra = field_extra });
            return try self.addNode(.struct_type_literal, bang_token, .{ .extra_range = try self.addNodeRange(&.{field}) });
        }

        return self.parseStructTypeLiteral();
    }

    fn parseGenericParamsStruct(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        const start_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.array_list.Managed(syn.NodeIndex).init(self.allocator);

        while (!self.tokenIs(.close_parenthesis)) {
            if (!self.tokenIs(.dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected generic parameter, found '{s}'", .{@tagName(self.current().content)});
                return SyntaxerError.ExpectedStructField;
            }
            self.advanceOne();
            const fname = try self.parseName();

            var ftype: ?syn.NodeIndex = null;
            if (self.tokenIs(.colon)) {
                self.advanceOne();
                ftype = try self.parseType();

                if (self.tokenIs(.colon)) {
                    if (ftype == null or self.file.tag(ftype.?) != .type_name or !std.mem.eql(u8, self.tokenText(self.tokens[@intFromEnum(self.file.mainToken(ftype.?))].content.identifier), "Type")) {
                        try self.diags.add(
                            self.tokenLocation(),
                            .syntax,
                            "generic parameter bounds use '.{s}: Type: Constraint'",
                            .{fname.text},
                        );
                        return SyntaxerError.ExpectedStructField;
                    }
                    self.advanceOne();
                    ftype = try self.parseType();
                }
            }

            var def_val: ?syn.NodeIndex = null;
            if (self.tokenIs(.equal)) {
                self.advanceOne();
                def_val = try self.parseExpression();
            }

            const extra = try self.addExtra(syn.FieldExtra{
                .type_node = syn.OptionalNodeIndex.init(ftype),
                .default_value = syn.OptionalNodeIndex.init(def_val),
            });
            try fields.append(try self.addNode(.struct_type_field, fname.token, .{ .extra = extra }));

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }
        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();

        return try self.addNode(.struct_type_literal, start_token, .{ .extra_range = try self.addNodeRange(fields.items) });
    }

    fn parseChoiceTypeLiteral(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        const start_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        self.advanceOne();
        self.skipNewLinesAndComments();

        var variants = std.array_list.Managed(syn.NodeIndex).init(self.allocator);

        while (!self.tokenIs(.close_parenthesis)) {
            var is_default = false;
            if (self.tokenIs(.equal)) {
                is_default = true;
                self.advanceOne();
                self.skipNewLinesAndComments();
            }

            var module_qualifier: ?ParsedName = null;
            if (std.meta.activeTag(self.current().content) == .identifier) {
                const qualifier = try self.parseName();
                self.skipNewLinesAndComments();
                if (!self.tokenIs(.double_dot)) {
                    try self.diags.add(self.tokens[@intFromEnum(qualifier.token)].location, .syntax, "expected '..' after choice option module qualifier", .{});
                    return SyntaxerError.ExpectedIdentifier;
                }
                module_qualifier = qualifier;
            } else if (!self.tokenIs(.double_dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected choice variant '..name'", .{});
                return SyntaxerError.ExpectedIdentifier;
            }
            self.advanceOne();
            const vname = try self.parseName();
            var payload_type: ?syn.NodeIndex = null;
            if (self.tokenStartsChoicePayloadType()) {
                payload_type = (try self.parseType()).?;
            }
            try variants.append(try self.addNode(
                if (is_default) .choice_type_variant_default else .choice_type_variant,
                vname.token,
                .{ .optional_token_and_optional_node = .{
                    .token = syn.OptionalTokenIndex.init(if (module_qualifier) |qualifier| qualifier.token else null),
                    .node = syn.OptionalNodeIndex.init(payload_type),
                } },
            ));

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }

        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();
        return try self.addNode(.choice_type_literal, start_token, .{ .extra_range = try self.addNodeRange(variants.items) });
    }

    fn tokenStartsChoicePayloadType(self: *Syntaxer) bool {
        return switch (self.current().content) {
            .identifier, .question_mark, .open_parenthesis, .open_bracket, .ampersand, .dollar => true,
            else => false,
        };
    }

    fn tokenStartsChoicePayloadExpr(self: *Syntaxer) bool {
        return switch (self.current().content) {
            .identifier, .literal, .double_dot, .open_parenthesis, .tilde, .hash, .ampersand, .dollar => true,
            .binary_operator => |op| op == .subtraction,
            else => false,
        };
    }

    fn parenthesizedTypeIsChoiceLiteral(self: *Syntaxer) bool {
        if (!self.tokenIs(.open_parenthesis)) return false;

        var idx = self.index + 1;
        while (idx < self.tokens.len) : (idx += 1) {
            const tag = std.meta.activeTag(self.tokens[idx].content);
            switch (tag) {
                .new_line, .comment => continue,
                .double_dot => return true,
                .equal => {
                    idx += 1;
                    while (idx < self.tokens.len) : (idx += 1) {
                        const inner_tag = std.meta.activeTag(self.tokens[idx].content);
                        switch (inner_tag) {
                            .new_line, .comment => continue,
                            .double_dot => return true,
                            .identifier => {
                                var j = idx + 1;
                                while (j < self.tokens.len) : (j += 1) {
                                    const next_tag = std.meta.activeTag(self.tokens[j].content);
                                    switch (next_tag) {
                                        .new_line, .comment => continue,
                                        .double_dot => return true,
                                        else => return false,
                                    }
                                }
                                return false;
                            },
                            else => return false,
                        }
                    }
                    return false;
                },
                .identifier => {
                    var j = idx + 1;
                    while (j < self.tokens.len) : (j += 1) {
                        const next_tag = std.meta.activeTag(self.tokens[j].content);
                        switch (next_tag) {
                            .new_line, .comment => continue,
                            .double_dot => return true,
                            else => return false,
                        }
                    }
                    return false;
                },
                else => return false,
            }
        }

        return false;
    }

    fn currentSentenceStartsChoiceOptionDeclaration(self: *Syntaxer) bool {
        if (!self.tokenIs(.double_dot)) return false;
        if (self.index + 1 >= self.tokens.len) return false;
        if (std.meta.activeTag(self.tokens[self.index + 1].content) != .identifier) return false;

        var idx = self.index + 2;
        while (idx < self.tokens.len) : (idx += 1) {
            const tag = std.meta.activeTag(self.tokens[idx].content);
            switch (tag) {
                .comment => continue,
                .new_line, .eof, .close_brace => return true,
                else => return false,
            }
        }

        return true;
    }

    fn commaStartsReachAlternative(self: *Syntaxer) bool {
        if (!self.tokenIs(.comma)) return false;

        var idx: usize = self.index + 1;
        while (idx < self.tokens.len) : (idx += 1) {
            switch (self.tokens[idx].content) {
                .new_line, .comment => continue,
                .identifier => return true,
                else => return false,
            }
        }

        return false;
    }

    fn parseReachDirective(self: *Syntaxer, hash_token: syn.TokenIndex) SyntaxerError!syn.NodeIndex {
        var alternatives = std.array_list.Managed(syn.NodeIndex).init(self.allocator);

        while (true) {
            var segments = std.array_list.Managed(syn.NodeIndex).init(self.allocator);
            const first = try self.parseName();
            try segments.append(try self.addNode(.identifier, first.token, .{ .unused = .{ 0, 0 } }));

            while (self.tokenIs(.dot)) {
                self.advanceOne();
                const segment = try self.parseName();
                try segments.append(try self.addNode(.identifier, segment.token, .{ .unused = .{ 0, 0 } }));
            }

            try alternatives.append(try self.addNode(.reach_alternative, first.token, .{ .extra_range = try self.addNodeRange(segments.items) }));
            segments.deinit();

            self.skipNewLinesAndComments();
            if (!self.commaStartsReachAlternative()) break;
            self.advanceOne();
            self.skipNewLinesAndComments();
        }

        return try self.addNode(.reach_directive, hash_token, .{ .extra_range = try self.addNodeRange(alternatives.items) });
    }

    fn findMatchingCloseParenIndex(self: *Syntaxer, open_paren_index: usize) ?usize {
        if (open_paren_index >= self.tokens.len) return null;
        if (std.meta.activeTag(self.tokens[open_paren_index].content) != .open_parenthesis) return null;

        var depth: i32 = 0;
        var idx = open_paren_index;
        while (idx < self.tokens.len) : (idx += 1) {
            const tag = std.meta.activeTag(self.tokens[idx].content);
            switch (tag) {
                .open_parenthesis => depth += 1,
                .close_parenthesis => {
                    depth -= 1;
                    if (depth == 0) return idx;
                },
                else => {},
            }
        }

        return null;
    }

    fn tokenIndexAfterCloseParen(self: *Syntaxer, open_paren_index: usize) ?usize {
        const close_idx = self.findMatchingCloseParenIndex(open_paren_index) orelse return null;
        var idx = close_idx + 1;
        while (idx < self.tokens.len) : (idx += 1) {
            switch (self.tokens[idx].content) {
                .new_line, .comment => continue,
                else => return idx,
            }
        }
        return null;
    }

    fn looksLikeFunctionDeclarationInput(self: *Syntaxer, open_paren_index: usize) bool {
        const after_close_idx = self.tokenIndexAfterCloseParen(open_paren_index) orelse return false;
        if (std.meta.activeTag(self.tokens[after_close_idx].content) != .arrow) return false;

        var idx = open_paren_index + 1;
        while (idx < self.tokens.len) : (idx += 1) {
            switch (self.tokens[idx].content) {
                .new_line, .comment => continue,
                .close_parenthesis => return true,
                .dot => {
                    idx += 1;
                    while (idx < self.tokens.len) : (idx += 1) {
                        switch (self.tokens[idx].content) {
                            .new_line, .comment => continue,
                            .identifier => {
                                idx += 1;
                                while (idx < self.tokens.len) : (idx += 1) {
                                    switch (self.tokens[idx].content) {
                                        .new_line, .comment => continue,
                                        .colon => return true,
                                        .equal => return false,
                                        else => return false,
                                    }
                                }
                                return false;
                            },
                            else => return false,
                        }
                    }
                    return false;
                },
                else => return false,
            }
        }

        return false;
    }

    fn parseCollectionLiteral(self: *Syntaxer, force_struct: bool) SyntaxerError!syn.NodeIndex {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        const start_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.array_list.Managed(syn.NodeIndex).init(self.allocator);
        var positional_elements = std.array_list.Managed(syn.NodeIndex).init(self.allocator);
        var positional_prefix_count: u32 = 0;
        var has_named = false;
        var positional_index: usize = 0;

        while (!self.tokenIs(.close_parenthesis)) {
            if (self.tokenIs(.dot)) {
                has_named = true;
                self.advanceOne();
                const fname = try self.parseName();

                if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
                self.advanceOne();

                const val = try self.parseExpression();
                try fields.append(try self.addNode(.struct_value_field, fname.token, .{ .node = val }));
            } else {
                if (has_named) {
                    try self.diags.add(
                        self.tokenLocation(),
                        .syntax,
                        "positional collection items must appear before named items",
                        .{},
                    );
                    return SyntaxerError.ExpectedStructField;
                }

                const val = try self.parseExpression();
                try positional_elements.append(val);
                try fields.append(try self.addNode(.positional_value_field, self.file.mainToken(val), .{ .u32_and_node = .{ .value = @intCast(positional_index), .node = val } }));
                positional_index += 1;
                positional_prefix_count += 1;
            }

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }
        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();

        if (!force_struct and !has_named) {
            const elems = try positional_elements.toOwnedSlice();
            positional_elements.deinit();
            fields.deinit();
            return try self.addNode(.list_literal, start_token, .{ .extra_range = try self.addNodeRange(elems) });
        }

        positional_elements.deinit();
        return try self.addNode(.struct_value_literal, start_token, .{ .u32_and_extra = .{
            .value = positional_prefix_count,
            .extra = try self.addExtra(try self.addNodeRange(fields.items)),
        } });
    }

    // ────────────────────────── postfix “.campo” chain ───────────────────────
    fn parsePostfix(self: *Syntaxer, mut: syn.NodeIndex) !syn.NodeIndex {
        var node = mut;
        while (true) {
            if (self.tokenIs(.dot)) {
                const dot_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                const fname = try self.parseName();
                node = try self.addNode(.struct_field_access, dot_token, .{ .token_and_node = .{ .token = fname.token, .node = node } });
                continue;
            }

            if (self.tokenIs(.double_dot)) {
                const dd_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                const vname = try self.parseName();
                node = try self.addNode(.choice_payload_access, dd_token, .{ .token_and_node = .{ .token = vname.token, .node = node } });
                continue;
            }

            if (self.tokenIs(.open_parenthesis)) {
                if (self.file.tag(node) == .struct_field_access) {
                    const sfa = self.file.data(node).token_and_node;
                    if (self.file.tag(sfa.node) != .identifier) break;
                    const struct_value_literal = try self.parseCollectionLiteral(true);
                    const empty = try self.addNodeRange(&.{});
                    const extra = try self.addExtra(syn.CallExtra{
                        .module_qualifier = syn.OptionalTokenIndex.init(self.file.mainToken(sfa.node)),
                        .type_arguments_start = empty.start,
                        .type_arguments_end = empty.end,
                        .type_arguments_struct = .none,
                        .input = struct_value_literal,
                    });
                    node = try self.addNode(.function_call, sfa.token, .{ .extra = extra });
                    continue;
                }
            }

            if (self.tokenIs(.open_bracket)) {
                const bracket_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                const idx_expr = try self.parseExpression();
                if (!self.tokenIs(.close_bracket))
                    return SyntaxerError.ExpectedRightBracket;
                self.advanceOne();
                node = try self.addNode(.index_access, bracket_token, .{ .node_and_node = .{ .first = node, .second = idx_expr } });
                continue;
            }

            if (self.tokenIs(.ampersand)) {
                const amp_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                node = try self.addNode(.dereference, amp_token, .{ .node = node });
                continue;
            }

            if (self.tokenIs(.bang)) {
                const bang_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                node = try self.addNode(.error_propagation, bang_token, .{ .node = node });
                continue;
            }

            if (self.tokenIs(.double_bang)) {
                const bang_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                const context = try self.parseExpression();
                node = try self.addNode(.error_context, bang_token, .{ .node_and_node = .{ .first = node, .second = context } });
                continue;
            }

            if (self.tokenIs(.question_mark)) {
                const question_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                node = try self.addNode(.nullable_test, question_token, .{ .node = node });
                continue;
            }

            break;
        }
        return node;
    }

    fn parsePipeRhs(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const prev_pipe_rhs = self.parsing_pipe_rhs;
        self.parsing_pipe_rhs = true;
        defer self.parsing_pipe_rhs = prev_pipe_rhs;
        return self.parsePrimary();
    }

    // ─────────────────────────────  EXPRESSIONS  ─────────────────────────────
    /// [primary] {'.' fld}  (bin-op rhs)?
    fn parsePrimary(self: *Syntaxer) !syn.NodeIndex {
        const t = self.current();

        if (t.content == .binary_operator and t.content.binary_operator == .subtraction) {
            return try self.parseSignedNumericLiteral();
        }

        if (self.tokenIs(.tilde)) {
            const move_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            const inner = try self.parsePrimary();
            return try self.addNode(.move_expression, move_token, .{ .node = inner });
        }

        if (self.tokenIs(.ampersand) or self.tokenIs(.dollar)) {
            var mutable = false;
            const main_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            var op_loc = t.location;

            if (self.tokenIs(.dollar)) {
                mutable = true;
                self.advanceOne();

                if (!self.tokenIs(.ampersand)) {
                    try self.diags.add(op_loc, .syntax, "expected '&' after '$' for mutable pointer", .{});
                    return SyntaxerError.ExpectedAmpersand;
                }
                op_loc = self.tokenLocation();
            }

            if (!self.tokenIs(.ampersand)) {
                try self.diags.add(op_loc, .syntax, "expected '&' for address-of", .{});
                return SyntaxerError.ExpectedAmpersand;
            }

            self.advanceOne();
            const inner = try self.parsePrimary(); // recursivo
            return try self.addNode(if (mutable) .address_of_mut else .address_of, main_token, .{ .node = inner });
        }

        if (self.tokenIs(.hash)) {
            const hash_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            const hash_loc = self.tokenLocation();
            self.advanceOne();
            const ident = try self.parseIdentifier();
            if (std.mem.eql(u8, ident, "reach")) {
                const node = try self.parseReachDirective(hash_token);
                return try self.parsePostfix(node);
            }
            if (!std.mem.eql(u8, ident, "import")) {
                try self.diags.add(hash_loc, .syntax, "unknown directive '#{s}' in expression position", .{ident});
                return SyntaxerError.ExpectedDeclarationOrAssignment;
            }
            if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
            self.advanceOne();
            self.skipNewLinesAndComments();
            const lit = self.current();
            switch (lit.content) {
                .literal => |literal| switch (literal) {
                    .string_literal => {},
                    else => return SyntaxerError.ExpectedStringLiteral,
                },
                else => return SyntaxerError.ExpectedStringLiteral,
            }
            const path_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            self.skipNewLinesAndComments();
            if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
            self.advanceOne();
            const node = try self.addNode(.import_statement, hash_token, .{ .token = path_token });
            return try self.parsePostfix(node);
        }

        const base: syn.NodeIndex = switch (t.content) {
            .double_dot => blk: {
                const dots_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                const variant = try self.parseName();
                var payload: ?syn.NodeIndex = null;
                if (self.tokenStartsChoicePayloadExpr()) {
                    payload = try self.parseExpression();
                }
                break :blk try self.addNode(.choice_literal, dots_token, .{ .token_and_optional = .{
                    .token = variant.token,
                    .optional = syn.OptionalNodeIndex.init(payload),
                } });
            },

            // ─── ident  /  call ─────────────────────────────────────────────
            .identifier => blk: {
                const name_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                const name = try self.parseIdentifier();
                if (self.parsing_pipe_rhs and std.mem.eql(u8, name, "_")) {
                    break :blk try self.addNode(.pipe_placeholder, name_token, .{ .unused = .{ 0, 0 } });
                }
                var type_args: []const syn.NodeIndex = &.{};
                var type_args_struct: ?syn.NodeIndex = null;
                if (self.tokenIs(.open_bracket) and self.lookaheadIsTypeArgument()) {
                    // Explicit type arguments on call site (old syntax)
                    type_args = try self.parseTypeList();
                } else if (self.tokenIs(.hash)) {
                    // New syntax: #(.T: Int32)
                    self.advanceOne();
                    type_args_struct = try self.parseStructTypeLiteral();
                }
                if (self.tokenIs(.open_parenthesis)) { // llamada
                    const struct_value_literal = try self.parseCollectionLiteral(true);
                    const range = try self.addNodeRange(type_args);
                    const extra = try self.addExtra(syn.CallExtra{
                        .module_qualifier = .none,
                        .type_arguments_start = range.start,
                        .type_arguments_end = range.end,
                        .type_arguments_struct = syn.OptionalNodeIndex.init(type_args_struct),
                        .input = struct_value_literal,
                    });
                    break :blk try self.addNode(.function_call, name_token, .{ .extra = extra });
                }
                break :blk try self.addNode(.identifier, name_token, .{ .unused = .{ 0, 0 } });
            },

            // ─── literal ────────────────────────────────────────────────────
            .literal => blk: {
                const literal_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                break :blk try self.addNode(.literal, literal_token, .{ .unused = .{ 0, 0 } });
            },

            // ─── struct value literal o list literal ─────────────────────────────────
            .open_parenthesis => blk: {
                break :blk try self.parseCollectionLiteral(false);
            },

            // ─── bloque `{}` embebido ───────────────────────────────────────
            .open_brace => try self.parseCodeBlock(),

            else => return SyntaxerError.ExpectedIntLiteral,
        };

        // aplica cadenas de “.campo”
        return try self.parsePostfix(base);
    }

    fn parsePipeExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parsePrimary();

        while (self.tokenIs(.pipe)) {
            const pipe_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            self.skipNewLinesAndComments();
            const right = try self.parsePipeRhs();
            lhs = try self.addNode(.pipe_expression, pipe_token, .{ .node_and_node = .{ .first = lhs, .second = right } });
        }
        return lhs;
    }

    fn parseBinaryExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parsePipeExpr();

        if (self.current().content == .binary_operator) {
            const op_tok = self.current();
            const op_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            const rhs = try self.parseBinaryExpr();
            const tag: syn.Node.Tag = switch (op_tok.content.binary_operator) {
                .addition => .binary_add,
                .subtraction => .binary_subtract,
                .multiplication => .binary_multiply,
                .division => .binary_divide,
                .modulo => .binary_modulo,
            };
            lhs = try self.addNode(tag, op_token, .{ .node_and_node = .{ .first = lhs, .second = rhs } });
        }

        return lhs;
    }

    fn parseComparisonExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parseBinaryExpr();

        while (self.current().content == .comparison_operator) {
            const op_tok = self.current();
            const op_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            var op: tok.ComparisonOperator = undefined;
            switch (op_tok.content) {
                .comparison_operator => |c| op = c,
                else => unreachable,
            }
            self.advanceOne();
            const rhs = try self.parseBinaryExpr();
            const tag: syn.Node.Tag = switch (op) {
                .equal => .compare_equal,
                .not_equal => .compare_not_equal,
                .less_than => .compare_less,
                .greater_than => .compare_greater,
                .less_than_or_equal => .compare_less_equal,
                .greater_than_or_equal => .compare_greater_equal,
            };
            lhs = try self.addNode(tag, op_token, .{ .node_and_node = .{ .first = lhs, .second = rhs } });
        }
        return lhs;
    }

    fn parseAndExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parseComparisonExpr();

        while (self.tokenIs(.keyword_and)) {
            const op_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            const rhs = try self.parseComparisonExpr();
            lhs = try self.addNode(.logical_and, op_token, .{ .node_and_node = .{ .first = lhs, .second = rhs } });
        }

        return lhs;
    }

    fn parseOrExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parseAndExpr();

        while (self.tokenIs(.keyword_or)) {
            const op_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            const rhs = try self.parseAndExpr();
            lhs = try self.addNode(.logical_or, op_token, .{ .node_and_node = .{ .first = lhs, .second = rhs } });
        }

        return lhs;
    }

    fn parseUnwrapExpr(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        var lhs = try self.parseOrExpr();

        while (self.currentIdentifierEquals("unwrap_or") or self.currentIdentifierEquals("unwrap_or_do")) {
            const op_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            const is_do = self.currentIdentifierEquals("unwrap_or_do");
            self.advanceOne();
            const rhs = if (is_do)
                try self.parsePrimary()
            else
                try self.parseOrExpr();

            lhs = try self.addNode(if (is_do) .unwrap_or_do else .unwrap_or, op_token, .{ .node_and_node = .{ .first = lhs, .second = rhs } });
        }

        return lhs;
    }

    fn parseExpression(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        return self.parseUnwrapExpr();
    }

    fn parseNamedFunctionLikeDeclaration(
        self: *Syntaxer,
        name: ParsedName,
        is_once: bool,
        generic_params: []const syn.NodeIndex,
        generic_params_struct: ?syn.NodeIndex,
    ) SyntaxerError!syn.NodeIndex {
        const input = try self.parseStructTypeLiteral();

        if (!self.tokenIs(.arrow)) return SyntaxerError.ExpectedArrow;
        self.advanceOne();
        const output = try self.parseFunctionOutputType();
        if (!self.tokenIs(.colon)) return SyntaxerError.ExpectedColon;
        self.advanceOne();

        switch (self.current().content) {
            .identifier => |ident_range| {
                const ident_name = self.tokenText(ident_range);
                if (std.mem.eql(u8, ident_name, "ExternFunction") or std.mem.eql(u8, ident_name, "CFunction")) {
                    self.advanceOne();
                    const range = try self.addNodeRange(generic_params);
                    const extra = try self.addExtra(syn.FunctionExtra{
                        .generic_params_start = range.start,
                        .generic_params_end = range.end,
                        .generic_params_struct = syn.OptionalNodeIndex.init(generic_params_struct),
                        .input = input,
                        .output = output,
                        .body = .none,
                    });
                    return try self.addNode(if (is_once) .function_declaration_once else .function_declaration, name.token, .{ .extra = extra });
                }
            },
            else => {},
        }

        if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
        self.advanceOne();
        const body = try self.parseCodeBlock();

        const range = try self.addNodeRange(generic_params);
        const extra = try self.addExtra(syn.FunctionExtra{
            .generic_params_start = range.start,
            .generic_params_end = range.end,
            .generic_params_struct = syn.OptionalNodeIndex.init(generic_params_struct),
            .input = input,
            .output = output,
            .body = body.optional(),
        });
        return try self.addNode(if (is_once) .function_declaration_once else .function_declaration, name.token, .{ .extra = extra });
    }

    fn parseTestDeclaration(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const test_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        const test_loc = self.tokenLocation();
        self.advanceOne();
        self.skipNewLinesAndComments();

        const name = try self.parseName();
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;

        const decl_node = try self.parseNamedFunctionLikeDeclaration(name, false, &.{}, null);
        const function = self.file.functionDeclaration(decl_node).?;

        if (function.body == null) {
            try self.diags.add(test_loc, .syntax, "tests must define a body", .{});
            return SyntaxerError.ExpectedAssignment;
        }

        self.file.nodes.items(.tag)[@intFromEnum(decl_node)] = .test_declaration;
        self.file.nodes.items(.main_token)[@intFromEnum(decl_node)] = test_token;
        return decl_node;
    }

    // (old parseStatement removed; unified version with generics is below)

    // Override parseStatement to support generics on function declarations
    fn parseStatement(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const start_index = self.index;
        self.skipNewLinesAndComments();

        switch (self.current().content) {
            .keyword_return => return self.parseReturn(),
            .keyword_if => return self.parseIf(),
            .keyword_for => return self.parseFor(),
            .keyword_match => return self.parseMatch(),
            .keyword_while => return self.parseWhile(),
            .keyword_test => return self.parseTestDeclaration(),
            .keyword_break => {
                const token_index: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                return try self.addNode(.break_statement, token_index, .{ .unused = .{ 0, 0 } });
            },
            .keyword_continue => {
                const token_index: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
                self.advanceOne();
                return try self.addNode(.continue_statement, token_index, .{ .unused = .{ 0, 0 } });
            },
            else => {},
        }

        var is_once = false;
        if (self.tokenIs(.keyword_once)) {
            is_once = true;
            self.advanceOne();
            self.skipNewLinesAndComments();
        }

        if (self.tokenIs(.hash)) {
            const hash_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            const hash_loc = self.tokenLocation();
            self.advanceOne();
            const ident = try self.parseIdentifier();
            if (std.mem.eql(u8, ident, "defer")) {
                const expr = try self.parseExpression();
                return try self.addNode(.defer_statement, hash_token, .{ .node = expr });
            }
            if (std.mem.eql(u8, ident, "keep")) {
                const kept_name = try self.parseName();
                return try self.addNode(.keep_statement, hash_token, .{ .token = kept_name.token });
            }
            if (std.mem.eql(u8, ident, "import")) {
                try self.diags.add(hash_loc, .syntax, "#import must be assigned to a name", .{});
                return SyntaxerError.ExpectedDeclarationOrAssignment;
            }

            try self.diags.add(hash_loc, .syntax, "unknown directive '#{s}'", .{ident});
            return SyntaxerError.ExpectedDeclarationOrAssignment;
        }

        if (self.currentSentenceStartsChoiceOptionDeclaration()) {
            const decl_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
            self.advanceOne();
            const option_name = try self.parseName();
            return try self.addNode(.choice_option_declaration, decl_token, .{ .token = option_name.token });
        }

        if (self.current().content != .identifier and self.currentCanStartBareExpressionStatement()) {
            const expr = try self.parseExpression();
            return try self.addNode(.expression_statement, self.file.mainToken(expr), .{ .node = expr });
        }

        const id_loc = self.tokenLocation();
        var name = try self.parseName();

        if (std.mem.eql(u8, name.text, "operator")) {
            name = try self.parseOperatorName(name.token);
        }

        // Optional generic params after name.
        // In statement position this is ambiguous with generic call type arguments,
        // so keep the parsed named-args block around and decide once we know
        // whether this becomes a declaration or a call.
        var generic_params: []const syn.NodeIndex = &.{};
        var generic_params_struct: ?syn.NodeIndex = null;
        if (self.tokenIs(.hash)) {
            self.advanceOne();
            const gen_struct = try self.parseGenericParamsStruct();
            generic_params = self.file.structTypeLiteral(gen_struct).?.fields;
            generic_params_struct = gen_struct;
        } else if (self.tokenIs(.open_bracket) and self.lookaheadIsTypeArgument()) {
            const parsed = try self.parseGenericParamNames();
            generic_params = parsed;
        }

        // Build identifier node to parse postfix (for p.x, p& etc.)
        const ident_node = try self.addNode(.identifier, name.token, .{ .unused = .{ 0, 0 } });
        const lhs_with_postfix = try self.parsePostfix(ident_node);

        // Assignment (store/pointer/index/regular)
        if (self.tokenIs(.equal)) {
            if (is_once) {
                try self.diags.add(id_loc, .syntax, "once can only be used on function declarations", .{});
                return SyntaxerError.ExpectedDeclarationOrAssignment;
            }
            self.advanceOne();
            const rhs_expr = try self.parseExpression();

            if (lhs_with_postfix == ident_node) {
                return try self.addNode(.assignment, name.token, .{ .node = rhs_expr });
            } else if (self.file.tag(lhs_with_postfix) == .index_access) {
                return try self.addNode(.index_assignment, name.token, .{ .node_and_node = .{ .first = lhs_with_postfix, .second = rhs_expr } });
            } else {
                return try self.addNode(.pointer_assignment, name.token, .{ .node_and_node = .{ .first = lhs_with_postfix, .second = rhs_expr } });
            }
        }

        if (self.tokenIs(.open_parenthesis)) {
            if (self.looksLikeFunctionDeclarationInput(self.index)) {
                return try self.parseNamedFunctionLikeDeclaration(
                    name,
                    is_once,
                    generic_params,
                    generic_params_struct,
                );
            } else {
                if (is_once) {
                    try self.diags.add(id_loc, .syntax, "once can only be used on function declarations", .{});
                    return SyntaxerError.ExpectedDeclarationOrAssignment;
                }
                // call: Name(...)
                const input_node = try self.parseCollectionLiteral(true);
                const empty = try self.addNodeRange(&.{});
                const extra = try self.addExtra(syn.CallExtra{
                    .module_qualifier = .none,
                    .type_arguments_start = empty.start,
                    .type_arguments_end = empty.end,
                    .type_arguments_struct = syn.OptionalNodeIndex.init(generic_params_struct),
                    .input = input_node,
                });
                const call_node = try self.addNode(.function_call, name.token, .{ .extra = extra });
                const expr = try self.parsePostfix(call_node);
                if (expr == call_node) return call_node;
                return try self.addNode(.expression_statement, self.file.mainToken(expr), .{ .node = expr });
            }
        }

        // Abstract relations (implements/defaultsto)
        switch (self.current().content) {
            .identifier => |kw_range| {
                const kw = self.tokenText(kw_range);
                if (is_once) {
                    try self.diags.add(id_loc, .syntax, "once can only be used on function declarations", .{});
                    return SyntaxerError.ExpectedDeclarationOrAssignment;
                }
                if (std.mem.eql(u8, kw, "implements")) {
                    self.advanceOne();
                    const abstract_ty = (try self.parseType()).?; // required
                    const range = try self.addNodeRange(generic_params);
                    const extra = try self.addExtra(syn.GenericValueExtra{
                        .generic_params_start = range.start,
                        .generic_params_end = range.end,
                        .generic_params_struct = syn.OptionalNodeIndex.init(generic_params_struct),
                        .value = abstract_ty,
                    });
                    return try self.addNode(.abstract_implements, name.token, .{ .extra = extra });
                } else if (std.mem.eql(u8, kw, "defaultsto")) {
                    self.advanceOne();
                    const ty = (try self.parseType()).?; // required
                    const range = try self.addNodeRange(generic_params);
                    const extra = try self.addExtra(syn.GenericValueExtra{
                        .generic_params_start = range.start,
                        .generic_params_end = range.end,
                        .generic_params_struct = syn.OptionalNodeIndex.init(generic_params_struct),
                        .value = ty,
                    });
                    return try self.addNode(.abstract_defaultsto, name.token, .{ .extra = extra });
                }
            },
            else => {},
        }

        // Declarations: ":" or "::"
        if (self.tokenIs(.colon) or self.tokenIs(.double_colon)) {
            const mutable = self.tokenIs(.double_colon);
            self.advanceOne();

            const ty_opt = try self.parseType();

            if (ty_opt) |ty| {
                const type_name = if (self.file.tag(ty) == .type_name) self.tokenText(self.tokens[@intFromEnum(self.file.mainToken(ty))].content.identifier) else "";
                if (std.mem.eql(u8, type_name, "Type") or std.mem.eql(u8, type_name, "CEnum") or std.mem.eql(u8, type_name, "CUnion")) {
                    if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
                    self.advanceOne();
                    if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
                    const tag: syn.Node.Tag = if (std.mem.eql(u8, type_name, "CEnum")) .c_enum_declaration else if (std.mem.eql(u8, type_name, "CUnion")) .c_union_declaration else .type_declaration;
                    const lit_node = if (tag == .c_enum_declaration or (tag == .type_declaration and self.parenthesizedTypeIsChoiceLiteral()))
                        try self.parseChoiceTypeLiteral()
                    else
                        try self.parseStructTypeLiteral();
                    const range = try self.addNodeRange(generic_params);
                    const extra = try self.addExtra(syn.GenericValueExtra{
                        .generic_params_start = range.start,
                        .generic_params_end = range.end,
                        .generic_params_struct = syn.OptionalNodeIndex.init(generic_params_struct),
                        .value = lit_node,
                    });
                    return try self.addNode(tag, name.token, .{ .extra = extra });
                } else if (std.mem.eql(u8, type_name, "Abstract")) {
                    var req_names: []const syn.NodeIndex = &.{};
                    var req_funcs: []const syn.NodeIndex = &.{};
                    if (self.tokenIs(.equal)) {
                        self.advanceOne();
                        const body = try self.parseAbstractBody();
                        req_names = body.req_names;
                        req_funcs = body.req_funcs;
                    }
                    const generic_range = try self.addNodeRange(generic_params);
                    const names_range = try self.addNodeRange(req_names);
                    const funcs_range = try self.addNodeRange(req_funcs);
                    const extra = try self.addExtra(syn.AbstractExtra{
                        .generic_params_start = generic_range.start,
                        .generic_params_end = generic_range.end,
                        .generic_params_struct = syn.OptionalNodeIndex.init(generic_params_struct),
                        .requires_abstracts_start = names_range.start,
                        .requires_abstracts_end = names_range.end,
                        .requires_functions_start = funcs_range.start,
                        .requires_functions_end = funcs_range.end,
                    });
                    return try self.addNode(.abstract_declaration, name.token, .{ .extra = extra });
                }
            }

            var rhs: ?syn.NodeIndex = null;
            if (self.tokenIs(.equal)) {
                self.advanceOne();
                rhs = try self.parseExpression();
            }

            const extra = try self.addExtra(syn.FieldExtra{
                .type_node = syn.OptionalNodeIndex.init(ty_opt),
                .default_value = syn.OptionalNodeIndex.init(rhs),
            });
            return try self.addNode(if (mutable) .symbol_declaration_variable else .symbol_declaration_constant, name.token, .{ .extra = extra });
        }

        self.index = start_index;
        const expr = try self.parseExpression();
        return try self.addNode(.expression_statement, self.file.mainToken(expr), .{ .node = expr });
    }

    // ─────────────────────────────  SENTENCES  ──────────────────────────────
    fn parseSentences(self: *Syntaxer) !std.array_list.Managed(syn.NodeIndex) {
        var list = std.array_list.Managed(syn.NodeIndex).init(self.allocator);

        while (!self.tokenIs(.eof) and !self.tokenIs(.close_brace)) {
            switch (self.current().content) {
                .new_line, .comment => self.skipNewLinesAndComments(),
                else => {
                    const stmt = try self.parseStatement();
                    try list.append(stmt);
                },
            }
            self.skipNewLinesAndComments();
        }
        return list;
    }

    fn parseCodeBlock(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        if (!self.tokenIs(.open_brace)) return SyntaxerError.ExpectedLeftBrace;
        const open_token: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        self.advanceOne();
        const items = try self.parseSentences();
        if (!self.tokenIs(.close_brace)) return SyntaxerError.ExpectedRightBrace;
        self.advanceOne();
        return try self.addNode(.code_block, open_token, .{ .extra_range = try self.addNodeRange(items.items) });
    }

    fn parseIf(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const start: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        if (!self.tokenIs(.keyword_if)) return SyntaxerError.ExpectedKeywordIf;
        self.advanceOne();
        const cond = try self.parseExpression();
        const thenB = try self.parseCodeBlock();
        var elseB: ?syn.NodeIndex = null;
        if (self.tokenIs(.keyword_else)) {
            self.advanceOne();
            elseB = if (self.tokenIs(.keyword_if)) try self.parseIf() else try self.parseCodeBlock();
        }
        const extra = try self.addExtra(syn.IfExtra{ .then_block = thenB, .else_block = syn.OptionalNodeIndex.init(elseB) });
        return try self.addNode(.if_statement, start, .{ .node_and_extra = .{ .node = cond, .extra = extra } });
    }

    fn parseMatch(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const start: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        if (!self.tokenIs(.keyword_match)) return SyntaxerError.ExpectedDeclarationOrAssignment;
        self.advanceOne();
        const value = try self.parseExpression();
        self.skipNewLinesAndComments();
        if (!self.tokenIs(.open_brace)) return SyntaxerError.ExpectedLeftBrace;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var cases = std.array_list.Managed(syn.NodeIndex).init(self.allocator);
        while (!self.tokenIs(.close_brace)) {
            if (!self.tokenIs(.double_dot)) return SyntaxerError.ExpectedIdentifier;
            self.advanceOne();
            const variant_name = try self.parseName();

            var payload_name_token: ?syn.TokenIndex = null;
            var case_tag: syn.Node.Tag = .match_case_value;
            const case_has_payload_binding = switch (self.current().content) {
                .identifier, .tilde, .dollar, .ampersand => true,
                else => false,
            };
            if (case_has_payload_binding) {
                if (self.tokenIs(.tilde)) {
                    case_tag = .match_case_move;
                    self.advanceOne();
                } else if (self.tokenIs(.dollar)) {
                    case_tag = .match_case_mut_borrow;
                    self.advanceOne();
                    if (!self.tokenIs(.ampersand)) {
                        try self.diags.add(self.tokenLocation(), .syntax, "expected '&' after '$' in match payload binding", .{});
                        return SyntaxerError.ExpectedAmpersand;
                    }
                    self.advanceOne();
                } else if (self.tokenIs(.ampersand)) {
                    case_tag = .match_case_borrow;
                    self.advanceOne();
                }
                payload_name_token = (try self.parseName()).token;
            }

            self.skipNewLinesAndComments();
            const body = try self.parseCodeBlock();
            const case_extra = try self.addExtra(syn.MatchCaseExtra{ .payload_name = syn.OptionalTokenIndex.init(payload_name_token), .body = body });
            try cases.append(try self.addNode(case_tag, variant_name.token, .{ .extra = case_extra }));
            self.skipNewLinesAndComments();
        }

        self.advanceOne();
        const cases_range_index = try self.addExtra(try self.addNodeRange(cases.items));
        return try self.addNode(.match_statement, start, .{ .node_and_extra = .{ .node = value, .extra = cases_range_index } });
    }

    fn parseFor(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const start: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        if (!self.tokenIs(.keyword_for)) return SyntaxerError.ExpectedKeywordFor;
        self.advanceOne();
        var tag: syn.Node.Tag = .for_value;
        if (self.tokenIs(.dollar)) {
            self.advanceOne();
            if (!self.tokenIs(.ampersand)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected '&' after '$' in for binding", .{});
                return SyntaxerError.ExpectedAmpersand;
            }
            tag = .for_mut_borrow;
            self.advanceOne();
        } else if (self.tokenIs(.ampersand)) {
            tag = .for_borrow;
            self.advanceOne();
        }
        const item_name = try self.parseName();
        if (!self.tokenIs(.keyword_in)) return SyntaxerError.ExpectedKeywordIn;
        self.advanceOne();
        const iterable = try self.parseExpression();
        const body = try self.parseCodeBlock();
        return try self.addNode(tag, start, .{ .extra = try self.addExtra(syn.ForExtra{
            .name_token = item_name.token,
            .iterable = iterable,
            .body = body,
        }) });
    }

    fn parseWhile(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const start: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        if (!self.tokenIs(.keyword_while)) return SyntaxerError.ExpectedKeywordWhile;
        self.advanceOne();
        const cond = try self.parseExpression();
        const body = try self.parseCodeBlock();
        return try self.addNode(.while_statement, start, .{ .node_and_node = .{ .first = cond, .second = body } });
    }

    fn parseReturn(self: *Syntaxer) SyntaxerError!syn.NodeIndex {
        const start: syn.TokenIndex = @enumFromInt(@as(u32, @intCast(self.index)));
        if (!self.tokenIs(.keyword_return))
            return SyntaxerError.ExpectedKeywordReturn;

        self.advanceOne(); // consume 'return'

        // ── ¿hay algo más en la línea?  --------------------------
        // Si lo siguiente es fin de línea, un '}', o EOF, NO hay expresión.
        switch (self.current().content) {
            .new_line, .close_brace, .eof => {
                return try self.addNode(.return_statement, start, .{ .optional_node = .none });
            },
            else => {},
        }

        // ── otherwise parse the expression -----------------------
        const expr = try self.parseExpression();
        return try self.addNode(.return_statement, start, .{ .optional_node = expr.optional() });
    }

    // ─────────────────────────────  DEBUG  ──────────────────────────────────
    pub fn printST(self: *Syntaxer) void {
        std.debug.print("\nSYNTAX TREE\n", .{});
        for (self.file.roots.items) |node| synp.printNode(&self.file, node, 0);
        std.debug.print("\n", .{});
    }
};

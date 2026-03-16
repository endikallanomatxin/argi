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
    ExpectedAmpersand,
    ExpectedStringLiteral,
    OutOfMemory,
};

// ─────────────────────────────────────────────────────────────────────────────
// Syntaxer state
// ─────────────────────────────────────────────────────────────────────────────
pub const Syntaxer = struct {
    tokens: []const tok.Token,
    index: usize,
    allocator: *const std.mem.Allocator,
    st: std.array_list.Managed(*syn.STNode),
    diags: *diagnostic.Diagnostics,
    parsing_pipe_rhs: bool,

    pub fn init(alloc: *const std.mem.Allocator, toks: []const tok.Token, diags: *diagnostic.Diagnostics) Syntaxer {
        return .{
            .tokens = toks,
            .index = 0,
            .allocator = alloc,
            .st = std.array_list.Managed(*syn.STNode).init(alloc.*),
            .diags = diags,
            .parsing_pipe_rhs = false,
        };
    }

    pub fn parse(self: *Syntaxer) ![]const *syn.STNode {
        self.st = parseSentences(self) catch |err| {
            if (err == SyntaxerError.OutOfMemory) {
                try self.diags.add(self.tokenLocation(), .internal, "out of memory while parsing", .{});
            } else {
                try self.diags.add(self.tokenLocation(), .syntax, "syntax error: {s}", .{@errorName(err)});
            }
            std.debug.print("Parse error: {s}\n", .{@errorName(err)});
            return err;
        };
        return self.st.items; // slice inmutable a devolver
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
    fn makeNode(self: *Syntaxer, c: syn.Content, l: tok.Location) !*syn.STNode {
        const n = try self.allocator.create(syn.STNode);
        n.*.content = c;
        n.*.location = l;
        return n;
    }

    // ───────────────────────────────  atoms ──────────────────────────────────
    fn parseIdentifier(self: *Syntaxer) SyntaxerError![]const u8 {
        const t = self.current();
        if (t.content != .identifier) {
            try self.diags.add(self.tokenLocation(), .syntax, "expected identifier, found '{s}'", .{@tagName(self.current().content)});
            return SyntaxerError.ExpectedIdentifier;
        }
        const name = t.content.identifier;
        self.advanceOne();
        return name;
    }

    fn parseName(self: *Syntaxer) SyntaxerError!syn.Name {
        const loc = self.tokenLocation();
        const ident = try self.parseIdentifier();
        return .{ .string = ident, .location = loc };
    }

    fn parseOperatorName(self: *Syntaxer) SyntaxerError![]const u8 {
        if (std.meta.activeTag(self.current().content) != .identifier) {
            try self.diags.add(self.tokenLocation(), .syntax, "expected operator name after 'operator'", .{});
            return SyntaxerError.ExpectedIdentifier;
        }

        const ident = try self.parseIdentifier();

        if (std.mem.eql(u8, ident, "get") or std.mem.eql(u8, ident, "set")) {
            if (!self.tokenIs(.open_bracket)) return SyntaxerError.ExpectedLeftBracket;
            self.advanceOne();
            if (!self.tokenIs(.close_bracket)) return SyntaxerError.ExpectedRightBracket;
            self.advanceOne();
            return try std.fmt.allocPrint(self.allocator.*, "operator {s}[]", .{ident});
        }

        try self.diags.add(self.tokenLocation(), .syntax, "unsupported operator '{s}'", .{ident});
        return SyntaxerError.ExpectedIdentifier;
    }

    fn parseGenericParamNames(self: *Syntaxer) SyntaxerError![]const []const u8 {
        // Parses: [T, U, ...]
        if (!self.tokenIs(.open_bracket)) return SyntaxerError.ExpectedLeftBracket;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var names = std.array_list.Managed([]const u8).init(self.allocator.*);
        while (!self.tokenIs(.close_bracket)) {
            const n = try self.parseIdentifier();
            try names.append(n);
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

    fn parseTypeList(self: *Syntaxer) SyntaxerError![]const syn.Type {
        // Parses: [Type, &Type, ( .a: Type=..., ... ) , ...]
        if (!self.tokenIs(.open_bracket)) return SyntaxerError.ExpectedLeftBracket;
        self.advanceOne();
        self.skipNewLinesAndComments();
        var tys = std.array_list.Managed(syn.Type).init(self.allocator.*);
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
    fn parseType(self: *Syntaxer) SyntaxerError!?syn.Type {
        // permitimos omitir la anotación
        if (self.tokenIs(.equal) or self.tokenIs(.comma) or self.tokenIs(.close_parenthesis))
            return null;

        if (self.tokenIs(.open_bracket)) {
            const len_loc = self.tokenLocation();
            self.advanceOne();
            self.skipNewLinesAndComments();

            if (std.meta.activeTag(self.current().content) != .literal) {
                try self.diags.add(len_loc, .syntax, "expected array length integer literal", .{});
                return SyntaxerError.ExpectedIntLiteral;
            }

            const length = length_blk: {
                const lit = switch (self.current().content) {
                    .literal => |value| value,
                    else => unreachable,
                };
                switch (lit) {
                    .decimal_int_literal => |text| {
                        break :length_blk std.fmt.parseInt(usize, text, 10) catch {
                            try self.diags.add(len_loc, .syntax, "invalid array length literal", .{});
                            return SyntaxerError.ExpectedIntLiteral;
                        };
                    },
                    else => {
                        try self.diags.add(len_loc, .syntax, "array length must be a decimal integer literal", .{});
                        return SyntaxerError.ExpectedIntLiteral;
                    },
                }
            };
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
            const elem_ty = elem_ty_opt.?;
            const elem_ptr = try self.allocator.create(syn.Type);
            elem_ptr.* = elem_ty;

            const array_ty = try self.allocator.create(syn.ArrayType);
            array_ty.* = .{ .length = length, .element = elem_ptr };
            return syn.Type{ .array_type = array_ty };
        } else if (self.tokenIs(.ampersand) or self.tokenIs(.dollar)) {
            var mutability: syn.PointerMutability = .read_only;
            var op_loc = self.tokenLocation();

            if (self.tokenIs(.dollar)) {
                mutability = .read_write;
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
            const base_ty = base_ty_opt.?;

            const ptr_inner = try self.allocator.create(syn.Type);
            ptr_inner.* = base_ty;

            const ptr_ty = try self.allocator.create(syn.PointerType);
            ptr_ty.* = .{ .mutability = mutability, .child = ptr_inner };

            return syn.Type{ .pointer_type = ptr_ty };
        } else if (self.tokenIs(.open_parenthesis)) {
            const lit = try self.parseStructTypeLiteral();
            return syn.Type{ .struct_type_literal = lit };
        }

        var tname = try self.parseName();
        if (self.tokenIs(.dot)) {
            self.advanceOne();
            const rhs = try self.parseName();
            tname = .{
                .string = try std.fmt.allocPrint(self.allocator.*, "{s}.{s}", .{ tname.string, rhs.string }),
                .location = tname.location,
            };
        }
        if (self.tokenIs(.hash)) {
            self.advanceOne();
            const gen_args = try self.parseStructTypeLiteral();
            return syn.Type{ .generic_type_instantiation = .{ .base_name = tname, .args = gen_args } };
        }
        return syn.Type{ .type_name = tname };
    }

    // Parse an abstract body: a parenthesized, comma-separated list of items.
    // Each item can be:
    //   - an identifier: composed abstract name (e.g., Addable)
    //   - a function requirement: name ( StructTypeLiteral ) -> ( StructTypeLiteral )
    // Newlines and comments are ignored.
    fn parseAbstractBody(self: *Syntaxer) SyntaxerError!struct {
        req_names: []const []const u8,
        req_funcs: []const syn.AbstractFunctionRequirement,
    } {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var names = std.array_list.Managed([]const u8).init(self.allocator.*);
        var funcs = std.array_list.Managed(syn.AbstractFunctionRequirement).init(self.allocator.*);

        while (!self.tokenIs(.close_parenthesis)) {
            var name = try self.parseName();
            const name_loc = name.location;

            if (std.mem.eql(u8, name.string, "operator")) {
                const operator_name = try self.parseOperatorName();
                name = .{ .string = operator_name, .location = name_loc };
            }

            if (self.tokenIs(.open_parenthesis)) {
                const in_st = try self.parseStructTypeLiteral();
                if (!self.tokenIs(.arrow)) return SyntaxerError.ExpectedArrow;
                self.advanceOne();
                const out_st = try self.parseStructTypeLiteral();
                try funcs.append(.{
                    .name = name,
                    .input = in_st,
                    .output = out_st,
                });
            } else {
                try names.append(name.string); // composed abstracts siguen siendo []const []const u8
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

    fn parseListLiteral(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        const start_loc = self.tokenLocation();
        self.advanceOne();
        self.skipNewLinesAndComments();

        var elems = std.array_list.Managed(*syn.STNode).init(self.allocator.*);

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

        return try self.makeNode(
            .{ .list_literal = .{ .element_type = null, .elements = elems.items } },
            start_loc,
        );
    }

    // ( .field : Type? (= expr)? , ... )
    fn parseStructTypeLiteral(self: *Syntaxer) SyntaxerError!syn.StructTypeLiteral {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.array_list.Managed(syn.StructTypeLiteralField).init(self.allocator.*);

        while (!self.tokenIs(.close_parenthesis)) {
            if (!self.tokenIs(.dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected struct field, found '{s}'", .{@tagName(self.current().content)});
                return SyntaxerError.ExpectedStructField;
            }
            self.advanceOne();
            const fname = try self.parseName();

            var ftype: ?syn.Type = null;
            if (self.tokenIs(.colon)) {
                self.advanceOne();
                ftype = try self.parseType();
            }

            var def_val: ?*syn.STNode = null;
            if (self.tokenIs(.equal)) {
                self.advanceOne();
                def_val = try self.parseExpression();
            }

            try fields.append(.{ .name = fname, .type = ftype, .default_value = def_val });

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }
        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();

        return .{ .fields = fields.items };
    }

    fn parseChoiceTypeLiteral(self: *Syntaxer) SyntaxerError!syn.ChoiceTypeLiteral {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var variants = std.array_list.Managed(syn.ChoiceTypeLiteralVariant).init(self.allocator.*);

        while (!self.tokenIs(.close_parenthesis)) {
            var is_default = false;
            if (self.tokenIs(.equal)) {
                is_default = true;
                self.advanceOne();
                self.skipNewLinesAndComments();
            }

            if (!self.tokenIs(.double_dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected choice variant '..name'", .{});
                return SyntaxerError.ExpectedIdentifier;
            }
            self.advanceOne();
            const vname = try self.parseName();
            var payload_type: ?syn.StructTypeLiteral = null;
            if (self.tokenIs(.open_parenthesis)) {
                payload_type = try self.parseStructTypeLiteral();
            }
            try variants.append(.{ .name = vname, .is_default = is_default, .payload_type = payload_type });

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }

        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();
        return .{ .variants = variants.items };
    }

    // ─────── struct VALUE literal  (p.e.  (.x=1, .y=2) ) ─────────────────────
    fn parseStructValueLiteral(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        const start_loc = self.tokenLocation();
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.array_list.Managed(syn.StructValueLiteralField).init(self.allocator.*);

        while (!self.tokenIs(.close_parenthesis)) {
            if (!self.tokenIs(.dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected struct field, found '{s}'", .{@tagName(self.current().content)});
                return SyntaxerError.ExpectedStructField;
            }
            self.advanceOne();
            const fname = try self.parseName();

            if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
            self.advanceOne();

            const val = try self.parseExpression();
            try fields.append(.{ .name = fname, .value = val });

            self.skipNewLinesAndComments();
            if (self.tokenIs(.comma)) {
                self.advanceOne();
                self.skipNewLinesAndComments();
            }
        }
        if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
        self.advanceOne();

        return try self.makeNode(
            .{ .struct_value_literal = .{ .fields = fields.items } },
            start_loc,
        );
    }

    // ────────────────────────── postfix “.campo” chain ───────────────────────
    fn parsePostfix(self: *Syntaxer, mut: *syn.STNode) !*syn.STNode {
        var node = mut;
        while (true) {
            if (self.tokenIs(.dot)) {
                const dot_loc = self.tokenLocation();
                self.advanceOne();
                const fname = try self.parseName();
                const floc = self.tokenLocation();
                node = try self.makeNode(
                    .{ .struct_field_access = .{ .struct_value = node, .field_name = syn.Name{ .string = fname.string, .location = floc } } },
                    dot_loc,
                );
                continue;
            }

            if (self.tokenIs(.double_dot)) {
                const dd_loc = self.tokenLocation();
                self.advanceOne();
                const vname = try self.parseName();
                node = try self.makeNode(
                    .{ .choice_payload_access = .{
                        .choice_value = node,
                        .variant_name = vname,
                    } },
                    dd_loc,
                );
                continue;
            }

            if (self.tokenIs(.open_parenthesis)) {
                if (node.content == .struct_field_access and node.content.struct_field_access.struct_value.*.content == .identifier) {
                    const sfa = node.content.struct_field_access;
                    const module_name = sfa.struct_value.*.content.identifier;
                    const struct_value_literal = try self.parseStructValueLiteral();
                    node = try self.makeNode(
                        .{ .function_call = .{
                            .callee = sfa.field_name.string,
                            .callee_loc = sfa.field_name.location,
                            .module_qualifier = module_name,
                            .type_arguments = null,
                            .type_arguments_struct = null,
                            .input = struct_value_literal,
                        } },
                        sfa.field_name.location,
                    );
                    continue;
                }
            }

            if (self.tokenIs(.open_bracket)) {
                const bracket_loc = self.tokenLocation();
                self.advanceOne();
                const idx_expr = try self.parseExpression();
                if (!self.tokenIs(.close_bracket))
                    return SyntaxerError.ExpectedRightBracket;
                self.advanceOne();
                node = try self.makeNode(
                    .{ .index_access = .{ .value = node, .index = idx_expr } },
                    bracket_loc,
                );
                continue;
            }

            if (self.tokenIs(.ampersand)) {
                const amp_loc = self.tokenLocation();
                self.advanceOne();
                node = try self.makeNode(.{ .dereference = node }, amp_loc);
                continue;
            }

            break;
        }
        return node;
    }

    fn parsePipeCall(self: *Syntaxer) SyntaxerError!syn.PipeCall {
        const callee_loc = self.tokenLocation();
        const first_name = try self.parseName();

        var module_qualifier: ?[]const u8 = null;
        var callee_name = first_name.string;
        var final_callee_loc = callee_loc;
        if (self.tokenIs(.dot)) {
            self.advanceOne();
            const rhs_name = try self.parseName();
            module_qualifier = first_name.string;
            callee_name = rhs_name.string;
            final_callee_loc = rhs_name.location;
        }

        var args = std.array_list.Managed(*syn.STNode).init(self.allocator.*);

        const prev_pipe_rhs = self.parsing_pipe_rhs;
        self.parsing_pipe_rhs = true;
        defer self.parsing_pipe_rhs = prev_pipe_rhs;

        if (self.tokenIs(.open_parenthesis)) {
            self.advanceOne();
            self.skipNewLinesAndComments();
            while (!self.tokenIs(.close_parenthesis)) {
                const arg = try self.parseExpression();
                try args.append(arg);
                self.skipNewLinesAndComments();
                if (self.tokenIs(.comma)) {
                    self.advanceOne();
                    self.skipNewLinesAndComments();
                } else break;
            }
            if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
            self.advanceOne();
        }

        return .{
            .callee = callee_name,
            .callee_loc = final_callee_loc,
            .module_qualifier = module_qualifier,
            .args = args.items,
        };
    }

    // ─────────────────────────────  EXPRESSIONS  ─────────────────────────────
    /// [primary] {'.' fld}  (bin-op rhs)?
    fn parsePrimary(self: *Syntaxer) !*syn.STNode {
        const t = self.current();

        if (self.tokenIs(.ampersand) or self.tokenIs(.dollar)) {
            var mutability: syn.PointerMutability = .read_only;
            var op_loc = t.location;

            if (self.tokenIs(.dollar)) {
                mutability = .read_write;
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
            return try self.makeNode(.{ .address_of = .{ .value = inner, .mutability = mutability } }, op_loc);
        }

        if (self.tokenIs(.hash)) {
            const hash_loc = self.tokenLocation();
            self.advanceOne();
            const ident = try self.parseIdentifier();
            if (!std.mem.eql(u8, ident, "import")) {
                try self.diags.add(hash_loc, .syntax, "unknown directive '#{s}' in expression position", .{ident});
                return SyntaxerError.ExpectedDeclarationOrAssignment;
            }
            if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
            self.advanceOne();
            self.skipNewLinesAndComments();
            const lit = self.current();
            const path = switch (lit.content) {
                .literal => |literal| switch (literal) {
                    .string_literal => |text| text,
                    else => return SyntaxerError.ExpectedStringLiteral,
                },
                else => return SyntaxerError.ExpectedStringLiteral,
            };
            self.advanceOne();
            self.skipNewLinesAndComments();
            if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
            self.advanceOne();
            const node = try self.makeNode(.{ .import_statement = .{ .path = path } }, hash_loc);
            return try self.parsePostfix(node);
        }

        const base: *syn.STNode = switch (t.content) {
            .double_dot => blk: {
                self.advanceOne();
                const variant = try self.parseName();
                var payload: ?*syn.STNode = null;
                if (self.tokenIs(.open_parenthesis)) {
                    payload = try self.parseStructValueLiteral();
                }
                break :blk try self.makeNode(.{ .choice_literal = .{
                    .name = variant,
                    .payload = payload,
                } }, t.location);
            },

            // ─── ident  /  call ─────────────────────────────────────────────
            .identifier => blk: {
                const name = try self.parseIdentifier();
                if (self.parsing_pipe_rhs and std.mem.eql(u8, name, "_")) {
                    break :blk try self.makeNode(.{ .pipe_placeholder = .{} }, t.location);
                }
                var type_args: ?[]const syn.Type = null;
                var type_args_struct: ?syn.StructTypeLiteral = null;
                if (self.tokenIs(.open_bracket) and self.lookaheadIsTypeArgument()) {
                    // Explicit type arguments on call site (old syntax)
                    type_args = try self.parseTypeList();
                } else if (self.tokenIs(.hash)) {
                    // New syntax: #(.T: Int32)
                    self.advanceOne();
                    type_args_struct = try self.parseStructTypeLiteral();
                }
                if (self.tokenIs(.open_parenthesis)) { // llamada
                    const struct_value_literal = try self.parseStructValueLiteral();
                    break :blk try self.makeNode(
                        .{ .function_call = .{
                            .callee = name,
                            .callee_loc = t.location,
                            .module_qualifier = null,
                            .type_arguments = type_args,
                            .type_arguments_struct = type_args_struct,
                            .input = struct_value_literal,
                        } },
                        t.location,
                    );
                }
                break :blk try self.makeNode(.{ .identifier = name }, t.location);
            },

            // ─── literal ────────────────────────────────────────────────────
            .literal => |lit| blk: {
                self.advanceOne();
                break :blk try self.makeNode(.{ .literal = lit }, t.location);
            },

            // ─── struct value literal o list literal ─────────────────────────────────
            .open_parenthesis => blk: {
                // Mirar el primer token no-trivial tras '(' para decidir:
                var saw_dot = false;
                {
                    var idx: usize = self.index + 1;
                    while (idx < self.tokens.len) : (idx += 1) {
                        const tag = std.meta.activeTag(self.tokens[idx].content);
                        switch (tag) {
                            .new_line, .comment => continue,
                            .dot => {
                                saw_dot = true;
                            },
                            else => {},
                        }
                        break;
                    }
                }

                if (saw_dot) {
                    break :blk try self.parseStructValueLiteral();
                } else {
                    break :blk try self.parseListLiteral();
                }
            },

            // ─── bloque `{}` embebido ───────────────────────────────────────
            .open_brace => try self.parseCodeBlock(),

            else => return SyntaxerError.ExpectedIntLiteral,
        };

        // aplica cadenas de “.campo”
        return try self.parsePostfix(base);
    }

    fn parseExpression(self: *Syntaxer) SyntaxerError!*syn.STNode {
        const lhs = try self.parsePrimary();

        if (self.tokenIs(.pipe)) {
            const pipe_loc = self.tokenLocation();
            self.advanceOne();
            self.skipNewLinesAndComments();
            const call = try self.parsePipeCall();
            return try self.makeNode(
                .{ .pipe_expression = .{ .left = lhs, .call = call } },
                pipe_loc,
            );
        }

        // (solo bin-op derecha-recursivo por ahora)
        if (self.current().content == .binary_operator) {
            const op_tok = self.current();
            self.advanceOne();
            const rhs = try self.parseExpression();
            return try self.makeNode(
                .{ .binary_operation = .{ .operator = op_tok.content.binary_operator, .left = lhs, .right = rhs } },
                op_tok.location,
            );
        }

        if (self.current().content == .comparison_operator) {
            const op_tok = self.current();
            var op: tok.ComparisonOperator = undefined;
            switch (op_tok.content) {
                .comparison_operator => |c| op = c,
                else => unreachable,
            }
            self.advanceOne();
            const rhs = try self.parseExpression();
            return try self.makeNode(
                .{ .comparison = .{ .operator = op, .left = lhs, .right = rhs } },
                op_tok.location,
            );
        }
        return lhs;
    }

    // (old parseStatement removed; unified version with generics is below)

    // Override parseStatement to support generics on function declarations
    fn parseStatement(self: *Syntaxer) SyntaxerError!*syn.STNode {
        self.skipNewLinesAndComments();

        switch (self.current().content) {
            .keyword_return => return self.parseReturn(),
            .keyword_if => return self.parseIf(),
            .keyword_match => return self.parseMatch(),
            else => {},
        }

        if (self.tokenIs(.hash)) {
            const hash_loc = self.tokenLocation();
            self.advanceOne();
            const ident = try self.parseIdentifier();
            if (std.mem.eql(u8, ident, "defer")) {
                const expr = try self.parseExpression();
                return try self.makeNode(.{ .defer_statement = expr }, hash_loc);
            }
            if (std.mem.eql(u8, ident, "import")) {
                try self.diags.add(hash_loc, .syntax, "#import must be assigned to a name", .{});
                return SyntaxerError.ExpectedDeclarationOrAssignment;
            }

            try self.diags.add(hash_loc, .syntax, "unknown directive '#{s}'", .{ident});
            return SyntaxerError.ExpectedDeclarationOrAssignment;
        }

        const id_loc = self.tokenLocation();
        var name = try self.parseName();

        if (std.mem.eql(u8, name.string, "operator")) {
            const op = try self.parseOperatorName();
            name = .{ .string = op, .location = id_loc };
        }

        // Optional generic params after name (unchanged)
        var generic_params: []const []const u8 = &.{};
        if (self.tokenIs(.hash)) {
            self.advanceOne();
            const gen_struct = try self.parseStructTypeLiteral();
            var names = std.array_list.Managed([]const u8).init(self.allocator.*);
            for (gen_struct.fields) |fld| try names.append(fld.name.string);
            generic_params = names.items;
        } else if (self.tokenIs(.open_bracket) and self.lookaheadIsTypeArgument()) {
            const parsed = try self.parseGenericParamNames();
            generic_params = parsed;
        }

        // Build identifier node to parse postfix (for p.x, p& etc.)
        const ident_node = try self.makeNode(.{ .identifier = name.string }, id_loc);
        const lhs_with_postfix = try self.parsePostfix(ident_node);

        // Assignment (store/pointer/index/regular)
        if (self.tokenIs(.equal)) {
            self.advanceOne();
            const rhs_expr = try self.parseExpression();

            if (lhs_with_postfix == ident_node) {
                return try self.makeNode(
                    .{ .assignment = .{ .name = name, .value = rhs_expr } },
                    id_loc,
                );
            } else if (lhs_with_postfix.*.content == .index_access) {
                return try self.makeNode(
                    .{ .index_assignment = .{ .target = lhs_with_postfix, .value = rhs_expr } },
                    id_loc,
                );
            } else {
                return try self.makeNode(
                    .{ .pointer_assignment = .{ .target = lhs_with_postfix, .value = rhs_expr } },
                    id_loc,
                );
            }
        }

        if (self.tokenIs(.open_parenthesis)) {
            const input = try self.parseStructTypeLiteral();

            if (self.tokenIs(.arrow)) {
                self.advanceOne();
                const output = try self.parseStructTypeLiteral();
                if (!self.tokenIs(.colon)) return SyntaxerError.ExpectedColon;
                self.advanceOne();

                switch (self.current().content) {
                    .identifier => |ident_name| {
                        if (std.mem.eql(u8, ident_name, "ExternFunction")) {
                            self.advanceOne();
                            const ef = syn.FunctionDeclaration{
                                .name = name,
                                .generic_params = generic_params,
                                .input = input,
                                .output = output,
                                .body = null,
                            };
                            return try self.makeNode(.{ .function_declaration = ef }, id_loc);
                        }
                    },
                    else => {},
                }

                if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
                self.advanceOne();
                const body = try self.parseCodeBlock();

                const fn_decl = syn.FunctionDeclaration{
                    .name = name,
                    .generic_params = generic_params,
                    .input = input,
                    .output = output,
                    .body = body,
                };
                return try self.makeNode(.{ .function_declaration = fn_decl }, id_loc);
            } else {
                // call: Name(...)
                const input_node = try self.makeNode(.{ .struct_type_literal = input }, id_loc);
                return try self.makeNode(
                        .{ .function_call = .{
                            .callee = name.string,
                            .callee_loc = id_loc,
                            .module_qualifier = null,
                            .type_arguments = null,
                            .type_arguments_struct = null,
                            .input = input_node,
                    } },
                    id_loc,
                );
            }
        }

        // Abstract relations (canbe/defaultsto)
        switch (self.current().content) {
            .identifier => |kw| {
                if (std.mem.eql(u8, kw, "canbe")) {
                    self.advanceOne();
                    const ty = (try self.parseType()).?; // required
                    const rel = syn.AbstractCanBe{ .name = name.string, .generic_params = generic_params, .ty = ty };
                    return try self.makeNode(.{ .abstract_canbe = rel }, id_loc);
                } else if (std.mem.eql(u8, kw, "defaultsto")) {
                    self.advanceOne();
                    const ty = (try self.parseType()).?; // required
                    const rel = syn.AbstractDefault{ .name = name, .generic_params = generic_params, .ty = ty };
                    return try self.makeNode(.{ .abstract_defaultsto = rel }, id_loc);
                }
            },
            else => {},
        }

        // Declarations: ":" or "::"
        if (self.tokenIs(.colon) or self.tokenIs(.double_colon)) {
            var mut: syn.Mutability = .constant;
            if (self.tokenIs(.double_colon)) mut = .variable;
            self.advanceOne();

            const ty_opt = try self.parseType();

            if (ty_opt) |ty| {
                if (ty == .type_name and std.mem.eql(u8, ty.type_name.string, "Type")) {
                    if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
                    self.advanceOne();
                    if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
                    var idx = self.index + 1;
                    var parse_choice = false;
                    while (idx < self.tokens.len) : (idx += 1) {
                        const tag = std.meta.activeTag(self.tokens[idx].content);
                        switch (tag) {
                            .new_line, .comment => continue,
                            .double_dot => parse_choice = true,
                            .equal => {
                                var j = idx + 1;
                                while (j < self.tokens.len) : (j += 1) {
                                    const next_tag = std.meta.activeTag(self.tokens[j].content);
                                    switch (next_tag) {
                                        .new_line, .comment => continue,
                                        .double_dot => parse_choice = true,
                                        else => {},
                                    }
                                    break;
                                }
                            },
                            else => {},
                        }
                        break;
                    }
                    const lit_node = if (parse_choice) blk: {
                        const chlit = try self.parseChoiceTypeLiteral();
                        break :blk try self.makeNode(.{ .choice_type_literal = chlit }, id_loc);
                    } else blk: {
                        const stlit = try self.parseStructTypeLiteral();
                        break :blk try self.makeNode(.{ .struct_type_literal = stlit }, id_loc);
                    };

                    const tdecl = syn.TypeDeclaration{
                        .name = name,
                        .generic_params = generic_params,
                        .value = lit_node,
                    };
                    return try self.makeNode(.{ .type_declaration = tdecl }, id_loc);
                } else if (ty == .type_name and std.mem.eql(u8, ty.type_name.string, "Abstract")) {
                    var req_names: []const []const u8 = &.{};
                    var req_funcs: []const syn.AbstractFunctionRequirement = &.{};
                    if (self.tokenIs(.equal)) {
                        self.advanceOne();
                        const body = try self.parseAbstractBody();
                        req_names = body.req_names;
                        req_funcs = body.req_funcs;
                    }
                    const adecl = syn.AbstractDeclaration{
                        .name = name,
                        .generic_params = generic_params,
                        .requires_abstracts = req_names,
                        .requires_functions = req_funcs,
                    };
                    return try self.makeNode(.{ .abstract_declaration = adecl }, id_loc);
                }
            }

            var rhs: ?*syn.STNode = null;
            if (self.tokenIs(.equal)) {
                self.advanceOne();
                rhs = try self.parseExpression();
            }

            const sym = syn.SymbolDeclaration{
                .name = name,
                .type = ty_opt,
                .mutability = mut,
                .value = rhs,
            };
            return try self.makeNode(.{ .symbol_declaration = sym }, id_loc);
        }

        return SyntaxerError.ExpectedDeclarationOrAssignment;
    }

    // ─────────────────────────────  SENTENCES  ──────────────────────────────
    fn parseSentences(self: *Syntaxer) !std.array_list.Managed(*syn.STNode) {
        var list = std.array_list.Managed(*syn.STNode).init(self.allocator.*);

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

    fn parseCodeBlock(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(.open_brace)) return SyntaxerError.ExpectedLeftBrace;
        self.advanceOne();
        const items = try self.parseSentences();
        if (!self.tokenIs(.close_brace)) return SyntaxerError.ExpectedRightBrace;
        self.advanceOne();
        return try self.makeNode(.{ .code_block = .{ .items = items.items } }, self.tokenLocation());
    }

    fn parseIf(self: *Syntaxer) SyntaxerError!*syn.STNode {
        const start = self.tokenLocation();
        if (!self.tokenIs(.keyword_if)) return SyntaxerError.ExpectedKeywordIf;
        self.advanceOne();
        const cond = try self.parseExpression();
        const thenB = try self.parseCodeBlock();
        var elseB: ?*syn.STNode = null;
        if (self.tokenIs(.keyword_else)) {
            self.advanceOne();
            elseB = if (self.tokenIs(.keyword_if)) try self.parseIf() else try self.parseCodeBlock();
        }
        return try self.makeNode(
            .{ .if_statement = .{ .condition = cond, .then_block = thenB, .else_block = elseB } },
            start,
        );
    }

    fn parseMatch(self: *Syntaxer) SyntaxerError!*syn.STNode {
        const start = self.tokenLocation();
        if (!self.tokenIs(.keyword_match)) return SyntaxerError.ExpectedDeclarationOrAssignment;
        self.advanceOne();
        const value = try self.parseExpression();
        self.skipNewLinesAndComments();
        if (!self.tokenIs(.open_brace)) return SyntaxerError.ExpectedLeftBrace;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var cases = std.array_list.Managed(syn.MatchCase).init(self.allocator.*);
        while (!self.tokenIs(.close_brace)) {
            if (!self.tokenIs(.double_dot)) return SyntaxerError.ExpectedIdentifier;
            self.advanceOne();
            const variant_name = try self.parseName();

            var payload_binding: ?syn.Name = null;
            if (self.tokenIs(.open_parenthesis)) {
                self.advanceOne();
                payload_binding = try self.parseName();
                if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
                self.advanceOne();
            }

            self.skipNewLinesAndComments();
            const body = try self.parseCodeBlock();
            try cases.append(.{
                .variant_name = variant_name,
                .payload_binding = payload_binding,
                .body = body,
            });
            self.skipNewLinesAndComments();
        }

        self.advanceOne();
        return try self.makeNode(.{ .match_statement = .{
            .value = value,
            .cases = cases.items,
        } }, start);
    }
    fn parseReturn(self: *Syntaxer) SyntaxerError!*syn.STNode {
        const start = self.tokenLocation();
        if (!self.tokenIs(.keyword_return))
            return SyntaxerError.ExpectedKeywordReturn;

        self.advanceOne(); // consume 'return'

        // ── ¿hay algo más en la línea?  --------------------------
        // Si lo siguiente es fin de línea, un '}', o EOF, NO hay expresión.
        switch (self.current().content) {
            .new_line, .close_brace, .eof => {
                return try self.makeNode(
                    .{ .return_statement = .{ .expression = null } },
                    start,
                );
            },
            else => {},
        }

        // ── otherwise parse the expression -----------------------
        const expr = try self.parseExpression();
        return try self.makeNode(
            .{ .return_statement = .{ .expression = expr } },
            start,
        );
    }

    // ─────────────────────────────  DEBUG  ──────────────────────────────────
    pub fn printST(self: *Syntaxer) void {
        std.debug.print("\nSYNTAX TREE\n", .{});
        for (self.st.items) |n| synp.printNode(n.*, 0);
        std.debug.print("\n", .{});
    }
};

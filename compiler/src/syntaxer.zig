const std = @import("std");
const tok = @import("token.zig");
const tokp = @import("token_print.zig");
const syn = @import("syntax_tree.zig");
const synp = @import("syntax_tree_print.zig");

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
    ExpectedArrow,
    ExpectedDoubleColon,
    ExpectedAssignment,
    ExpectedDeclarationOrAssignment,
    ExpectedKeywordReturn,
    ExpectedKeywordIf,
    OutOfMemory,
};

// ─────────────────────────────────────────────────────────────────────────────
// Syntaxer state
// ─────────────────────────────────────────────────────────────────────────────
pub const Syntaxer = struct {
    tokens: []const tok.Token,
    index: usize,
    allocator: *const std.mem.Allocator,
    st: std.ArrayList(*syn.STNode),

    pub fn init(alloc: *const std.mem.Allocator, toks: []const tok.Token) Syntaxer {
        return .{
            .tokens = toks,
            .index = 0,
            .allocator = alloc,
            .st = std.ArrayList(*syn.STNode).init(alloc.*),
        };
    }

    pub fn parse(self: *Syntaxer) ![]const *syn.STNode {
        std.debug.print("\n\nsyntaxing...\n", .{});
        self.st = parseSentences(self) catch |err| {
            std.debug.print("Error al parsear: {any}\n", .{err});
            return err;
        };

        // Convert to const slice
        return self.st.items;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // token helpers
    // ─────────────────────────────────────────────────────────────────────────────
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

    fn skipNewLinesAndComments(self: *Syntaxer) void {
        while (self.index < self.tokens.len) {
            switch (self.current().content) {
                .new_line, .comment => self.advanceOne(),
                else => break,
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Node helpers
    // ─────────────────────────────────────────────────────────────────────────────
    fn makeNode(self: *Syntaxer, c: syn.Content, l: tok.Location) !*syn.STNode {
        const n = try self.allocator.create(syn.STNode);
        n.*.content = c;
        n.*.location = l;
        return n;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    //  Basic atoms
    // ─────────────────────────────────────────────────────────────────────────────
    fn parseIdentifier(self: *Syntaxer) SyntaxerError![]const u8 {
        const t = self.current();
        if (t.content != .identifier) return SyntaxerError.ExpectedIdentifier;
        const name = t.content.identifier;
        self.advanceOne();
        return name;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    //  TYPE  ( Type = ident | struct-type-literal )
    // ─────────────────────────────────────────────────────────────────────────────
    fn parseType(self: *Syntaxer) SyntaxerError!?syn.Type {
        // type annotation may be omitted
        if (self.tokenIs(.equal) or self.tokenIs(.comma) or self.tokenIs(.close_parenthesis))
            return null;

        if (self.tokenIs(.open_parenthesis)) {
            const lit = try self.parseStructTypeLiteral();
            return syn.Type{ .struct_type_literal = lit };
        }

        const name = try self.parseIdentifier();
        return syn.Type{ .type_name = name };
    }

    // ( .field : Type? (= expr)? , ... )
    fn parseStructTypeLiteral(self: *Syntaxer) SyntaxerError!syn.StructTypeLiteral {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.ArrayList(syn.StructTypeLiteralField).init(self.allocator.*);

        while (!self.tokenIs(.close_parenthesis)) {
            if (!self.tokenIs(.dot)) return SyntaxerError.ExpectedIdentifier;
            self.advanceOne();
            const fname = try self.parseIdentifier();

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

            try fields.append(.{
                .name = fname,
                .type = ftype,
                .default_value = def_val,
            });

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

    // ─────────────────────────────────────────────────────────────────────────────
    //  Struct VALUE literal (same syntax, but all fields are value-expressions)
    // ─────────────────────────────────────────────────────────────────────────────
    fn parseStructValueLiteral(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.ArrayList(syn.StructValueLiteralField).init(self.allocator.*);

        while (!self.tokenIs(.close_parenthesis)) {
            if (!self.tokenIs(.dot)) return SyntaxerError.ExpectedIdentifier;
            self.advanceOne();
            const fname = try self.parseIdentifier();

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
            self.tokenLocation(),
        );
    }

    // ─────────────────────────────────────────────────────────────────────────────
    //  Expressions  (subset-- only what changed)
    // ─────────────────────────────────────────────────────────────────────────────
    fn parsePrimary(self: *Syntaxer) !*syn.STNode {
        const t = self.current();
        return switch (t.content) {
            .identifier => blk: {
                // Could be call or bare identifier
                const name = try self.parseIdentifier();
                if (self.tokenIs(.open_parenthesis)) { // call
                    self.advanceOne();
                    self.skipNewLinesAndComments();
                    var args = std.ArrayList(syn.CallArgument).init(self.allocator.*);
                    while (!self.tokenIs(.close_parenthesis)) {
                        var arg_name: ?[]const u8 = null;
                        if (self.current().content == .identifier and self.next().?.content == .colon) {
                            arg_name = try self.parseIdentifier();
                            self.advanceOne(); // ':'
                        }
                        const val = try self.parseExpression();
                        try args.append(.{ .name = arg_name, .value = val });
                        if (self.tokenIs(.comma)) {
                            self.advanceOne();
                            self.skipNewLinesAndComments();
                        }
                    }
                    if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
                    self.advanceOne();

                    break :blk try self.makeNode(
                        .{ .function_call = .{ .callee = name, .args = args.items } },
                        t.location,
                    );
                }

                break :blk try self.makeNode(.{ .identifier = name }, t.location);
            },

            .literal => |lit| blk: {
                self.advanceOne();
                break :blk try self.makeNode(.{ .literal = lit }, t.location);
            },

            .open_parenthesis => try self.parseStructValueLiteral(),

            .open_bracket => blk: {
                self.advanceOne();
                const e = try self.parseExpression();
                if (!self.tokenIs(.close_bracket)) {
                    return SyntaxerError.ExpectedRightBracket;
                }
                self.advanceOne();
                break :blk e;
            },

            .open_brace => try self.parseCodeBlock(),
            else => SyntaxerError.ExpectedIntLiteral,
        };
    }

    fn parseExpression(self: *Syntaxer) SyntaxerError!*syn.STNode {
        // De momento: sin precedencia completa – igual que antes.
        // Solo binario simple   <prim> <op> <expr>?
        const lhs = try self.parsePrimary();
        if (self.current().content == .binary_operator or
            self.current().content == .check_equals or
            self.current().content == .check_not_equals)
        {
            const op_tok = self.current();
            var op: tok.BinaryOperator = undefined;
            switch (op_tok.content) {
                .binary_operator => |b| op = b,
                .check_equals => op = .equals,
                .check_not_equals => op = .not_equals,
                else => unreachable,
            }
            self.advanceOne();
            const rhs = try self.parseExpression();
            return try self.makeNode(
                .{ .binary_operation = .{ .operator = op, .left = lhs, .right = rhs } },
                op_tok.location,
            );
        }
        return lhs;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    //  Declarations, assignments, etc.
    // ─────────────────────────────────────────────────────────────────────────────
    fn parseStatement(self: *Syntaxer) SyntaxerError!*syn.STNode {
        self.skipNewLinesAndComments();

        switch (self.current().content) {
            .keyword_return => return self.parseReturn(),
            .keyword_if => return self.parseIf(),
            else => {},
        }

        const id_loc = self.tokenLocation();
        const name = try self.parseIdentifier();

        // ---------- FUNCTION DECLARATION ----------
        if (self.tokenIs(.open_parenthesis)) {
            // parse input struct-type-literal
            const input = try self.parseStructTypeLiteral();
            if (!self.tokenIs(.arrow)) return SyntaxerError.ExpectedArrow;
            self.advanceOne();
            const output = try self.parseStructTypeLiteral();
            if (!self.tokenIs(.colon)) return SyntaxerError.ExpectedColon;
            self.advanceOne();
            if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
            self.advanceOne();

            // body
            const body = try self.parseCodeBlock();

            const fn_decl = syn.FunctionDeclaration{
                .name = name,
                .input = input,
                .output = output,
                .body = body,
            };
            return try self.makeNode(.{ .function_declaration = fn_decl }, id_loc);
        }

        // ---------- ASSIGNMENT ----------
        if (self.tokenIs(.equal)) {
            self.advanceOne();
            const val = try self.parseExpression();
            return try self.makeNode(
                .{ .assignment = .{ .name = name, .value = val } },
                id_loc,
            );
        }

        // ---------- TYPE DECLARATION  ( Foo = (<struct-type-literal>) ) ----------
        if (self.tokenIs(.equal)) unreachable; // already handled
        if (self.tokenIs(.colon) or self.tokenIs(.double_colon) or self.tokenIs(.open_parenthesis)) {
            // SYMBOL DECLARATION or TYPE DECLARATION
            var mut: syn.Mutability = .constant;
            if (self.tokenIs(.double_colon)) {
                mut = .variable;
            }
            if (self.tokenIs(.colon) or self.tokenIs(.double_colon)) self.advanceOne();

            // type annotation MAY be omitted for symbols
            const ty_opt = try self.parseType();

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

        // ---------- TYPE DECLARATION (Foo = (.x:Int) afuera) ----------
        if (self.tokenIs(.equal)) {
            self.advanceOne();
            if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
            const stlit = try self.parseStructTypeLiteral();
            const lit_node = try self.makeNode(.{ .struct_type_literal = stlit }, id_loc);

            const tdecl = syn.TypeDeclaration{
                .name = name,
                .value = lit_node,
            };
            return try self.makeNode(.{ .type_declaration = tdecl }, id_loc);
        }

        return SyntaxerError.ExpectedDeclarationOrAssignment;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    //  Higher-level constructs (unchanged except for node tags)
    // ─────────────────────────────────────────────────────────────────────────────
    fn parseSentences(self: *Syntaxer) !std.ArrayList(*syn.STNode) {
        var list = std.ArrayList(*syn.STNode).init(self.allocator.*);
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
        return try self.makeNode(.{ .if_statement = .{ .condition = cond, .then_block = thenB, .else_block = elseB } }, start);
    }

    fn parseReturn(self: *Syntaxer) SyntaxerError!*syn.STNode {
        const start = self.tokenLocation();
        if (!self.tokenIs(.keyword_return)) return SyntaxerError.ExpectedKeywordReturn;
        self.advanceOne();
        const expr = try self.parseExpression();
        return try self.makeNode(.{ .return_statement = .{ .expression = expr } }, start);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    pub fn printST(self: *Syntaxer) void {
        std.debug.print("\nSYNTAX TREE\n", .{});
        for (self.st.items) |n| synp.printNode(n.*, 0);
        std.debug.print("\n", .{});
    }
};

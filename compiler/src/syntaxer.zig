const std = @import("std");
const tok = @import("token.zig");
const tokp = @import("token_print.zig");
const syn = @import("syntax_tree.zig");
const synp = @import("syntax_tree_print.zig");
const diagnostic = @import("diagnostic.zig");

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
    diags: *diagnostic.Diagnostics,

    pub fn init(alloc: *const std.mem.Allocator, toks: []const tok.Token, diags: *diagnostic.Diagnostics) Syntaxer {
        return .{
            .tokens = toks,
            .index = 0,
            .allocator = alloc,
            .st = std.ArrayList(*syn.STNode).init(alloc.*),
            .diags = diags,
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

    fn parseGenericParamNames(self: *Syntaxer) SyntaxerError![]const []const u8 {
        // Parses: [T, U, ...]
        if (!self.tokenIs(.open_bracket)) return SyntaxerError.ExpectedLeftBracket;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var names = std.ArrayList([]const u8).init(self.allocator.*);
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
        var tys = std.ArrayList(syn.Type).init(self.allocator.*);
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

        if (self.tokenIs(.ampersand)) { // &T
            self.advanceOne();
            const base_ty = (try self.parseType()).?; // recursivo

            // guardar el sub-tipo en heap: debe vivir más que esta llamada
            const ptr_inner = try self.allocator.create(syn.Type);
            ptr_inner.* = base_ty;

            return syn.Type{ .pointer_type = ptr_inner };
        } else if (self.tokenIs(.open_parenthesis)) {
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
            if (!self.tokenIs(.dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected struct field, found '{s}'", .{@tagName(self.current().content)});
                return SyntaxerError.ExpectedStructField;
            }
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

    // ─────── struct VALUE literal  (p.e.  (.x=1, .y=2) ) ─────────────────────
    fn parseStructValueLiteral(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(.open_parenthesis)) return SyntaxerError.ExpectedLeftParen;
        self.advanceOne();
        self.skipNewLinesAndComments();

        var fields = std.ArrayList(syn.StructValueLiteralField).init(self.allocator.*);

        while (!self.tokenIs(.close_parenthesis)) {
            if (!self.tokenIs(.dot)) {
                try self.diags.add(self.tokenLocation(), .syntax, "expected struct field, found '{s}'", .{@tagName(self.current().content)});
                return SyntaxerError.ExpectedStructField;
            }
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

    // ────────────────────────── postfix “.campo” chain ───────────────────────
    fn parsePostfix(self: *Syntaxer, mut: *syn.STNode) !*syn.STNode {
        var new_mut = mut;
        while (true) {
            if (self.tokenIs(.dot)) {
                const dot_loc = self.tokenLocation();
                self.advanceOne(); // consume '.'
                const fld_name = try self.parseIdentifier();
                new_mut = try self.makeNode(
                    .{ .struct_field_access = .{ .struct_value = mut, .field_name = fld_name } },
                    dot_loc,
                );
            } else if (self.tokenIs(.ampersand)) {
                // POST-FIX `&`  ==>  **dereference**
                const amp_loc = self.tokenLocation();
                self.advanceOne(); // consume '&'
                new_mut = try self.makeNode(.{ .dereference = new_mut }, amp_loc);
            } else break;
        }
        return new_mut;
    }

    // ─────────────────────────────  EXPRESSIONS  ─────────────────────────────
    /// [primary] {'.' fld}  (bin-op rhs)?
    fn parsePrimary(self: *Syntaxer) !*syn.STNode {
        const t = self.current();

        if (self.tokenIs(.ampersand)) {
            const loc = t.location;
            self.advanceOne();
            const inner = try self.parsePrimary(); // recursivo
            return try self.makeNode(.{ .address_of = inner }, loc);
        }

        const base: *syn.STNode = switch (t.content) {
            // ─── ident  /  call ─────────────────────────────────────────────
            .identifier => blk: {
                const name = try self.parseIdentifier();
                var type_args: ?[]const syn.Type = null;
                var type_args_struct: ?syn.StructTypeLiteral = null;
                if (self.tokenIs(.open_bracket)) {
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
                        .{ .function_call = .{ .callee = name, .type_arguments = type_args, .type_arguments_struct = type_args_struct, .input = struct_value_literal } },
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

            // ─── struct value literal ───────────────────────────────────────
            .open_parenthesis => try self.parseStructValueLiteral(),

            // ─── [expr] en corchetes ────────────────────────────────────────
            .open_bracket => blk: {
                self.advanceOne();
                const e = try self.parseExpression();
                if (!self.tokenIs(.close_bracket))
                    return SyntaxerError.ExpectedRightBracket;
                self.advanceOne();
                break :blk e;
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
            else => {},
        }

        const id_loc = self.tokenLocation();
        const name = try self.parseIdentifier();

        // Allow optional generic parameter block after name for function declarations
        var generic_params: []const []const u8 = &.{};
        if (self.tokenIs(.hash)) {
            self.advanceOne();
            const gen_struct = try self.parseStructTypeLiteral();
            // Extract parameter names from fields: id#(.T: Type, .U: Type)
            var names = std.ArrayList([]const u8).init(self.allocator.*);
            for (gen_struct.fields) |fld| try names.append(fld.name);
            generic_params = names.items;
        } else if (self.tokenIs(.open_bracket)) {
            // Back-compat: old syntax name[T, U]
            const parsed = try self.parseGenericParamNames();
            generic_params = parsed;
        }

        // Build identifier node and (optionally) consume postfix chains so
        // we can detect pointer‑dereference assignments like `p& = 0`.
        const ident_node = try self.makeNode(.{ .identifier = name }, id_loc);
        const lhs_with_postfix = try self.parsePostfix(ident_node);

        // ─── Assignment (simple or pointer) ───────────────────
        if (self.tokenIs(.equal)) {
            self.advanceOne();
            const rhs_expr = try self.parseExpression();

            if (lhs_with_postfix == ident_node) {
                // Regular binding reassignment
                return try self.makeNode(
                    .{ .assignment = .{ .name = name, .value = rhs_expr } },
                    id_loc,
                );
            } else {
                // Store through dereference or field
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

                // caso ExternFunction
                switch (self.current().content) {
                    .identifier => |ident_name| {
                        if (std.mem.eql(u8, ident_name, "ExternFunction")) {
                            // Consumimos la palabra clave
                            self.advanceOne();
                            // Construimos el nodo
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

                // caso normal: ":= { ... }"
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
                // Si no hay flecha, es una llamada a función.
                const input_node = try self.makeNode(
                    .{ .struct_type_literal = input },
                    id_loc,
                );
                return try self.makeNode(
                    .{ .function_call = .{ .callee = name, .type_arguments = null, .type_arguments_struct = null, .input = input_node } },
                    id_loc,
                );
            }
        }

        // ----------- ASSIGNMENT --------------------------------------------
        if (self.tokenIs(.equal)) {
            self.advanceOne();
            const val = try self.parseExpression();
            return try self.makeNode(
                .{ .assignment = .{ .name = name, .value = val } },
                id_loc,
            );
        }

        // ----------- SYMBOL / TYPE DECLARATION -----------------------------
        if (self.tokenIs(.colon) or self.tokenIs(.double_colon)) {
            var mut: syn.Mutability = .constant;
            if (self.tokenIs(.double_colon)) mut = .variable;
            self.advanceOne();

            const ty_opt = try self.parseType();

            // Check for type declaration
            if (ty_opt) |ty| {
                if (ty == .type_name and std.mem.eql(u8, ty.type_name, "Type")) {
                    if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
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
        return try self.makeNode(
            .{ .if_statement = .{ .condition = cond, .then_block = thenB, .else_block = elseB } },
            start,
        );
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

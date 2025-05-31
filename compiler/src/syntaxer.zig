const std = @import("std");
const tok = @import("token.zig");
const syn = @import("syntax_tree.zig");

pub const SyntaxerError = error{
    ExpectedIdentifier,
    ExpectedColon,
    ExpectedEqual,
    ExpectedIntLiteral,
    ExpectedLeftParen,
    ExpectedRightParen,
    ExpectedLeftBrace,
    ExpectedRightBrace,
    ExpectedTypeAnnotation,
    ExpectedDoubleColon,
    ExpectedAssignment,
    ExpectedDeclarationOrAssignment,
    ExpectedFuncAssignment,
    ExpectedKeywordReturn,
    OutOfMemory,
};

/// Estado del syntaxer
pub const Syntaxer = struct {
    tokens: []const tok.Token,
    index: usize,
    allocator: *const std.mem.Allocator,
    st: std.ArrayList(*syn.st.STNode),

    pub fn init(allocator: *const std.mem.Allocator, tokens: []const tok.Token) Syntaxer {
        return Syntaxer{
            .tokens = tokens,
            .index = 0,
            .allocator = allocator,
            .ast = std.ArrayList(*syn.STNode).init(allocator.*),
        };
    }

    pub fn parse(self: *Syntaxer) !std.ArrayList(*syn.STNode) {
        std.debug.print("\n\nPARSING\n", .{});
        self.ast = parseSentences(self) catch |err| {
            std.debug.print("Error al parsear: {any}\n", .{err});
            return err;
        };
        return self.ast;
    }

    fn current(self: *Syntaxer) tok.Token {
        if (self.index < self.tokens.len) {
            return self.tokens[self.index];
        }
        return tok.Token.eof;
    }

    fn next(self: *Syntaxer) tok.Token {
        if (self.index + 1 < self.tokens.len) {
            return self.tokens[self.index + 1];
        }
        return tok.Token.eof;
    }

    fn advance(self: *Syntaxer) void {
        std.debug.print("Parseado token: ", .{});
        tok.printToken(self.current());
        if (self.index < self.tokens.len) self.index += 1;
    }

    fn tokenIs(self: *Syntaxer, expected: tok.Token) bool {
        return switch (self.current()) {
            tok.Token.eof => switch (expected) {
                tok.Token.eof => true,
                else => false,
            },
            tok.Token.comment => switch (expected) {
                tok.Token.comment => true,
                else => false,
            },
            tok.Token.new_line => switch (expected) {
                tok.Token.new_line => true,
                else => false,
            },
            tok.Token.identifier => switch (expected) {
                tok.Token.identifier => true,
                else => false,
            },
            tok.Token.literal => switch (expected) {
                tok.Token.literal => true,
                else => false,
            },
            tok.Token.colon => switch (expected) {
                tok.Token.colon => true,
                else => false,
            },
            tok.Token.double_colon => switch (expected) {
                tok.Token.double_colon => true,
                else => false,
            },
            tok.Token.equal => switch (expected) {
                tok.Token.equal => true,
                else => false,
            },
            tok.Token.open_brace => switch (expected) {
                tok.Token.open_brace => true,
                else => false,
            },
            tok.Token.close_brace => switch (expected) {
                tok.Token.close_brace => true,
                else => false,
            },
            tok.Token.open_parenthesis => switch (expected) {
                tok.Token.open_parenthesis => true,
                else => false,
            },
            tok.Token.close_parenthesis => switch (expected) {
                tok.Token.close_parenthesis => true,
                else => false,
            },
            tok.Token.keyword_return => switch (expected) {
                tok.Token.keyword_return => true,
                else => false,
            },
            else => false,
        };
    }

    fn expect(self: *Syntaxer, expected: tok.Token) !SyntaxerError {
        if (!self.tokenIs(expected)) return SyntaxerError.ExpectedAssignment;
        self.advance();
        return;
    }

    fn ignoreNewLinesAndComments(self: *Syntaxer) void {
        while (self.index < self.tokens.len) {
            const token = self.current();
            if (token == tok.Token.new_line or tok == tok.Token.comment) {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn parseIdentifier(self: *Syntaxer) ![]const u8 {
        const token = self.current();
        return switch (token) {
            tok.Token.identifier => |name| {
                self.advance();
                return name;
            },
            else => return SyntaxerError.ExpectedIdentifier,
        };
    }

    fn parseType(self: *Syntaxer) SyntaxerError!?syn.TypeLiteral {
        if (self.tokenIs(tok.Token.equal)) {
            return null;
        }
        const typeName = try self.parseIdentifier();
        return try self.allocator.create(syn.TypeLiteral, .{ .name = typeName });
    }

    fn parseLiteral(self: *Syntaxer) !*syn.STNode {
        const token = self.current();
        return switch (token.literal) {
            .int_literal => |value| {
                self.advance();
                const intLiteral = try self.allocator.create(syn.IntLiteral);
                intLiteral.* = syn.IntLiteral{ .value = value };
                const valLiteral = try self.allocator.create(syn.ValueLiteral);
                valLiteral.* = syn.ValueLiteral{ .intLiteral = intLiteral };
                const node = try self.allocator.create(syn.STNode);
                node.* = syn.STNode{ .valueLiteral = valLiteral };
                return node;
            },
            .float_literal => |value| {
                self.advance();
                const floatLiteral = try self.allocator.create(syn.FloatLiteral);
                floatLiteral.* = syn.FloatLiteral{ .value = @floatCast(value) };
                const valLiteral = try self.allocator.create(syn.ValueLiteral);
                valLiteral.* = syn.ValueLiteral{ .floatLiteral = floatLiteral };
                const node = try self.allocator.create(syn.STNode);
                node.* = syn.STNode{ .valueLiteral = valLiteral };
                return node;
            },
            else => return SyntaxerError.ExpectedIntLiteral,
        };
    }

    fn parseSymbolOrLiteral(self: *Syntaxer) !*syn.STNode {
        const token = self.current();
        return switch (token) {
            tok.Token.identifier => |_| {
                const name = try self.parseIdentifier();
                const node = try self.allocator.create(syn.STNode);
                node.* = syn.STNode{ .identifier = name };
                return node;
            },
            tok.Token.literal => {
                return self.parseLiteral();
            },
            else => return SyntaxerError.ExpectedIntLiteral,
        };
    }

    fn parseExpression(self: *Syntaxer) !*syn.STNode {
        const token = self.current();
        return switch (token) {
            tok.Token.literal, tok.Token.identifier => {
                // Check if the next token is a binary operator
                if (self.next() == tok.Token.binary_operator) {
                    const left = try self.parseSymbolOrLiteral();

                    const op = self.current().binary_operator;
                    self.advance(); // consume binary operator
                    const right = try self.parseExpression();

                    const node = try self.allocator.create(syn.STNode);
                    const binOp = try self.allocator.create(syn.BinaryOperation);
                    binOp.* = syn.BinaryOperation{ .operator = op, .left = left, .right = right };
                    node.* = syn.STNode{ .binaryOperation = binOp };
                    return node;
                }

                const node = try parseSymbolOrLiteral(self);
                return node;
            },
            tok.Token.open_parenthesis => {
                self.advance();
                const expr = try self.parseExpression();
                if (!self.tokenIs(tok.Token.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
                self.advance();
                return expr;
            },
            tok.Token.open_brace => {
                return self.parseCodeBlock();
            },
            else => return SyntaxerError.ExpectedIntLiteral,
        };
    }

    fn parseDeclarationOrAssignment(self: *Syntaxer) SyntaxerError!*syn.STNode {
        const name = try self.parseIdentifier();

        var kind: ?syn.SymbolKind = null;
        // Check for parenthesis
        if (self.tokenIs(tok.Token.open_parenthesis)) {
            self.advance(); // consume '('
            const args = try self.parseArguments();
            std.debug.print("args: {any}\n", .{args});
            if (!self.tokenIs(tok.Token.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
            self.advance(); // consume ')'
            kind = syn.SymbolKind.Function;
        }

        // Assignment
        if (self.tokenIs(tok.Token.equal)) {
            self.advance(); // consume '='
            const value = try self.parseExpression();
            const node = try self.allocator.create(syn.STNode);
            const assign = try self.allocator.create(syn.Assignment);
            assign.* = syn.Assignment{ .name = name, .value = value };
            node.* = syn.STNode{ .assignment = assign };
            return node;
        }

        var tipo: ?syn.TypeLiteral = null;
        // Declaration
        if (self.tokenIs(tok.Token.colon) or self.tokenIs(tok.Token.double_colon)) {
            // Check for another : indicating variable declaration (::)
            var mutability = syn.Mutability.Const;
            if (self.tokenIs(tok.Token.double_colon)) {
                mutability = syn.Mutability.Var;
            }
            self.advance(); // consume ':' or '::'

            if (kind == null) {
                tipo = try self.parseType();
            }
            var value: ?*syn.STNode = null;
            if (!self.tokenIs(tok.Token.new_line)) {
                if (!self.tokenIs(tok.Token.equal)) return SyntaxerError.ExpectedEqual;
                self.advance(); // consume '='
                value = try self.parseExpression();
            }
            const node = try self.allocator.create(syn.STNode);
            const decl = try self.allocator.create(syn.Declaration);
            // Asumimos que no hay argumentos, por eso usamos undefined.
            const args: []const syn.Argument = undefined;
            decl.* = syn.Declaration{
                .name = name,
                .kind = kind orelse null,
                .type = tipo orelse null,
                .mutability = mutability,
                .args = args,
                .value = value,
            };
            node.* = syn.STNode{ .declaration = decl };
            return node;
        }

        return SyntaxerError.ExpectedDeclarationOrAssignment;
    }

    fn parseArguments(self: *Syntaxer) SyntaxerError![]const syn.Argument {
        var args = std.ArrayList(syn.Argument).init(self.allocator.*);
        while (self.index < self.tokens.len and !self.tokenIs(tok.Token.close_parenthesis)) {
            const name = try self.parseIdentifier();
            if (!self.tokenIs(tok.Token.colon)) return SyntaxerError.ExpectedColon;
            self.advance(); // consume ':'
            const tipo = try self.parseType();
            const arg = syn.Argument{ .name = name, .type = tipo orelse null, .mutability = syn.Mutability.Var };
            try args.append(arg);
            if (self.tokenIs(tok.Token.comma)) {
                self.advance(); // consume ','
            }
        }
        return args.items;
    }

    fn parseSentences(self: *Syntaxer) !std.ArrayList(*syn.STNode) {
        var ast = std.ArrayList(*syn.STNode).init(self.allocator.*);
        while (self.index < self.tokens.len and !self.tokenIs(tok.Token.eof) and !self.tokenIs(tok.Token.close_brace)) {
            self.ignoreNewLinesAndComments();
            switch (self.current()) {
                tok.Token.keyword_return => {
                    const retNode = try self.parseReturn();
                    try ast.append(retNode);
                },
                else => {
                    const declNode = try self.parseDeclarationOrAssignment();
                    try ast.append(declNode);
                },
            }
            self.ignoreNewLinesAndComments();
        }
        return ast;
    }

    fn parseCodeBlock(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(tok.Token.open_brace)) return SyntaxerError.ExpectedLeftBrace;
        self.advance(); // consume '{'
        const list = try self.parseSentences();
        if (!self.tokenIs(tok.Token.close_brace)) return SyntaxerError.ExpectedRightBrace;
        self.advance(); // consume '}'
        const node = try self.allocator.create(syn.STNode);
        const codeBlock = try self.allocator.create(syn.CodeBlock);
        codeBlock.* = syn.CodeBlock{ .items = list.items };
        node.* = syn.STNode{ .codeBlock = codeBlock };
        return node;
    }

    fn parseReturn(self: *Syntaxer) SyntaxerError!*syn.STNode {
        // Verificar que el token actual es 'keyword_return'
        if (!self.tokenIs(tok.Token.keyword_return)) {
            return SyntaxerError.ExpectedKeywordReturn;
        }
        self.advance(); // consume 'keyword_return'

        // Intentamos parsear una expresión que se retorne.
        const expr = try self.parseExpression();

        const node = try self.allocator.create(syn.STNode);
        const retStmt = try self.allocator.create(syn.ReturnStmt);
        retStmt.* = syn.ReturnStmt{ .expression = expr };
        node.* = syn.STNode{ .returnStmt = retStmt };
        return node;
    }

    pub fn printAST(self: *Syntaxer) void {
        std.debug.print("\nast:\n", .{});
        for (self.st.items) |node| {
            node.print(0);
        }
    }
};

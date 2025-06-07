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
    ExpectedLeftBrace,
    ExpectedRightBrace,
    ExpectedTypeAnnotation,
    ExpectedDoubleColon,
    ExpectedAssignment,
    ExpectedDeclarationOrAssignment,
    ExpectedFuncAssignment,
    ExpectedKeywordReturn,
    ExpectedKeywordIf,
    OutOfMemory,
};

/// Estado del syntaxer
pub const Syntaxer = struct {
    tokens: []const tok.Token,
    index: usize,
    allocator: *const std.mem.Allocator,
    st: std.ArrayList(*syn.STNode),

    pub fn init(allocator: *const std.mem.Allocator, tokens: []const tok.Token) Syntaxer {
        return Syntaxer{
            .tokens = tokens,
            .index = 0,
            .allocator = allocator,
            .st = std.ArrayList(*syn.STNode).init(allocator.*),
        };
    }

    pub fn parse(self: *Syntaxer) !std.ArrayList(*syn.STNode) {
        std.debug.print("\n\nPARSING\n", .{});
        self.st = parseSentences(self) catch |err| {
            std.debug.print("Error al parsear: {any}\n", .{err});
            return err;
        };
        return self.st;
    }

    fn current(self: *Syntaxer) tok.Token {
        return self.tokens[self.index];
    }

    fn next(self: *Syntaxer) ?tok.Token {
        if (self.tokenIs(tok.Content.eof)) {
            return null;
        }
        return self.tokens[self.index + 1];
    }

    fn advanceOne(self: *Syntaxer) void {
        std.debug.print("Parseado token: ", .{});
        tokp.printToken(self.current());
        if (self.index < self.tokens.len) self.index += 1;
    }

    fn tokenIs(self: *Syntaxer, expected: tok.Content) bool {
        return switch (self.current().content) {
            .eof => switch (expected) {
                .eof => true,
                else => false,
            },
            .comment => switch (expected) {
                .comment => true,
                else => false,
            },
            .new_line => switch (expected) {
                .new_line => true,
                else => false,
            },
            .identifier => switch (expected) {
                .identifier => true,
                else => false,
            },
            .literal => switch (expected) {
                .literal => true,
                else => false,
            },
            .colon => switch (expected) {
                .colon => true,
                else => false,
            },
            .double_colon => switch (expected) {
                .double_colon => true,
                else => false,
            },
            .arrow => switch (expected) {
                .arrow => true,
                else => false,
            },
            .equal => switch (expected) {
                .equal => true,
                else => false,
            },
            .open_brace => switch (expected) {
                .open_brace => true,
                else => false,
            },
            .close_brace => switch (expected) {
                .close_brace => true,
                else => false,
            },
            .open_parenthesis => switch (expected) {
                .open_parenthesis => true,
                else => false,
            },
            .close_parenthesis => switch (expected) {
                .close_parenthesis => true,
                else => false,
            },
            .keyword_return => switch (expected) {
                .keyword_return => true,
                else => false,
            },
            .keyword_if => switch (expected) {
                .keyword_if => true,
                else => false,
            },
            .keyword_else => switch (expected) {
                .keyword_else => true,
                else => false,
            },
            else => false,
        };
    }

    fn tokenLocation(self: *Syntaxer) tok.Location {
        return self.current().location;
    }

    fn expect(self: *Syntaxer, expected: tok.Token) !SyntaxerError {
        if (!self.tokenIs(expected)) return SyntaxerError.ExpectedAssignment;
        self.advanceOne();
        return;
    }

    fn ignoreNewLinesAndComments(self: *Syntaxer) void {
        while (self.index < self.tokens.len) {
            const token = self.current();
            if (token.content == .new_line or token.content == .comment) {
                self.advanceOne();
            } else {
                break;
            }
        }
    }

    fn newNode(self: *Syntaxer, content: syn.Content, location: tok.Location) !*syn.STNode {
        const node = try self.allocator.create(syn.STNode);
        node.*.content = content;
        node.*.location = location;
        return node;
    }

    fn parseIdentifier(self: *Syntaxer) ![]const u8 {
        const token = self.current();
        return switch (token.content) {
            .identifier => |name| {
                self.advanceOne();
                return name;
            },
            else => return SyntaxerError.ExpectedIdentifier,
        };
    }

    fn parseType(self: *Syntaxer) SyntaxerError!?syn.TypeName {
        if (self.tokenIs(.equal)) {
            return null;
        }
        const typeName = try self.parseIdentifier();
        return syn.TypeName{ .name = typeName };
    }

    fn parseLiteral(self: *Syntaxer) !*syn.STNode {
        const token = self.current();
        const node = try self.allocator.create(syn.STNode);
        node.*.content = syn.Content{ .literal = token.content.literal };
        node.*.location = token.location;
        self.advanceOne();
        return node;
    }

    fn parseSymbolOrLiteral(self: *Syntaxer) !*syn.STNode {
        const token = self.current();
        return switch (token.content) {
            .identifier => |_| {
                const name = try self.parseIdentifier();
                const node = try self.allocator.create(syn.STNode);
                node.*.content = syn.Content{ .identifier = name };
                node.*.location = token.location;
                return node;
            },
            .literal => {
                return self.parseLiteral();
            },
            else => return SyntaxerError.ExpectedIntLiteral,
        };
    }

    fn parseExpression(self: *Syntaxer) !*syn.STNode {
        const token = self.current();
        return switch (token.content) {
            .literal, .identifier => {
                // call-expression?  <ident> '(' ...
                if (token.content == .identifier and self.next().?.content == .open_parenthesis) {
                    const callee = try self.parseIdentifier(); // consumed ident
                    self.advanceOne(); // consume '('

                    // --- parse comma-separated arg list -----------------------
                    var arg_nodes = std.ArrayList(syn.CallArgument).init(self.allocator.*);
                    self.ignoreNewLinesAndComments();
                    while (!self.tokenIs(.close_parenthesis)) {
                        var name: ?[]const u8 = null;
                        if (self.current().content == .identifier and self.next().?.content == .colon) {
                            name = try self.parseIdentifier();
                            self.advanceOne(); // consume ':'
                        }
                        const val = try self.parseExpression();
                        try arg_nodes.append(.{ .name = name, .value = val });
                        if (self.tokenIs(.comma)) {
                            self.advanceOne();
                            self.ignoreNewLinesAndComments();
                        } else {
                            break;
                        }
                    }
                    if (!self.tokenIs(.close_parenthesis)) {
                        return SyntaxerError.ExpectedRightParen;
                    }
                    self.advanceOne(); // consume ')'

                    const node = try self.allocator.create(syn.STNode);
                    node.*.location = token.location;
                    node.*.content = syn.Content{
                        .function_call = .{
                            .callee = callee,
                            .args = arg_nodes.items,
                        },
                    };
                    return node;
                }

                // Check if the next token is a binary operator
                if (self.next().?.content == .binary_operator or
                    self.next().?.content == .check_equals or
                    self.next().?.content == .check_not_equals)
                {
                    const left = try self.parseSymbolOrLiteral();

                    const op_token = self.current();
                    var op: tok.BinaryOperator = undefined;
                    switch (op_token.content) {
                        .binary_operator => |bop| op = bop,
                        .check_equals => op = tok.BinaryOperator.equals,
                        .check_not_equals => op = tok.BinaryOperator.not_equals,
                        else => unreachable,
                    }
                    self.advanceOne(); // consume operator
                    const right = try self.parseExpression();

                    const node = try self.allocator.create(syn.STNode);
                    node.*.content = syn.Content{ .binary_operation = syn.BinaryOperation{ .operator = op, .left = left, .right = right } };
                    node.*.location = token.location;
                    return node;
                }

                const node = try parseSymbolOrLiteral(self);
                return node;
            },
            .open_parenthesis => {
                self.advanceOne();
                const expr = try self.parseExpression();
                if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
                self.advanceOne();
                return expr;
            },
            .open_brace => {
                return self.parseCodeBlock();
            },
            else => return SyntaxerError.ExpectedIntLiteral,
        };
    }

    fn parseDeclarationOrAssignment(self: *Syntaxer) SyntaxerError!*syn.STNode {
        const name = try self.parseIdentifier();

        var kind: syn.SymbolKind = .binding;
        var ret_type: ?syn.TypeName = null;
        var fn_args: ?[]const syn.Argument = null;
        // Check for parenthesis (function)
        if (self.tokenIs(.open_parenthesis)) {
            self.advanceOne(); // consume '('
            const args = try self.parseArguments();
            std.debug.print("args: {any}\n", .{args});
            if (!self.tokenIs(.close_parenthesis)) return SyntaxerError.ExpectedRightParen;
            self.advanceOne(); // consume ')'
            fn_args = args;
            kind = .function;

            if (self.tokenIs(.arrow)) {
                self.advanceOne(); // consume '->'
                ret_type = try self.parseType();
            }
        }

        // Assignment
        if (self.tokenIs(.equal)) {
            self.advanceOne(); // consume '='
            const value = try self.parseExpression();
            const node = try self.allocator.create(syn.STNode);
            node.*.content = syn.Content{ .assignment = syn.Assignment{ .name = name, .value = value } };
            node.*.location = self.tokenLocation();
            return node;
        }

        var tipo: ?syn.TypeName = if (kind == .function) ret_type else null;
        // Declaration
        if (self.tokenIs(.colon) or self.tokenIs(.double_colon)) {
            var mutability: syn.Mutability = .constant;
            if (self.tokenIs(.double_colon)) {
                mutability = .variable;
            }
            self.advanceOne(); // consume ':' or '::'

            if (kind != .function) {
                tipo = try self.parseType();
            }
            var value: ?*syn.STNode = null;
            if (!self.tokenIs(.new_line)) {
                if (!self.tokenIs(.equal)) return SyntaxerError.ExpectedEqual;
                self.advanceOne(); // consume '='
                value = try self.parseExpression();
            }
            const node = try self.allocator.create(syn.STNode);
            const decl = syn.Declaration{
                .name = name,
                .kind = kind,
                .type = tipo orelse null,
                .mutability = mutability,
                .args = if (kind == .function) fn_args else null,
                .value = value,
            };
            node.*.content = syn.Content{ .declaration = decl };
            node.*.location = self.tokenLocation();
            return node;
        }

        return SyntaxerError.ExpectedDeclarationOrAssignment;
    }

    fn parseArguments(self: *Syntaxer) SyntaxerError![]const syn.Argument {
        var args = std.ArrayList(syn.Argument).init(self.allocator.*);
        while (self.index < self.tokens.len and !self.tokenIs(.close_parenthesis)) {
            const name = try self.parseIdentifier();
            if (!self.tokenIs(.colon)) return SyntaxerError.ExpectedColon;
            self.advanceOne(); // consume ':'
            const tipo = try self.parseType();
            const arg = syn.Argument{ .name = name, .type = tipo orelse null, .mutability = syn.Mutability.variable };
            try args.append(arg);
            if (self.tokenIs(.comma)) {
                self.advanceOne(); // consume ','
            }
        }
        return args.items;
    }

    fn parseSentences(self: *Syntaxer) !std.ArrayList(*syn.STNode) {
        var st = std.ArrayList(*syn.STNode).init(self.allocator.*);
        while (self.index < self.tokens.len and !self.tokenIs(tok.Content.eof) and !self.tokenIs(.close_brace)) {
            self.ignoreNewLinesAndComments();
            switch (self.current().content) {
                .keyword_return => {
                    const retNode = try self.parseReturn();
                    try st.append(retNode);
                },
                .keyword_if => {
                    const ifNode = try self.parseIf();
                    try st.append(ifNode);
                },
                else => {
                    const declNode = try self.parseDeclarationOrAssignment();
                    try st.append(declNode);
                },
            }
            self.ignoreNewLinesAndComments();
        }
        return st;
    }

    fn parseCodeBlock(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(.open_brace)) return SyntaxerError.ExpectedLeftBrace;
        self.advanceOne(); // consume '{'
        const list = try self.parseSentences();
        if (!self.tokenIs(.close_brace)) return SyntaxerError.ExpectedRightBrace;
        self.advanceOne(); // consume '}'
        const node = try self.allocator.create(syn.STNode);
        node.*.content = syn.Content{ .code_block = syn.CodeBlock{ .items = list.items } };
        node.*.location = self.tokenLocation();
        return node;
    }

    fn parseIf(self: *Syntaxer) SyntaxerError!*syn.STNode {
        if (!self.tokenIs(.keyword_if)) return SyntaxerError.ExpectedKeywordIf;
        const loc = self.tokenLocation();
        self.advanceOne(); // consume 'if'

        const condition = try self.parseExpression();
        const then_block = try self.parseCodeBlock();

        var else_block: ?*syn.STNode = null;
        if (self.tokenIs(.keyword_else)) {
            self.advanceOne();
            if (self.tokenIs(.keyword_if)) {
                else_block = try self.parseIf();
            } else {
                else_block = try self.parseCodeBlock();
            }
        }

        const node = try self.allocator.create(syn.STNode);
        node.*.content = syn.Content{ .if_statement = syn.IfStatement{
            .condition = condition,
            .then_block = then_block,
            .else_block = else_block,
        } };
        node.*.location = loc;
        return node;
    }

    fn parseReturn(self: *Syntaxer) SyntaxerError!*syn.STNode {
        // Verificar que el token actual es 'keyword_return'
        if (!self.tokenIs(.keyword_return)) {
            return SyntaxerError.ExpectedKeywordReturn;
        }
        self.advanceOne(); // consume 'keyword_return'

        // Intentamos parsear una expresión que se retorne.
        const expr = try self.parseExpression();

        const node = try self.allocator.create(syn.STNode);
        node.*.content = syn.Content{ .return_statement = syn.ReturnStatement{ .expression = expr } };
        node.*.location = self.tokenLocation();
        return node;
    }

    pub fn printST(self: *Syntaxer) void {
        std.debug.print("\nst:\n", .{});
        for (self.st.items) |node| {
            synp.printNode(node.*, 0);
        }
    }
};

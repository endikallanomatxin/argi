const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;

pub const AST = struct {
    nodes: []const *ASTNode,
};

pub const ASTNode = union(enum) {
    declaration: *Declaration,
    assignment: *Assignment,
    identifier: []const u8,
    codeBlock: *CodeBlock,
    valueLiteral: *ValueLiteral,
    typeLiteral: *TypeLiteral,
    returnStmt: *ReturnStmt,
    binaryOperation: *BinaryOperation,

    pub fn print(self: ASTNode, indent: usize) void {
        printIndent(indent);
        switch (self) {
            ASTNode.declaration => |decl| {
                std.debug.print("Declaration {s} ({s}) =\n", .{ decl.*.name, if (decl.*.mutability == Mutability.Var) "var" else "const" });
                // Se incrementa el nivel de indentación para el nodo hijo.
                if (decl.*.value) |v| {
                    v.print(indent + 1);
                }
            },
            ASTNode.assignment => |assign| {
                std.debug.print("Assignment {s} =\n", .{assign.*.name});
                // Se incrementa el nivel de indentación para el nodo hijo.
                assign.*.value.print(indent + 1);
            },
            ASTNode.identifier => |ident| {
                std.debug.print("identifier: {s}\n", .{ident});
            },
            ASTNode.codeBlock => |codeBlock| {
                std.debug.print("code block:\n", .{});
                for (codeBlock.*.items) |item| {
                    item.print(indent + 1);
                }
            },
            ASTNode.valueLiteral => |valueLiteral| {
                switch (valueLiteral.*) {
                    ValueLiteral.intLiteral => |intLit| {
                        std.debug.print("IntLiteral {d}\n", .{intLit.value});
                    },
                    ValueLiteral.floatLiteral => |floatLit| {
                        std.debug.print("FloatLiteral {}\n", .{floatLit.value});
                    },
                    ValueLiteral.doubleLiteral => |doubleLit| {
                        std.debug.print("DoubleLiteral {}\n", .{doubleLit.value});
                    },
                    ValueLiteral.charLiteral => |charLit| {
                        std.debug.print("CharLiteral {c}\n", .{charLit.value});
                    },
                    ValueLiteral.boolLiteral => |boolLit| {
                        std.debug.print("BoolLiteral {}\n", .{boolLit.value});
                    },
                    ValueLiteral.stringLiteral => |stringLit| {
                        std.debug.print("StringLiteral {s}\n", .{stringLit.value});
                    },
                }
            },
            ASTNode.typeLiteral => |typeLiteral| {
                std.debug.print("TypeLiteral: ", .{});
                switch (typeLiteral.*.type) {
                    Type.Int32 => std.debug.print("Int32\n", .{}),
                    Type.Int => std.debug.print("Int\n", .{}),
                    Type.Float => std.debug.print("Float\n", .{}),
                    Type.Double => std.debug.print("Double\n", .{}),
                    Type.Char => std.debug.print("Char\n", .{}),
                    Type.Bool => std.debug.print("Bool\n", .{}),
                    Type.String => std.debug.print("String\n", .{}),
                    Type.Array => std.debug.print("Array\n", .{}),
                    Type.Struct => std.debug.print("Struct\n", .{}),
                    Type.Enum => std.debug.print("Enum\n", .{}),
                    Type.Union => std.debug.print("Union\n", .{}),
                    Type.Pointer => std.debug.print("Pointer\n", .{}),
                    Type.Function => std.debug.print("Function\n", .{}),
                }
            },
            ASTNode.returnStmt => |returnStmt| {
                std.debug.print("return\n", .{});
                if (returnStmt.expression) |expr| {
                    // Se incrementa la indentación para la expresión retornada.
                    expr.print(indent + 1);
                }
            },
            ASTNode.binaryOperation => |binOp| {
                std.debug.print("BinaryOperation\n", .{});
                binOp.left.print(indent + 1);
                binOp.right.print(indent + 1);
            },
        }
    }
};

pub const Declaration = struct {
    name: []const u8,
    type: ?Type,
    mutability: Mutability,
    args: []const Argument,
    value: ?*ASTNode,

    pub fn isFunction(self: Declaration) bool {
        const v = self.value orelse return false;
        // if the value points to a code block, then it's a function
        switch (v.*) {
            ASTNode.codeBlock => return true,
            else => return false,
        }
    }
};

pub const Assignment = struct {
    name: []const u8,
    value: *ASTNode,
};

pub const Mutability = enum {
    Const,
    Var,
};

pub const CodeBlock = struct {
    items: []const *ASTNode,
    // Return args in the future.
};

pub const Argument = struct {
    name: []const u8,
    mutability: Mutability,
    type: Type,
};

pub const TypeLiteral = struct {
    type: Type,
};

pub const Type = enum {
    Int32,
    Int,
    Float,
    Double,
    Char,
    Bool,
    String,
    Array,
    Struct,
    Enum,
    Union,
    Pointer,
    Function,
};

pub const ValueLiteral = union(enum) {
    intLiteral: *IntLiteral,
    floatLiteral: *FloatLiteral,
    doubleLiteral: *DoubleLiteral,
    charLiteral: *CharLiteral,
    boolLiteral: *BoolLiteral,
    stringLiteral: *StringLiteral,
};

pub const IntLiteral = struct {
    value: i64,
};

pub const FloatLiteral = struct {
    value: f32,
};

pub const DoubleLiteral = struct {
    value: f64,
};

pub const CharLiteral = struct {
    value: u8,
};

pub const BoolLiteral = struct {
    value: bool,
};

pub const StringLiteral = struct {
    value: []const u8,
};

pub const ReturnStmt = struct {
    expression: ?*ASTNode,
};

pub const BinaryOperation = struct {
    operator: lexer.BinaryOperator,
    left: *ASTNode,
    right: *ASTNode,
};

pub const ParseError = error{
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

/// Estado del parser.
pub const Parser = struct {
    tokens: []const Token,
    index: usize,
    allocator: *const std.mem.Allocator,
    ast: std.ArrayList(*ASTNode),

    pub fn init(allocator: *const std.mem.Allocator, tokens: []const lexer.Token) Parser {
        return Parser{
            .tokens = tokens,
            .index = 0,
            .allocator = allocator,
            .ast = std.ArrayList(*ASTNode).init(allocator.*),
        };
    }

    pub fn parse(self: *Parser) !std.ArrayList(*ASTNode) {
        std.debug.print("\n\nPARSING\n", .{});
        self.ast = parseSentences(self) catch |err| {
            std.debug.print("Error al parsear: {any}\n", .{err});
            return err;
        };
        return self.ast;
    }

    fn current(self: *Parser) Token {
        if (self.index < self.tokens.len) {
            return self.tokens[self.index];
        }
        return Token.eof;
    }

    fn next(self: *Parser) Token {
        if (self.index + 1 < self.tokens.len) {
            return self.tokens[self.index + 1];
        }
        return Token.eof;
    }

    fn advance(self: *Parser) void {
        std.debug.print("Parseado token: ", .{});
        lexer.printToken(self.current());
        if (self.index < self.tokens.len) self.index += 1;
    }

    fn tokenIs(self: *Parser, expected: Token) bool {
        return switch (self.current()) {
            Token.eof => switch (expected) {
                Token.eof => true,
                else => false,
            },
            Token.comment => switch (expected) {
                Token.comment => true,
                else => false,
            },
            Token.new_line => switch (expected) {
                Token.new_line => true,
                else => false,
            },
            Token.identifier => switch (expected) {
                Token.identifier => true,
                else => false,
            },
            Token.literal => switch (expected) {
                Token.literal => true,
                else => false,
            },
            Token.colon => switch (expected) {
                Token.colon => true,
                else => false,
            },
            Token.double_colon => switch (expected) {
                Token.double_colon => true,
                else => false,
            },
            Token.equal => switch (expected) {
                Token.equal => true,
                else => false,
            },
            Token.open_brace => switch (expected) {
                Token.open_brace => true,
                else => false,
            },
            Token.close_brace => switch (expected) {
                Token.close_brace => true,
                else => false,
            },
            Token.open_parenthesis => switch (expected) {
                Token.open_parenthesis => true,
                else => false,
            },
            Token.close_parenthesis => switch (expected) {
                Token.close_parenthesis => true,
                else => false,
            },
            Token.keyword_return => switch (expected) {
                Token.keyword_return => true,
                else => false,
            },
            else => false,
        };
    }

    fn expect(self: *Parser, expected: Token) !ParseError {
        if (!self.tokenIs(expected)) return ParseError.ExpectedAssignment;
        self.advance();
        return;
    }

    fn ignoreNewLinesAndComments(self: *Parser) void {
        while (self.index < self.tokens.len) {
            const tok = self.current();
            if (tok == Token.new_line or tok == Token.comment) {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn parseIdentifier(self: *Parser) ![]const u8 {
        const tok = self.current();
        return switch (tok) {
            Token.identifier => |name| {
                self.advance();
                return name;
            },
            else => return ParseError.ExpectedIdentifier,
        };
    }

    fn parseType(self: *Parser) ParseError!?Type {
        if (self.tokenIs(Token.equal)) {
            return null;
        }
        const typeName = try self.parseIdentifier();
        if (std.mem.eql(u8, typeName, "Int")) {
            return Type.Int;
        } else if (std.mem.eql(u8, typeName, "Float")) {
            return Type.Float;
        } else if (std.mem.eql(u8, typeName, "Double")) {
            return Type.Double;
        } else if (std.mem.eql(u8, typeName, "Char")) {
            return Type.Char;
        } else if (std.mem.eql(u8, typeName, "Bool")) {
            return Type.Bool;
        } else if (std.mem.eql(u8, typeName, "String")) {
            return Type.String;
        } else {
            return ParseError.ExpectedTypeAnnotation;
        }
    }

    fn parseLiteral(self: *Parser) !*ASTNode {
        const tok = self.current();
        return switch (tok.literal) {
            .int_literal => |value| {
                self.advance();
                const intLiteral = try self.allocator.create(IntLiteral);
                intLiteral.* = IntLiteral{ .value = value };
                const valLiteral = try self.allocator.create(ValueLiteral);
                valLiteral.* = ValueLiteral{ .intLiteral = intLiteral };
                const node = try self.allocator.create(ASTNode);
                node.* = ASTNode{ .valueLiteral = valLiteral };
                return node;
            },
            .float_literal => |value| {
                self.advance();
                const floatLiteral = try self.allocator.create(FloatLiteral);
                floatLiteral.* = FloatLiteral{ .value = @floatCast(value) };
                const valLiteral = try self.allocator.create(ValueLiteral);
                valLiteral.* = ValueLiteral{ .floatLiteral = floatLiteral };
                const node = try self.allocator.create(ASTNode);
                node.* = ASTNode{ .valueLiteral = valLiteral };
                return node;
            },
            else => return ParseError.ExpectedIntLiteral,
        };
    }

    fn parseSymbolOrLiteral(self: *Parser) !*ASTNode {
        const tok = self.current();
        return switch (tok) {
            Token.identifier => |_| {
                const name = try self.parseIdentifier();
                const node = try self.allocator.create(ASTNode);
                node.* = ASTNode{ .identifier = name };
                return node;
            },
            Token.literal => {
                return self.parseLiteral();
            },
            else => return ParseError.ExpectedIntLiteral,
        };
    }

    fn parseExpression(self: *Parser) !*ASTNode {
        const tok = self.current();
        return switch (tok) {
            Token.literal, Token.identifier => {
                // Check if the next token is a binary operator
                if (self.next() == Token.binary_operator) {
                    const left = try self.parseSymbolOrLiteral();

                    const op = self.current().binary_operator;
                    self.advance(); // consume binary operator
                    const right = try self.parseExpression();

                    const node = try self.allocator.create(ASTNode);
                    const binOp = try self.allocator.create(BinaryOperation);
                    binOp.* = BinaryOperation{ .operator = op, .left = left, .right = right };
                    node.* = ASTNode{ .binaryOperation = binOp };
                    return node;
                }

                const node = try parseSymbolOrLiteral(self);
                return node;
            },
            Token.open_parenthesis => {
                self.advance();
                const expr = try self.parseExpression();
                if (!self.tokenIs(Token.close_parenthesis)) return ParseError.ExpectedRightParen;
                self.advance();
                return expr;
            },
            Token.open_brace => {
                return self.parseCodeBlock();
            },
            else => return ParseError.ExpectedIntLiteral,
        };
    }

    fn parseDeclarationOrAssignment(self: *Parser) ParseError!*ASTNode {
        const name = try self.parseIdentifier();

        // Assignment
        if (self.tokenIs(Token.equal)) {
            self.advance(); // consume '='
            const value = try self.parseExpression();
            const node = try self.allocator.create(ASTNode);
            const assign = try self.allocator.create(Assignment);
            assign.* = Assignment{ .name = name, .value = value };
            node.* = ASTNode{ .assignment = assign };
            return node;
        }

        // Declaration
        if (self.tokenIs(Token.colon) or self.tokenIs(Token.double_colon)) {
            // Check for another : indicating variable declaration (::)
            var mutability = Mutability.Const;
            if (self.tokenIs(Token.double_colon)) {
                mutability = Mutability.Var;
            }
            self.advance(); // consume ':' or '::'

            const tipo = try self.parseType();
            var value: ?*ASTNode = null;
            if (!self.tokenIs(Token.new_line)) {
                if (!self.tokenIs(Token.equal)) return ParseError.ExpectedEqual;
                self.advance(); // consume '='
                value = try self.parseExpression();
            }
            const node = try self.allocator.create(ASTNode);
            const decl = try self.allocator.create(Declaration);
            // Asumimos que no hay argumentos, por eso usamos undefined.
            const args: []const Argument = undefined;
            decl.* = Declaration{
                .name = name,
                .type = tipo,
                .mutability = mutability,
                .args = args,
                .value = value,
            };
            node.* = ASTNode{ .declaration = decl };
            return node;
        }

        return ParseError.ExpectedDeclarationOrAssignment;
    }

    fn parseSentences(self: *Parser) !std.ArrayList(*ASTNode) {
        var ast = std.ArrayList(*ASTNode).init(self.allocator.*);
        while (self.index < self.tokens.len and !self.tokenIs(Token.eof) and !self.tokenIs(Token.close_brace)) {
            std.debug.print("Parsing sentence...\n", .{});
            self.ignoreNewLinesAndComments();
            switch (self.current()) {
                Token.keyword_return => {
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

    fn parseCodeBlock(self: *Parser) ParseError!*ASTNode {
        if (!self.tokenIs(Token.open_brace)) return ParseError.ExpectedLeftBrace;
        self.advance(); // consume '{'
        const list = try self.parseSentences();
        if (!self.tokenIs(Token.close_brace)) return ParseError.ExpectedRightBrace;
        self.advance(); // consume '}'
        const node = try self.allocator.create(ASTNode);
        const codeBlock = try self.allocator.create(CodeBlock);
        codeBlock.* = CodeBlock{ .items = list.items };
        node.* = ASTNode{ .codeBlock = codeBlock };
        return node;
    }

    fn parseReturn(self: *Parser) ParseError!*ASTNode {
        // Verificar que el token actual es 'keyword_return'
        if (!self.tokenIs(Token.keyword_return)) {
            return ParseError.ExpectedKeywordReturn;
        }
        self.advance(); // consume 'keyword_return'

        // Intentamos parsear una expresión que se retorne.
        const expr = try self.parseExpression();

        const node = try self.allocator.create(ASTNode);
        const retStmt = try self.allocator.create(ReturnStmt);
        retStmt.* = ReturnStmt{ .expression = expr };
        node.* = ASTNode{ .returnStmt = retStmt };
        return node;
    }

    pub fn printAST(self: *Parser) void {
        std.debug.print("\nast:\n", .{});
        for (self.ast.items) |node| {
            node.print(0);
        }
    }
};

/// Función auxiliar para imprimir espacios de indentación.
fn printIndent(indent: usize) void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        std.debug.print("  ", .{}); // 2 espacios por nivel
    }
}

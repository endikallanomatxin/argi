const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;

pub const ASTNode = union(enum) {
    decl: *Decl,
    identifier: []const u8,
    codeBlock: *CodeBlock,
    valueLiteral: *ValueLiteral,
    typeLiteral: *TypeLiteral,
    returnStmt: *ReturnStmt,
};

const Decl = struct {
    name: []const u8,
    type: ?Type,
    mutability: Mutability,
    args: []const Argument,
    value: *ASTNode,
};

const Mutability = enum {
    Const,
    Var,
};

const CodeBlock = struct {
    items: []const *ASTNode,
    // Return args in the future.
};

const Argument = struct {
    name: []const u8,
    mutability: Mutability,
    type: Type,
};

const TypeLiteral = struct {
    type: Type,
};

const Type = enum {
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

const ValueLiteral = union(enum) {
    intLiteral: *IntLiteral,
    floatLiteral: *FloatLiteral,
    doubleLiteral: *DoubleLiteral,
    charLiteral: *CharLiteral,
    boolLiteral: *BoolLiteral,
    stringLiteral: *StringLiteral,
};

const IntLiteral = struct {
    value: i64,
};

const FloatLiteral = struct {
    value: f32,
};

const DoubleLiteral = struct {
    value: f64,
};

const CharLiteral = struct {
    value: u8,
};

const BoolLiteral = struct {
    value: bool,
};

const StringLiteral = struct {
    value: []const u8,
};

const ReturnStmt = struct {
    expression: ?*ASTNode,
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
    ExpectedFuncAssignment,
    OutOfMemory,
};

/// Estado del parser.
pub const Parser = struct {
    tokens: []const Token,
    index: usize,
};

/// Inicializa el parser.
pub fn initParser(tokens: []const Token) Parser {
    return Parser{
        .tokens = tokens,
        .index = 0,
    };
}

/// Devuelve el token actual o Token.eof si se han consumido todos.
fn current(parser: *Parser) Token {
    std.debug.print("Parseando token {d}", .{parser.index});
    lexer.printToken(parser.tokens[parser.index]);
    if (parser.index < parser.tokens.len) {
        return parser.tokens[parser.index];
    }
    return Token.eof;
}

/// Avanza un token.
fn advance(parser: *Parser) void {
    std.debug.print("Parseado token {d}\n", .{parser.index});
    if (parser.index < parser.tokens.len) parser.index += 1;
}

/// Comprueba que el token actual es el esperado; de lo contrario retorna un error.
fn expect(parser: *Parser, expected: Token) !ParseError {
    if (!tokenIs(parser, expected)) return ParseError.ExpectedAssignment;
    advance(parser);
    return;
}

/// Compara el token actual con uno esperado mediante un switch exhaustivo.
fn tokenIs(parser: *Parser, expected: Token) bool {
    return switch (current(parser)) {
        Token.identifier => switch (expected) {
            Token.identifier => true,
            else => false,
        },
        Token.int_literal => switch (expected) {
            Token.int_literal => true,
            else => false,
        },
        Token.colon => switch (expected) {
            Token.colon => true,
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
        Token.eof => switch (expected) {
            Token.eof => true,
            else => false,
        },
        Token.keyword_return => switch (expected) {
            Token.keyword_return => true,
            else => false,
        },
        else => false,
    };
}

/// Parsea un identificador.
fn parseIdentifier(parser: *Parser) ParseError![]const u8 {
    std.debug.print("Parseando identificador\n", .{});
    const tok = current(parser);
    return switch (tok) {
        Token.identifier => |name| {
            advance(parser);
            return name;
        },
        else => return ParseError.ExpectedIdentifier,
    };
}

/// Parsea (de forma opcional) una anotación de tipo.
/// Se asume que el tipo viene como un identificador (ej., "Int", "Float", etc.).
fn parseType(parser: *Parser) ParseError!?Type {
    std.debug.print("Parseando tipo\n", .{});
    if (tokenIs(parser, Token.equal)) {
        return null;
    }
    // Desempaquetamos usando ".?" ya que esperamos que no sea null.
    const typeName = try parseIdentifier(parser);
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

fn parseExpression(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    std.debug.print("Parseando expresión\n", .{});
    const tok = current(parser);
    lexer.printToken(tok);
    return switch (tok) {
        Token.int_literal => |value| {
            advance(parser);
            // Creamos la constante entera
            const intLiteral = try allocator.create(IntLiteral);
            intLiteral.* = IntLiteral{ .value = value };
            // Creamos la unión ValueLiteral y luego el nodo AST
            const valLiteral = try allocator.create(ValueLiteral);
            valLiteral.* = ValueLiteral{ .intLiteral = intLiteral };
            const node = try allocator.create(ASTNode);
            node.* = ASTNode{ .valueLiteral = valLiteral };
            return node;
        },
        Token.identifier => |_| {
            const name = try parseIdentifier(parser);
            const node = try allocator.create(ASTNode);
            node.* = ASTNode{ .identifier = name };
            return node;
        },
        Token.open_parenthesis => {
            advance(parser);
            const expr = try parseExpression(parser, allocator);
            if (!tokenIs(parser, Token.close_parenthesis)) return ParseError.ExpectedRightParen;
            advance(parser);
            return expr;
        },
        Token.open_brace => {
            return parseCodeBlock(parser, allocator);
        },
        else => return ParseError.ExpectedIntLiteral,
    };
}

/// Parsea una declaración de variable o constante.
/// Se asume que no se usan tokens "const" o "var".
fn parseDecl(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    std.debug.print("Parseando declaración\n", .{});
    const name = try parseIdentifier(parser);
    var mutability = Mutability.Var;
    if (!tokenIs(parser, Token.colon)) return ParseError.ExpectedColon;
    advance(parser); // consume el primer ':'
    if (tokenIs(parser, Token.colon)) {
        mutability = Mutability.Const;
        advance(parser);
    }
    const tipo = try parseType(parser);
    if (!tokenIs(parser, Token.equal)) return ParseError.ExpectedEqual;
    advance(parser); // consume '='
    const value = try parseExpression(parser, allocator);
    const node = try allocator.create(ASTNode);
    const decl = try allocator.create(Decl);
    // Asumimos que no hay argumentos, por eso usamos undefined.
    const args: []const Argument = undefined;
    decl.* = Decl{
        .name = name,
        .type = tipo,
        .mutability = mutability,
        .args = args,
        .value = value,
    };
    node.* = ASTNode{ .decl = decl };
    return node;
}

fn parseCodeBlock(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    std.debug.print("Parseando bloque de código\n", .{});
    if (!tokenIs(parser, Token.open_brace)) return ParseError.ExpectedLeftBrace;
    advance(parser); // consume '{'
    var list = std.ArrayList(*ASTNode).init(allocator.*);
    while (!tokenIs(parser, Token.close_brace)) {
        switch (current(parser)) {
            Token.eof => return ParseError.ExpectedRightBrace,
            Token.keyword_return => {
                const retNode = try parseReturn(parser, allocator);
                try list.append(retNode);
            },
            else => {
                const declNode = try parseDecl(parser, allocator);
                try list.append(declNode);
            },
        }
    }
    advance(parser); // consume '}'
    const node = try allocator.create(ASTNode);
    const codeBlock = try allocator.create(CodeBlock);
    codeBlock.* = CodeBlock{ .items = list.items };
    node.* = ASTNode{ .codeBlock = codeBlock };
    return node;
}

/// Parsea una sentencia de retorno.
fn parseReturn(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    std.debug.print("Parseando sentencia de retorno\n", .{});
    // Verificar que el token actual es 'keyword_return'
    if (!tokenIs(parser, Token.keyword_return)) {
        return ParseError.ExpectedIdentifier; // O un error específico para 'return'
    }
    advance(parser); // consume 'keyword_return'

    // Intentamos parsear una expresión que se retorne.
    const expr = try parseExpression(parser, allocator);

    const node = try allocator.create(ASTNode);
    const retStmt = try allocator.create(ReturnStmt);
    retStmt.* = ReturnStmt{ .expression = expr };
    node.* = ASTNode{ .returnStmt = retStmt };
    return node;
}

/// Función principal: parsee todos los tokens hasta eof y retorne una lista de nodos AST.
pub fn parse(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!std.ArrayList(*ASTNode) {
    std.debug.print("Parseando\n", .{});
    var ast = std.ArrayList(*ASTNode).init(allocator.*);
    while (parser.index < parser.tokens.len and !tokenIs(parser, Token.eof)) {
        switch (current(parser)) {
            Token.eof => return ParseError.ExpectedRightBrace,
            Token.keyword_return => {
                const retNode = try parseReturn(parser, allocator);
                try ast.append(retNode);
            },
            else => {
                const declNode = try parseDecl(parser, allocator);
                try ast.append(declNode);
            },
        }
    }
    return ast;
}

/// Función para imprimir el AST.
pub fn printAST(ast: []*ASTNode) void {
    for (ast) |node| {
        printNode(node);
    }
}

/// Función para imprimir un nodo del AST.
pub fn printNode(node: *ASTNode) void {
    switch (node.*) {
        ASTNode.decl => |decl| {
            std.debug.print("Declaration {s} ({s}) = ", .{ decl.*.name, if (decl.*.mutability == Mutability.Var) "var" else "const" });
            printNode(decl.*.value);
        },
        ASTNode.identifier => |ident| {
            std.debug.print("identifier: {s}", .{ident});
        },
        ASTNode.codeBlock => |codeBlock| {
            std.debug.print("Bloque de código:\n", .{});
            for (codeBlock.*.items) |item| {
                printNode(item);
            }
        },
        ASTNode.valueLiteral => |valueLiteral| {
            switch (valueLiteral.*) {
                ValueLiteral.intLiteral => |intLit| {
                    std.debug.print("IntLiteral {d}", .{intLit.value});
                },
                ValueLiteral.floatLiteral => |floatLit| {
                    std.debug.print("FloatLiteral {}", .{floatLit.value});
                },
                ValueLiteral.doubleLiteral => |doubleLit| {
                    std.debug.print("DoubleLiteral {}", .{doubleLit.value});
                },
                ValueLiteral.charLiteral => |charLit| {
                    std.debug.print("CharLiteral {c}", .{charLit.value});
                },
                ValueLiteral.boolLiteral => |boolLit| {
                    std.debug.print("BoolLiteral {}", .{boolLit.value});
                },
                ValueLiteral.stringLiteral => |stringLit| {
                    std.debug.print("StringLiteral {s}", .{stringLit.value});
                },
            }
        },
        ASTNode.typeLiteral => |typeLiteral| {
            switch (typeLiteral.*.type) {
                Type.Int32 => std.debug.print("Int32", .{}),
                Type.Int => std.debug.print("Int", .{}),
                Type.Float => std.debug.print("Float", .{}),
                Type.Double => std.debug.print("Double", .{}),
                Type.Char => std.debug.print("Char", .{}),
                Type.Bool => std.debug.print("Bool", .{}),
                Type.String => std.debug.print("String", .{}),
                Type.Array => std.debug.print("Array", .{}),
                Type.Struct => std.debug.print("Struct", .{}),
                Type.Enum => std.debug.print("Enum", .{}),
                Type.Union => std.debug.print("Union", .{}),
                Type.Pointer => std.debug.print("Pointer", .{}),
                Type.Function => std.debug.print("Function", .{}),
            }
        },
        ASTNode.returnStmt => |returnStmt| {
            std.debug.print("return ", .{});
            if (returnStmt.expression) |expr| {
                printNode(expr);
            }
            std.debug.print(";\n", .{});
        },
    }
}

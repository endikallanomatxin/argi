const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;

pub const ASTNode = union(enum) {
    varDecl: *VarDecl,
    constDecl: *ConstDecl,
    codeBlock: *[]*ASTNode,
    intLiteral: *IntLiteral,
    identifier: *[]const u8,
    returnStmt: *ReturnStmt,
};

const VarDecl = struct {
    name: []const u8,
    type: ?Type,
    value: *ASTNode,
};

const ConstDecl = struct {
    name: []const u8,
    type: ?Type,
    value: *ASTNode,
};

const Type = enum {
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

const IntLiteral = struct {
    value: i64,
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
    if (parser.index < parser.tokens.len) {
        return parser.tokens[parser.index];
    }
    return Token.eof;
}

/// Avanza un token.
fn advance(parser: *Parser) void {
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
        // Otros tokens se consideran false:
        Token.keyword_func => false,
        Token.keyword_return => false,
        Token.string_literal => false,
        Token.open_parenthesis => false,
        Token.close_parenthesis => false,
        Token.symbol => false,
    };
}

/// Parsea un identificador y lo devuelve.
fn parseIdentifier(parser: *Parser) ParseError![]const u8 {
    const tok = current(parser);
    return switch (tok) {
        Token.identifier => |ident| {
            advance(parser);
            return ident;
        },
        else => return ParseError.ExpectedIdentifier,
    };
}

/// Parsea (de forma opcional) una anotación de tipo.
/// Se asume que el tipo viene como un identificador (ej., "Int", "Float", etc.).
fn parseTypeAnnotation(parser: *Parser) ParseError!?Type {
    if (tokenIs(parser, Token.equal)) {
        return null;
    }
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

/// Parsea una expresión simple (por ahora, únicamente literales enteros).
fn parseExpression(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    const tok = current(parser);
    return switch (tok) {
        Token.int_literal => |value| {
            advance(parser);
            const lit = try allocator.create(IntLiteral);
            lit.* = IntLiteral{ .value = value };
            const node = try allocator.create(ASTNode);
            node.* = ASTNode{ .intLiteral = lit };
            return node;
        },
        else => return ParseError.ExpectedIntLiteral,
    };
}

/// Parsea una declaración de variable o constante.
/// Se asume que no se usan tokens "const" o "var".
fn parseVarOrConstDecl(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    const name = try parseIdentifier(parser);
    if (!tokenIs(parser, Token.colon)) return ParseError.ExpectedColon;
    advance(parser); // consume ':'
    const tipo = try parseTypeAnnotation(parser);
    if (!tokenIs(parser, Token.equal)) return ParseError.ExpectedEqual;
    advance(parser); // consume '='
    const value = try parseExpression(parser, allocator);
    const node = try allocator.create(ASTNode);
    const varDecl = try allocator.create(VarDecl);
    varDecl.* = VarDecl{
        .name = name,
        .type = tipo,
        .value = value,
    };
    node.* = ASTNode{ .varDecl = varDecl };
    return node;
}

/// Parsea un bloque de código delimitado por '{' y '}'.
fn parseCodeBlock(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    if (!tokenIs(parser, Token.open_brace)) return ParseError.ExpectedLeftBrace;
    advance(parser); // consume '{'
    var list = std.ArrayList(*ASTNode).init(allocator.*);
    while (!tokenIs(parser, Token.close_brace)) {
        const declNode = try parseDeclaration(parser, allocator);
        try list.append(declNode);
    }
    advance(parser); // consume '}'
    // Creamos una variable local para tomar la dirección del slice.
    var items = list.items;
    const node = try allocator.create(ASTNode);
    node.* = ASTNode{ .codeBlock = &items };
    return node;
}

/// Parsea una declaración: unifica variables, constantes y bloques.
pub fn parseDeclaration(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
    if (tokenIs(parser, Token.open_brace)) {
        return parseCodeBlock(parser, allocator);
    }
    // Aquí se podría incluir parseo de "return" u otros.
    return parseVarOrConstDecl(parser, allocator);
}

/// Función principal: parsee todos los tokens hasta eof y retorne una lista de nodos AST.
pub fn parse(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!std.ArrayList(*ASTNode) {
    var ast = std.ArrayList(*ASTNode).init(allocator.*);
    while (parser.index < parser.tokens.len and !tokenIs(parser, Token.eof)) {
        std.debug.print("Parsing token {d}\n", .{parser.index});
        const node = try parseDeclaration(parser, allocator);
        try ast.append(node);
    }
    return ast;
}

/// Función para imprimir el AST.
pub fn printAST(ast: []*ASTNode) void {
    for (ast) |child| {
        printNode(child);
    }
}

/// Función para imprimir un nodo del AST.
pub fn printNode(node: *ASTNode) void {
    switch (node.*) {
        ASTNode.varDecl => |varDecl| {
            const tipoStr = if (varDecl.type) |t| switch (t) {
                Type.Int => "Int",
                Type.Float => "Float",
                Type.Double => "Double",
                Type.Char => "Char",
                Type.Bool => "Bool",
                Type.String => "String",
                else => "Unknown",
            } else "None";
            std.debug.print("Variable {s}: {s} = ", .{ varDecl.name, tipoStr });
            printNode(varDecl.value);
            std.debug.print("\n", .{});
        },
        ASTNode.constDecl => |constDecl| {
            const tipoStr = if (constDecl.type) |t| switch (t) {
                Type.Int => "Int",
                Type.Float => "Float",
                Type.Double => "Double",
                Type.Char => "Char",
                Type.Bool => "Bool",
                Type.String => "String",
                else => "Unknown",
            } else "None";
            std.debug.print("Constante {s}: {s} = ", .{ constDecl.name, tipoStr });
            printNode(constDecl.value);
            std.debug.print("\n", .{});
        },
        ASTNode.codeBlock => |codeBlock| {
            std.debug.print("Bloque de código:\n", .{});
            printAST(codeBlock.*);
        },
        ASTNode.intLiteral => |intLiteral| {
            std.debug.print("{d}", .{intLiteral.value});
        },
        ASTNode.identifier => |ident| {
            std.debug.print("{s}", .{ident});
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

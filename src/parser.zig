const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;

pub const ASTNode = union(enum) {
    declaration: *Declaration,
    identifier: []const u8,
    codeBlock: *CodeBlock,
    valueLiteral: *ValueLiteral,
    typeLiteral: *TypeLiteral,
    returnStmt: *ReturnStmt,
};

pub const Declaration = struct {
    name: []const u8,
    type: ?Type,
    mutability: Mutability,
    args: []const Argument,
    value: *ASTNode,

    pub fn isFunction(self: Declaration) bool {
        // if the value points to a code block, then it's a function
        switch (self.value.*) {
            ASTNode.codeBlock => return true,
            else => return false,
        }
    }
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
        Token.keyword_return => switch (expected) {
            Token.keyword_return => true,
            else => false,
        },
        else => false,
    };
}

/// Parsea un identificador.
fn parseIdentifier(parser: *Parser) ParseError![]const u8 {
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
    const tok = current(parser);
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
fn parseDeclaration(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
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
    const decl = try allocator.create(Declaration);
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

fn parseCodeBlock(parser: *Parser, allocator: *const std.mem.Allocator) ParseError!*ASTNode {
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
                const declNode = try parseDeclaration(parser, allocator);
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
    var ast = std.ArrayList(*ASTNode).init(allocator.*);
    while (parser.index < parser.tokens.len and !tokenIs(parser, Token.eof)) {
        switch (current(parser)) {
            Token.eof => return ParseError.ExpectedRightBrace,
            Token.keyword_return => {
                const retNode = try parseReturn(parser, allocator);
                try ast.append(retNode);
            },
            else => {
                const declNode = try parseDeclaration(parser, allocator);
                try ast.append(declNode);
            },
        }
    }
    return ast;
}

/// Imprime el AST completo iniciando en el nivel 0.
pub fn printAST(ast: []*ASTNode) void {
    std.debug.print("\n\nAST\n", .{});
    for (ast) |node| {
        printNode(node, 0);
    }
}

/// Función auxiliar para imprimir espacios de indentación.
fn printIndent(indent: usize) void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        std.debug.print("  ", .{}); // 2 espacios por nivel
    }
}

/// Imprime un nodo del AST, recibiendo el nivel de indentación.
pub fn printNode(node: *ASTNode, indent: usize) void {
    printIndent(indent);
    switch (node.*) {
        ASTNode.declaration => |decl| {
            std.debug.print("Declaration {s} ({s}) =\n", .{ decl.*.name, if (decl.*.mutability == Mutability.Var) "var" else "const" });
            // Se incrementa el nivel de indentación para el nodo hijo.
            printNode(decl.*.value, indent + 1);
        },
        ASTNode.identifier => |ident| {
            std.debug.print("identifier: {s}\n", .{ident});
        },
        ASTNode.codeBlock => |codeBlock| {
            std.debug.print("code block:\n", .{});
            for (codeBlock.*.items) |item| {
                printNode(item, indent + 1);
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
                printNode(expr, indent + 1);
            }
        },
    }
}

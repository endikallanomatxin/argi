const std = @import("std");

pub const ASTNode = union(enum) {
    varDecl: VarDecl,
    function: FunctionDecl,
    literal: Literal,
};

pub const VarDecl = struct {
    identifier: []const u8,
    type_annotation: ?[]const u8, // nulo si no se especificó
    initializer: ASTNode,
};

pub fn parseVarDecl(tokens: []Token, index: *usize) !ASTNode {
    // Suponemos que tokens[*index] es un identifier.
    const ident = tokens[*index].value;
    *index += 1;
    
    // Espera token colon.
    if (tokens[*index].kind != .colon) {
        return error.ExpectedColon;
    }
    *index += 1;
    
    // Verifica si el siguiente token es igual o es un tipo.
    // Si es igual, entonces es una declaración con inferencia.
    var type_annotation: ?[]const u8 = null;
    if (tokens[*index].kind == .equal) {
        // Declaración sin tipo explícito.
        *index += 1;
    } else {
        // Opcional: Si se especifica un tipo, podrías leerlo.
        type_annotation = tokens[*index].value;
        *index += 1;
        
        // Ahora debe seguir un token equal.
        if (tokens[*index].kind != .equal) {
            return error.ExpectedEqual;
        }
        *index += 1;
    }
    
    // Ahora, parsea la expresión del inicializador.
    // Por simplicidad, supongamos que es un literal numérico.
    if (tokens[*index].kind != .number) {
        return error.ExpectedNumberLiteral;
    }
    const literal_node = ASTNode{ .literal = Literal{ .value = tokens[*index].value } };
    *index += 1;
    
    return ASTNode{ .varDecl = VarDecl{
        .identifier = ident,
        .type_annotation = type_annotation,
        .initializer = literal_node,
    }};
}

pub fn inferTypeForVarDecl(decl: VarDecl) []const u8 {
    if (decl.type_annotation) |explicitType| {
        // Si se especificó un tipo, úsalo.
        return explicitType;
    } else {
        // Inferencia: si el inicializador es un literal numérico, asumimos "Int".
        // (Para otros casos, deberás ampliar la lógica).
        // Suponiendo que decl.initializer es un nodo literal.
        return "Int";
    }
}

pub const FunctionDecl = struct {
    identifier: []const u8,
    return_type: ?[]const u8, // nulo si no se especificó
    body: []ASTNode,
};

pub fn parse(tokens: []Token) !std.ArrayList(ASTNode) {
    var ast = std.ArrayList(ASTNode).init(std.heap.page_allocator);
    return ast;
}

const std = @import("std");
const parser = @import("parser.zig");

// Type inference
/// Recorre el AST y fija todos los Declaration.type == null.
pub fn inferTypes(
    allocator: *const std.mem.Allocator,
    ast: std.ArrayList(*parser.ASTNode),
) !void {
    // 1) Primer pase: inferir tipos de todos los ValueLiteral y anotar
    //    (aunque el parser los almacena en ValueLiteral, aquí los traducimos
    //     a nuestro enum Type, y guardamos en una tabla temporal).
    var literalTypes = std.AutoHashMap(*parser.ASTNode, parser.Type).init(allocator.*);

    // Recorremos nodos del AST
    for (ast.items) |nodePtr| {
        // Si es un literal
        switch (nodePtr.*) {
            parser.ASTNode.valueLiteral => |vl| {
                const litType = switch (vl.*) {
                    parser.ValueLiteral.intLiteral => parser.Type.Int,
                    parser.ValueLiteral.floatLiteral => parser.Type.Float,
                    else => continue, // (si añades más literales)
                };
                _ = try literalTypes.put(nodePtr, litType);
            },
            else => {},
        }
    }

    // 2) Segundo pase: inferir Declaration.type y ReturnStmt, y propagar a BinaryOperation
    //    Podrías necesitar un map de nombres->Type para variables.
    var varTypes = std.StringHashMap(parser.Type).init(allocator.*);

    for (ast.items) |nodePtr| {
        switch (nodePtr.*) {
            // Declaraciones: si no tienen tipo, tomamos el tipo de su inicializador
            parser.ASTNode.declaration => |declPtr| {
                if (declPtr.isFunction()) {
                    // Si lo deseas, márcalo explícitamente:
                    declPtr.*.type = parser.Type.Function;
                    _ = try varTypes.put(declPtr.*.name, parser.Type.Function);
                    continue; // ← muy importante
                }

                if (declPtr.*.type == null) {
                    if (declPtr.*.value) |v| {
                        const inferred = try computeExprType(v, &literalTypes, &varTypes);
                        declPtr.*.type = inferred;
                    }
                }
                // Guardamos en tabla de variables para usos posteriores
                if (declPtr.*.type) |t| {
                    _ = try varTypes.put(declPtr.*.name, t);
                }
            },
            // Return: si la función no tenía tipo de retorno explícito,
            // podrías guardarlo en algún campo de Declaration correspondiente.
            parser.ASTNode.returnStmt => |ret| {
                if (ret.*.expression) |expr| {
                    const retType = try computeExprType(expr, &literalTypes, &varTypes);
                    // Aquí enlazarías con tu Declaration de función, p.ej. mainDecl.returnType = retType
                    _ = retType;
                }
            },
            else => {},
        }
    }
}

/// Dada una expresión, devuelve su Type (o error si no puede).
fn computeExprType(
    nodePtr: *parser.ASTNode,
    literalTypes: *std.AutoHashMap(*parser.ASTNode, parser.Type),
    varTypes: *std.StringHashMap(parser.Type),
) !parser.Type {
    switch (nodePtr.*) {
        parser.ASTNode.valueLiteral => {
            return literalTypes.get(nodePtr) orelse return error.CannotInferType;
        },
        parser.ASTNode.identifier => |name| {
            const varType = varTypes.get(name) orelse return error.CannotInferType;
            return varType;
        },
        parser.ASTNode.binaryOperation => |binOpPtr| {
            const leftT = try computeExprType(binOpPtr.left, literalTypes, varTypes);
            const rightT = try computeExprType(binOpPtr.right, literalTypes, varTypes);
            // unificación muy simple:
            if (leftT == parser.Type.Float or rightT == parser.Type.Float) {
                return parser.Type.Float;
            } else {
                return parser.Type.Int;
            }
        },
        else => return error.CannotInferType,
    }
}

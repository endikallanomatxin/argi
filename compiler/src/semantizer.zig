const std = @import("std");
const syn = @import("syntax_tree.zig");
const sem = @import("semantic_graph.zig");

pub const Semantizer = struct {
    allocator: *const std.mem.Allocator,
    graph: sem.SemanticGraph,

    // Type inference
    /// Recorre el ST y fija todos los Declaration.type == null.
    pub fn inferTypes(
        allocator: *const std.mem.Allocator,
        st: std.ArrayList(*syn.STNode),
    ) !void {
        // 1) Primer pase: inferir tipos de todos los ValueLiteral y anotar
        //    (aunque el syn los almacena en ValueLiteral, aquí los traducimos
        //     a nuestro enum Type, y guardamos en una tabla temporal).
        var literalTypes = std.AutoHashMap(*syn.STNode, syn.Type).init(allocator.*);

        // Recorremos nodos del ST
        for (st.items) |nodePtr| {
            // Si es un literal
            switch (nodePtr.*) {
                syn.STNode.valueLiteral => |vl| {
                    const litType = switch (vl.*) {
                        syn.ValueLiteral.intLiteral => syn.Type.Int,
                        syn.ValueLiteral.floatLiteral => syn.Type.Float,
                        else => continue, // (si añades más literales)
                    };
                    _ = try literalTypes.put(nodePtr, litType);
                },
                else => {},
            }
        }

        // 2) Segundo pase: inferir Declaration.type y ReturnStmt, y propagar a BinaryOperation
        //    Podrías necesitar un map de nombres->Type para variables.
        var varTypes = std.StringHashMap(syn.Type).init(allocator.*);

        for (st.items) |nodePtr| {
            switch (nodePtr.*) {
                // Declaraciones: si no tienen tipo, tomamos el tipo de su inicializador
                syn.STNode.declaration => |declPtr| {
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
                syn.STNode.returnStmt => |ret| {
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
};

/// Dada una expresión, devuelve su Type (o error si no puede).
fn computeExprType(
    scope: *const sem.Scope,
    nodePtr: *sem.SGNode,
) !*sem.TypeDeclaration {
    switch (nodePtr.*) {
        .ValueLiteral => switch (nodePtr.*) {
            .intLiteral => return syn.Type.Int,
            .floatLiteral => return syn.Type.Float,
            .charLiteral => return syn.Type.Char,
            .stringLiteral => return syn.Type.String,
            else => return error.CannotInferType,
        },
        .BindingDeclaration => |bindingPtr| {
            // Aquí buscarías el tipo en tu tabla de variables
            const varType = scope.bindingDeclarations.items[bindingPtr.*.sym_id].ty;
            if (varType == null) return error.CannotInferType;
            return varType;
        },
        .BinaryOperation => |binOpPtr| {
            // Recurre a computeExprType para los operandos
            const leftT = try computeExprType(scope, binOpPtr.left);
            const rightT = try computeExprType(scope, binOpPtr.right);
            // Unificación muy simple:
            if (leftT == syn.Type.Float or rightT == syn.Type.Float) {
                return syn.Type.Float;
            } else {
                return syn.Type.Int;
            }
        },
        .FunctionCall => |callPtr| {
            // Aquí buscarías la declaración de la función y su tipo de retorno
            const funcDecl = scope.functionDeclarations.items[callPtr.*.callee];
            if (funcDecl.returnType) |retType| {
                return retType;
            } else {
                return error.CannotInferType; // o un tipo por defecto
            }
        },
        else => return error.CannotInferType,
    }
}

# CHAT COMMENT ON ARRAYS


Sí, te entiendo: no quieres que `(1,2,3)` “se materialice” como un valor runtime (un struct/tuple), sino que sea **un literal efímero de compile-time** que solo sirve para inspección (longitud, tipo de elementos, indexado de lectura en tiempo de compilación) y para inicializar estructuras como tu `Array`.

Para conseguir eso sin reventar tu sema actual, te propongo este **plan minimal-invasivo**:

# 1) Representar el list literal como nodo propio en el SG

En vez de bajarlo a `sem.StructValueLiteral`, crea un nodo `sem.ListLiteral` y tipa el `TypedExpr` como `Any` (porque no es un valor runtime). Así evitas que el backend intente emitirlo.

### En `semantic_graph.zig` (o donde definas `sem.*`)

* Añade al `Content`:

```zig
list_literal: *ListLiteral,
```

* Define:

```zig
pub const ListLiteral = struct {
    // nodos (ya semantizados) de cada elemento
    elements: []const *SGNode,
    // tipos de cada elemento (útil para consultas en compile-time)
    element_types: []const Type,
};
```

# 2) Cambia `handleListLiteral` para crear ese nodo y devolver `Any`

Tu `handleListLiteral` quedaría así (nota: ya no fabrica un struct value):

```zig
fn handleListLiteral(
    self: *Semantizer,
    ll: syn.ListLiteral,
    s: *Scope,
) SemErr!TypedExpr {
    // Tipo explícito homogéneo opcional
    var expected_elem_ty_opt: ?sem.Type = null;
    if (ll.element_type) |elt_ty_syn| {
        expected_elem_ty_opt = try self.resolveType(elt_ty_syn, s);
    }

    var elems   = std.ArrayList(*sem.SGNode).init(self.allocator.*);
    var elemtys = std.ArrayList(sem.Type).init(self.allocator.*);
    defer {
        elems.deinit();
        elemtys.deinit();
    }

    for (ll.elements, 0..) |e, i| {
        const te = try self.visitNode(e.*, s);

        if (expected_elem_ty_opt) |exp_ty| {
            if (!typesStructurallyEqual(exp_ty, te.ty)) {
                const exp = try self.formatType(exp_ty, s);
                const got = try self.formatType(te.ty, s);
                defer {
                    self.allocator.free(exp);
                    self.allocator.free(got);
                }
                try self.diags.add(
                    e.*.location,
                    .semantic,
                    "list element {d} has type '{s}', expected '{s}'",
                    .{ i, got, exp },
                );
                return error.Reported;
            }
        }

        try elems.append(te.node);
        try elemtys.append(te.ty);
    }

    const lit = try self.allocator.create(sem.ListLiteral);
    lit.* = .{
        .elements = try elems.toOwnedSlice(),
        .element_types = try elemtys.toOwnedSlice(),
    };

    const n = try self.makeNode(undefined, .{ .list_literal = lit }, null);
    return .{ .node = n, .ty = .{ .builtin = .Any } }; // No es un valor runtime
}
```

# 3) Builtin `length` para listas (compile-time)

Añade un builtin parecido a `size_of/alignment_of`, pero que acepte **directamente** un list literal como argumento posicional *o* dentro de `.value`. Ej.:

```zig
if (std.mem.eql(u8, call.callee, "length"))
    return self.handleLengthBuiltin(call, s);
```

```zig
fn handleLengthBuiltin(
    self: *Semantizer,
    call: syn.FunctionCall,
    s: *Scope,
) SemErr!TypedExpr {
    // Acepta: length( (1,2,3) )  o  length(.value=(1,2,3))
    const inp = call.input.*;
    var lit_node: ?*sem.ListLiteral = null;

    switch (inp.content) {
        .list_literal => {
            lit_node = inp.content.list_literal;
        },
        .struct_value_literal => |sv| {
            if (sv.fields.len == 1 and std.mem.eql(u8, sv.fields[0].name, "value")) {
                const te = try self.visitNode(sv.fields[0].value.*, s);
                if (te.node.content == .list_literal)
                    lit_node = te.node.content.list_literal;
            }
        },
        else => {},
    }

    if (lit_node == null) {
        try self.diags.add(
            inp.location,
            .semantic,
            "length expects a list literal (e.g. length((1,2,3)))",
            .{},
        );
        return error.Reported;
    }

    const n_elems: i64 = @intCast(lit_node.?.elements.len);
    return try self.makeIntLiteral(inp.location, n_elems, .{ .builtin = .Int32 });
}
```

> Con esto puedes hacer `n := length((1,2,3))` y `n` será un **const** `Int32` generado en compile-time.

# 4) Indexado de un list literal en compile-time

Permite `type_of(.value=( (1,2,3)[0] ))` o incluso usar el valor en sitios que aceptan exprs constexpr.

Modifica `handleIndexAccess` con un **fast-path** cuando el base sea un `list_literal`:

```zig
fn handleIndexAccess(
    self: *Semantizer,
    ia: syn.IndexAccess,
    s: *Scope,
) SemErr!TypedExpr {
    const base = try self.visitNode(ia.value.*, s);

    // --- Compile-time list literal indexing ---
    if (base.node.content == .list_literal) {
        const idx_te = try self.visitNode(ia.index.*, s);

        // Require índice entero literal (compile-time)
        if (idx_te.node.content != .value_literal) {
            try self.diags.add(
                ia.index.*.location,
                .semantic,
                "index into a list literal must be an integer compile-time literal",
                .{},
            );
            return error.Reported;
        }

        const vl = idx_te.node.content.value_literal;
        const i: i64 = switch (vl) {
            .int_literal => |v| v,
            else => blk: {
                try self.diags.add(
                    ia.index.*.location,
                    .semantic,
                    "index must be an integer literal",
                    .{},
                );
                break :blk 0;
            },
        };

        if (i < 0 or i >= base.node.content.list_literal.elements.len) {
            try self.diags.add(
                ia.index.*.location,
                .semantic,
                "list literal index {d} out of bounds (length {d})",
                .{ i, base.node.content.list_literal.elements.len },
            );
            return error.Reported;
        }

        const ui: usize = @intCast(i);
        const elem_node = base.node.content.list_literal.elements[ui];
        const elem_ty   = base.node.content.list_literal.element_types[ui];

        // Devolvemos **directamente** ese elemento (ya semantizado)
        return .{ .node = elem_node, .ty = elem_ty };
    }

    // --- Resto de casos (tu código actual para get[]) ---
    // (queda igual que lo tenías)
    // ...
}
```

> Con esto, `type_of(.value=( (1,2,3)[0] ))` te devuelve `Int32` en compile-time.


---


hay dos caminos buenos aquí. te dejo el “mínimo viable” (funciona ya con lo que tienes) y el “bonito” (con un `Abstract`), y cómo implementarlos.

# opción A (mínimo viable, cero cambios al tipo del literal)

mantén el `list_literal` como **`Any`** (como propusimos) y deja que el *core* lo consuma usando los **builtins** `length`, `type_of` y el **indexado compile-time** sobre el literal.

### firma

```text
init (.a: $&Array#(.t: Type), .from: Any) -> ()
```

### idea del cuerpo (pseudo):

```text
n := length(.value = from)                 -- Int32 en compile-time
t := type_of(.value = from[0])             -- Type de su primer elemento

-- si quieres, chequear que t == .t (del Array):
-- (puedes confiar en el tipo de destino cuando hagas stores, o
-- emitir diag si no coincide usando tus helpers del semantizador)

size := size_of(.type = t) * n
align := alignment_of(.type = t)

-- reservar y copiar:
-- for i in 0..n-1:
--   *(&elem_ptr) = from[i]    -- indexado compile-time te da el nodo del i-ésimo
```

### por qué funciona

* `from` llega al cuerpo como **SG node** `list_literal` (ty = `Any`), no hay valor runtime.
* `length`, `type_of`, `from[i]` se resuelven **en compile-time** por tus fast-paths.
* tu `Array` sigue 100% en la *core library*; el compilador solo provee los builtins y el fast-path de indexado sobre `list_literal`.

> más tarde, si quieres admitir otras fuentes (otra `Array`, una vista, etc.), añade overloads de `init` con `.from: &Array#(.t)` o con pares `(.data, .length)`.

---

# opción B (limpia/bonita con interfaz): `Abstract List`

si quieres que la firma **exprese** “esto recibe algo list-like”, crea un `Abstract` de lista y haz que el **list literal lo implemente implícitamente** (el compilador pone la magia).

### 1) declara el abstract

```text
List#(.T: Type) : Abstract = (
  length (.self: Self) -> (.n: UInt64),
  operator get[] (.self: Self, .i: UInt64) -> (.value: T)
)
```

* Usamos `Self` (ya tienes soporte en los requirements).
* Asociamos el tipo de elemento vía parámetro genérico `.T`.

### 2) firma del `init`

```text
init (.a: $&Array#(.t), .src: List#(.T: .t)) -> ()
```

Ahora el tipo ya **garantiza** que el elemento de la lista es `.t`.

### 3) cómo lo hace el compilador

* Para **list literals** `(1,2,3)`, el front-end **deduce** `T` (= tipo de los elementos) y **fabrica** overloads/builtins que satisfacen los requirements de `List` (`length` y `get[]`) cuando `Self` es “ese literal”.
* No necesitas un tipo nominal visible; basta con que la resolución de sobrecarga encuentre `length` y `get[]` para ese `Self` y que la instanciación del abstract `List#(.T: deducido)` pase.

### 4) cuerpo del `init`

con esa garantía, el cuerpo puede ser igual al de la opción A, pero sin `type_of(from[0])`, porque ya sabes que `.T == .t` por tipo.

---

## ¿cuál elijo?

* **A** si quieres avanzar **ya** con el mínimo trabajo en el compilador (solo mantener `list_literal` como `Any`, los builtins y el fast-path de `from[i]`).
* **B** si te interesa una API **auto-documentada** y extensible (cualquier cosa que implemente `List` –p. ej., tu `Array` en el futuro– podrá pasar por ese parámetro). Requiere que el compilador haga que el `list_literal` “conforme” al abstract (pero es poco: ya tienes `length` y `get[]` como builtins, solo hay que conectarlos a `Self`).

---

## resumen de firmas

**opción A**

```text
init (.a: $&Array#(.t), .from: Any) -> ()
```

**opción B**

```text
List#(.T: Type) : Abstract = (
  length (.self: Self) -> (.n: UInt64),
  operator get[] (.self: Self, .i: UInt64) -> (.value: T)
)

init (.a: $&Array#(.t), .src: List#(.T: .t)) -> ()
```

si quieres, te paso el esqueleto exacto del `init` con esas primitivas para tu DSL.


---

Decisión, me gusta más la B.

---

Need to implement before core library array:

- inlineación de funciones
- unrolling de loops
- edit init to be the only function that can receive uninitialized arguments, and only if it is an inlined function.

---

En realidad siempre vamos a necesitar un \[N\]T, o al menos un \[N\]Byte, y total está en LLVM así que igual podemos soportarlas por nuestro compilador directamente.

Conclusión: No tiene sentido tanto jaleo para que Array esté en la core library en lugar de en el compilador.



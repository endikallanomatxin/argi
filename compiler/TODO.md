- Split the semantizer into multiple passes:

    Checklists, worklists:

    * `TypeNames`, `TypeBodies`
    * `Signatures` (funciones sin genéricos)
    * `Bodies` (cuerpos a tipar)
    * `Overloads` (call sites con args tipados)
    * `Generics` (instanciaciones pedidas: funciones y tipos)
    * `Abstracts` (pares abstracto↔concreto a verificar)
    * `Arrays` (listas→arrays/inferencia de longitud)

    Pasadas:

    1. **Index**
       Registra símbolos top-level, plantillas genéricas y **stubs** nominales de tipos.
       ✔ Garantiza: nombres en tablas, pero sin resolver cuerpos/firmas.
       ➕ Encola `TypeBodies`, `Signatures`.

    2. **Signatures**
       Resuelve tipos de parámetros y retornos (no entra a los cuerpos).
       ✔ Garantiza: firmas concretas para no genéricas.
       ➕ Encola `Bodies`. Si falta un tipo ⇒ `TypeNames`.

    3. **Bodies**
       Tipado intra-función (bindings, literales, punteros, etc.), **sin** decidir overloads definitivos.
       ✔ Garantiza: cada call site produce un `CallSite` (callee name, args tipados).
       ➕ Encola `Overloads`, `Generics`, `Arrays`.

    4. **Overloads**
       Elige overload concreto si es determinista; si implica genéricos ⇒ `Generics`.
       ✔ Garantiza: call sites fijados o re-encolados solo si cambió generación de tipos/ámbito.

    5. **Generics**
       Monomorfiza con caché `(template_id, subst_tuple<TypeId>)`. Registra la especialización como función/tipo nuevo y **re-encola** su firma/cuerpo donde toque.
       ✔ Garantiza: no hay duplicados; la memo evita explosiones.

    6. **Abstracts**
       Verifica `canbe`/`defaultsto` contra `requirements` ahora que el universo de funciones está estable.
       ✔ Diagnósticos definitivos y con candidatos.

    7. **Coercions**
       Literales a builtin, lista→array, RO/RW pointers, etc. Mensajes afinados (ya los tienes, solo muévelos aquí).

    8. **Finalize**
       Inserta `defer` automáticos, congela orden de emisión del SG, limpia diferidos.

    Tu `Semantizer` actual se convierte en:

    * **Contexto + helpers** (visitadores para cuerpo: `visitNode`, `coerce…`, etc.) usados por `pass_bodies` y amigos.
    * **Driver** (o renómbralo a `SemanticPipeline`). El método `analyze()` pasa a ser un *thin wrapper* que crea el `Context`, lanza el `PassManager` y devuelve `root_nodes`.

    Así **todo sigue “dentro” del semántico**, no como postprocesos, pero **ya no es un dios-objeto**: cada pasada es un módulo pequeño y testeable.


    Plan de migración en 5 pasos:

    1. Extrae `resolveOverload`, `specificityScore`, `collectFunctionSignatures…` a `overload_resolver.zig`.
    2. Crea `Context` con tus tablas de `Scope`, `root_list`, `pending_*` → **reemplázalos por checklists**.
    3. Implementa `passIndex` y `passSignatures`; deja `visitNode` solo para `passBodies`.
    4. Mete `Generics` y `Abstracts` como pasadas dedicadas, reutilizando tus `instantiateGeneric*` y `verifyAbstracts`.
    5. Cambia `analyze()` para que llame al `PassManager` y elimine los reintentos globales; los reintentos ahora son **por checklist**.


- Choice types: Implement

- Implement checks like: `let x: UInt8 = 300` → error de rango.

- Abstracts:

    - Fix: Actualmente el símbolo del abstract se registra como “tipo nominal”
    placeholder que internamente mapea a Any. Además, no se permite usar un
    abstract como tipo de símbolo si no hay defaultsto.

    - Self en salidas: extender el checker para sustituir Self también en
    retornos antes de comparar, igual que ya hacéis para entradas. Pequeño
    cambio: aplicar buildExpected… a output y comparar tras sustitución.

    - canbe/defaultsto genéricos: soportar patrones Indexable#(T) canbe
    Vector#(T) resolviendo con un mapa de sustitución (ya tenéis infra de
    sustituciones para genéricos). Esto permite que los bounds pasen al
    instanciar Vector#(Int32)

    (por ahora no trabajar más en el defaultsto, que igual lo quitamos)


- Modules: switch from file-based to directory-based modules


- **Índices/offsets de puntero: fija la política.**

   * Mejor: exige **`usize`** en el semantizador para `ptr + n` y indexado.
   * En codegen, convierte `usize` al ancho que pida LLVM con `LLVMIntPtrType` (+ `zext/sext` si hace falta). Ese *widen* es solo *lowering*, no semántica.
     Si prefieres atarte a 64-bit, documenta que es decisión de lenguaje y mantén todo coherente (también `length: UInt64`).


- **`refineStructTypeWithActual` mutando in-place.**
   Riesgo de aliasing. Mejor clonar el `StructType` refinado e internarlo, no modificar el original.

- Really avoid implicit conversions/coercions:

    - **No castear literales en codegen.**
       Deja toda la fijación de literales en el **semantizador** (`coerceLiteralToBuiltin`, `coerceStructLiteral`, etc.).
       **Acción:** elimina de `codegen.zig` `literalAsInteger/intLiteralValue` y las ramas que los usan en:

       * `genBinaryOp`
       * `genStructValueLiteral`
       * init de bindings
         Si tipos LLVM no coinciden → `InvalidType`. Codegen solo baja lo ya tipado.

    - **Asignación de structs “reempacando” en codegen.**

       Quita el bloque que reconstruye agregados cuando los LLVM structs difieren.
       Eso es conversión implícita encubierta. Si algún día soportas
       “struct-coercions”, que sea en el semantizador; por ahora, **igualdad
       estricta**.

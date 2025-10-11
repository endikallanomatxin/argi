
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


- Implement checks like: `let x: UInt8 = 300` → error de rango.

- Choice types: Implement

- Generics:

    - Compile time parameter inference

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


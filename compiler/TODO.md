- Semantizer:

    - Menos repetición en errores de overload. Hay unas 15 líneas repetidas 3 veces.

    - Genéricos: unifica las dos rutas. instantiateGenericNamed y
    instantiateGeneric comparten un 90%. Saca una función interna.

    - Implement an arena allocator to avoid memory leaks in semantizer.

    - Revisar `refineStructTypeWithActual`: ahora muta `StructType.fields`
    in-place al refinar genéricos. Riesgo de aliasing y de contaminar otras
    rutas de resolución. Mejor clonar/internar el tipo refinado.

- Choice types: Implement

- `let x: UInt8 = 300` → el check de rango para literales ya está
  implementado. Quitar esta entrada y añadir tests negativos dedicados para
  overflow/underflow de enteros con anotación explícita.

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

    - Añadir al harness los tests negativos de abstracts que ya existen
    (`332X`, `333X`, `335X`) para que estos errores no regresen sin enterarnos.


- Modules: implement explicit `#import` on top of directory-based modules

    - El harness no está ejecutando algunos casos de módulos/imports que ya
    existen (`62_folder_imports_overview`).

    - Dejar de pensar el build alrededor de `main.rg`/`build <file>` y mover el
    modelo al nivel de directorio-módulo. Compilar un directorio completo
    encaja mejor con la regla actual de que todos los `.rg` de una carpeta
    comparten namespace.

    - Revisar el CLI para pasar de `build <file.rg>` a `build <directory>` (o
    equivalente), y adaptar resolución de entrypoint, tests y mensajes de uso a
    ese modelo.


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

- Capado a Int32 en size_of/alignment_of

    Estás calculando en u64 y luego fallas si supera Int32. Si no te hace falta
    esa restricción, quita el check y devuelve UInt64 siempre (ahorras
    diagnósticos y conversiones).

    - Revisar también la coherencia con `length`, que ahora devuelve `UInt64`.


- Restricción de “sólo Int64/UInt64” en suma de punteros

    En handleBinOp para pointer + int exiges 64-bit exacto. Si te vale
    cualquier entero (con promoción), elimina ese check duro y usa
    typ.isIntegerType.


- Tests / cobertura:

    - Añadir al harness `compiler/tests/test.zig` los casos que ya existen pero
    no se están ejecutando: `06_if`, `131X_multiple_dispatch_ambiguous`,
    `223X`, `224X`, `225X`, `414`, `415`, `416`, `43_alias`, `61_system`,
    `71_loops`.

    - `42_choice`, `81_comptime` y `90_build_system` existen pero sus
    `main.rg` están vacíos. Decidir si son placeholders o features a
    implementar y actuar en consecuencia.

    - Añadir tests específicos para la política final de offsets de puntero,
    para `size_of/alignment_of` una vez fijado el tipo de retorno, y para
    evitar coerciones implícitas desde codegen.


- LSP:

    - Endurecer el servidor: ahora varias rutas silencian errores con
    `catch {}` / `catch return`. Conviene responder errores del protocolo o al
    menos loggarlos para no perder fallos de análisis o de parsing JSON.

    - Añadir tests del `LanguageService` y de `semanticTokens`. Ahora no hay
    cobertura visible para esa capa.


- CLI / docs:

    - Alinear `README.md` con el CLI real:
      * usar `tests/` en vez de `test/`
      * documentar el nuevo modelo de build por directorio cuando se haga el
        cambio
      * reflejar los flags de build y el comando `lsp`

    - Mantener la ayuda del CLI sincronizada con lo que realmente soporta el
    compilador.

    - Cuando se haga el cambio a build por directorio, revisar también el
    harness de tests para no seguir compilando rutas a fichero individuales.

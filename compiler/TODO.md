- Prioridad de coherencia con `description/`:

    - `Abstract` es ahora mismo el mayor hueco entre diseño e implementación.
    En la descripción es un mecanismo central del lenguaje, pero en el
    compilador sigue teniendo piezas provisionales y restricciones semánticas
    importantes.

    - Después de `Abstract`, la siguiente incoherencia grande es el modelo de
    build: la descripción ya piensa en módulos por carpeta, pero la CLI sigue
    orientada a `build <file.rg>`.

- Abstracts:

- Añadir test negativo de underflow de enteros anotados cuando exista sintaxis
  de literales negativos (`-1` ahora falla en parsing antes del check de rango).

    - Seguir integrando el abstract como tipo del compilador de pleno derecho.
    Ya no se registra como `Any`, pero aún quedan restricciones semánticas
    importantes para usarlo fuera de los casos con `defaultsto`.

    - Fix: Aunque el abstract ya tiene representación nominal propia, todavía
    no se permite usarlo como tipo de símbolo si no hay `defaultsto`.

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


- Modules / build model:

    - El harness no está ejecutando algunos casos de módulos/imports que ya
    existen (`62_folder_imports_overview`).

    - Ahora `build` ya compila directorios-módulo. Revisar si merece la pena
    eliminar del todo la compatibilidad residual con rutas a fichero.


- **Índices/offsets de puntero: fija la política.**

   * `length`, `size_of`, `alignment_of`, casts puntero↔entero e indexado de arrays ya usan `UIntNative`.
   * Decidir si el indexado debe seguir estricto (`UIntNative`) o aceptar otros enteros mediante coerción semántica más adelante.


- Semantizer:
    - Implement an arena allocator to avoid memory leaks in semantizer.

- **`refineStructTypeWithActual` mutando in-place.**
   Riesgo de aliasing. Mejor clonar el `StructType` refinado e internarlo, no modificar el original.

   - Revisar `refineStructTypeWithActual`: ahora muta `StructType.fields`
   in-place al refinar genéricos. Riesgo de aliasing y de contaminar otras
   rutas de resolución. Mejor clonar/internar el tipo refinado.

- Choice types: Implement

- Really avoid implicit conversions/coercions:

    - Revisar los literales no fijados por el semantizador para que lleguen a
      codegen con `sem_type` cuando corresponda. Ya se quitaron las coerciones
      implícitas en `genBinaryOp`, `genComparison`, stores de campos e init de
      bindings; el resto debería seguir la misma línea.

- Tests / cobertura:

    - Añadir al harness `compiler/tests/test.zig` los casos que ya existen pero
    aún no están listos o no se están ejecutando: `414`, `415`, `416`,
    `43_alias`, `61_system`, `71_loops`.

    - `62_folder_imports_overview` sigue vacío; decidir si se implementa como
    caso real o se elimina.

    - `42_choice`, `81_comptime` y `90_build_system` existen pero sus
    `main.rg` están vacíos. Decidir si son placeholders o features a
    implementar y actuar en consecuencia.

    - Añadir tests específicos para la política final de offsets de puntero y
    para evitar coerciones implícitas desde codegen.


- LSP:

    - Endurecer el servidor: ahora varias rutas silencian errores con
    `catch {}` / `catch return`. Conviene responder errores del protocolo o al
    menos loggarlos para no perder fallos de análisis o de parsing JSON.

    - Añadir tests del `LanguageService` y de `semanticTokens`. Ahora no hay
    cobertura visible para esa capa.


- CLI / docs:

    - Mantener la ayuda del CLI sincronizada con lo que realmente soporta el
    compilador.

    - Cuando se haga el cambio a build por directorio, revisar también el
    harness de tests para no seguir compilando rutas a fichero individuales.

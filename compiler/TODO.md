- North star

    - Llevar Argi a un punto en el que el compilador pueda empezar a migrarse
    gradualmente desde Zig hacia Argi.

    - Eso implica tres cosas a la vez:
        1. que la semántica central del lenguaje esté suficientemente cerrada,
        2. que `core` y `more` tengan las piezas mínimas para escribir un
           compilador serio,
        3. que el backend/tooling del compilador deje de estar tan acoplado a
           decisiones ad hoc del prototipo actual.


- Prioridades reales ahora

    - 1. Seguir cerrando las discrepancias grandes entre `description/` y
      `compiler/`, especialmente en `Abstract`, ownership/copying y tipos
      compuestos.

    - 2. Construir las piezas mínimas para self-hosting parcial:
      colecciones, asignadores, errores, testing, módulos/build y C/LLVM
      interop suficientemente usables.

    - 3. Desacoplar el compilador de detalles del prototipo Zig actual para que
      el backend y el front puedan sustituirse por fases.


- Coherencia lenguaje <-> compilador

    - Abstracts

        - Seguir ampliando la monomorfización y el desempate de overloads con
          inputs abstractos.

        - Cerrar la política de outputs abstractos:
            - ligados a inputs abstractos,
            - inferidos desde el code block,
            - o existenciales reales.

        - Endurecer `implements/defaultsto` genéricos:
            - matching,
            - diagnósticos,
            - y alcance real de `defaultsto`.

        - Alinear `Abstract` con `Virtual#(...)` cuando esa frontera esté más
          madura.

    - Ownership, copying y memoria

        - Completar la semántica de copyability:
            - consulta clara `isTypeCopyable`,
            - errores consistentes en value position,
            - y cobertura homogénea en asignación, paso por valor, retorno y
              almacenamiento by-value.

        - Consolidar `copy()` implícito:
            - resolverlo igual que `deinit()`,
            - revisar su firma final,
            - y cerrar su interacción con allocators reached.

        - Refinar `deinit` automático:
            - bindings inicializados vs movidos vs no inicializados,
            - y semántica más creíble para `init(out: $&T, ...)`.

        - Endurecer la exclusividad mínima de `$&` en llamadas.

        - Revisar copyability de views, punteros, slices, arrays y listas para
          que no fingan ownership.

    - Choice / nullability / errores

        - Añadir la capa de ergonomía y propagación:
          `?`, `unwrap_or`, `unwrap_or_do`, `!` y similares.

    - Pipe operator

        - Ampliarlo para:
            - placeholders en expresiones más complejas,
            - builtins,
            - casos cualificados con genéricos,
            - y semántica/precedencia ya cerradas.

    - Comptime

        - Mantenerlo fuera del núcleo por ahora.

        - Solo introducir el trozo mínimo necesario cuando desbloquee una pieza
          estructural clara del compilador o del build system. No usarlo para
          tapar huecos de semántica base.


- Infraestructura mínima para self-hosting

    - Core library usable para un compilador

        - Strings
            - Cuando `StringView` esté realmente maduro como vista borrowed
              usable, hacer que las string literals se materialicen en el
              segmento de datos/constants de solo lectura y que el usuario las
              vea semánticamente como `StringView`, no como `String` owner ni
              como C-string ad hoc del backend.
        - IO / system streams

            - La capa nueva `File -> Reader/Writer -> BufferedReader/BufferedWriter`
              ya existe en `core`, pero ahora mismo es todavía un esqueleto de
              arquitectura más que una implementación final.

            - Cosas claramente temporales del estado actual:
                - `FileReader.read_byte()` está stubbeado a `..end` porque aún
                  faltan casts/modelado suficientes para bajar bien desde las
                  APIs reales del sistema.
                - `FileWriter.write_byte()` sigue usando `putchar()`, así que
                  `stdout` y `stderr` todavía comparten backend real.
                - `BufferedReader` y `BufferedWriter` tienen shape propia, pero
                  su comportamiento está simplificado para evitar chocar con
                  limitaciones actuales del compilador/codegen.
                - `read_line()` sigue siendo placeholder; la capa de texto sobre
                  IO todavía no está cerrada.
                - La helper `write(.text: String)` sobre `Writer` es útil de
                  transición, pero no debería condicionar el diseño bajo nivel.

            - Dirección deseable:
                - `File` debería representar un handle/fd abierto del sistema,
                  no necesariamente un archivo regular.
                - `stdin`, `stdout` y `stderr` deberían ser simplemente `File`s
                  preabiertos por el runtime/sistema.
                - `Reader` y `Writer` deben quedarse byte-oriented; texto,
                  líneas, formatting y parsing tienen que vivir en capas
                  superiores.
                - `BufferedReader` y `BufferedWriter` deberían ser wrappers
                  reales, con buffering efectivo y semántica clara sobre si
                  poseen o no el recurso subyacente.
                - A medio plazo conviene decidir si `Reader`/`Writer` cuelgan de
                  `File` como wrappers concretos o si `File` implementa además
                  las operaciones base directamente y los wrappers sólo añaden
                  política de buffering/posición.

            - Trabajo pendiente para acercarlo a algo final:
                - Añadir bindings/platform layer para leer y escribir bytes de
                  verdad distinguiendo `stdin`, `stdout` y `stderr`.
                - Cerrar una historia mínima de EOF/errores/short reads/short
                  writes.
                - Diseñar una capa de texto sencilla y explícita para esta fase:
                  probablemente algo estilo buffer C (`$&Char` + longitud /
                  capacidad) antes de apoyar todo en `String` owner.
                - Rehacer `read_line()` y helpers de impresión encima de esa
                  capa de texto simple.
                - Revisar ownership/lifetime de buffers internos para que quede
                  claro qué inicializa, quién hace `deinit` y qué parte vive en
                  allocator externo vs storage interno.
        - Lists / arrays / slices
        - Hash maps / sets
        - Allocators
        - Basic file/path handling
        - Diagnostics helpers
        - Testing helpers

        - CLI
            - Implementar `audit` para detectar red flags y antipatterns de uso
              del lenguaje en el código compilado, por ejemplo `#reach` más
              allá de lo que la core lib suele esperar o patrones similares
              que merezcan aviso.

            - Añadir `init project` y `init module` sin `main` como punto de
              entrada, dejando claro qué esqueleto generan y cómo encajan con
              el flujo normal de compilación.

            - Preparar `argi test` para ejecutar la suite completa; dejar su
              funcionamiento final pendiente de la historia de testing aún no
              cerrada.

    - Asignadores

        - Implementar el story mínimo de allocators descrito en
          `description/35_allocation.md`.

        - En particular, hace falta un allocator tipo arena/bump usable para
          futuras fases reescritas en Argi.

        - `build` y LSP ya analizan módulos dentro de una arena, y el
          semantizador ya ha reducido bastante su dependencia de temporales con
          `alloc/free` manual. El siguiente paso es terminar de empujar ese
          modelo de lifetime hacia helpers internos y estructuras auxiliares.

    - Testing language-side

        - Llevar `description/72_testing.md` a algo implementable.

        - Un compilador en Argi necesitará poder testear:
            - parsing,
            - semántica,
            - utilidades de `core`,
            - golden tests de diagnósticos.

        - No hace falta un framework enorme, pero sí un mínimo viable real.

    - Build / package model

        - `build` ya compila módulos-carpeta. El siguiente paso es acercarlo al
          modelo de `description/03_building.md`.

        - Definir una historia mínima y realista para el fichero de proyecto
          (`argi.toml` hoy; quizá `project.rgo` u otro formato más adelante).

        - Añadir target selection, optimization mode y salidas configurables.

        - Más adelante: tests/build/install como comandos declarables desde el
          propio proyecto.

    - C subset / FFI

        - Si el compilador futuro quiere seguir usando LLVM o librerías del
          sistema, la interop con C no es opcional.

        - Hay que concretar e implementar el mínimo de `description/20_c.md`:
            - `CFunction`,
            - `CString`,
            - `CArray`,
            - enums/unions mínimos,
            - calling convention clara.

        - Sin eso, la transición del backend desde Zig a Argi será mucho más
          difícil.


- Backend y toolchain

    - Separar mejor front-end semántico de backend LLVM.

        - El compilador no debería asumir tan pronto que todo baja
          directamente a LLVM sin una capa intermedia más estable.

        - A medio plazo conviene introducir una IR propia más pequeña o, como
          mínimo, una frontera más clara entre semántica y lowering.

    - Targets

        - Introducir concepto explícito de target y data layout.

        - `UIntNative`, alineaciones, ABI, name mangling y linking no deberían
          depender solo del host actual.

        - Esto es importante tanto para multi-plataforma como para self-hosting:
          un compilador en Argi tendrá que compilarse y generar artefactos para
          más de un target.

    - Linking / outputs

        - Mejorar el flujo actual de `output.ll` / `output.o` / `output`.

        - Permitir salidas configurables y controlar mejor la etapa de link.

        - Eventualmente separar:
            - emitir LLVM IR,
            - emitir objeto,
            - enlazar ejecutable,
            - enlazar librería.


- Arquitectura interna del compilador

    - Semantizer arena allocator

        - El pipeline principal ya usa arena en `build` y LSP.

        - El semantizador y `types.zig` ya han eliminado bastante boilerplate
          de ownership temporal y varias allocations auxiliares.

        - Falta rematar helpers internos y estructuras auxiliares para que la
          fase deje de depender de cleanup manual disperso.

    - `refineStructTypeWithActual`

        - Revisar si conviene internar tipos refinados compartidos o si basta
          con seguir clonándolos cuando una instanciación necesita precisión
          adicional.

    - Seguir quitando coerciones implícitas residuales

        - El trabajo principal ya empezó, pero todavía hay que revisar que el
          codegen no siga “arreglando” tipos en silencio.

    - Preparar fases reutilizables

        - Tokenizer, syntaxer, semantizer y codegen deberían ser cada vez más
          invocables como librería, no solo a través del comando `build`.

        - Eso facilitará:
            - tests más finos,
            - LSP más fiable,
            - futura reescritura parcial en Argi.


- LSP y tooling de desarrollo

    - Endurecer el servidor LSP:
        - menos `catch {}` / `catch return`,
        - mejores respuestas de error,
        - logs o diagnósticos cuando falla el pipeline.

    - Añadir tests visibles para:
        - `LanguageService`,
        - `semanticTokens`,
        - `hover`,
        - `definition`,
        - resolución de módulo,
        - diagnóstico incremental.

    - Hacer que el harness también cubra LSP de forma explícita, no solo
      `build`, para detectar regresiones de protocolo y tooling.

    - Mantener el LSP usando exactamente el mismo pipeline que `build`.
      Eso ya está bastante mejor alineado; toca evitar regresiones y seguir
      cerrando diferencias de diagnóstico o errores degradados.


- Tests y cobertura

    - Seguir ampliando cobertura de features ya soportadas, especialmente en
      `Abstract`, módulos, reached arguments y ownership.

    - Eliminar o activar placeholders:
        - `81_comptime`
        - `90_build_system`
        - `62_folder_imports_overview`

    - Ampliar la cobertura de `choice` más allá del corte mínimo actual:
        - operadores de nullability / errables (`?`, `unwrap_or`, `!`, etc.).
        - checks/runtime safety adicionales sobre acceso a payload si hace falta.

    - Ampliar la cobertura del `pipe`:
        - genéricos y abstracts,
        - placeholders anidados en expresiones arbitrarias,
        - mejores diagnósticos de overload posicional.

    - Añadir golden tests de diagnósticos donde el wording importe.

    - Añadir más tests por fase:
        - tokenizer,
        - syntaxer,
        - semantizer,
        - codegen,
        - LSP,
        - end-to-end.


- Refactor de `System` y bootstrap de runtime

    - Mantener `System` como agregador de capabilities por puntero/handle donde
      eso exprese mejor la semántica del runtime.

    - Decidir qué primitivas mínimas de runtime/FFI hacen falta para inicializar
      cada capability real sin hardcodear la estructura completa en codegen.


- Roadmap de bootstrap

    - Etapa 1: escribir utilidades de `core` en Argi
        - strings,
        - colecciones,
        - allocators,
        - testing helpers.

    - Etapa 2: escribir piezas no críticas del compilador en Argi
        - utilidades de diagnóstico,
        - formatters,
        - helpers de AST/SG,
        - partes del build/test tooling.

    - Etapa 3: escribir front-end parcial en Argi
        - tokenizer,
        - parser,
        - quizá partes del semantizador.

    - Etapa 4: mantener backend/LLVM aún en Zig o vía C FFI
        mientras el front ya migra.

    - Etapa 5: decidir si el compilador final:
        - sigue usando LLVM por FFI,
        - mantiene una parte del backend en Zig/C,
        - o da el salto a otra arquitectura.


- No perder de vista

    - No abrir demasiadas features nuevas “bonitas” si no acercan el lenguaje a
      ser implementable por sí mismo.

    - Cada cambio importante debería responder al menos a una de estas
      preguntas:
        - ¿reduce una discrepancia fuerte con `description/`?
        - ¿acerca `core` a poder alojar un compilador?
        - ¿reduce el acoplamiento estructural del compilador actual?

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

        - Seguir ampliando la monomorfización de funciones con inputs
          abstractos:
            - múltiples parámetros abstractos,
            - reglas de desempate más finas entre overload concreto y abstracto,
            - interacción con generics explícitos,
            - mejores diagnósticos cuando varias implementaciones `canbe`
              compiten.

        - Decidir y fijar la política de outputs abstractos:
            - ligados a inputs abstractos,
            - inferidos desde el code block,
            - o existenciales reales.
          Ahora solo están cubiertos parcialmente.

        - Soportar `canbe/defaultsto` genéricos:
          patrones tipo `Indexable#(T) canbe Vector#(T)`.

        - Decidir si `defaultsto` se mantiene como parte estable del lenguaje o
          si es un mecanismo transitorio.

        - Más adelante: alinear `Abstract` con `Virtual#(...)` y comprobar que
          la frontera estática/dinámica queda explicable.

    - Ownership, copying y memoria

        - Implementar de verdad la historia de copia que se describe en
          `description/32_copying_behaviour.md`.

        - Cerrar qué tipos son copyables, movibles o solo pasables por `&`/`$&`
          y hacer que el compilador lo verifique.

        - Conectar esto con `init/deinit`, auto-deinit y asignadores.

        - Revisar punteros, slices, arrays y listas para que la semántica de
          aliasing y mutabilidad sea consistente.

    - Choice / nullability / errores

        - Implementar `choice` types y el mínimo de nullability/error handling
          que ya aparece en `description/12_choice.md`, `51_nullability.md` y
          `59_errors.md`.

        - Esto es importante no solo por completitud del lenguaje, sino porque
          un compilador escrito en Argi necesitará representar fallos,
          resultados y variantes de forma nativa.

    - Comptime

        - Mantenerlo fuera del núcleo por ahora.

        - Solo introducir el trozo mínimo necesario cuando desbloquee una pieza
          estructural clara del compilador o del build system. No usarlo para
          tapar huecos de semántica base.


- Infraestructura mínima para self-hosting

    - Core library usable para un compilador

        - Strings
        - Lists / arrays / slices
        - Hash maps / sets
        - Allocators
        - Basic file/path handling
        - Diagnostics helpers
        - Testing helpers

        - La pregunta útil aquí es:
          “¿podría implementarse un tokenizer/lexer razonable en Argi con el
          `core` actual?”
          Si la respuesta es no, todavía falta base para self-hosting.

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
        - resolución de módulo,
        - diagnóstico incremental.

    - Mantener el LSP usando exactamente el mismo pipeline que `build`.
      Eso ya está bastante mejor alineado; toca evitar regresiones y seguir
      cerrando diferencias de diagnóstico o errores degradados.


- Tests y cobertura

    - Seguir ampliando el harness para cubrir las features ya soportadas,
      especialmente en los puntos nuevos de `Abstract`, módulos e inferencia.

    - Mantener el harness limpio y con menos boilerplate ahora que ya usa un
      runner más uniforme y limpieza explícita de artefactos.

    - Eliminar o activar placeholders:
        - `81_comptime`
        - `90_build_system`
        - `62_folder_imports_overview`

    - Ampliar la cobertura de `choice` más allá del corte mínimo actual:
        - payloads,
        - `match`,
        - `Nullable`,
        - `Errable`.

    - Añadir golden tests de diagnósticos donde el wording importe.

    - Empezar a pensar en tests por fase:
        - tokenizer,
        - syntaxer,
        - semantizer,
        - codegen,
        - end-to-end.


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

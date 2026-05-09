# TODOs antes de release `0.1`

## Bloqueantes para `0.1`

### 1. Endurecer el tokenizer

El tokenizer necesita una revisión antes de taggear `0.1`.

Problemas detectados:

- Hay caminos donde se llama a `self.this()` sin comprobar antes si `offset < source.len`.
- Algunos inputs mal formados pueden acabar en acceso fuera de rango en vez de producir un diagnóstico limpio.
- Casos sensibles:
  - comentarios que llegan a EOF sin `\n`;
  - strings sin cerrar;
  - literales de char incompletos;
  - números con prefijos incompletos;
  - operadores sueltos al final del fichero.

Casos que habría que probar sí o sí:

```txt
// comentario sin newline final
0
0x
0b
1e
"string sin cerrar
'c
-
````

Acciones:

* Reescribir helpers seguros:

  * `peek() ?u8`
  * `peekNext() ?u8`
  * `advance() bool`
* Eliminar accesos directos inseguros.
* Añadir tests de crash-resistance del lexer.
* Asegurar que todo input inválido produce diagnóstico, no panic.

Esto sí bloquea `0.1`.

---

### 2. Mejorar detección de imports

Ahora los imports se detectan buscando literalmente `#import("` en el texto fuente antes de tokenizar/parsear.

Problemas:

* Puede detectar imports dentro de comentarios.
* Puede detectar imports dentro de strings.
* Duplica parte de la sintaxis fuera del parser.
* Acopla el sistema de módulos a una búsqueda textual frágil.

Opciones:

* Solución buena: extraer imports desde el árbol sintáctico.
* Solución mínima para `0.1`: hacer un escaneo léxico que ignore strings y comentarios.
* Documentar que el sistema actual es provisional si no se arregla del todo.

Para release pública, no conviene dejarlo como búsqueda por substring sin cubrir comentarios/strings.

---

### 3. Quitar ruido de debug en diagnósticos del parser

El parser, al fallar, añade diagnóstico pero también imprime directamente algo como:

```txt
Parse error: Expected...
```

Problemas:

* Esa salida se ha convertido accidentalmente en salida pública.
* Puede aparecer mezclada con snapshots de tests.
* El usuario debería ver solo diagnósticos formateados.

Acciones:

* Quitar ese `print`.
* O moverlo detrás de una flag debug.
* Mantener la salida pública basada en diagnósticos con fichero, línea, columna y mensaje.

---

### 4. Mejorar build/linking

El linking funciona, pero todavía es demasiado dependiente del entorno local.

Problemas:

* Usa directamente `cc`.
* No parece respetar `CC`.
* No captura bien `stdout/stderr` del linker.
* Si falla, el usuario recibe un error demasiado genérico.
* `-lc` está fijo.
* La dependencia de LLVM es sensible y debe estar bien explicada.

Acciones mínimas:

* Respetar la variable de entorno `CC` si existe.
* Capturar `stdout/stderr` del linker.
* Mostrar una explicación accionable si falta `cc`.
* Mostrar una explicación accionable si falta LLVM.
* Declarar oficialmente plataformas soportadas para `0.1`, probablemente Linux/macOS.
* Revisar imports/bindings LLVM y añadir explícitamente headers necesarios como `Target` / `TargetMachine` si procede.

---

### 5. Revisar ownership y liberar `CodeGenerator`

En `compileTarget`, se crea `CodeGenerator`, pero hay que asegurar que se llama a `deinit()`.

Acciones:

* Añadir algo como:

```zig
var gen = codegen.CodeGenerator.init(...);
defer gen.deinit();
```

* Revisar ownership de `LLVMModuleRef`.
* Aclarar quién crea, quién usa y quién libera el módulo LLVM.
* Asegurar que `argi test`, LSP o ejecuciones repetidas no acumulen memoria innecesariamente.

No tiene por qué bloquear por sí solo, pero conviene arreglarlo antes de release.

---

### 6. Prueba de instalación limpia

Antes de taggear, hacer una prueba desde cero fuera del repo.

Acciones:

```bash
git clean -xfd
zig build test --summary all
zig build install
```

Después, desde fuera del repo:

```bash
argi version
argi build <ruta-a-un-modulo-de-prueba>
argi test <ruta-a-un-modulo-de-prueba>
```

También probar instalación con prefijo explícito:

```bash
zig build -p /tmp/argi-install
/tmp/argi-install/bin/argi version
/tmp/argi-install/bin/argi build <ruta-a-un-modulo-de-prueba>
/tmp/argi-install/bin/argi test <ruta-a-un-modulo-de-prueba>
```

Objetivo:

* Confirmar que `core` se resuelve desde instalación/sysroot.
* Confirmar que no depende accidentalmente de estar dentro del repo.
* Confirmar que los tests instalados funcionan fuera del árbol de desarrollo.

---

## No bloqueante, pero recomendable antes de seguir creciendo

### 7. Documentar invariantes del `Semantizer`

La arquitectura del semantizer parece razonable: fases staged, predeclaración top-level, estabilización de declaraciones, interfaces de funciones antes de cuerpos, verificación de abstracts, retries, verificación de `once`, inferencia de error reasons, etc.

Pero hay zonas sensibles:

* `max_retry_rounds = 8` es arbitrario.
* Los retries pueden ocultar dependencias mal modeladas.
* Hay que probar cadenas largas de forward references.
* Cuando se agotan retries, el diagnóstico debe ser claro.

Acciones:

* Añadir tests de forward references largos.
* Documentar brevemente la lógica de retries.
* Mejorar el diagnóstico cuando no se puede estabilizar una declaración.

No bloquea `0.1` si funciona, pero hay que tenerlo vigilado.

---

### 8. Documentar responsabilidades de `Scope`

`Scope` acumula muchas responsabilidades:

* bindings;
* refined bindings;
* moved bindings;
* functions;
* types;
* choice options;
* abstracts;
* impls;
* generic templates;
* deferred nodes;
* module aliases.

No hace falta refactorizarlo antes de `0.1`, pero sí conviene documentar invariantes.

Acciones:

* Documentar qué vive solo en scope global.
* Documentar qué puede shadowear.
* Documentar cómo se separan módulos.
* Documentar qué mapas representan semántica nominal.
* Documentar qué mapas pertenecen a análisis de flujo.

Además, revisar búsquedas “in module” que usen `startsWith(origin_file, module_dir)`, porque pueden confundir rutas como:

```txt
/foo/bar
/foo/bar2
```

Solución:

* Normalizar rutas.
* Comprobar límites con separador de path.

---

### 9. Documentar las distintas igualdades de tipos

Hay varias funciones relacionadas con igualdad/compatibilidad de tipos:

* `typesExactlyEqual`
* `typesStructurallyEqual`
* `typesCompatible`
* superset de choices
* identidad genérica

Esto puede estar bien, pero debe estar documentado para evitar usos incorrectos.

Añadir una mini nota interna:

```md
## Type equality / compatibility

- `typesExactlyEqual`: identidad nominal / identidad genérica estricta.
- `typesStructurallyEqual`: igualdad estructural usada en contextos concretos.
- `typesCompatible`: compatibilidad para asignación y paso de argumentos.
- `choiceTypeIsSupersetOf`: relación de inclusión para choices abiertos.
```

Esto probablemente va mejor en documentación interna del compilador.

---

### 10. Revisar `argi test`

El test runner nativo descubre tests parseando el módulo y compila un binario por test.

Para `0.1` está bien, pero hay que cuidar:

* limpieza o gestión de `.argi-cache/tests`;
* diagnósticos completos cuando falla la compilación de un test;
* comportamiento desde instalación externa al repo.

No hace falta optimizarlo todavía.

---

### 11. Acotar expectativas del LSP

El LSP ya cubre bastante para un MVP:

* initialize;
* open/change/close;
* diagnostics;
* semantic tokens;
* hover;
* definition;
* references;
* rename.

Pero no debería venderse como estable todavía.

Acciones:

* En README/release notes, decir que el LSP es experimental.
* No presentarlo como feature madura.
* Aceptar que para `0.1` el foco real es compilador/CLI.

---

## Documentación de release

### 12. Añadir resumen de release en `plan/0.1.md`

Añadir un breve resumen final de qué representa `0.1`.

Debe incluir:

* primer baseline usable del compilador;
* comandos básicos;
* core library mínima;
* tests nativos;
* instalación de `core`;
* limitaciones conocidas;
* aviso de que el lenguaje sigue siendo experimental.

---

### 13. Añadir sección de versiones en `README.md`

Añadir una sección tipo:

```md
## Versions

### 0.1.0

First experimental compiler release.

Includes:
- basic compiler pipeline;
- `build`, `run`, `test`, `init`, `lsp`;
- installed `core` library;
- native test runner;
- basic language and memory-management baseline.

Not included:
- stable language specification;
- formatter;
- package manager;
- stable LSP;
- `more` library.
```

También dejar claro:

* la API/lenguaje aún no es estable;
* puede haber breaking changes;
* `0.1` es una release experimental.

---

### 14. Crear `CHANGELOG.md`

Añadir entrada inicial para `0.1.0`.

Contenido sugerido:

```md
# Changelog

## 0.1.0

First experimental development release of Argi.

### Added

- Basic compiler pipeline.
- CLI commands:
  - `build`
  - `run`
  - `test`
  - `init`
  - `lsp`
- Native `argi test` runner.
- Basic `core` library.
- Installation of `core` alongside the compiler.
- Sysroot-based core resolution.
- Basic diagnostics.
- Integration/regression test suite.

### Not included

- Stable language specification.
- Stable standard library.
- Formatter.
- Package manager.
- Stable LSP.
- `more` library.
- Runtime model documentation.

### Notes

Argi `0.1.0` is experimental. Breaking changes are expected.
```

---

### 15. Actualizar `build.zig.zon`

Revisar `.paths`.

Añadir:

```zig
"README.md",
"CHANGELOG.md",
```

Mantener `core` incluido.

No incluir `more` todavía para `0.1`.

---

### 16. Aclarar que `more/` no entra en `0.1`

En README o release notes, dejar explícito:

* `core/` sí forma parte de `0.1`;
* `more/` no forma parte de `0.1`;
* `more/` queda como experimental/futuro;
* no se instala ni se considera estable.

---

### 17. Recopilar TODOs internos del repo

Buscar TODOs en:

* `src/`
* `core/`
* `more/`
* `description/`
* `plan/`

Clasificarlos en:

```md
## TODOs para 0.1

- ...

## Deuda aceptada en 0.1

- ...

## Movido a 0.2

- ...
```

Criterio:

* Si puede causar panic/crash con input pequeño, va a `0.1`.
* Si afecta a UX básica de errores, probablemente va a `0.1`.
* Si es diseño futuro o ampliación de tipos/librería, va a `0.2`.
* Si afecta a `more`, no bloquea `0.1`.

---

## Runtime / 0.2

### 18. Documentar `Runtime`

Dejar documentado qué se entiende por `Runtime` en Argi.

Temas a cubrir:

* arranque del programa;
* inicialización mínima;
* memoria base;
* errores/panic;
* IO mínima;
* integración con `core`;
* hooks internos que necesite el compilador;
* qué parte vive en librería y qué parte es convención del compilador;
* qué responsabilidades no pertenecen al runtime.

No entra en `0.1`.

Marcarlo explícitamente como objetivo de `0.2`.

---

### 19. Diseñar threading antes de desarrollar el Runtime

Antes de implementar o cerrar el diseño del `Runtime`, conviene pensar primero el modelo de threading/concurrencia.

Motivo:

El diseño del runtime puede depender bastante de si Argi tendrá:

* un solo hilo principal;
* varios hilos gestionados por el runtime;
* integración directa con hilos del sistema operativo;
* scheduler propio;
* IO asíncrona;
* modelo tipo event loop;
* capacidades por hilo;
* memoria/thread-local;
* propagación de errores/panic entre hilos;
* inicialización y destrucción por hilo.

Acciones:

* Documentar primero el modelo de threading deseado.
* Decidir qué parte será responsabilidad del lenguaje.
* Decidir qué parte será responsabilidad de `core`.
* Decidir qué parte será responsabilidad del runtime.
* Decidir si `0.2` solo documenta el modelo o también implementa una primera versión.

Conclusión:

Antes de desarrollar seriamente el runtime, tiene sentido diseñar primero threading/concurrencia, porque puede condicionar la arquitectura del runtime.

---

## Preparar release final

### 20. Commit final de release

Cuando todo lo anterior esté cerrado:

* actualizar documentación;
* actualizar `plan/0.1.md`;
* actualizar `README.md`;
* añadir `CHANGELOG.md`;
* actualizar `build.zig.zon`;
* cerrar TODOs críticos;
* dejar `more` fuera;
* dejar runtime/threading marcado para `0.2`.

---

### 21. Taggear `v0.1.0`

Cuando la release esté lista:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Crear release en GitHub usando el resumen del `CHANGELOG.md`.

---

# Decisión de scope

## Entra en `0.1`

* Robustez del tokenizer.
* Tests de inputs inválidos.
* Diagnósticos limpios.
* Mejor gestión de imports.
* Linker más informativo.
* Respeto de `CC`.
* `CodeGenerator.deinit()`.
* Prueba de instalación limpia.
* `README.md` actualizado.
* `CHANGELOG.md`.
* `build.zig.zon` actualizado.
* Documentar que `more` queda fuera.

## No entra en `0.1`

* CI.
* Formatter.
* Package manager.
* `more`.
* Runtime.
* Threading.
* Refactor grande del `Scope`.
* Rediseño grande del semantizer.
* LSP estable.

## Se mueve a `0.2`

* Runtime.
* Modelo de threading/concurrencia.
* Documentación interna más profunda del compilador.
* Refactor gradual de `Scope`.
* Mejoras de tipos avanzadas.
* Evolución de `more`.
* Posible estabilización mayor del LSP.


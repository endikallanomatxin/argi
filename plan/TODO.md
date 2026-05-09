# TODOs antes de release `0.1`

## Bloqueantes para `0.1`

### Revisar ownership y liberar `CodeGenerator`

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

### Prueba de instalación limpia

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

### Documentar invariantes del `Semantizer`

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

### Documentar responsabilidades de `Scope`

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

### Documentar las distintas igualdades de tipos

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

### Revisar `argi test`

El test runner nativo descubre tests parseando el módulo y compila un binario por test.

Para `0.1` está bien, pero hay que cuidar:

* limpieza o gestión de `.argi-cache/tests`;
* diagnósticos completos cuando falla la compilación de un test;
* comportamiento desde instalación externa al repo.

No hace falta optimizarlo todavía.

---

### Acotar expectativas del LSP

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

### Añadir resumen de release en `plan/0.1.md`

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

### Añadir sección de versiones en `README.md`

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

### Crear `CHANGELOG.md`

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

### Actualizar `build.zig.zon`

Revisar `.paths`.

Añadir:

```zig
"README.md",
"CHANGELOG.md",
```

Mantener `core` incluido.

No incluir `more` todavía para `0.1`.

---

### Aclarar que `more/` no entra en `0.1`

En README o release notes, dejar explícito:

* `core/` sí forma parte de `0.1`;
* `more/` no forma parte de `0.1`;
* `more/` queda como experimental/futuro;
* no se instala ni se considera estable.

---

### Recopilar TODOs internos del repo

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

### Documentar `Runtime`

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

### Diseñar threading antes de desarrollar el Runtime

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

### Commit final de release

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

### Taggear `v0.1.0`

Cuando la release esté lista:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Crear release en GitHub usando el resumen del `CHANGELOG.md`.

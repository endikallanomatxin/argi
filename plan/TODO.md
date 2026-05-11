# TODOs antes de release `0.1`


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


## Documentación de release

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


### Actualizar `build.zig.zon`

Revisar `.paths`.

Añadir:

```zig
"README.md",
"CHANGELOG.md",
```

Mantener `core` incluido.

No incluir `more` todavía para `0.1`.


### Aclarar que `more/` no entra en `0.1`

En README o release notes, dejar explícito:

* `core/` sí forma parte de `0.1`;
* `more/` no forma parte de `0.1`;
* `more/` queda como experimental/futuro;
* no se instala ni se considera estable.


## Preparar release final


### Taggear `v0.1.0`

Cuando la release esté lista:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Crear release en GitHub usando el resumen del `CHANGELOG.md`.

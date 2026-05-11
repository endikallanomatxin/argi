# TODOs antes de release `0.1`

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

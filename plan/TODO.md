# TODOs antes de release `0.1`

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

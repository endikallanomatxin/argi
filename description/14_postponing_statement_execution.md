## Postponing statement execution

Ejecutar cosas en otro momento:
- Defer: hasta que acabe el scope (from D)
- Lazy: hasta que alguien lo necesite

igual podría hacerse más coherente:
- defer:scope
- defer:need

Y el defer scope, igual estaría bien que se pudiera postponer más niveles.

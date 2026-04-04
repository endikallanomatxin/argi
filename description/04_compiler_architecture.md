# Compiler Architecture

Este documento fija la arquitectura actual del compilador y resume las
decisiones que han salido de las rondas recientes de limpieza y rendimiento.

La intención es que la arquitectura no viva sólo en commits o en el estado
accidental del código, sino en un marco explícito y mantenible.

## Phases

Los nombres de fase del compilador están estandarizados y deben mantenerse
consistentes en código, timings, logs, tests y documentación:

- `tokenizing`
- `syntaxing`
- `semantizing`
- `codegen`

`frontend` es un nombre paraguas aceptable para referirse al tramo previo a
`codegen`, pero no sustituye los nombres de fase.

## Frontend pipeline

`src/0_commands/frontend_pipeline.zig` centraliza el tramo:

1. collect files
2. tokenizing
3. syntaxing
4. semantizing

Esto evita que `build` y `lsp` mantengan pipelines paralelos con pequeñas
diferencias. La intención no es introducir una nueva fase, sino compartir la
orquestación del frontend.

## Semantizing architecture

El `semantizing` ya no se organiza como una sola pasada monolítica con retries
como flujo normal. La organización actual es:

1. Predeclaración top-level
2. Estabilización de top-level de soporte
3. Interfaz de funciones
4. Verificación de `abstracts`
5. Defaults y cuerpos de función pendientes
6. Rondas residuales de retry
7. Verificaciones finales (`once`, inferencia de error reasons)

### 1. Predeclaración top-level

Antes de visitar semánticamente el programa completo se registran los símbolos
top-level que conviene conocer pronto:

- imports
- `choice options`
- tipos top-level
- firmas de función

Esto reduce el número de sitios donde una declaración llega "demasiado pronto"
y se reencola por falta de contexto básico.

### 2. Top-level de soporte

Se semantiza primero lo top-level que no son cuerpos de función. Esto incluye
tipos, relaciones abstractas y otros elementos que deben quedar estabilizados
antes de entrar en el comportamiento ejecutable.

### 3. Interfaz de funciones

Las funciones se semantizan en dos etapas:

- primero su interfaz callable
- más tarde sus defaults y su cuerpo

La interfaz resuelve:

- nombre
- input/output
- slot de overload
- relación con `abstracts`

pero no depende de recorrer todavía el cuerpo de la función.

### 4. Verify abstracts before bodies

Una vez estabilizadas las interfaces, `verifyAbstracts` corre antes de entrar en
los cuerpos. Esto hace que la validación abstracta viva en el mundo declarativo
top-level y no dependa accidentalmente del orden de los cuerpos.

### 5. Pending function bodies

Los cuerpos se tratan como trabajo diferido explícito.

Primero se preparan los defaults de input/output que sí hacen falta para poder
llamar correctamente a la función. Después se semantiza el cuerpo usando esa
preparación ya materializada.

Esta etapa reutiliza estructuras ya construidas cuando es posible:

- scope preparado
- input struct preparado

para evitar rehacer el mismo trabajo al pasar de defaults a cuerpo.

### 6. Retries are residual, not the normal path

Los retries top-level siguen existiendo, pero ya no deberían ser el flujo normal
de resolución de funciones.

La dirección correcta es:

- el mundo nominal se estabiliza primero
- las interfaces de función después
- los cuerpos al final

y los retries sólo cubren dependencias todavía residuales o casos realmente
mutuos.

### 7. Final verification

Tras el `semantizing` estructural:

- `verifyOnceFunctions`
- inferencia de `error reasons`

cierran verificaciones que necesitan ver ya el grafo semántico completo.

## Function signature discipline

Las firmas de función requieren tipos explícitos en inputs y outputs.

Esto no es sólo una preferencia superficial; es una decisión de arquitectura del
compilador.

Permitir que la firma dependa de defaults o de inferencias tardías complica
demasiado la separación entre:

- interfaz nominal
- semántica ejecutable del cuerpo

Con tipos explícitos, la interfaz de función se vuelve una pieza mucho más
declarativa y estable.

## Automatic deinit

La gestión de auto-`deinit` sigue esta distinción:

- tipos nominales pueden resolver un `deinit` visible
- tipos anónimos no "tienen deinit" nominal
- para tipos anónimos, el auto-`deinit` es estructural y recursivo

Esto es importante semánticamente y también para rendimiento.

Buscar `deinit` visible para tipos anónimos era trabajo innecesario. La regla
correcta es ir directamente al descenso estructural en esos casos.

## Timings and measurement

`argi build --time-phases` imprime timings por fase y desglose interno de
`semantizing`.

La instrumentación actual sirve para tomar decisiones con datos y no a ciegas.
El desglose útil hoy es:

- support top-level
- function interface
- function input defaults
- function output defaults
- function bodies
- retry passes
- verify abstracts
- verify once
- infer error reasons

## What worked

Estas rondas sí produjeron mejoras reales y se han quedado en el compilador:

- compartir el frontend pipeline entre `build` y `lsp`
- instrumentar timings por fase y por subfase
- predeclarar más símbolos top-level
- estabilizar top-level de soporte antes de funciones
- separar interfaz de función de defaults/cuerpo
- reutilizar scope/input preparados entre defaults y cuerpo
- cachear resolución de tipos top-level de firmas
- dejar de buscar `deinit` nominal para tipos anónimos
- exigir tipos explícitos en firmas de función

## What did not work

Estas exploraciones se probaron y no se quedaron:

- lowering especial de `for` para evitar supuesta re-semantización
- scopes scratch para `if` / `while` / `match`
- internado/canonicalización barata de tipos sin un diseño más profundo
- reservas/microoptimizaciones superficiales en `Scope`
- atajos groseros en auto-`deinit` como:
  - saltar bindings `trivially copyable`
  - cachear plantillas de auto-`deinit`
  - apoyarse sólo en `findDeinitInfo`

En unos casos no dieron mejora medible. En otros rompían semántica real de
ownership y cleanup.

La regla práctica es:

- no forzar microoptimizaciones que debiliten el modelo
- si una mejora de rendimiento rompe ownership o cleanup, se revierte

## Current bottleneck

Con la arquitectura actual, el cuello principal dentro de `semantizing` está en
`function bodies`, no en retries top-level ni en inferencia de `error reasons`.

Dentro de `function bodies`, el trabajo de `symbol_declaration` y auto-`deinit`
ha demostrado ser especialmente sensible.

Eso significa que las próximas mejoras deberían centrarse en:

- trabajo real de cuerpos
- resolución de cleanup
- y reutilización segura de información ya semantizada

no en volver a tocar el staging top-level salvo que aparezca un nuevo dato que
lo justifique.

## External references

Las referencias externas útiles para esta arquitectura han sido:

- Go: separación explícita entre declarations y bodies
- Zig: disciplina de internado/canonicalización e instrumentación de costes

La lección importante no es copiar su diseño, sino mantener esta separación:

- trabajo nominal/declarativo
- trabajo ejecutable de cuerpos

y no volver a mezclarlos por comodidad local.

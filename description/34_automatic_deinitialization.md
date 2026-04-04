Objetivo semántico base: que los valores se destruyan automáticamente cuando
salen de scope.

Optimización futura: mover `deinit()` hacia el último uso cuando el análisis lo
permita.

## Nominal vs anonymous auto-`deinit`

Los tipos nominales pueden resolver un `deinit` visible.

Los tipos anónimos no deberían intentar resolver un `deinit` nominal propio.
Su auto-`deinit` debe salir por descenso estructural recursivo sobre sus
campos.

Esta distinción no es sólo conceptual. También es importante para evitar
trabajo innecesario durante el `semantizing` de cuerpos.

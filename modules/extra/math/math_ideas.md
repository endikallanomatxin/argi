## Uncertainty and units

```
-- Para físicos e ingenieros:
NumberWithUncertainty -- Trabajar en esto, igual interesa poder usar el signo +-
NumberWithUnits       -- Es una idea, igual viene bien para aplicaciones de ingeniería.
```

Hay que pensar que tener unidades no perjudique el desempeño. Que solo se considere para el desarollo, pero no al ejecutar.

## Tracking probability distributions through operations

Si tienes una distribución de probabilidad y marcas sus percentiles (0..100, por ejemplo) puedes utilizar ese vector para representarla.

Puedes trackear a través de las operaciones.

- Aplicas la trasformación a los percentiles.
- Igual hay que cosiderar la deformación correspondiente también (si se estira por un factor, tiene que reducirse por el mismo factor.)



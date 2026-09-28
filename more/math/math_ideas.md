## Uncertainty and units

```
-- For physicists and engineers:
NumberWithUncertainty -- Explore this; supporting the ± sign may be useful.
NumberWithUnits       -- An idea that may be useful for engineering applications.
```

Units should not affect performance. They should be considered only during development, not at runtime.

## Tracking probability distributions through operations

You can represent a probability distribution with a vector of its percentiles (for example, 0..100).

The distribution can be tracked through operations:

- Apply the transformation to the percentiles.
- Account for the corresponding change in density as well (if the distribution stretches by a factor, its density must shrink by the same factor).


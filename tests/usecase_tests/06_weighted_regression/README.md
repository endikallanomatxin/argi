# Weighted linear regression

Build and run from the repository root:

```sh
zig build
./zig-out/bin/argi build tests/usecase_tests/06_weighted_regression
./tests/usecase_tests/06_weighted_regression/build/output
```

The example fits `y = intercept + slope * x` to three weighted observations.
It constructs the normal equations `Xᵀ W X` and `Xᵀ W y` through matrix
contracts, then solves the resulting two-variable system. The expected intercept
is 1 and slope is 2. Success is silent; an incorrect coefficient returns a
nonzero status. The fixture uses a nonsingular, well-conditioned input; this
explicit small-system solution is not a general numerical solver.

The design matrix is 3 by 2, the observation vector is 3 by 1, and the weights
use compact diagonal storage. Contract selection checks compatible dimensions
and chooses the product representations. Transposition changes the static
shape. No allocator or runtime erasure is required.

This is a reproducible compiler workload, not a numerical throughput benchmark.
Measure cold compilation with `argi build --no-cache`; measure frontend reuse
with `zig build -Doptimize=ReleaseSafe benchmark-frontend --
tests/usecase_tests/06_weighted_regression 12 1`. Keep compiler and execution
timings separate. A runtime benchmark needs larger inputs and repeated work
whose results remain observable.

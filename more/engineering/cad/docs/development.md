# Development

The kernel is part of this Argi repository under `more/engineering/cad`.
Build the compiler after editing the bundled library so that the installed `more/`
bundle contains the changes. Public modules use imports such as
`import("engineering/cad/topology")`.

Ordinary CAD tests propagate plain errors. Assertions need no tracer:

```rg
test example := () -> !() {
    testing.expect(true)!
}
```

Generic declarations attach their parameters to the expression, for example
`Point := #(.Scalar: Type: Float) (.x: Scalar, .y: Scalar)`.

## Verification

From the repository root, build the compiler and run its test suite:

```sh
zig build
zig build test -j16 -Dtest-jobs=16
```

Installed library bundles omit `*_test.rg` files. Run the colocated tests from
the repository; applications import only production library sources. This also
keeps test-only construction helpers out of consumer compilations.

Tests alongside kernel modules and public examples can also be selected with
`argi test` using their module directories. Importing a module does not run its
tests. For example:

```sh
./zig-out/bin/argi test more/engineering/cad/geometry
./zig-out/bin/argi test more/engineering/cad/storage --filter storage_
./zig-out/bin/argi test more/engineering/cad/_examples/construction --filter usage_
```

Tests cover Float32/Float64 geometry, tetrahedral and quadrilateral topology,
open boundaries, winding and manifoldness, input ownership, invalid references,
invalid geometry, permutation invariants and planar-profile extrusion with concavities, holes and disconnected regions, analytic periodic supports without seams,
vertexless circular boundaries, chart periodicity, oriented curve evaluation
and malformed analytic geometry in both scalar precisions.
Face editing tests cover hole assignment, exterior-to-hole bridges, shared edge
refinement, closed shells, source ownership and domain-checked history.
Composition tests cover repeated and branching bridges, cuts through joined
contours, bridge refinement and conversion into shared face interfaces.
They also cover fusion with surviving bridges, separate holes, retained internal
tips after filling a hole, reverse face arguments and subsequent edits.
Refined bridge pieces retained on hole walks are included in those edit sequences.

The storage tests cover runtime membership, ownership transfer and growth
independent of the domain marker. See [model domains and incremental
construction](model-builder.md) for the handle design.

## Large test modules

The complete `argi check more/engineering/cad/topology` workload now passes,
including imported development tests. A protected Linux ReleaseSafe run took
31.8 seconds of frontend work and peaked at 416 MiB RSS, below a 2 GiB limit
with swap disabled. The earlier report above 15 GiB preceded reclaimable CLI
frontend storage and the generic contextual-input inference fix. See the
[measurement and reproduction notes](../../../../docs/compiler-performance.md#complete-cad-topology-validation).

This checks every body and its Safety obligations; it does not execute every
test. Isolated native tests remain useful for focused validation and retain
shared helpers and production sources. The repository integration fixture
exercises the installed public modules separately.

Run public examples from a directory outside the checkout when validating the
installed bundle. Bare imports prefer the working-tree `more/` directory when
it exists; that tree intentionally retains the colocated development tests.
The installed bundle omits those test files.

## Source conventions

Use short module aliases: `g` for geometry, `t` for topology, `m` for modeling,
`s` for sketches, and `idx` for storage domains. Construct `IndexDomain`,
`ModelBuilder`, `BrepBuilder` and
`SketchBuilder` through `Init`. Builders default to `Float32`; specialize
explicitly when another scalar is needed. Named factories describe alternative
placements or modeling operations. Infer compile-time arguments from typed
inputs where unambiguous. Qualify a contract operation when its name overlaps
another protocol, as with `Indexable.length` and `_FaceUses.length`.

Entity IDs are nominal wrappers around `UIntNative`. Their explicit conversions
are infallible; domain membership and collection bounds remain checked separately.
Use `:=` for type definitions; an empty type still needs `: Type = ()` to
distinguish its definition from an empty value literal.

Algorithms and ordinary tests return plain errors. Use `!` for propagation.
Tests dedicated to diagnostic traces use the explicit `_with_trace` assertion
forms and `!!` only for meaningful context. Builder operations use the pipe:

```rg
a ::= builder | t.add_vertex($&_, (0.0, 0.0, 0.0))!
b ::= builder | t.add_vertex($&_, (1.0, 0.0, 0.0))!
edge ::= builder | t.add_edge($&_, a, b)!
```

Use positional arguments for conventional operands such as coordinates and
edge endpoints. Keep labels for options such as tolerance, closure and dimensions.
The pipe explicitly preserves borrowing or moving through `$&_`, `&_` and `~_`.

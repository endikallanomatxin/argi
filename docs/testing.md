# Fixture tests

Each ordinary feature fixture keeps a `test.zig` beside its Argi sources:

```zig
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/01_scalar_vm" {
    const path = "tests/feature_tests/execution/01_scalar_vm";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 42);
    try support.vmExpect(path, 42, null);
}
```

`build.zig` discovers `tests/feature_tests/<category>/<case>/test.zig`, sorts
those paths and assembles one test module in the build cache. Zig discovers
the ordinary `test` blocks through imports; no test-body parsing or separate
expectation registry is involved. The generated tree copies Zig test sources,
not Argi programs or build outputs. Shared helpers live in `tests/support.zig`.
Additional compile-time imports or embedded files must also be included in the
generated tree; runtime fixture paths continue to refer to the source checkout.

Terminal editing and interruption probes live in `tests/terminal_probe.zig`.
They use native pseudo-terminals on Linux and macOS, without a Python runner;
Windows skips these POSIX terminal probes.

Tests requiring custom orchestration across fixtures or shared installation
state remain in `tests/test.zig` and run exclusively. The coverage check requires
every substantive root `main.rg` to have a sibling `test.zig` or coverage in those
custom tests. Nested imported modules belong to their containing fixture.
Unfiltered runs also reject discovered files that contribute no Zig tests.

## In-process frontend fixtures

Semantic/Safety fixtures can keep their `.rg` modules and ordinary Zig test
beside them while replacing the subprocess check:

```zig
test "feature_tests/collections/example_rejection" {
    try support.expectFrontendFailure(
        "tests/feature_tests/collections/example_rejection",
        "reference depends on a root that has ended",
    );
}
```

`expectFrontendFailureWithoutNoise` additionally rejects a diagnostic substring;
`expectFrontendFailureWithoutParseNoise` requires a semantic failure without
syntax diagnostics. Syntax checks use `expectSyntaxFailure`. These helpers
match structured diagnostics, not rendered paths or stderr. Keep CLI helpers
for source-collection errors, exact rendering, exit behavior and backend errors.

The runner owns a lazily prepared environment per worker. It loads the checkout's
real core and uses the ordinary module collector, including imports and source
origins. Only canonical module snapshots are cached; GlobalSG, Safety and
compile-time execution are fresh for every check. No build artifacts or disk
cache entries are written. Such read-only checks can declare `.fixture` isolation;
review additional orchestration before changing an existing declaration.

Each invocation releases its compilation region, matching the frontend's existing
allocation contract. Source buffers and cached modules have separate owners;
per-case allocations use the testing allocator, and the worker checks the cache
owner for leaks before exiting. This is lifetime-boundary coverage, not proof of
individual deallocation of every immutable Safety slice. Direct strict-allocator
tests remain appropriate for components with independent allocation ownership.

The same `Environment` is available explicitly to compiler tests in
`src/4_semantics/frontend_test_support.zig`, including in-memory multi-file cases.
Its `execute` method lowers an accepted case to verified bytecode and runs it
within the same compilation lifetime. Use it for VM rules that need real core
contracts; the smaller execution harness remains useful for isolated primitives.
Keep representative native/VM fixtures to check backend agreement. For example,
choice diagnostics live in `choice_rules_test.zig`, while `types/01_choice`
executes equality, extraction and matching on both backends. Exact CLI rendering
and related-location checks remain separate integration cases.
There is no second expectation registry, compiler executable or test discovery
mechanism. `test-programs` runs both frontend fixtures and executable fixtures.

## Isolation

Declare `.fixture` only after reviewing the test's resources. All tests in that
file run on the same worker, so they may share their fixture's outputs and cache.
External files, ports and other mutable resources must be private to the test.
Use `.exclusive` for shared resources or when isolation has not been audited.
Exclusive tests finish before fixture workers start. Categories and helper names
do not determine scheduling.

Execution fixtures use fixture isolation: builds write to that fixture's `build/`
directory, VM state belongs to the child process, and imported fixture modules
are read-only. Captured stdout and process-local allocators do not require
exclusive scheduling. Tests that reuse a fixture from the central orchestration
finish in the exclusive phase before its owning worker starts. Persistent
frontend snapshots are published atomically and may be shared across workers.

One executable contains the complete suite. Workers are separate processes,
since Zig's testing allocator and I/O context are global. The runner uses Zig's
test namespaces to find each fixture's declared isolation; it does not inspect
source code. Original test names retain their slash-separated fixture paths,
so existing `-Dtest-filter=<substring>` filters keep working.

## Running and measuring

Run program fixtures with:

```sh
zig build test-programs -Doptimize=ReleaseSafe -j16 -Dtest-jobs=16
```

`-Dtest-jobs=1` runs the same discovered tests sequentially. Keep compiler unit
tests in a separate Debug run with `zig build test-internal -j16 -Dtest-jobs=16`.
Do not overlap invocations that reinstall the bundled libraries.

Per-worker text logs are written under `.zig-cache/program-tests/`. Each `case`
line records isolation, outcome, elapsed nanoseconds, Zig test name and leak
status and the number of in-process frontend checks, separated by tabs.
`-Dtest-progress=true` additionally records active
cases before they run. Timings include all orchestration performed by a test;
compare runs using the same optimization mode and environment.

## Coverage maintenance

Pure source diagnostics can live in compiler unit tests instead of launching the
CLI per case. `src/4_semantics/numeric_diagnostics_test.zig` demonstrates a bounded
table of independent sources checked through `FrontendPipeline`, including real
Safety analysis. It verifies exact diagnostic messages and source offsets, with
valid boundary cases as controls. These builtin-only cases need no installed
core; tests of library contracts must preserve their real module dependencies.
Keep representative CLI fixtures for rendered diagnostics and remove equivalent
integration cases when moving their semantic checks in-process.
Use `source_test_support.zig` for shared frontend setup, retaining independent
sources and the testing allocator. Keep CLI error translation and rendering
checks at the integration level; an internal diagnostic check does not exercise
those paths. Keep these strict allocator checks. The real-core environment has an
explicit compilation-region lifetime instead; it does not prove that all
inference scratch is released before that region ends.

Each test should establish a distinct rule, boundary or interaction. Before
adding a regression, check nearby fixtures and extend an existing one when it
can assert the new behavior independently. Keep failures isolated when an
earlier diagnostic would mask the intended check. Prefer the stronger existing
test when two fixtures execute the same program and assert the same behavior.

Name fixtures after their current guarantees, not the syntax or limitation that
originally motivated them. For negative tests, confirm that rejection exercises
the intended rule; a matching generic diagnostic alone may hide another error.
Positive counterparts can establish that the same mechanism accepts valid input.
Preserve distinct aliasing, control-flow, module and backend interactions even
when their programs look similar.

Do not retain migration-only rejection tests for retired syntax or APIs once a
transition is complete. Test the current language rather than cataloguing every
historical spelling. Keep negative tests for active grammar, type and safety
rules when they establish a distinct boundary or interaction.

Group small positive cases by the operation or protocol they exercise, using
named functions or separate scopes and checking each result. For example, range
iteration covers default bounds, signed steps and integer widths in one fixture;
error propagation covers statement, argument, condition and assignment contexts
in one fixture. Keep independent generic definitions when the test needs both
inferred and explicit specialization to be materialized separately. Retain
separate process tests when startup, cache state or failure isolation is itself
the behavior being checked. Put a fixture's native/VM checks and runtime error
expectations together rather than rebuilding it from an unrelated central test.

Central orchestration is reserved for checks whose resources span fixtures or
installation state. Native C fixture checks can run beside their source: the
shared `checkNativeCFixture` helper uses a private temporary directory and retains
both repeated-build IR checks and executable assertions. Semantic C boundary
rejections use the frontend helpers; C enum grammar uses the syntax helpers.
Safety wrapper-parity checks belong to the fixture whose output they build, so
ordinary and wrapped execution cannot race with another worker for that output.

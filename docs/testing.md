# Program tests

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

## Isolation

Declare `.fixture` only after reviewing the test's resources. All tests in that
file run on the same worker, so they may share their fixture's outputs and cache.
External files, ports and other mutable resources must be private to the test.
Use `.exclusive` for shared resources or when isolation has not been audited.
Exclusive tests finish before fixture workers start. Categories and helper names
do not determine scheduling.

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
status, separated by tabs. `-Dtest-progress=true` additionally records active
cases before they run. Timings include all orchestration performed by a test;
compare runs using the same optimization mode and environment.

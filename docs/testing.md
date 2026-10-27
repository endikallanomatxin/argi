# Compiler tests

Run program fixtures with `zig build test-programs -Doptimize=ReleaseSafe -j16
-Dtest-jobs=16`. Run compiler unit tests separately with `zig build test-internal
-j16 -Dtest-jobs=16` in Debug. `zig build test-harness` checks discovery,
expectation validation and scheduling without compiling Argi programs.

## Discovered fixtures

The runner discovers `tests/feature_tests/<category>/<case>/main.rg`. Nested
modules belong to their containing fixture and are not independent tests.
Every substantive root fixture needs either a sibling `test.json` or explicit
coverage from a custom test. Directory names, including `X` prefixes, do not
select expectations or execution isolation.

A native/VM differential case can use:

```json
{
  "version": 1,
  "isolation": "fixture",
  "cases": [
    {
      "steps": [
        { "kind": "build" },
        { "kind": "run", "status": 42 },
        { "kind": "vm", "status": 42 }
      ]
    }
  ]
}
```

Steps run in order:

- `build`: successfully compile the fixture.
- `run`: run its native executable, checking `status`. Optional `stdout` or
  `stderr` checks the exact stream. `args` and `stdin` accompany a `stdout`
  expectation. A preceding `build` is required.
- `run_failure`: require unsuccessful native execution after `build`.
- `vm`: execute through the VM, checking `status` and an optional `diagnostic`.
- `reject`: require a rejected build, checking a diagnostic substring or exact
  `stderr`. `forbidden_stdout` and `forbidden_stderr` exclude diagnostic noise.

For example, a rejected program declares:

```json
{
  "version": 1,
  "isolation": "fixture",
  "cases": [
    { "steps": [{ "kind": "reject", "diagnostic": "type mismatch" }] }
  ]
}
```

The default case name is its path without `tests/`. Multiple cases in one
fixture need distinct explicit `name` values. Unknown fields, duplicate names,
invalid expectations and uncovered fixtures fail discovery.

## Isolation and custom tests

`fixture` permits parallel execution with other fixtures. All cases sharing a
fixture directory run on the same worker, protecting its build outputs and
cache. Use it only when files, ports and other mutable resources are confined
to that fixture or privately created temporary storage.

`exclusive` runs before the fixture workers. Use it for shared resources or
cases whose isolation has not been audited. Moving a case to workers requires
reviewing its actual resources; its category alone does not establish safety.

Tests needing custom orchestration remain in `tests/test.zig`, with one matching
entry in `tests/custom_tests.json`. Each entry declares `name`, `isolation` and
`covers` (complete root fixture paths, or an empty list). A fixture-isolated
custom test additionally declares its `fixture` scheduling group. The runner
rejects missing or stale custom registrations. Shared process helpers live in
`tests/support.zig`.

## Filtering and measurements

`-Dtest-filter=<substring>` selects both descriptor and custom cases. With
`-Dtest-jobs=1`, the same inventory runs sequentially. With multiple workers,
exclusive cases finish first, then fixture groups are distributed by a stable
hash of their paths.

Each process writes totals to `.zig-cache/program-tests/*.log` and individual
results to the corresponding `.log.jsonl`. Records contain the case name,
fixture, origin, isolation, shard, duration in nanoseconds, result and leak
status. `-Dtest-progress=true` also records active cases in the text logs.
Compare timings from equivalent build modes and environments; these durations
include each case's complete orchestration, not just compiler execution.

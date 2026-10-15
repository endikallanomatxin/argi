# Parallel regression tests

The default Zig test runner executes each binary's cases serially. Build jobs
alone therefore do not parallelize program cases. Program fixtures share an
installed compiler bundle, while some CLI tests delete global test caches.

Implementation affects the test harness and build graph only. Compile one program
test binary, install the compiler and libraries once, execute unsafe/shared-state
cases serially, then run bounded independent processes over safe fixture groups.
Use a conservative source-based classification: only audited build/run helpers
with one literal fixture path qualify. Keep each fixture on one worker. Unknown
helpers, arbitrary test bodies and filesystem/network/CLI cases remain serial.
Preserve filters, per-case allocator/leak checks, error logs, failure exit status,
and optional progress. Internal tests retain Zig's standard runner.

Validate assignment coverage and isolation rules, compare serial/parallel timings
on the same filtered suite, and run the complete regression with bounded workers.


## Implementation and validation

`build.zig` installs once and launches one serial shared-state phase followed by
fixture workers. The source classifier accepts only audited helper calls, one
literal fixture, and straight-line statements; unknown cases fall back to serial.
Eligible cases for one fixture hash to one worker. Current assignment is 407 serial
cases and 1,326 parallel cases (337/341/333/315 with four workers). Worker processes
retain independent allocator/I/O state, check leaks and logged errors, report
failures with case names and traces, and always rerun even when Zig artifacts are
cached. Captured stdio avoids the build runner's terminal lock. Terminal progress
and per-worker logs retain active case names; logs also record final totals.

The complete four-worker Debug regression passed: 1,722 program tests and 366
internal tests, with 11 and one skips respectively; no failures, leaks, or logged
errors. Wall time was 15m33.96s; shared-state tests took approximately nine minutes,
so worker scaling cannot remove that serial portion. Standalone failure probes
confirmed nonzero exit status for assertion failures, leaked allocations, and
error logs, and preserved skip handling. Classifier tests cover arbitrary writes,
unknown helpers/categories, loops, multiple fixtures and mismatched bindings.

On the local 16-CPU machine, the same 109-contract suite passed with each count:

| Workers | Wall time |
| --- | --- |
| 1 | 71.57s |
| 4 | 22.58s |
| 8 | 16.84s |
| 16 | 8.84s |

These are individual warm-cache local runs, including the build invocation.
Defaults now follow the host CPU count capped at 16, with `-Dtest-jobs=N` as an
override and `-jN` controlling actual build concurrency. Use both worker and build
limits of one for serial memory investigations. Further shared-state cases can be
parallelized only after auditing their output/cache/native-resource isolation.

The final automatic-default smoke run used 16 workers on this machine and passed
both sharding checks plus the mixed static/virtual contract fixture. Serial mode
retains the stock Zig runner, as verified by the 109-contract serial baseline.

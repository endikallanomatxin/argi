# Parallel module semantics experiment

## Scope

Run independent module discovery and local semantic lowering through bounded
std.Io async workers. Keep parsing, cache acquisition/publication, GlobalSema,
safety and codegen serial. Preserve module ordering, diagnostic ordering and
source identities. No language syntax changes.

## Ownership

Each uncached module owns a separate arena. Cached modules use their existing
entry arenas. During worker execution only, arena backing allocations share a
locked parent allocator; restore original backing allocators after all workers
finish. Workers own diagnostic bags borrowing the immutable source index.
Merge copied diagnostics on the coordinator before releasing task storage.
Cache leases and publication remain coordinator-owned.

## Validation

Compare serial and parallel graphs, diagnostics and cache reuse. Exercise failure
cleanup and real Threaded I/O. Run compiler internal and program suites. Measure
cold and cached frontend runs at 1, 2, 4 and 8 jobs before selecting a default.

## Controls

- CLI build/check/run: `--frontend-jobs N`, accepting auto or 1..256, default auto.
- Pipeline callers: `Options.module_jobs`.
- Benchmark: `zig build -Doptimize=ReleaseSafe benchmark-frontend -- MODULE 10 N`.
- Build both tools without starting measurements:
  `zig build -Doptimize=ReleaseSafe install build-frontend-benchmark -j16`.
- Cache hits are not submitted as work; zero or one dirty module takes the serial
  path. Job count is execution policy and does not affect cache fingerprints.

## Measurements

ReleaseSafe, twelve measured iterations per scenario after priming, with source
collection, LLVM and native linking excluded. The machine was otherwise not
running a compiler test suite. CSV data is in parallel_module_sema_results.csv.

| Case | Jobs | Fresh frontend (ms) | ModuleSema (ms) | Reused frontend (ms) |
| --- | ---: | ---: | ---: | ---: |
| Contract specialization | 1 | 100.321 | 59.837 | 41.500 |
| Contract specialization | 2 | 74.297 | 29.788 | 41.922 |
| Contract specialization | 4 | 56.475 | 15.802 | 42.041 |
| Contract specialization | 8 | 51.642 | 9.720 | 42.593 |
| Matrix specialization | 1 | 110.789 | 62.091 | 49.523 |
| Matrix specialization | 2 | 83.080 | 31.124 | 49.583 |
| Matrix specialization | 4 | 65.245 | 15.713 | 50.143 |
| Matrix specialization | 8 | 60.418 | 9.284 | 49.548 |

Eight jobs reduce fresh frontend time by approximately 49% and 45% respectively.
Fully reused builds show no material benefit. Auto uses half the logical CPUs
reported by Zig, rounded down, with a minimum of one and a maximum of eight. Zig's
Linux CPU query honors affinity, but this is not a global scheduler or a guarantee
that CPU quotas are detected. CPU-query failure falls back to one worker. Explicit
counts override auto; use one when an outer build schedules many compiler processes.
Zero or one dirty module still runs serially regardless of the configured count.

Complete CLI compilations with one and eight jobs produce byte-identical LLVM
and successful executable results for contract specialization, matrix shape/product
specialization and native FFI capability forwarding. These checks use isolated
source copies so they cannot collide with active fixture workers.

## Test execution policy

Program-fixture process helpers insert `--frontend-jobs 1` for compiler build/check
calls and preserve explicit worker selections. Run commands keep a named package
executable in its original position. Native child programs and unrelated commands
are unchanged. The language test command also selects one worker internally.
Dedicated concurrency tests and performance runs request multiple workers explicitly.

## Final validation

- Full Debug internal suite: 392 passed, 1 skipped; subsequently registered build
  planning and automatic worker policy tests pass in focused Debug runs.
- Full ReleaseSafe program suite with fixture frontends forced to one worker:
  1956 passed, 11 skipped, no failures, leaks or error logs.
- Explicit auto resolves to eight workers on the measurement machine and produces
  LLVM identical to explicit eight-worker compilation.
- Zig formatting and whitespace checks pass. No language/library source changed.

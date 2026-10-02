# Incremental compilation

Scheduling: [0.3](0.3.md), before C interop and cross-compilation.

## Direction

Reuse work at the existing file/module boundaries before attempting fine-grained
incrementality. Canonical `ModuleSG`s are reused through a bounded session cache
in the LSP and versioned disk snapshots in CLI builds. Import discovery reads
open editor buffers, including unsaved dependencies. This first milestone is
complete; consider syntax-tree caching only if profiling warrants it.

## Measuring reuse

Run `zig build -Doptimize=ReleaseSafe benchmark-frontend -- <module-directory>`
(with an optional iteration count). It compares clean and reused frontend work
for unchanged inputs and local/import/core edits, including linked abstract
lowering and retained cache memory. Source collection, codegen, and linking are
outside these timings. Canonical modules are reusable; GlobalSG, safety, and
codegen are still rebuilt for each compilation.

Compare separate `argi build --stats` invocations with `--no-cache` to measure
persistent reuse. CLI snapshots live under `.argi-cache/frontend/`; incompatible
or damaged snapshots are rebuilt automatically. Keys include source sets/content,
core prelude inputs, semantizing options, compiler/format identity, and the current
target configuration. Explicit cross-compilation must extend those inputs when
introduced. Imported contents belong in keys only where cached decisions depend
on them. Process-local IDs and borrowed source pointers cannot serve as
persistent provenance.

Declaration-level incrementality, persistent GlobalSG/safety, and a mandatory
compiler daemon are outside the first step. Reuse supports a future interactive
session but does not define REPL state or redefinition behavior.

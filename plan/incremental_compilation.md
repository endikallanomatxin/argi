# Incremental compilation

Scheduling: [0.3](0.3.md), before C interop and cross-compilation.

## Direction

Reuse work at the existing file/module boundaries before attempting fine-grained
incrementality. Canonical `ModuleSG`s can be reused in memory by persistent
consumers. LSP semantic requests share a bounded cache; decide on CLI disk
persistence from measured benefits.

## Work to do

- [ ] Evaluate versioned persistent module caches for separate CLI builds;
  consider syntax-tree caching if tokenizing/syntaxing remain costly.

## Measuring reuse

Run `zig build -Doptimize=ReleaseSafe benchmark-frontend -- <module-directory>`
(with an optional iteration count). It compares clean and reused frontend work
for unchanged inputs and local/import/core edits, including linked abstract
lowering and retained cache memory. Source collection, codegen, and linking are
outside these timings. Canonical modules are reusable; GlobalSG, safety, and
codegen are still rebuilt for each compilation.

The in-memory cache fingerprints source sets/content, core prelude inputs, and
semantizing options; compiler and target are fixed within the process. Persistent
or target-aware caches also need compiler/format versions and target settings. Imported contents belong in
keys only where cached decisions depend on them. Process-local IDs and borrowed
source pointers cannot serve as persistent provenance.

Declaration-level incrementality, persistent GlobalSG/safety, and a mandatory
compiler daemon are outside the first step. Reuse supports a future interactive
session but does not define REPL state or redefinition behavior.

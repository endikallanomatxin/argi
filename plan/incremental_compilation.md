# Incremental compilation

Scheduling: [0.3](0.3.md), before C interop and cross-compilation.

## Direction

Reuse work at the existing file/module boundaries before attempting fine-grained
incrementality. Start with in-memory `ModuleSG` reuse and a persistent consumer
such as the LSP; decide on CLI disk persistence from measured benefits.

## Work to do

- [ ] Compare cold builds, unchanged rebuilds, local edits, and imported-module
  edits; measure phase costs, total latency, and retained memory.
- [ ] Reuse canonical module graphs while rebuilding GlobalSG, safety, and
  codegen initially. Ordinary imported requirements remain unresolved until
  linking; measure the extra pass for qualified imported abstracts separately.
- [ ] Preserve source provenance and diagnostic locations across reuse, including
  unsaved editor buffers, file changes, and failed builds followed by corrections.
- [ ] Integrate useful reuse into LSP requests and bound retained cache memory.
- [ ] Add versioned persistent module caches only if separate CLI builds benefit;
  consider syntax-tree caching separately if tokenizing/syntaxing remain costly.

Cache keys need source-set/content fingerprints, compiler/configuration versions,
core prelude inputs, and relevant target settings. Imported contents belong in
keys only where cached decisions depend on them. Process-local IDs and borrowed
source pointers cannot serve as persistent provenance.

Declaration-level incrementality, persistent GlobalSG/safety, and a mandatory
compiler daemon are outside the first step. Reuse supports a future interactive
session but does not define REPL state or redefinition behavior.

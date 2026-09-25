# Incremental compilation

## Current boundary

Tokenizing and syntaxing produce one `FileSyntaxTree` per source file. All direct
`.rg` files in a directory form one module. ModuleSema builds a canonical,
module-owned `ModuleSemanticGraph` (`ModuleSG`) from those trees; GlobalSema then
links module graphs and resolves cross-module and whole-program operations before
Safety and Codegen.

A durable `ModuleSG` may finish only decisions that cannot change when an ordinary
imported module changes. It retains external requirements for GlobalSema rather
than embedding decisions owned by imported modules. Bundled core prelude abstracts
are explicit compiler semantic configuration, so their fingerprint belongs in
the cache key. The cacheable graph is the canonical module representation, not
ModuleSema's temporary discovery state.

## Cache boundaries

- `FileSyntaxTree` is the natural per-file cache boundary. A changed file can be
  tokenized and syntaxed again while unchanged file trees are reused if their
  reuse proves worthwhile.
- `ModuleSG` is the primary semantic cache boundary. A module with the same
  direct source set and semantic configuration can be reused across builds;
  GlobalSema still resolves its external requirements for the current program.

Cache hits must preserve stable source provenance for diagnostics without
depending on process-local `FileId` values or pointers into source buffers.
Load source text or syntax trees when diagnostics or LSP operations need them.

## Qualified imported abstracts

The current frontend can build a transient linked derivative when a qualified
imported abstract appears in a function input position. That derivative reruns
ModuleSema for affected modules. The durable `ModuleSG` remains independent of
the imported declaration kind, but a cache experiment must measure this extra
work separately. If it materially limits reuse, represent the external contract
candidate in the durable graph and activate abstract semantics after linking,
without a second ModuleSema pass.

## Next experiment

1. Reuse completed `ModuleSG`s in memory on an unchanged rebuild, before
   designing a disk format. Measure total frontend time and the work saved by
   module reuse, including the linked-abstract derivative separately.
2. Compare cold builds, unchanged rebuilds, one-file changes, and changes to a
   widely imported module in the same environment. Check diagnostics and output
   for equivalence with a clean build.
3. Add a versioned persistent `ModuleSG` format only if the measured benefit
   justifies serialization and loading costs. Bundled `core` is an initial
   high-value candidate. Evaluate a persistent `FileSyntaxTree` cache separately
   if tokenizing and syntaxing remain material after module reuse.

## Cache key

A persistent `ModuleSG` key must include:

- identity and content fingerprints for every direct `.rg` file, including file
  additions, removals, and renames;
- compiler, language, and artifact-format versions;
- bundled core prelude fingerprint;
- compiler options and module layout inputs that affect module-local semantics.

Ordinary imported-module contents stay out of the basic key while their effects
remain unresolved external requirements. If a later graph embeds imported
semantic decisions, its key must also track the relevant imported interfaces.

## Non-goals for the first cache implementation

- Subtree-level incremental syntaxing and declaration-level semantizing.
- Persistent `GlobalSemanticGraph` or incremental Safety.
- Dependency-interface hashing and stable semantic IDs across source edits.
- Zero-copy loading or a broader representation redesign before measurements
  show a need.

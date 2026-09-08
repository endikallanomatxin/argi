# Indexed semantic graph representation checkpoint

This checkpoint closes the **representation/schema** required to migrate Argi away
from the pointer-heavy semantic graph. It deliberately does not claim that the
current Semantizer, Safety checker, Codegen or persistent cache already consume
only this representation.

## Architectural boundary

The target frontend remains:

```text
SourceFile
    ↓
FileTokenList
    ↓
FileSyntaxTree[]
    ↓ one directory / language module
ModuleSemanticGraph
    ↓ GlobalSema + relocation
GlobalSemanticGraph
    ↓
Safety
    ↓
Codegen
```

Files are parsing units. Module directories are semantic/cache units. There is no
persistent `FileSemanticGraph` layer.

## Representation completed

- [x] Separate strongly typed `Module*Id`, `Global*Id` and `Template*Id` domains.
- [x] Shared canonical payload schema for declarations, types, functions,
  bindings, blocks, nodes and all side-table entities needed by the legacy SG.
- [x] Compact ranges/reference pools instead of semantic object pointers.
- [x] Module-owned strings and stable module-file source provenance.
- [x] Explicit module `ExternalRef` and `PendingOperation` states for semantic
  decisions that another module can affect.
- [x] Complete node/control-flow payload coverage needed by Safety and Codegen,
  including auto-deinit, virtual dispatch, reach, choice refinement, pointer
  operations and error propagation/context.
- [x] Generic identity represented independently from its concrete materialized
  shape (`structure`, `choice`, `array` or `alias`).
- [x] Complete ModuleSGs require exactly one materialized shape for every
  resolved generic identity.
- [x] Source-independent template/abstract IR owned by ModuleSG.
- [x] Template IR explicitly represents `Self`, generic type parameters,
  external/module references and dependent `comptime_int` expressions
  (`literal`, parameter and `+ - * / %`).
- [x] Template bodies and symbolic holes use semantic IDs rather than
  `FileSyntaxTree` / `SyntaxRef` / `NodeIndex` references.
- [x] Indexed final `GlobalSemanticGraph` with independent global identities.
- [x] Mechanical ModuleSG-to-GlobalSG relocation for resolved entities, body
  side tables, reference pools, source provenance and generic materializations.
- [x] Global symbol entries preserve module ownership through their declaration
  IDs; equal spellings in different modules remain distinct.
- [x] Structural verifiers reject dangling IDs/ranges, duplicate generic shapes,
  unresolved final nodes, malformed symbol ownership and invalid source/string
  references.
- [x] Final GlobalSG rejects ModuleSema-only type sugar (`nullable` and
  `inferred_errable`); GlobalSema must materialize those into concrete semantic
  types before finalization.
- [x] Representation modules are registered in `src/internal_tests.zig` so the
  normal internal test build compiles their tests.
- [x] End-to-end representation tests exercise independent module-ID relocation,
  inferred-choice identity, generic identity + materialized shape relocation,
  and identical symbol names owned by different modules.

## Migration compatibility state

The physical `ModuleSemanticGraph` currently remains a **hybrid migration
container**. Its older compatibility-prefix tables still contain temporary syntax
bridges such as `syn.NodeIndex` for declarations, field defaults and discovery
references. They exist only so the current compiler can migrate incrementally.

They are **not** the persistent ModuleSG ABI and must not be serialized as the
future cache format.

The canonical representation is the logical ModuleSG exposed by the shared
payloads/views plus `module.semantic` and its template IR. As producers move to
that storage directly, the compatibility prefixes and syntax bridges should be
deleted rather than copied into another artifact.

A cache hit must eventually be able to continue GlobalSema/monomorphization from
the cached ModuleSG without reparsing source merely to recover generic or abstract
patterns.

## Work that remains after this representation checkpoint

These are implementation/migration phases, not missing representation design:

1. **Populate canonical ModuleSG directly**
   - Lower all module-local types, callable interfaces, lexical bindings,
     expressions, defaults and bodies into `Module*Id` storage.
   - Emit `ExternalRef` / `PendingOperation` whenever another module can change
     the result.
   - Populate template IR directly while ModuleSema still has FileST available.
   - Remove the compatibility-prefix syntax bridges when their consumers are gone.

2. **Implement GlobalSema over ModuleSGs**
   - Resolve external module symbols and pending calls/fields/abstract/copy/deinit
     work.
   - Instantiate/consume generic and abstract templates from ModuleSG template IR.
   - Materialize `nullable` / `inferred_errable` states.
   - Close virtual registries and other program-wide semantic sets.
   - Produce only verifier-valid final GlobalSG state.

3. **Migrate downstream consumers**
   - Safety -> `Global*Id` / indexed views.
   - Codegen -> `Global*Id` / indexed views.
   - Semantic debug/printing utilities -> indexed representation.
   - Delete the pointer-heavy `semantic_graph.zig` after the last consumer moves.

4. **Persistence**
   - Define explicit versioned FileSyntaxTree and ModuleSG formats.
   - Do not serialize Zig pointer/slice ABI or migration-prefix syntax bridges.
   - Key ModuleSG by its direct source set/content plus semantic configuration.
   - Make bundled `core` the first high-value prebuilt/cached ModuleSG consumer.
   - Benchmark cold, unchanged and one-file-changed builds before further layout
     optimization or mmap/zero-copy work.

## Validation before integrating this branch

The representation was statically audited in the ChatGPT environment, but that
environment does not provide a Zig toolchain and cannot execute the repository's
build. Before merging/cherry-picking this checkpoint, run locally:

```sh
zig fmt src/4_semantics/semantic_primitives.zig \
  src/4_semantics/semantic_type_shapes.zig \
  src/4_semantics/module_semantic_entities.zig \
  src/4_semantics/module_semantic_storage.zig \
  src/4_semantics/module_semantic_templates.zig \
  src/4_semantics/module_semantic_template_ir.zig \
  src/4_semantics/module_semantic_template_ir_verify.zig \
  src/4_semantics/module_semantic_template_verify.zig \
  src/4_semantics/module_generic_instance_verify.zig \
  src/4_semantics/module_semantic_views.zig \
  src/4_semantics/module_semantic_verify.zig \
  src/4_semantics/module_semantic_complete_verify.zig \
  src/4_semantics/global_semantic_graph.zig \
  src/4_semantics/global_semantic_verify.zig \
  src/4_semantics/semantic_payload_verify.zig \
  src/4_semantics/semantic_verify.zig \
  src/4_semantics/semantic_globalizer.zig \
  src/4_semantics/semantic_representation_test.zig \
  src/internal_tests.zig

zig build test
git diff --check compact-semantic-graph...compact-semantic-graph-chatgpt
```

If those pass, this branch is ready to be treated as the completed indexed
semantic **representation** checkpoint, and further work should migrate the
compiler onto it rather than expand the schema speculatively.

# Frontend file and module artifacts

## Goal

Make the frontend naturally incremental across compiler invocations while using
semantic boundaries that match the language rather than forcing semantic analysis
to follow source-file boundaries.

Argi has two different natural units:

- a **source file** is the natural unit of tokenizing and parsing;
- a **module directory** is the natural unit of semantic analysis.

The target pipeline is therefore:

```text
SourceFile
    ↓
FileTokenList
    ↓
FileSyntaxTree ────────────────┐
                              │ all direct .rg files in one module
FileSyntaxTree ────────────────┤
                              ▼
                     ModuleSemanticGraph
                              │
                              │ modules used by this compilation
                              ▼
                     GlobalSemanticGraph
                              ↓
                            Safety
                              ↓
                           Codegen
```

The intended persistent cache boundaries are:

```text
FileSyntaxTree          per source file
ModuleSemanticGraph     per module directory
```

`FileTokenList` remains a useful pipeline artifact, but does not necessarily need
its own persistent cache. `FileSemanticGraph` is no longer an intended persistent
artifact or semantic boundary.

## Why semantics should start at module scope

A file boundary is syntactic, but in Argi a directory is already a real semantic
module boundary:

- a module consists of the `.rg` files directly in one directory;
- `#import` resolves another module directory;
- module dependency order is already constructed from those imports;
- declarations in different files of the same directory participate in the same
  module world;
- existing semantic lookup already distinguishes module-scoped resolution.

Consequently, many useful semantic decisions are artificially deferred if each
file must first produce an independently valid semantic graph.

For example:

```text
geometry/
    point.rg
    distance.rg
```

```argi
-- point.rg
Point :: struct {
    x: Float64,
    y: Float64,
}
```

```argi
-- distance.rg
distance :: (a: Point, b: Point) -> Float64 {
    ...
}
```

A file-semantic pass over `distance.rg` has to preserve `Point` as an unresolved
lookup even though `Point` is part of the same semantic module. A module semantic
pass can first discover declarations from both syntax trees and then resolve
`Point` directly while semantizing `distance`.

This is both more useful and simpler than constructing a file graph, copying its
names and IDs, relocating it, and only then doing the semantic work that required
another file in the same module.

## Parsing and semantic analysis are intentionally different granularities

Do not conflate the unit of parsing with the unit of semantic analysis.

Tokenizing and parsing remain independent per file:

```text
a.rg -> FileSyntaxTree A
b.rg -> FileSyntaxTree B
c.rg -> FileSyntaxTree C
```

The syntax trees do not need to be physically concatenated. ModuleSema receives a
view over all file trees belonging to the module:

```text
ModuleSyntaxInputs {
    files: []const FileSyntaxTree,
}
```

Syntax references can continue carrying file provenance where necessary. Semantic
identities created by ModuleSema, however, should be module identities rather than
`{ file, local_id }` identities.

Conceptually:

```text
ModuleDeclId
ModuleFunctionId
ModuleBindingId
ModuleNodeId
ModuleTypeId
ModuleExternalRefId
```

A declaration remembers where it came from for diagnostics, but its semantic
identity belongs to the module:

```text
ModuleFunctionId #21
    source = { module_file = 2, byte_offset = 418 }
```

The source location is provenance, not semantic identity.

## `ModuleSemanticGraph` invariant

A `ModuleSemanticGraph` may contain only semantic decisions whose correctness is
independent of the contents of other modules.

This is the semantic cache invariant.

If changing another module could change a decision, ModuleSema must represent the
requirement explicitly for GlobalSema instead of choosing a final target.

This permits aggressive resolution inside one module while keeping the module
artifact independently cacheable.

### Safe to finish in ModuleSema

Where language rules permit it, ModuleSema can finish work such as:

- declaration discovery across all files in the module;
- module symbol-table construction;
- lexical scopes and local binding identities;
- references to parameters and local bindings;
- cross-file references to declarations in the same module;
- type declarations and type names defined in the same module;
- function interfaces whose types are module-local or built in;
- field lookup on known module-local types;
- local control-flow lowering;
- literals and intrinsically known operations;
- generic/template structure defined by the module;
- overload sets whose relevant candidate set is closed within the module;
- abstract and implementation information that can be established without
  consulting another module;
- source provenance needed by later diagnostics.

The exact set should follow language semantics, not a target percentage of work.
The rule is simply: another module must not be able to invalidate the answer.

### Must remain pending for GlobalSema

ModuleSema preserves explicit unresolved requirements for work that depends on
other modules or the whole program, including where applicable:

- imported-module name and type resolution;
- calls whose candidate set includes declarations from imported modules;
- cross-module abstract implementation selection;
- generic instantiation whose selected declaration or inputs are external;
- `copy` / `deinit` selection when external candidates can affect the answer;
- inferred information that crosses module boundaries;
- virtual method closure/registries with external participants;
- reachability-dependent program-wide work;
- any other operation whose result could change when another module changes.

These should be represented as semantic requirements, not as pointers into
another module artifact.

For example:

```text
ExternalTypeRef {
    module = "geometry"
    name = "Point"
}
```

or:

```text
PendingCall {
    target = ExternalFunctionSetRef(...)
    arguments = ...
}
```

## Module semantic construction

The first implementation should semantize one module directly from its
`FileSyntaxTree`s rather than constructing `FileSemanticGraph`s first.

A useful staged shape is:

```text
all FileSyntaxTrees in module
        ↓
1. discover all module declarations
        ↓
2. build module symbol indexes
        ↓
3. stabilize module types/support declarations
        ↓
4. semantize callable interfaces
        ↓
5. verify module-local abstract/template relationships where valid
        ↓
6. semantize function defaults and bodies
        ↓
7. emit explicit external refs / pending global operations
        ↓
ModuleSemanticGraph
```

This deliberately resembles the useful staging already present in the current
Semantizer, but moves the first semantic world from program scope to module scope.

### Direct construction, not file relocation

The module builder should allocate semantic IDs directly in module storage.

Instead of:

```text
file A Binding #0 ─┐
                   ├─ relocate → module Binding #37
file B Binding #0 ─┘
```

prefer:

```text
process file A -> ModuleBindingId #0 ...
process file B -> ModuleBindingId #37 ...
```

This removes an otherwise unnecessary intermediate representation, string copy,
ID relocation pass, and set of offset tables.

The current file-local discovery helpers can still be reused internally where
they are convenient, but their results should write into module-owned stores or
short-lived builder scratch rather than becoming a long-lived FileSG artifact.

## Compact semantic representation

`ModuleSemanticGraph` should be compact and index-based. Do not reproduce the
current pointer-heavy semantic graph in serializable form.

Use a small number of semantic tables based on actual access patterns, for
example:

```text
ModuleSemanticGraph
    nodes
    declarations
    functions
    bindings
    blocks
    types
    external_refs
    pending_global_ops
    extra_data
    strings
    source_files / source provenance
```

The representation should use the same data-oriented principles that worked for
the compact syntax tree, but not blindly force every semantic entity into one
universal node format.

A reasonable split is:

- expression/statement nodes: compact tagged records with small fixed payloads
  and `extra_data` for variable operands;
- functions, bindings, declarations and other large semantic populations:
  dedicated dense tables;
- types: compact module-local type IDs, with canonicalization/interning where it
  is semantically useful;
- variable-length collections: ranges into shared side storage;
- names: one module-owned string store, unless measurements justify a different
  representation.

Pointers between independently allocated semantic objects should not be part of
the persistent representation.

## Building the global graph

The global boundary is now between modules, not files:

```text
ModuleSG A ─┐
ModuleSG B ─┼─→ globalize / link
ModuleSG C ─┘         ↓
                 resolve external refs
                 resolve pending ops
                       ↓
                GlobalSemanticGraph
```

Globalization may still use a flatten-and-relocate strategy for compact module
arrays if that is simplest. At this level the copy has semantic value because it
crosses the real module boundary and gives Safety/Codegen simple global IDs.

Conceptually:

```text
ModuleDeclId     -> GlobalDeclId
ModuleFunctionId -> GlobalFunctionId
ModuleBindingId  -> GlobalBindingId
ModuleNodeId     -> GlobalNodeId
ModuleTypeId     -> GlobalTypeId
```

Types may require canonicalization rather than a simple offset relocation. Start
with the simplest correct representation and introduce interning where canonical
identity is actually useful.

### Global symbol indexes

GlobalSema builds the indexes required to resolve symbolic references exported by
module artifacts. Normal downstream consumers should see resolved global IDs, not
symbolic module references on hot paths.

For example:

```text
ExternalTypeRef("geometry", "Point")
        ↓
GlobalTypeId #74
```

and:

```text
PendingCall(...)
        ↓
Call {
    callee = GlobalFunctionId #183
}
```

Safety remains after `GlobalSemanticGraph` for now. Incremental Safety and
fine-grained semantic dependency invalidation are separate future work.

## Persistence and caching

### File syntax cache

A `FileSyntaxTree` is naturally independent and can be cached per source file.
On a module cache miss after changing one source file:

```text
load FileST(a)
parse b.rg
load FileST(c)
        ↓
ModuleSema
```

This preserves fine-grained reuse where file boundaries are genuinely natural.

`FileTokenList` can remain part of `FileSyntaxTree` ownership as today. Do not add
a separate persistent token cache unless measurements or LSP requirements justify
it.

### Module semantic cache

`ModuleSemanticGraph` is the primary semantic cache target.

```text
module files
    ↓ cache miss
load/parse FileSyntaxTrees
    ↓
ModuleSema
    ↓
ModuleSemanticGraph ──→ persistent cache

cache hit ─────────────→ ModuleSemanticGraph
```

If no file in a module has changed, a normal compilation should be able to load
the cached ModuleSG without reading/tokenizing/parsing those sources merely to
reconstruct semantic state.

A ModuleSG cache key must include everything allowed to affect module-local
semantics, at minimum:

- the identity and content fingerprint of every direct `.rg` file in the module;
- compiler/language semantic format version;
- compiler options that can affect module-local semantics;
- module layout/configuration inputs that are semantically relevant.

Adding, removing, renaming or changing a direct source file invalidates that
module artifact.

Imported modules do **not** belong in the basic V1 ModuleSG cache key if their
contents are only represented as unresolved external requirements. This keeps the
artifact independently cacheable.

### Future dependency-interface cache

A later optimization can allow a more resolved module artifact to depend on
stable semantic interfaces of imported modules:

```text
ModuleInterface(geometry) -> hash ABC
```

A dependent cache key could then include interface hashes rather than full
implementation hashes. Changes to another module that preserve its interface
would not invalidate dependent semantic work.

Do not build this dependency-interface layer in the first implementation.

### Why there is no persistent FileSG cache

The current branch demonstrated that a FileSG can safely precompute declaration,
lexical-binding, type-reference and import metadata. However, most valuable
semantic work remains artificially pending until other files in the same module
are visible.

Persisting FileSG as another cache layer would therefore add:

- another semantic representation;
- another string/ownership boundary;
- local IDs that later require relocation;
- another serialization format and validity rule;
- another merge pass;
- duplicated semantic traversal during migration;
- limited saved work compared with caching the complete ModuleSG.

For V1, prefer the simpler model:

```text
FileSyntaxTree cache
        ↓
ModuleSemanticGraph cache
```

If future measurements show that rebuilding very large changed modules is a
problem, solve that with real semantic dependency tracking at declaration or
analysis-unit granularity rather than reinstating source files as an arbitrary
semantic boundary.

## Source and diagnostics

A persistent ModuleSG must not depend on runtime `FileId` values or slices into
transient source buffers.

Use module-local source provenance, for example:

```text
ModuleFileId / ModuleFileIndex
byte_offset
```

with a module-owned table mapping those file identities to stable relative paths
or equivalent source identities.

The source text or FileSyntaxTree may be loaded lazily when rich diagnostics,
LSP operations or source reconstruction require it. Ordinary ModuleSG cache hits
should not read and parse source only because a later error might need source
text.

## Current branch and migration direction

The `compact-semantic-graph` branch first accumulated useful exploratory work
around `FileSemanticGraph` and a `GlobalSemanticGraphBuilder`:

- frontend artifact naming (`FileTokenList`, `FileSyntaxTree`);
- file-local declaration discovery;
- lexical scope/binding/reference discovery;
- owned shared string ranges;
- symbolic type references;
- import references;
- file-local IDs;
- flatten/relocation experiments for declarations and lexical tables;
- integration of some pre-discovered information into the legacy Semantizer;
- storage and timing instrumentation.

This work was useful because it exposed the natural semantic boundary. It should
now be treated as migration scaffolding, not as architecture to preserve.

Do **not** continue investing in a persistent FileSG format or complete
file-to-global relocation machinery.

Reuse or adapt the algorithms that are still useful, but redirect them toward:

```text
[]FileSyntaxTree for one module
        ↓
ModuleSemanticGraphBuilder
        ↓
ModuleSemanticGraph
```

In particular:

- declaration discovery should populate module declaration storage directly;
- lexical scope and binding discovery should allocate module IDs directly;
- type/import reference extraction should feed module resolution directly;
- file provenance should remain available for diagnostics;
- the current global flattening helpers can inform the eventual
  ModuleSG-to-GlobalSG globalization layer, where relocation is actually useful.

Do not preserve an intermediate FileSG merely to avoid deleting or reshaping code
written during this investigation.

The Phase 0 pivot is now reflected in the implementation. `FrontendPipeline`
groups syntax trees by their directory, constructs one `ModuleSemanticGraph` per
group directly from those trees, and globalizes module graphs. Declaration,
reference, string and lexical storage is module-owned; file ordinals inside it
are module-local provenance and are translated to invocation `FileId`s only by
the temporary global compatibility bridge. No `FileSemanticGraph` artifact or
file-to-global semantic merge remains.

## Implementation plan

### Phase 0 — pivot the current scaffolding (complete)

1. Keep `FileTokenList` and `FileSyntaxTree` as the per-file frontend artifacts.
2. Introduce an explicit module grouping in the frontend pipeline: one module is
   one directory and contains its direct `.rg` files.
3. Introduce `ModuleSemanticGraph` / `ModuleSemanticGraphBuilder` terminology and
   storage.
4. Stop extending `FileSemanticGraph` as a persistent or complete semantic
   artifact.
5. Move/reuse file declaration, lexical, type-reference and import discovery so
   it writes directly into module-owned builder state.
6. Remove file-local relocation layers once their consumers have moved.
7. Keep tests that describe language semantics and ownership guarantees; rewrite
   tests that only exist to validate the obsolete file-to-global architecture.

### Phase 1 — direct module semantic analysis (in progress)

1. [x] Give ModuleSema all `FileSyntaxTree`s belonging to one module.
2. [x] Discover all top-level declarations before resolving module semantics.
3. [x] Build module symbol indexes.
4. [ ] Semantize module-local types and callable interfaces. Module-local type
   identities, simple nominal struct fields and non-generic callable interfaces
   made from names, builtins, pointers and arrays are now produced and consumed;
   richer type forms remain.
5. [ ] Lower lexical scopes, bindings, expressions and control flow directly to
   module IDs.
6. [ ] Resolve cross-file references inside the same module. Unqualified named
   type references are the first migrated case.
7. [ ] Emit explicit external-module references and pending global operations for
   everything whose answer can depend on another module.
8. [x] Ensure ModuleSema does not need semantic state from imported modules to build
   the basic cacheable ModuleSG.

### Phase 2 — compact `ModuleSemanticGraph`

1. Stabilize the semantic tables and ID taxonomy before optimizing layout.
2. Convert hot/large tables to data-oriented compact storage as justified by
   access patterns.
3. Introduce module-local type IDs and canonicalization where needed.
4. Eliminate raw semantic pointers and transient source slices from the
   persistent representation.
5. Measure ModuleSG build time, retained bytes and downstream traversal cost.

### Phase 3 — module globalization

1. Make `GlobalSemanticGraphBuilder` consume ModuleSGs rather than FileSGs.
2. Flatten/relocate module semantic IDs into global IDs where appropriate.
3. Canonicalize global types where simple relocation is insufficient.
4. Build global symbol indexes.
5. Resolve external module references.
6. Resolve pending cross-module/program operations.
7. Produce an indexed `GlobalSemanticGraph` for Safety and Codegen.

### Phase 4 — migrate downstream consumers

1. Move Safety from pointer-based SG objects to global semantic IDs/views.
2. Move Codegen and semantic debug/printing utilities to the indexed global
   representation.
3. Remove the legacy pointer-heavy semantic graph once no consumer needs it.
4. Preserve the current language/test baseline throughout the migration.

### Phase 5 — persistent caches

1. Define an explicit versioned FileSyntaxTree cache format if measurements show
   that parsing reuse is worthwhile independently of ModuleSG cache hits.
2. Define an explicit versioned ModuleSG disk format; do not serialize raw Zig
   pointer/slice ABI.
3. Key ModuleSGs by module source set/content plus semantic configuration.
4. Make bundled `core` the first high-value consumer of prebuilt ModuleSGs.
5. On ModuleSG cache hits, avoid loading source/FileST unless diagnostics or LSP
   require them.
6. Benchmark cold builds, unchanged rebuilds and one-file-changed rebuilds.
7. Optimize loading (including mmap/zero-copy) only if measurements justify it.

### Phase 6 — later incremental semantics

If changed-module ModuleSema becomes a bottleneck, add true semantic dependency
tracking at declaration/analysis-unit granularity:

```text
analysis unit B depends on interface/value of analysis unit A
```

Invalidate only affected units when possible. This is preferable to treating
source files as semantic dependency units merely because they are convenient
filesystem boundaries.

## Non-goals for the first module-semantic implementation

Do not combine these into the initial pivot:

- subtree-incremental parsing;
- declaration-level incremental Sema;
- dependency-interface hashing;
- persistent GlobalSemanticGraph cache;
- incremental Safety;
- mmap/zero-copy cache loading;
- stable semantic IDs across arbitrary source edits;
- redesigning every semantic table for maximum compactness before its shape is
  stable.

The immediate goal is simpler: make files the parsing unit, modules the semantic
unit, and modules the primary semantic cache boundary.

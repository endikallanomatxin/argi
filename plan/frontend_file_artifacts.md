# Frontend file artifacts

## Goal

Make the frontend naturally incremental across compiler invocations by giving each
source file self-contained, compact artifacts and delaying only genuinely
program-wide semantic work until the files are combined.

The target pipeline is:

```text
SourceFile
    ↓
FileTokenList
    ↓
FileSyntaxTree
    ↓
FileSemanticGraph
    ↓
GlobalSemanticGraph
    ↓
Safety
    ↓
Codegen
```

The important architectural boundary is `FileSemanticGraph`:

- everything up to and including it is file-local;
- it can be persisted and reused independently for an unchanged file;
- everything whose meaning can change when another file is added, removed, or
  changed is deferred to globalization;
- `GlobalSemanticGraph` is the fully linked semantic representation consumed by
  later whole-program passes.

This gives us a stronger cache boundary than syntax alone without requiring
fine-grained incremental parsing or semantic invalidation as the first step.

## Current state

The compact frontend migration is complete enough that tokenizing and syntaxing
already operate independently per source file. `FrontendPipeline` owns one
compact syntax artifact per file and Semantizer consumes those compact syntax
files directly.

The artifact names have been introduced. `FileTokenList` is defined by the
tokenizing layer and its columns are transferred into `FileSyntaxTree`.
`GlobalSemanticGraph` names the existing global representation; it does not yet
imply indexed storage. The ownership model still needs migration:

- tokens are currently retained as part of `FileSyntaxTree`;
- semantic analysis currently constructs one global, pointer-heavy
  `GlobalSemanticGraph`/`SGNode` world;
- semantic declarations, types, bindings, calls, scopes, and helper structures
  are connected extensively through pointers and allocator-owned slices;
- local and global semantic work are performed by the same Semantizer.

The next work is therefore not another syntax migration. It is to establish the
file/global semantic boundary and make semantic storage data-oriented and
index-based.

## Naming

Use the following names consistently for the long-lived frontend artifacts:

```text
FileTokenList
FileSyntaxTree
FileSemanticGraph
GlobalSemanticGraph
```

`File*` means that the artifact's correctness depends only on that source file
plus compiler/language configuration explicitly included in its cache key.

`GlobalSemanticGraph` means that cross-file names, types, calls, abstracts,
generics, and other program-wide relationships have been resolved as required
by later passes.

Internal builders or temporary merge state do not need to become additional
public artifact kinds. Conceptually:

```text
globalize(file_graphs)
    = mergeFileGraphs(file_graphs)
    + resolveGlobalGraph()
```

## Fundamental `FileSemanticGraph` invariant

A `FileSemanticGraph` must never contain a semantic decision whose correctness
depends on the contents of another source file.

This is stronger and safer than "do as much semantic work as possible".

If changing another file could change the answer, `FileSema` must preserve an
explicit unresolved/pending representation for `GlobalSema` instead.

For example, this is safe to resolve in `FileSema`:

```argi
foo :: () -> Int32 {
    x ::= 3
    return x
}
```

The file graph can know that the return refers to the local binding `x` and can
represent that with a local binding/node index.

By contrast, if a call, type, abstract implementation, destructor, copy
operation, overload, or other operation may be affected by declarations in
another file, the file graph records the semantic requirement but does not
choose the global target yet.

This invariant is what makes per-file semantic caching correct by construction.

## File-local semantic work

`FileSema` should lower syntax into a more semantic, compact representation and
finish all work whose answer is guaranteed to be file-local.

Likely responsibilities include:

- top-level declaration discovery and file-local declaration identities;
- lexical scopes and local binding identities;
- references to parameters and local bindings;
- local control-flow structure;
- literals and operations whose meaning is intrinsically known;
- structural information for declarations and type expressions;
- generic parameter declarations and other local template structure;
- source locations needed by later diagnostics;
- module/import references in a compact form;
- explicit external references;
- explicit pending semantic operations that require global knowledge.

The exact boundary should be refined as implementation proceeds, but the rule
above is non-negotiable: a decision is file-local only if another file cannot
change it.

## What remains global

`GlobalSema` handles work whose candidate set, identity, or result can depend on
other files or on the program as a whole. This includes, where applicable:

- external name and type resolution;
- call/overload resolution;
- cross-file field/type completion;
- abstract implementation lookup and verification;
- generic instantiation whose inputs or selected declaration are global;
- `copy` and `deinit` selection;
- inferred information that crosses declaration/file boundaries;
- virtual method closure/registries;
- reachability-dependent semantic work;
- any other operation whose result could change when another visible
  declaration changes.

Safety remains after `GlobalSemanticGraph` for now. Incremental safety or
fine-grained semantic invalidation is a separate future problem.

## File-local identities

`FileSemanticGraph` should use dense local indices rather than pointers.
Conceptually:

```text
FileNodeId
FileDeclId
FileFunctionId
FileTypeId
FileBindingId
ExternalRefId
```

The concrete set can evolve, but semantic relationships should be represented
by integer IDs into compact tables rather than allocator addresses.

A file graph can then look roughly like:

```text
FileSemanticGraph
    nodes
    declarations
    functions
    types
    bindings
    extra_data
    external_refs
    pending_global_ops
```

Storage should follow the same data-oriented principles as the compact syntax
representation where useful: dense arrays, small tagged records, stable local
indices, and side tables/`extra_data` for variable payloads.

## Local versus external references

References inside `FileSemanticGraph` should make the boundary explicit in the
type system.

For example:

```text
FileDeclRef =
    local(FileDeclId)
    external(ExternalRefId)
```

Similarly, where needed:

```text
FileTypeRef
FileFunctionRef
FileAbstractRef
```

may distinguish local and external identities.

Bindings that are lexically local do not need an external form.

An external reference stores enough stable symbolic information for the global
pass to resolve it, for example:

```text
ExternalRef #0
    kind = type
    module = "geometry"
    name = "Point"

ExternalRef #1
    kind = function
    module = "geometry"
    name = "distance"
    resolution_inputs = ...
```

The representation should encode semantic lookup requirements, not pointers to
objects owned by another file graph.

A `FileSemanticGraph` must therefore never directly reference another
`FileSemanticGraph`'s local IDs.

## Building the global graph

The initial design should favor a simple flatten-and-resolve strategy:

```text
FileSG A ─┐
FileSG B ─┼─→ merge + relocate
FileSG C ─┘          ↓
              provisional global state
                       ↓
                 resolve pending
                       ↓
              GlobalSemanticGraph
```

Do not initially keep the final graph as `[]FileSemanticGraph` with permanent
`{ file, local_id }` references. A compact copy/relocation step should be cheap,
and flattening lets Safety and Codegen use simple global IDs thereafter.

### 1. Merge

`mergeFileGraphs()` should be mostly mechanical, not semantic.

For each file, compute base offsets for the flat global tables:

```text
                 node_base   decl_base   function_base
A                    0           0             0
B                   21           5             3
C                   34           9             8
```

Then local identities relocate naturally:

```text
A FileNodeId(7) + node_base 0  → GlobalNodeId(7)
B FileNodeId(7) + node_base 21 → GlobalNodeId(28)
C FileNodeId(7) + node_base 34 → GlobalNodeId(41)
```

The implementation can be close to:

```text
allocate total storage
copy/append file arrays
relocate local IDs by their table base
collect external references
collect pending global operations
```

The expected cost is linear copying and integer fixups over compact arrays. We
should measure it before considering schemes that avoid the copy.

### 2. Canonicalize global types

Types need special treatment. File-local type tables are useful while building
`FileSemanticGraph`, but the final program should not retain duplicate canonical
copies of equivalent global types.

Conceptually:

```text
A FileType #4 = Int32 ─┐
B FileType #7 = Int32 ─┼→ GlobalType #0 = Int32
C FileType #2 = Int32 ─┘
```

During globalization, build a per-file type remap:

```text
(FileId, FileTypeId) -> GlobalTypeId
```

and intern/canonicalize types into the global type store.

This is analogous in spirit to Zig's `InternPool`: later global semantic nodes
should refer to compact canonical type IDs rather than pointer identity.

Not every semantic entity necessarily needs interning. Introduce it where
canonical identity is useful, starting with types.

### 3. Build global symbol indexes

After declarations from all files are known, construct the indexes needed for
program-wide lookup. These indexes should resolve stable symbolic requirements
from `external_refs` to global declaration/function/type identities.

The symbol index is global semantic infrastructure, not part of any individual
file cache.

### 4. Resolve external references

For example:

```text
ExternalTypeRef("geometry::Point")
        ↓
GlobalTypeId(74)

ExternalFunctionRef("geometry::distance", ...)
        ↓
GlobalFunctionId(183)
```

Once resolved, final global nodes should use direct global IDs:

```text
Call {
    callee = GlobalFunctionId(183)
}
```

rather than retaining symbolic external references on hot downstream paths.

### 5. Resolve pending global operations

Some file-local nodes cannot be finalized merely by resolving one symbol.

For example:

```argi
get_x :: (p: Point) -> Int32 {
    return p.x
}
```

If `Point` is external, `FileSema` may produce:

```text
UnresolvedFieldAccess {
    value = FileNodeId(...)
    field_name = "x"
    receiver_type = ExternalTypeRef(...)
}
```

After `Point` resolves globally, `GlobalSema` can replace/finalize it as:

```text
FieldAccess {
    value = GlobalNodeId(...)
    struct_type = GlobalTypeId(42)
    field_index = 0
    result_type = GlobalTypeId(0) // Int32
}
```

The same model applies to calls, overloads, abstracts, copy/deinit lookup,
generic instantiation, and other operations that require a global world.

## `GlobalSemanticGraph`

The finalized graph should also be compact and index-based.

Conceptually:

```text
GlobalNodeId
GlobalDeclId
GlobalFunctionId
GlobalTypeId
GlobalBindingId
```

and flat stores such as:

```text
GlobalSemanticGraph
    nodes
    declarations
    functions
    types
    bindings
    extra_data
    ...
```

The exact tables should follow actual access patterns rather than forcing every
current pointer-owned struct into a one-to-one array. The migration is an
opportunity to make the semantic representation data-oriented instead of
serializing the existing pointer graph.

A finalized `GlobalSemanticGraph` should not expose file-local IDs or unresolved
external references to normal Safety/Codegen consumers.

## Persistence and caching

The primary persistent frontend cache target should eventually be
`FileSemanticGraph`, because it subsumes the expensive file-local work before
the global semantic pass.

```text
source file
    ↓ cache miss
FileTokenList
    ↓
FileSyntaxTree
    ↓
FileSemanticGraph ──→ persistent cache

cache hit ──────────→ FileSemanticGraph
```

`FileTokenList` and `FileSyntaxTree` remain useful architectural artifacts and
may also be cached where LSP or diagnostics benefit, but they do not need to be
the primary compilation cache boundary once `FileSemanticGraph` exists.

A file-semantic cache key must include everything allowed to affect
`FileSemanticGraph`, at minimum:

- source identity/content fingerprint or equivalent validity metadata;
- compiler/language semantic format version;
- any compiler options that are permitted to change file-local semantics.

It must not depend on arbitrary other files. If such a dependency appears, the
FileSG invariant has been violated or the dependency belongs in `GlobalSema`.

Bundled `core` is the first high-value consumer: release/compiler builds can
ship or generate precomputed core `FileSemanticGraph` artifacts, avoiding
source reads, tokenizing, parsing, and file-local semantizing for unchanged
stdlib files during ordinary compilation.

The first implementation does not need mmap or zero-copy persistence. A simple
explicit binary format plus allocate/read is enough to validate the
architecture and benchmark the win. Optimize loading only after measurements.

## Source and diagnostics

A persistent `FileSemanticGraph` must contain the semantic strings/identities
needed by globalization without requiring the original source to be read on a
cache hit.

Source text and/or `FileSyntaxTree` may still be loaded lazily when rich
diagnostics, LSP operations, or source reconstruction require them. Do not make
ordinary semantic cache hits read and parse source merely because diagnostic
paths may need it later.

This should be designed explicitly rather than accidentally retaining slices
into transient source buffers.

## Implementation plan

### Phase 1 — establish names and file-local semantic representation

1. Introduce the `FileTokenList` / `FileSyntaxTree` terminology and types where
   it improves clarity without doing a gratuitous all-at-once rename.
2. Design compact local semantic IDs and `FileSemanticGraph` storage.
3. Split the existing Semantizer conceptually into file-local and global work.
4. Lower one file at a time into `FileSemanticGraph`.
5. Represent every cross-file dependency explicitly as an external reference or
   pending global operation.
6. Add invariants/tests proving one FileSG cannot directly reference another
   file's local identities.

### Phase 2 — globalization

1. Implement `mergeFileGraphs()` with base offsets and local-ID relocation.
2. Introduce canonical global type IDs/type interning.
3. Build global symbol indexes.
4. Resolve external references.
5. Resolve pending global semantic operations.
6. Produce the index-based `GlobalSemanticGraph` expected by Safety and Codegen.
7. Preserve current language behavior and test baseline throughout the
   migration.

### Phase 3 — migrate downstream consumers

1. Move Safety from pointer-based SG objects to global semantic IDs/views.
2. Move Codegen and semantic debug/printing utilities to the same indexed
   representation.
3. Remove the legacy pointer-heavy semantic graph once no consumers require it.
4. Measure memory, semantic build time, globalization time, and downstream
   traversal performance.

### Phase 4 — persistent FileSG cache

1. Define an explicit versioned FileSG disk format; do not serialize raw Zig
   pointer/slice ABI.
2. Add round-trip tests:

   ```text
   source
       ↓
   FileSemanticGraph A
       ↓ serialize
   artifact
       ↓ deserialize
   FileSemanticGraph B

   globalize(A, others) == globalize(B, others)
   ```

3. Add cache validity metadata and cache-hit/miss plumbing.
4. Make bundled `core` use persistent/prebuilt FileSG artifacts first.
5. Extend the same mechanism to project files.
6. Benchmark cache-hit startup and compilation costs before considering mmap or
   finer-grained incremental parsing.

### Phase 5 — future semantic incrementalism

Only after the file/global split and persistence are stable, investigate
fine-grained invalidation inside `GlobalSemanticGraph`.

Possible future work includes:

- stable global semantic identities across updates;
- dependency edges between semantic analysis units;
- declaration/interface hashes;
- preserving unaffected global semantic results when one FileSG changes;
- old-to-new semantic identity mapping similar in spirit to Zig's tracked ZIR
  instructions and semantic dependency graph.

This is deliberately not required for the first persistent FileSG cache.

## Non-goals for the first version

Do not initially require:

- incremental parsing within an edited file;
- stable `FileNodeId` values across edits;
- mmap/zero-copy cache loading;
- avoiding the flatten/copy step when building the global graph;
- cross-version cache compatibility;
- fine-grained incremental Safety or Codegen;
- preservation of the current pointer-based `SemanticGraph` layout.

A changed source file may simply rebuild its complete `FileTokenList`,
`FileSyntaxTree`, and `FileSemanticGraph`. Unchanged files should be reusable as
whole file artifacts.

## Measurements

Keep measuring the frontend with `--stats`, but extend the measurements around
the new boundary:

```text
tokenize time
syntax time
FileSema time
FileSG storage bytes
global merge/relocation time
global type interning time
global resolution time
GlobalSG storage bytes
safety time
total compilation time
```

For cache experiments also measure:

```text
FileSG cache hits/misses
bytes read from source
bytes read from cache
FileSG deserialize/load time
stdlib work avoided
```

The design should be judged primarily by correctness of the file/global
invariant, cacheability, and measured whole-compilation wins rather than by
avoiding a cheap linear copy during globalization.

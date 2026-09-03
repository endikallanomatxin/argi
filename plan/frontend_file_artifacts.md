# Frontend file artifacts

The frontend currently uses a single arena for a module, but tokenizing and
syntaxing are independent per source file. The migration keeps that semantic
model while making their outputs suitable cache boundaries.

1. **File boundaries (complete)** — introduce `SourceDb` and stable `FileId`,
   retain one owned token buffer per file, and syntax each buffer separately.
   Tokens no longer cross a module-wide concatenation or copy boundary.
2. **Compact locations (complete)** — make `Location` contain only `FileId` and byte
   offset. `SourceDb` will calculate paths and line/column information only
   while rendering diagnostics or LSP positions.
3. **Dense syntax storage (in progress)** — each file now owns a
   `SyntaxStore` with densely allocated node bodies and `NodeId` roots. The
   pointer-based semantizer consumes a non-owning adapter over those bodies,
   rather than a reconstructed AST. Child references, type extra data, and
   names remain on the legacy representation until their `NodeId`/range-based
   forms can be migrated together; they are not serializable yet. Nodes use
   fixed pages while the adapter exists, avoiding a token-proportional reserve
   solely to keep legacy pointers stable; serialization will flatten the pages.
   The stable target is a compact node header plus fixed-width index data and a
   shared `extra_data: []u32` table. Optional node references use a sentinel;
   variable-length child lists use half-open ranges into `extra_data`. Keep
   small-list inline encodings as a later measured optimization rather than a
   prerequisite for removing pointers. Roots already use the same range
   representation intended for blocks and other child lists.
4. **Persistent cache** — version and serialize the source hash, token stream,
   syntax store, and side tables. No artifact may contain arena pointers or
   borrowed source slices; textual token payloads will be source-relative
   ranges before this stage starts.

Measure every stage with `--stats`: tokenizing and syntaxing time, token count
and storage bytes, and the `minimal`, `cat_cli`, and dynamic-array build times.
Do not introduce incremental semantizing or alter semantic graph identities as
part of this migration.

## Baseline integration failures

On 2026-09-03, `zig build test` was run at `b32a357` (the parent of the
location/token compacting change) and at `8cb47ab`. Both runs produced the
same 17 failures with byte-for-byte identical diagnostic sections; only the
test runner seed differed. They are therefore preexisting and must not be
attributed to compact locations or tokens:

- `polymorphism/14X_abstract_function_output_requires_default`
- `ownership/08X_noncopyable_output_binding`, `ownership/37X_ambiguous_copy_return`
- `collections/17_string_hash_map_baseline`,
  `collections/35_dynamic_array_fallible_copy_cleanup`
- `system/02_reached_arguments`, `system/03X_reached_argument_missing`,
  `system/33_array_view_libc_memcpy`
- `types/15_default_type_initializer_argument`,
  `types/38_inferred_errable_from_propagation`,
  `types/39_inferred_errable_direct_error`,
  `types/40_inferred_errable_explicit_output`
- `modules/20_inferred_errable_imported`,
  `modules/21_inferred_explicit_errable_imported`,
  `modules/25_inferred_errable_omitted_reasons_transitive`,
  `modules/26_inferred_shorthand_omitted_reasons_transitive`
- `io/23X_abstract_writer_field_conflicting_assignment`

The compacting change introduced no newly failing integration test. The
frontend's internal test suite remains green (87/87).

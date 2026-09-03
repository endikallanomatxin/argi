# Frontend file artifacts

The frontend currently uses a single arena for a module, but tokenizing and
syntaxing are independent per source file. The migration keeps that semantic
model while making their outputs suitable cache boundaries.

1. **File boundaries (current)** — introduce `SourceDb` and stable `FileId`,
   retain one owned token buffer per file, and syntax each buffer separately.
   Tokens no longer cross a module-wide concatenation or copy boundary.
2. **Compact locations** — make `Location` contain only `FileId` and byte
   offset. `SourceDb` will calculate paths and line/column information only
   while rendering diagnostics or LSP positions.
3. **Dense syntax storage** — replace `*STNode` ownership with a per-file
   `SyntaxStore`, `NodeId` references, and dense child/index tables. Preserve
   the old semantic-facing traversal through an adapter until semantizing can
   consume IDs directly.
4. **Persistent cache** — version and serialize the source hash, token stream,
   syntax store, and side tables. No artifact may contain arena pointers or
   borrowed source slices; textual token payloads will be source-relative
   ranges before this stage starts.

Measure every stage with `--stats`: tokenizing and syntaxing time, token count
and storage bytes, and the `minimal`, `cat_cli`, and dynamic-array build times.
Do not introduce incremental semantizing or alter semantic graph identities as
part of this migration.

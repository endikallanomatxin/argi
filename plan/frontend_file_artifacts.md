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
3. **Dense syntax storage (in progress)** — use per-file `SyntaxFile`, local
   `NodeIndex`, and file-aware `SyntaxRef` identities. Semantizer consumes
   typed views directly, including syntax type nodes. Do not introduce an
   adapter or reconstruct the legacy tree. Preserve lazy function bodies and
   the generic specialization cache throughout the migration.
4. **Complete and validate the migration** — finish Semantizer and the normal
   pipeline first, restore all feature tests, remove syntax legacy and parity
   scaffolding, then finish LSP and restore its syntax highlighting overlay.
   Resolve duplicated token ownership after the semantic path is stable.
5. **Future investigation, outside this migration** — evaluate per-file
   frontend caching and incremental compilation only after the compact
   frontend is complete and stable. No persistent cache, serialization, new
   IR, or semantic identity redesign is part of the current work.

Measure every stage with `--stats`: tokenizing and syntaxing time, token count
and storage bytes, and the `minimal`, `cat_cli`, and dynamic-array build times.
Do not introduce incremental semantizing or alter semantic graph identities as
part of this migration.

## Migration checkpoint (2026-09-05)

The working tree routes FrontendPipeline through SyntaxFile, but Semantizer
still contains unreachable legacy handlers and incomplete compact handlers.
A successful `zig build` does not validate this transition: Zig does not
typecheck unreachable function bodies.

Direct compact visitors now cover while, defer, move, keep, list and choice
literals, dereference, address-of, index access, and pointer/index assignment.
Reach-default diagnostic formatting also reads compact nodes. The existing
selected tests for while/if/break, defer, list indexing, pointer reads/writes,
and UIntNative array indexing pass.

Full validation currently reports 129/658 integration tests and 92/95 internal
tests passing (221/753 total), up from 185/753 at the start of this checkpoint.
This is not the target baseline. In particular, the use-after-move negative
test still fails before reaching its expected diagnostic. Generic implements,
function interfaces/calls, and the remaining compact visitor cases still need
completion before deleting legacy, finishing LSP, or measuring performance.
The available local toolchain is Zig 0.16.0 with LLVM 21; llvm-config-20 was not
found. Obtain the supported LLVM 20 toolchain for final baseline validation.

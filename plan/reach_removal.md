# Remove reach

Remove `reach` from the language, without a replacement mechanism. Keep ordinary
parameters and lexical `assume`; do not implement LSP propagation, new directives
or compatibility with the removed syntax.

- Migrate core, more, generated entrypoints and tests to declared dependencies
  supplied explicitly or through ordinary lexical assumptions.
- Remove reach syntax, call-chain propagation, reached-input completion and the
  resolver state, rollback bookkeeping and diagnostics needed only for them.
  Preserve shared lexical call context where ordinary `assume` still needs it.
- Update formatting, highlighting, editor services and language documentation.
  Delete tests devoted to reach rather than preserving obsolete rejection cases.
- Validate generic providers, contract operations, iterator calls, cleanup,
  entrypoints, REPL and compile-time execution with explicit interfaces.

Do not add machinery to preserve reach behavior during the migration.

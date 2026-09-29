# Contextual virtual conversion

- [x] Tokenizing keeps the existing tokens; syntaxing accepts positional
  comptime types in `#(Type)` as well as named comptime arguments.
- [x] Semantizing infers the abstract argument of `to_virtual` from an expected
  `Virtual` result, including a borrowed pipe result with an explicit type.
  Without an expected type, the abstract remains explicit.
- [x] Materialize borrowed pipe expression results in local storage. Preserve
  pointer collapsing and keep tracer and wrapper temporaries alive for the
  enclosing `assume` scope, with their normal cleanup and safety dependencies.
- [x] Accept the single positional receiver in `to_virtual($&value)`.
- [x] Validate runtime dispatch, cleanup, pointer collapsing, missing context,
  explicit conversion compatibility, and escaping temporary diagnostics.
- [x] Run the complete compiler test suite and inspect generated LLVM IR.
- [x] Accept positional comptime types in virtual calls and use them in the
  compact error tracer examples.

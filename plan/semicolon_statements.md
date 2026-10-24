# Explicit statement separators

- Tokenizing: retain `;` as its own punctuation token, preserving source locations.
- Syntaxing: consume it between statements/declarations and terminate bare returns.
  Keep it distinct from newline whitespace in argument and field parsing.
- Semantizing and codegen: reuse existing statement nodes and cleanup rules.
- Tooling: preserve the punctuation when formatting and separate following text.
- Validation: exercise module declarations, local declarations, writes, calls,
  compact blocks, return, string/comment text, and rejected argument separation.

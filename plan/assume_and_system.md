# Lexical assumptions and checked program entry

## Commit 1: lexical assumptions (implemented and validated)

- Add `assume name` as a lexical statement enabling an existing binding for
  omitted call arguments with that name. Also allow `assume` to prefix a
  normal variable declaration, preserving initialization and mutability rules.
- Resolve explicit arguments before assumed bindings, then defaults. Assumptions
  do not propagate into callees. Keep `reach` propagation unchanged.
- Carry lexical candidates through ordinary and parameterized call resolution;
  materialize selected arguments before ownership, safety, and codegen.
- Migrate routine allocator and stream dependencies in core and their callers.
- Cover scope, precedence, generic inference, type errors, and temporal safety.

## Commit 2: checked program entry

- Represent resource setup, the user entry call, and cleanup before safety.
- Keep only the host ABI adapter in codegen.
- Make the entry scope own resources and make System a reference context.
- Keep System aggregated at main and use the same lifetime arrangement for
  tests. Bind its fields locally with compact assume declarations.
- Validate cleanup, safety rejection of invalid entry lifetimes, and generated IR.

The active release checklist is plan/0.2.md; plan/0.1.md no longer exists.

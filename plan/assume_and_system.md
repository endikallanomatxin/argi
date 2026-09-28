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

## Commit 2: checked program entry (implemented and validated)

- Represent resource setup, the user entry call, and cleanup before safety.
- Keep only the host ABI adapter in codegen; pass System explicitly.
- Make the entry scope own resources and make System a reference context.
- Keep System aggregated at main and use the same lifetime arrangement for
  tests. Bind its fields locally with compact assume declarations.
- Validate cleanup, safety rejection of invalid entry lifetimes, and generated IR.

The active release checklist is plan/0.2.md; plan/0.1.md no longer exists.

## Explicit memory policy (implemented and validated)

- The checked entry owns `Memory` and a `PageAllocator` backed by it. System
  exposes references to these capabilities without selecting program policy.
- Programs construct `GeneralPurposeAllocator` with an explicit backing
  allocator and enable it with `assume`; allocating functions retain explicit
  allocator inputs. Arena blocks also use their chosen backing allocator.
- Terminal initialization has no allocation; buffered adapters require a
  program-selected allocator. C allocation wrappers require the FFI capability.
- Safety applies constructor effects and preserves backing dependencies across
  erased allocator dispatch. Compiler-generated error-trace allocations remain
  a separate runtime exception tracked in plan/0.2.md.

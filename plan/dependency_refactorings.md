# Dependency propagation refactorings

Undecided proposal for later study. Neither replacing `reach` nor adding a new
source directive is approved. Current language semantics remain unchanged.

Explore replacing semantic `reach` propagation with compiler-backed source
refactorings. `assume` would remain the lexical mechanism for supplying implicit
arguments; intermediate dependencies would appear in source signatures.

A temporary request, provisionally spelled `#reach allocator`, could ask the LSP
to identify the missing dependency, add parameters to intermediate functions,
update their calls and continue until a suitable source is found. The tool would
show the edits and remove the request when applying them. This spelling is not
proposed executable or compile-time syntax.

The reverse operation would remove an unnecessary parameter and update affected
signatures and calls. Both operations transform source; neither supplies values
or changes resolution during compilation.

## Open questions

- What counts as a suitable source, and when must the user choose a provider?
- How are recursion, generic specializations, aliases and multiple callers
  handled without specializing source edits to just one observed call?
- What happens at public APIs, contract operations, callbacks, virtual dispatch
  and imported code that cannot be edited? A closed call graph cannot be assumed.
- How are compile-time provider parameters, defaults, Safety guarantees and
  lifetimes propagated together with ordinary inputs?
- Can edits preserve behavior and diagnostics across modules, and can removal
  preserve side effects of previously supplied argument expressions?
- Should requests live entirely in editor actions rather than source directives?
  How can the same refactoring be used without an LSP client?

Tooling may remove repetitive editing, but it cannot automatically replace every
semantic use of `reach`. Before removing the language feature, demonstrate that
explicit interfaces compose across these boundaries and measure the resulting
source complexity.

## Evaluation

First explore a compiler-backed editor action to propagate dependencies as
explicit parameters, with previewable edits and a possible CLI equivalent.
A temporary `#reach` request is an alternative interaction to evaluate, not
required language syntax. Also support removing unnecessary parameters while
preserving argument-expression effects.

Try existing `reach` consumers, including generic functions and contracts.
Compare source clarity and editing ergonomics. At fixed interfaces such as
callbacks, public contracts or external APIs, report the boundary and require
an explicit design choice instead of silently changing the interface.

The refactoring can be useful while `reach` remains available. Decide whether
to remove the semantic feature only after these experiments demonstrate that
explicit dependencies compose adequately across real call boundaries.

References: [contracts](../description/135_contracts.md),
[function arguments](../description/41_function_args.md), and
[allocation](../description/35_allocation.md).

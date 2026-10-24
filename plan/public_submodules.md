# Public submodule access

- Discover directory prefixes named through module aliases, without recursively
  loading unused subtrees. Retain source-free parent namespaces in the frontend.
- Preserve full qualifier chains in syntax and lower types, calls, and values to
  the selected module path. Keep ordinary record projections working.
- Enforce underscore directory privacy for both qualified access and explicit
  imports: only the private directory's parent and its descendants may use it.
- Include discovered directory context in local semantic cache fingerprints.
- Validate empty parents, nested and local aliases, more/math, private access,
  direct imports, target-selected discovery, cache reuse, and LLVM output.

TODO: Improve the diagnostic for inferred nested module-level aggregate constants
that currently fail graph verification; the regression fixture uses an explicit
aggregate type to keep this independent issue outside submodule resolution.

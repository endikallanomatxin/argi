# C interoperability follow-ups

- Generic callback invocation/selection when a wrapper needs it.
- Bounded `#c_import` when manual bindings become an obstacle; include headers,
  defines, include paths, and target inputs in cache identity.
- Retained callback contexts with explicit lifetime, storage, and cleanup rules.
- Foreign lifetime contracts before safe-reference fields cross the ABI.

Extend signatures from concrete consumers. Unsupported ABIs must fail with
useful diagnostics. Full macro translation, C++, arbitrary variadics, and
automatic dependency downloads remain outside scope.

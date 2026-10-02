# C interoperability

Scope: manual native bindings for [0.3](0.3.md); consumer-driven extensions in
[0.4](0.4.md) and lifetime/registration work in [0.5](0.5.md).
Language contracts belong in `description/20_c.md` and `description/02_modules.md`.

## Direction

Keep the 0.3 boundary to explicit typed imports/exports, linking, raw handles
and buffers, supported C aggregates, and concrete typed callbacks. Preserve
the shared ABI classification and foreign-result safety rules; unsupported
signatures must receive diagnostics rather than guessed lowering.

The zlib checksum wrapper provides a real manual-binding consumer. Further
signature shapes and binding automation should follow concrete library needs,
not become prerequisites for cross-compilation or the first Python bridge.

## Work to do

- [ ] In 0.4, support callback invocation and selection inside generic wrappers
  when a library consumer requires them.
- [ ] In 0.4, introduce a bounded `#c_import` subset when manual bindings become
  a concrete obstacle;
  account for headers, defines, include paths, and target inputs in caching.
  Extend enum constant expressions, aliases, and representation selection as
  required by that subset.
- [ ] In 0.5, define retained context, storage effects, and cleanup before
  supporting callback registration that outlives a call.
- [ ] Define an explicit foreign lifetime contract before adapting safe-reference
  fields across the ABI; keep this outside the initial native-binding scope.

Start on supported native hosts. Full macro translation, C++, arbitrary
variadics, and automatic dependency downloads remain later extensions.

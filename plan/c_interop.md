# C interoperability

Language contracts belong in `description/20_c.md` and `description/02_modules.md`.

## Direction

Build on explicit typed imports/exports, linking, raw handles and buffers,
supported C aggregates, and concrete typed callbacks. Preserve
the shared ABI classification and foreign-result safety rules; unsupported
signatures must receive diagnostics rather than guessed lowering.

The zlib checksum wrapper provides a real manual-binding consumer. Further
signature shapes and binding automation should follow concrete library needs.

## Work to do

- [ ] Support callback invocation and selection inside generic wrappers
  when a library consumer requires them.
- [ ] Introduce a bounded `#c_import` subset when manual bindings become
  a concrete obstacle;
  account for headers, defines, include paths, and target inputs in caching.
  Extend enum constant expressions, aliases, and representation selection as
  required by that subset.
- [ ] Define retained context, storage effects, and cleanup before
  supporting callback registration that outlives a call.
- [ ] Define an explicit foreign lifetime contract before adapting safe-reference
  fields across the ABI; keep this outside the initial native-binding scope.

Start on supported native hosts. Full macro translation, C++, arbitrary
variadics, and automatic dependency downloads are outside this scope.

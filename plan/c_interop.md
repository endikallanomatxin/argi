# C interoperability

Scheduling: [0.3](0.3.md), after initial module reuse and before cross-compilation.
Language contracts belong in `description/20_c.md` and `description/02_modules.md`.

## Direction

Implement the accepted typed-binding design before automating header imports.
Validate the ABI against C and exercise a real library through Argi wrappers;
existing external calls do not establish support for every signature shape.

## Work to do

- [ ] Define an explicit foreign lifetime contract before adapting safe-reference
  fields across the ABI.
- [ ] Add checked indirect callback invocation, and support
  callback selection inside generic wrappers. Define retained context and storage
  effects before supporting registration, preparing the Python bridge.
- [ ] Introduce a bounded `#c_import` subset after explicit bindings work;
  account for headers, defines, include paths, and target inputs in caching.
  Extend enum constant expressions, aliases, and representation selection as
  required by that subset.

Start on supported native hosts. Full macro translation, C++, arbitrary
variadics, and automatic dependency downloads remain later extensions.

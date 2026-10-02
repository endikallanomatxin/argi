# C interoperability

Scheduling: [0.3](0.3.md), after initial module reuse and before cross-compilation.
Language contracts belong in `description/20_c.md` and `description/02_modules.md`.

## Direction

Make a real C library usable through explicit bindings before automating header
imports. Existing external calls, C enums/unions, and C strings provide a base,
but do not establish support for every C ABI shape.

## Work to do

- [ ] Choose a small native-library consumer and validate its signatures/layouts
  against C, including aggregate arguments/results.
- [ ] Make library names, search paths, and static/shared linking explicit and
  reusable by the target/toolchain work.
- [ ] Keep foreign-call capabilities, resource cleanup, pointer bounds, and
  allocation/free pairing explicit in wrappers; headers do not prove safety.
- [ ] Add exported C-callable functions and scope function pointers/callbacks,
  preparing the later Python bridge.
- [ ] Introduce a bounded `#c_import` subset after explicit bindings work;
  account for headers, defines, include paths, and target inputs in caching.

Start on supported native hosts. Full macro translation, C++, arbitrary
variadics, and automatic dependency downloads remain later extensions.

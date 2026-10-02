# C interoperability

Scheduling: [0.3](0.3.md), after initial module reuse and before cross-compilation.
Language contracts belong in `description/20_c.md` and `description/02_modules.md`.

## Direction

Implement the accepted typed-binding design before automating header imports.
Validate the ABI against C and exercise a real library through Argi wrappers;
existing external calls do not establish support for every signature shape.

## Work to do

- [ ] Extend raw-pointer field effects to arrays and unions; safe-reference
  fields require an explicit foreign lifetime contract before ABI adaptation.
- [ ] Keep foreign-call capabilities, resource cleanup, pointer bounds, and
  allocation/free pairing explicit in wrappers; headers do not prove safety.
- [ ] Settle incomplete types, callback syntax, and foreign storage effects,
  preparing the later Python bridge.
- [ ] Introduce a bounded `#c_import` subset after explicit bindings work;
  account for headers, defines, include paths, and target inputs in caching.

Start on supported native hosts. Full macro translation, C++, arbitrary
variadics, and automatic dependency downloads remain later extensions.

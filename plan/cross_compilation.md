# Cross-compilation

Scheduling: [0.3](0.3.md), after initial module reuse and C interop.
[Native Windows support](windows_support.md) is an independent effort.

## Direction

Establish coherent explicit target selection, then one usable cross-linked
executable path. Native packages for several architectures do not themselves
provide cross-compilation.

## Work to do

- [ ] Share target configuration across semantizing/layouts, safety, codegen,
  core platform selection, and linking; include relevant settings in cache keys.
- [ ] Replace host-derived assumptions such as pointer size and native LLVM
  target initialization with target-aware decisions.
- [ ] Start with Linux x86_64 → aarch64 object emission, then executable linking.
- [ ] Expose linker/CC, sysroot, and target library inputs explicitly; diagnose
  missing inputs rather than silently using host libraries.
- [ ] Exercise generated programs and C ABI/layouts on the destination runner.
  Keep native defaults and reject incompatible `argi run` targets.

Reuse the existing C ABI classification with the selected target. Expanding
the supported C signature shapes is separate, consumer-driven work.

Bundled cross toolchains, macOS SDK distribution, Windows cross-linking, wasm,
32-bit and freestanding platforms are subsequent extensions, not the first scope.

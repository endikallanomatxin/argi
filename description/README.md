# Language description

These notes describe the intended Argi language. Unmarked text states the
design; `[!IMPLEMENTATION]` marks a compiler gap, `[!QUESTION]` an unresolved
decision, and `[!IDEA]` an exploratory possibility. Implementation work and
milestones belong in [`plan/`](../plan/).

For a first pass, read [Syntax overview](00_syntax_overview.md),
[Modules](02_modules.md), [Types](10_types.md),
[Values and validity](31_values_and_validity.md), and
[Functions](40_functions.md).

## Language topics

- **Types and data:** [Types](10_types.md), [Structs](11_structs.md),
  [Choice](12_choice.md), [Basic built-in types](15_basic_builtins.md), and
  [Nullability](51_nullability.md).
- **Memory and safety:**
  [Initialization and deinitialization](30_initialization_and_deinitialization.md),
  [Values and validity](31_values_and_validity.md),
  [References](32_references.md),
  [Copying and moving](33_copying_behaviour.md),
  [Safety model](34_safety_model.md), and [Allocation](35_allocation.md).
- **Functions and execution:** [Functions](40_functions.md),
  [Function arguments](41_function_args.md), [Once](42_once.md),
  [Control flow](44_control_flow.md),
  [Compile-time computation](50_comptime.md), and [Errors](59_errors.md).
- **Polymorphism:** [Overview](130_polymorphism.md),
  [Multiple dispatch](131_multiple_dispatch.md),
  [Compile-time parameters](132_generics.md),
  [Abstract types](133_abstract_types.md), and
  [Virtual types](134_virtual_types.md).
- **Collections:** [Lists](161_lists.md), [Strings](162_strings.md), and
  [Other collections](169_other_collections.md).
- **Numeric utilities:** [Deterministic randomness](163_randomness.md) and
  [Duration and clocks](164_time.md).
- **Native tools:** [Processes](165_processes.md) and
  [Semantic versions](166_semver.md).
- **Integration and tooling:** [Modules](02_modules.md),
  [C interoperability](20_c.md), [Testing](72_testing.md),
  [Documentation comments](73_documentation.md), and [System](80_system.md).

## Exploratory designs

- [Building](03_building.md): a possible procedural build layer beyond
  `argi.toml`.
- [Runtime](81_runtime.md): an async and concurrency capability proposal.
- [Parallel computing](82_parallel_computing.md): hardware descriptions and
  parallel execution sketches.

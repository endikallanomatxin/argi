# Compiler follow-ups

## Resolution and transactions

- Remove resolver state used only to communicate temporary results.
- Clarify pass dependencies and ownership operand staging versus lowering.
- Reduce measured redundant resolution and verification, including remaining
  binding/type sweeps. Include older entities completed by new facts.
  Do not restrict expression type propagation to execution reachability alone:
  ownership finalization also needs pending choice-payload write operands.
- Investigate repeated propagation and Safety checking in the measured
  specialization workload before introducing shared semantic bodies.

## Safety

- Extend conditional storage effects through stored results, indirect outputs
  and loops, preserving intervening writes and exact caller identities.
- Extend hidden retention/replacement and grouped opaque mappings through output
  fields when a consumer needs them.
- Represent hidden storage and cleanup identities before virtualizing Resizable.

## Execution

- Track external compile-time reads in build dependencies and cache identity.
- Separate host execution from target semantics for cross-compilation.
- Reclaim immutable aggregate payloads using all roots: results, cross-frame
  writes, session/acquired storage and virtual descriptors.

Validate with growing REPL sessions, rollback/allocation failures and native/VM
comparisons. New Safety precision needs aliasing and duplicate-cleanup rejections.
Finish auditing I/O/system fixture isolation by actual shared resources.

References: [performance](../docs/compiler-performance.md),
[Safety](../description/34_safety_model.md#precision-of-safety-effects),
[virtual contracts](../description/134_virtual_types.md).

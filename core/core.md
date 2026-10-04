# Core library

`core/` supplies the bundled library used by Argi programs. Building the
compiler installs it under `zig-out/lib/argi/core`; rebuild after editing core
before running the installed compiler manually.

The implemented foundations include:

- Memory: raw storage, allocations, temporal dependencies, opaque ownership,
  and allocator composition.
- Collections and text: arrays, array views, dynamic arrays, Deque with value
  and borrowed iteration, hash maps and sets, strings, and collection operations.
- Binary data: checked unsigned endian reads and writes, and borrowed byte
  cursors whose positions advance only after successful operations.
- System and I/O: program capabilities, files, filesystem operations, terminal
  streams, blocking networking, processes, and byte/block reader/writer contracts.
  Filesystem helpers include directory enumeration, metadata, file positioning
  and truncation, and temporary directory owners. Stream helpers support exact
  reads, complete writes, bounded delimiter reads, and copying with caller buffers.
- Errors: nominal reasons, `Errable`, explicit propagation, and tracing policies.
- Interoperability: explicit foreign-function capability and libc declarations.

A directory's presence does not imply that its module is complete. Consult
its `.rg` implementation and registered feature tests for the supported
operations. Language contracts belong in `description/`; planned library
extensions and implementation milestones belong in the
[0.3 preparation](../plan/0.3.md) and
[0.4 roadmap](../plan/0.4.md).
Exploratory possibilities that are not scheduled remain in
[the library ideas inventory](library_ideas.txt), alongside existing module
sketches.

Core trusted operations form an explicit compiler boundary. Their contracts
must preserve the distinction between owned bytes, initialized values,
physical ranges, and temporal validity. Names alone do not grant trust:
recognition requires the bundled source identity and matching declaration.
See [the safety model](../description/34_safety_model.md).

Other language libraries can inform API choices, but Argi's capability,
ownership, and error contracts determine the design. Reference checkouts
are inspiration; do not copy their implementations or documentation.

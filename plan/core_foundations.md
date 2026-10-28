# Library follow-ups

Prioritize real consumers; reproduce compiler gaps before adding workarounds.

- Audit owning containers under structural cleanup and allocation failures.
  Remove residual lexical `reach allocator` defaults; retain explicit arguments
  and assumed allocator inference.
- Audit stream adapters under allocation/native failures; compose owning lines.
- Extend CLI argument relationships, subcommands, and typed diagnostics.
- Audit traversal under filesystem changes and resource limits.
- Extend math and timezone-aware date formats.
- Add owning/typed JSON consumers, streaming CSV, then compression/archives.
- Explore HTTP and selected hashes/crypto with explicit capabilities.

Threads, synchronization, and task cleanup follow cross-thread transfer rules
in [0.5](0.5.md). Use executable consumers and negative ownership tests.

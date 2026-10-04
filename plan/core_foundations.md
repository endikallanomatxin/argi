# Standard-library foundations

Implement reusable foundations before application libraries. Preserve explicit
allocation, capabilities, ownership and nominal errors throughout.

## Development order

2. Numeric foundations: floating-point rounding.
4. Collections: bitsets, priority queues, and owner-aware algorithms.
5. Streams: memory adapters, composable limits and bounded LF/CRLF lines.
6. Filesystem/tools: harden existing path operations, walking and CLI options.
7. More: hex/Base64, JSON/CSV, then compression/archive consumers.
8. Services/runtime: logging, HTTP, selected hashes/crypto, then concurrency
   and cancellation aligned with the language runtime plans.

Each unit includes executable or negative feature tests and public contracts.
Use application usecases to validate composition. Existing implementations must
be audited before adding parallel APIs; empty sketches do not count as support.
Library-only foundations use existing tokenizing, syntaxing, semantizing and
codegen constructs. Compiler work is justified by a concrete failing consumer.

# Standard-library foundations

Implement reusable foundations before application libraries. Preserve explicit
allocation, capabilities, ownership and nominal errors throughout.

## Development order

1. Collections: priority queues for owning elements and owner-aware algorithms.
   Generic function bodies still need for-loop lowering, including consuming loops.
2. Streams: byte-level limited adapters and owning line iteration.
3. Filesystem/tools: path normalization, directory walking and CLI options.
4. More: hex/Base64, JSON/CSV, then compression/archive consumers.
5. Services/runtime: logging, HTTP, selected hashes/crypto, then concurrency
   and cancellation aligned with the language runtime plans.

Each unit includes executable or negative feature tests and public contracts.
Use application usecases to validate composition. Existing implementations must
be audited before adding parallel APIs; empty sketches do not count as support.
Library-only foundations use existing tokenizing, syntaxing, semantizing and
codegen constructs. Compiler work is justified by a concrete failing consumer.
